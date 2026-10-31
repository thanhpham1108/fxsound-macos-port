#!/bin/sh
set -eu
cd "$HOME/fxsound-port"
cmake_bin="$HOME/Library/Python/3.9/bin/cmake"
"$cmake_bin" --build macos/gui/build --target FxSoundMac -j 4
app="macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
codesign --force --deep --sign - "$app"
sh macos/gui/smoke_gui.sh
