#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
app="macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="dist/FxSound-Mac-$version-arm64.zip"
shasum -a 256 "$archive"
unzip -tq "$archive"
codesign --verify --deep --strict --verbose=2 "$app"
test -f "$app/Contents/Resources/AGPL-3.0.txt"
test -f "$app/Contents/Resources/JUCE-LICENSE.md"
test -f "$app/Contents/Resources/APPLE_SAMPLE_LICENSE.txt"
test -f "$app/Contents/Resources/presets/factory.json"
test -f "$app/Contents/Resources/dsp/stream.js"
file "$app/Contents/MacOS/FxSound Mac"
echo "package verification passed"
