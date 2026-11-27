// Exercise a stalled DSP worker without involving the audio device.
#include "FxBufferedDsp.hpp"
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cstdio>
#include <limits>

namespace {
std::atomic<bool> stall{true};
std::atomic<unsigned> entered{0}, completed{0};

template <typename Predicate>
void waitFor(Predicate condition) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (!condition()) {
        assert(std::chrono::steady_clock::now() < deadline);
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}
}

namespace fxport {
struct JsDsp::Impl {};
JsDsp::JsDsp() = default;
JsDsp::~JsDsp() = default;
bool JsDsp::process(float* samples, size_t frames) noexcept {
    ++entered;
    while (stall.load()) std::this_thread::yield();
    if (samples[0] == -0.9f) samples[0] = std::numeric_limits<float>::quiet_NaN();
    for (size_t i = 0; i < frames * 2; ++i) samples[i] *= 0.5f;
    ++completed;
    return true;
}
}

int main() {
    auto buffered = std::make_unique<fxport::BufferedDsp>(std::make_unique<fxport::JsDsp>(), 128);
    std::array<float, 192> input{}, output{};
    const auto process = [&](size_t frames, float value) {
        for (size_t i = 0; i < frames; ++i) {
            input[2 * i] = value;
            input[2 * i + 1] = -value;
        }
        buffered->process(input.data(), output.data(), frames);
    };
    const auto check = [&](size_t start, size_t count, float value) {
        for (size_t i = start; i < start + count; ++i) {
            assert(output[2 * i] == value && output[2 * i + 1] == -value);
        }
    };
    for (unsigned i = 0; i < 20; ++i) {
        process(64, float(i + 1) / 32);
        if (i == 0) waitFor([] { return entered.load() == 1; });
        check(0, 64, i < 2 ? 0.f : float(i - 1) / 32);
    }
    stall.store(false);
    waitFor([] { return completed.load() == 16; });

    process(96, 0.6f);
    check(0, 64, 19.f / 32);
    check(64, 32, 20.f / 32);
    waitFor([] { return entered.load() >= 17; });
    process(32, 0.4f);
    check(0, 32, 20.f / 32);
    // Entry to the second job confirms the first result is published.
    waitFor([] { return entered.load() >= 18; });
    process(96, -0.9f);
    check(32, 64, 0.3f);
    waitFor([&] { return buffered->needsRestart(); });
    process(32, 0.2f);
    check(0, 32, 0.2f);
    process(96, 0.1f);
    check(32, 64, -0.9f);
    buffered->stop();
    assert(buffered->nonFiniteBlocks() == 1);
    assert(buffered->fallbackFrames() == 20 * 64 + 96);
    std::puts("BufferedDsp: delayed dry playback, queue saturation, recovery and non-finite fallback passed");
}
