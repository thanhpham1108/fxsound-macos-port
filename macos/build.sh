#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
mkdir -p macos/FxTap.app/Contents/MacOS macos/FxTap.app/Contents/Resources
clang++ -std=c++17 -O2 -fobjc-arc -mmacosx-version-min=14.2 \
  -I native/include macos/FxTap.mm macos/FxJsDsp.mm macos/FxPreset.mm native/FxEq.cpp \
  -framework CoreAudio -framework Foundation -framework JavaScriptCore \
  -o macos/FxTap.app/Contents/MacOS/FxTap
cp macos/Info.plist macos/FxTap.app/Contents/Info.plist
cp LICENSE macos/FxTap.app/Contents/Resources/AGPL-3.0.txt
cp macos/APPLE_SAMPLE_LICENSE.txt macos/FxTap.app/Contents/Resources/APPLE_SAMPLE_LICENSE.txt
mkdir -p macos/FxTap.app/Contents/Resources/dsp
cp macos/dsp/*.js macos/FxTap.app/Contents/Resources/dsp/
mkdir -p macos/FxTap.app/Contents/Resources/presets
cp macos/presets/factory.json macos/FxTap.app/Contents/Resources/presets/
codesign --force --deep --sign - macos/FxTap.app
