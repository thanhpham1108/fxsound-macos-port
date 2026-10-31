#!/bin/sh
set -eu
cd "$HOME/fxsound-port"
archive="dist/FxSound-Mac-0.1.0-arm64.zip"
app="macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
shasum -a 256 "$archive"
codesign --verify --deep --strict --verbose=2 "$app"
test -f "$app/Contents/Resources/AGPL-3.0.txt"
test -f "$app/Contents/Resources/JUCE-LICENSE.md"
test -f "$app/Contents/Resources/APPLE_SAMPLE_LICENSE.txt"
test -f "$app/Contents/Resources/presets/factory.json"
test -f "$app/Contents/Resources/dsp/stream.js"
file "$app/Contents/MacOS/FxSound Mac"
echo "package verification passed"
