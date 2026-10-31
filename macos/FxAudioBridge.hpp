// GUI-facing Core Audio engine interface. AGPL-3.0-or-later.
#pragma once
#include "FxJsDsp.hpp"
#include <string>
#include <vector>

namespace fxport {
struct OutputDevice { std::string uid, name; bool isDefault=false; };
using AudioHandle = void*;
std::vector<OutputDevice> outputDevices();
AudioHandle startAudio(const Settings& settings, const std::string& deviceUID, std::string& error);
void stopAudio(AudioHandle handle);
bool outputChanged(AudioHandle handle);
}
