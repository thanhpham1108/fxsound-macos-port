// Buffered handoff between Core Audio and JavaScriptCore. AGPL-3.0-or-later.
#pragma once
#include "FxJsDsp.hpp"
#include <array>
#include <atomic>
#include <cstdint>
#include <thread>
#include <vector>

namespace fxport {
class BufferedDsp {
public:
    BufferedDsp(std::unique_ptr<JsDsp> dsp, size_t delayFrames);
    ~BufferedDsp();
    size_t process(const float* input, float* output, size_t frames) noexcept;

    // Read after stopping the I/O callback and joining the worker.
    void stop() noexcept;
    size_t fallbackFrames() const noexcept { return fallbackFrames_; }
    size_t failures() const noexcept { return failures_; }
    size_t nonFiniteBlocks() const noexcept { return nonFiniteBlocks_; }
    bool needsRestart() const noexcept { return needsRestart_.load(std::memory_order_relaxed); }

private:
    enum State { empty, queued, ready };
    struct Block {
        std::atomic<State> state{empty};
        uint64_t firstFrame = 0;
        size_t frames = 0;
        bool processed = false;
        std::array<float, JsDsp::maxFrames * 2> samples{};
    };
    void run() noexcept;

    std::unique_ptr<JsDsp> dsp_;
    const size_t delayFrames_;
    std::vector<float> dry_;
    std::array<Block, 16> blocks_;
    uint64_t nextFrame_ = 0;
    size_t write_ = 0, read_ = 0, dryIndex_ = 0;
    size_t fallbackFrames_ = 0, failures_ = 0, nonFiniteBlocks_ = 0;
    std::array<float, 2> lastOutput_{}, fadeFrom_{};
    size_t fadeRemaining_ = 0;
    bool wasWet_ = false;
    std::atomic<bool> needsRestart_{false}, running_{true};
    std::thread worker_;
};
}
