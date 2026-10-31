// FxSound DSP tutorial bridge. AGPL-3.0-or-later.
#pragma once
#include <array>
#include <cstddef>
#include <memory>
#include <string>

namespace fxport {
struct Settings {
    bool power = true;
    bool eq = true;
    std::array<float, 10> gains{};
    std::array<float, 10> freqs{};
    float qMultiplier = 1.f, masterGainDb = 0.f, balanceDb = 0.f;
    float normalizationDb = 0.f, volumeLeveling = 0.f;
    float fidelity = 0.f, ambience = 0.f, surround = 0.f;
    float dynamicBoost = 0.f, bass = 0.f;
};

class JsDsp {
public:
    JsDsp();
    ~JsDsp();
    JsDsp(const JsDsp&) = delete;
    JsDsp& operator=(const JsDsp&) = delete;
    bool start(double sampleRate, const Settings& settings, const std::string& resourceDirectory);
    bool process(float* interleavedStereo, size_t frames) noexcept;
    bool warmup(size_t blocks) noexcept;
    const std::string& error() const noexcept { return error_; }
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
    std::string error_;
};
}
