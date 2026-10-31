// Offline FxSound full-chain verifier. AGPL-3.0-or-later.
// Input and output are headerless interleaved stereo float32, like the upstream golden harness.
#include "FxJsDsp.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 5) {
        std::cerr << "usage: fxfull in.f32 out.f32 sampleRate dspResourceDir [key=value ...]\n";
        return 2;
    }
    try {
        fxport::Settings settings;
        size_t block = 441;
        for (int i = 5; i < argc; ++i) {
            std::string arg = argv[i];
            const auto pos = arg.find('=');
            if (pos == std::string::npos) throw std::runtime_error("expected key=value");
            const std::string key = arg.substr(0, pos);
            const float value = std::stof(arg.substr(pos + 1));
            if (key == "power") settings.power = value != 0;
            else if (key == "eq") settings.eq = value != 0;
            else if (key == "fid") settings.fidelity = value;
            else if (key == "amb") settings.ambience = value;
            else if (key == "sur") settings.surround = value;
            else if (key == "dyn") settings.dynamicBoost = value;
            else if (key == "bass") settings.bass = value;
            else if (key == "mg") settings.masterGainDb = value;
            else if (key == "bal") settings.balanceDb = value;
            else if (key == "norm") settings.normalizationDb = value;
            else if (key == "vl") settings.volumeLeveling = value;
            else if (key == "q") settings.qMultiplier = value;
            else if (key == "frames") block = static_cast<size_t>(value);
            else if (key.size() >= 2 && key[0] == 'g') {
                const int band = std::stoi(key.substr(1));
                if (band < 0 || band >= 10) throw std::runtime_error("EQ band must be 0..9");
                settings.gains[band] = value;
            } else throw std::runtime_error("unknown setting: " + key);
        }
        if (block == 0 || block > 8192) throw std::runtime_error("frames must be 1..8192");
        std::ifstream in(argv[1], std::ios::binary);
        if (!in) throw std::runtime_error("cannot open input");
        std::vector<char> bytes{std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
        if (bytes.empty() || bytes.size() % 8) throw std::runtime_error("input must be stereo float32");
        std::vector<float> samples(bytes.size() / 4);
        std::memcpy(samples.data(), bytes.data(), bytes.size());
        fxport::JsDsp dsp;
        if (!dsp.start(std::stod(argv[3]), settings, argv[4])) throw std::runtime_error(dsp.error());
        for (size_t i = 0; i < samples.size() / 2; i += block) {
            const size_t n = std::min(block, samples.size() / 2 - i);
            if (!dsp.process(samples.data() + 2 * i, n)) throw std::runtime_error("DSP processing failed");
        }
        float peak = 0;
        size_t clipped = 0;
        for (float sample : samples) {
            if (!std::isfinite(sample)) throw std::runtime_error("nonfinite output");
            peak = std::max(peak, std::abs(sample));
            if (std::abs(sample) > 1.f) ++clipped;
        }
        std::ofstream out(argv[2], std::ios::binary);
        if (!out) throw std::runtime_error("cannot open output");
        out.write(reinterpret_cast<const char*>(samples.data()), samples.size() * sizeof(float));
        if (!out) throw std::runtime_error("write failed");
        std::cout << "frames=" << samples.size() / 2 << " peak=" << peak << " samples_above_full_scale=" << clipped << '\n';
    } catch (const std::exception& ex) {
        std::cerr << ex.what() << '\n';
        return 1;
    }
}
