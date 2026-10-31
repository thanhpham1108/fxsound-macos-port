// Portable numeric factory presets extracted from FxSound .fac files.
// AGPL-3.0-or-later.
#pragma once
#include "FxJsDsp.hpp"
#include <string>
#include <vector>

namespace fxport {
struct NamedPreset {
    std::string name;
    Settings settings;
};
std::vector<NamedPreset> loadFactoryPresets(const std::string& resourceDirectory);
}
