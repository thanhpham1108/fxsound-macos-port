// Lock-free stereo bridge between virtual capture and physical playback clocks.
// AGPL-3.0-or-later.
#pragma once
#include <array>
#include <atomic>
#include <algorithm>
#include <cstddef>
#include <cstdint>

namespace fxport {
class LegacyRing {
public:
    static constexpr size_t capacity = 16384;
    static constexpr size_t target = 1024;

    size_t push(const float* stereo, size_t frames) noexcept {
        auto write = write_.load(std::memory_order_relaxed);
        const auto read = read_.load(std::memory_order_acquire);
        const size_t available = capacity - std::min<size_t>(capacity, write - read);
        const size_t accepted = std::min(frames, available);
        for (size_t i = 0; i < accepted; ++i) {
            const size_t slot = ((write + i) % capacity) * 2;
            data_[slot] = stereo[i * 2];
            data_[slot + 1] = stereo[i * 2 + 1];
        }
        write_.store(write + accepted, std::memory_order_release);
        if (accepted != frames) overruns_.fetch_add(1, std::memory_order_relaxed);
        return accepted;
    }

    bool pull(float* stereo, size_t frames, double inputRate, double outputRate) noexcept {
        auto read = read_.load(std::memory_order_relaxed);
        const auto write = write_.load(std::memory_order_acquire);
        if (write - read < 2 || (!primed_ && write - read < target)) {
            std::fill_n(stereo, frames * 2, 0.f);
            underruns_.fetch_add(1, std::memory_order_relaxed);
            primed_ = false;
            fraction_ = 0;
            return false;
        }
        primed_ = true;
        const double fillError = static_cast<double>(write - read) - target;
        const double correction = std::clamp(fillError / 100000.0, -0.005, 0.005);
        const double step = inputRate / outputRate + correction;
        size_t i = 0;
        for (; i < frames; ++i) {
            if (write - read < 2) break;
            const size_t a = (read % capacity) * 2;
            const size_t b = ((read + 1) % capacity) * 2;
            stereo[2 * i] = static_cast<float>(data_[a] + (data_[b] - data_[a]) * fraction_);
            stereo[2 * i + 1] = static_cast<float>(data_[a + 1] + (data_[b + 1] - data_[a + 1]) * fraction_);
            fraction_ += step;
            const auto advance = static_cast<uint64_t>(fraction_);
            fraction_ -= advance;
            read += advance;
        }
        read_.store(read, std::memory_order_release);
        if (i < frames) {
            std::fill_n(stereo + i * 2, (frames - i) * 2, 0.f);
            underruns_.fetch_add(1, std::memory_order_relaxed);
            primed_ = false;
            fraction_ = 0;
            return false;
        }
        return true;
    }

    uint64_t underruns() const noexcept { return underruns_.load(); }
    uint64_t overruns() const noexcept { return overruns_.load(); }
private:
    std::array<float, capacity * 2> data_{};
    std::atomic<uint64_t> read_{0}, write_{0}, underruns_{0}, overruns_{0};
    double fraction_ = 0;
    bool primed_ = false;
};
}
