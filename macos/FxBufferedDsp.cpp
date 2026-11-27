#include "FxBufferedDsp.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <pthread.h>
#include <utility>

namespace fxport {
BufferedDsp::BufferedDsp(std::unique_ptr<JsDsp> dsp, size_t delayFrames)
    : dsp_(std::move(dsp)), delayFrames_(std::max<size_t>(delayFrames, 1)), dry_(delayFrames_ * 2),
      worker_(&BufferedDsp::run, this) {}

BufferedDsp::~BufferedDsp() { stop(); }

void BufferedDsp::stop() noexcept {
    running_.store(false, std::memory_order_relaxed);
    if (worker_.joinable()) worker_.join();
}

void BufferedDsp::run() noexcept {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    size_t next = 0;
    while (running_.load(std::memory_order_relaxed)) {
        auto& block = blocks_[next];
        if (block.state.load(std::memory_order_acquire) != queued) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }

        block.processed = !needsRestart() && dsp_->process(block.samples.data(), block.frames);
        if (block.processed && !std::all_of(block.samples.data(), block.samples.data() + 2 * block.frames,
                                          [](float sample) { return std::isfinite(sample); })) {
            block.processed = false;
            ++nonFiniteBlocks_;
            needsRestart_.store(true, std::memory_order_relaxed);
        }
        if (!block.processed) ++failures_;
        block.state.store(ready, std::memory_order_release);
        next = (next + 1) % blocks_.size();
    }
}

size_t BufferedDsp::process(const float* input, float* output, size_t frames) noexcept {
    // Use one playback timeline for dry and wet audio. Each queued block keeps its
    // original playback position even if the worker misses a deadline or the queue fills.
    for (size_t i = 0; i < frames; ++i) {
        for (size_t channel = 0; channel < 2; ++channel) {
            const size_t sample = 2 * i + channel;
            const size_t delayed = 2 * dryIndex_ + channel;
            output[sample] = dry_[delayed];
            dry_[delayed] = input[sample];
        }
        if (++dryIndex_ == delayFrames_) dryIndex_ = 0;
    }

    size_t offset = 0, changed = 0;
    while (offset < frames) {
        const uint64_t position = nextFrame_ + offset;
        auto& block = blocks_[read_];
        size_t count = frames - offset;
        const float* wet = nullptr;
        if (block.state.load(std::memory_order_acquire) == ready) {
            const uint64_t end = block.firstFrame + block.frames;
            if (end <= position) {
                block.state.store(empty, std::memory_order_release);
                read_ = (read_ + 1) % blocks_.size();
                continue;
            }
            if (block.firstFrame > position) {
                count = std::min<uint64_t>(count, block.firstFrame - position);
            } else {
                count = std::min<uint64_t>(count, end - position);
                if (block.processed) wet = block.samples.data() + 2 * (position - block.firstFrame);
            }
        }

        float* destination = output + 2 * offset;
        if (wet) {
            for (size_t i = 0; i < count; ++i) {
                if (std::fabs(destination[2 * i] - wet[2 * i]) > 1.e-4f ||
                    std::fabs(destination[2 * i + 1] - wet[2 * i + 1]) > 1.e-4f) ++changed;
            }
            std::memcpy(destination, wet, 2 * count * sizeof(float));
        } else if (position + count > delayFrames_) {
            fallbackFrames_ += position + count - std::max<uint64_t>(position, delayFrames_);
        }

        // A short ramp from the previous output sample softens a switch between paths.
        constexpr size_t fadeFrames = 32;
        if (wasWet_ != (wet != nullptr)) {
            wasWet_ = wet != nullptr;
            fadeFrom_ = lastOutput_;
            fadeRemaining_ = fadeFrames;
        }
        for (size_t i = 0; i < count && fadeRemaining_ > 0; ++i, --fadeRemaining_) {
            const float oldWeight = float(fadeRemaining_ - 1) / fadeFrames;
            for (size_t channel = 0; channel < 2; ++channel) {
                auto& sample = destination[2 * i + channel];
                sample = oldWeight * fadeFrom_[channel] + (1.f - oldWeight) * sample;
            }
        }
        lastOutput_ = {destination[2 * count - 2], destination[2 * count - 1]};
        offset += count;
    }

    auto& block = blocks_[write_];
    if (frames && frames <= JsDsp::maxFrames && block.state.load(std::memory_order_acquire) == empty) {
        block.firstFrame = nextFrame_ + delayFrames_;
        block.frames = frames;
        std::memcpy(block.samples.data(), input, 2 * frames * sizeof(float));
        block.state.store(queued, std::memory_order_release);
        write_ = (write_ + 1) % blocks_.size();
    }
    nextFrame_ += frames;
    return changed;
}
}
