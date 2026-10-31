// SPDX-License-Identifier: AGPL-3.0-or-later
#pragma once
#include <cstddef>
#include <vector>

namespace fxport {
struct Band { float frequencyHz; float gainDb; float q; };
// Initial portable slice: FxSound's original SOS/parametric EQ kernel.
// Does NOT implement the five enhancement effects or preset/UI mappings.
class Processor {
public:
    explicit Processor(float sampleRate, const std::vector<Band>& bands = {}, float masterGainDb = 0);
    ~Processor();
    Processor(const Processor&) = delete;
    Processor& operator=(const Processor&) = delete;
    // Interleaved float32 stereo; no allocation, locks or I/O. Fully dry bypass
    // leaves samples/state untouched (different from FxSound power-off+EQ-on).
    bool process(float* samples, std::size_t frames, bool dryBypass = false) noexcept;
    bool reset() noexcept;
private:
    struct State;
    State* handle_ = nullptr;
    float sampleRate_;
};
}
