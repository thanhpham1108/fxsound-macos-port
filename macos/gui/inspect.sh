#!/bin/sh
set -eu
app="$HOME/fxsound-port/macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
plutil -p "$app/Contents/Info.plist" | grep -E 'CFBundleExecutable|CFBundleIdentifier|NSAudioCapture|LSMinimum'
ls -l "$app/Contents/MacOS"
