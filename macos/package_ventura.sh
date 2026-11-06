#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
cmake_bin=${CMAKE_BIN:-cmake}
if ! command -v "$cmake_bin" >/dev/null 2>&1; then
    cmake_bin="$HOME/Library/Python/3.9/bin/cmake"
fi
"$cmake_bin" -S macos/gui -B macos/gui/build-ventura -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DFXSOUND_VENTURA=ON
"$cmake_bin" --build macos/gui/build-ventura --target FxSoundMac -j 4
app="$repo/macos/gui/build-ventura/FxSoundMac_artefacts/Release/FxSound Mac Ventura.app"
codesign --force --sign - "$app/Contents/MacOS/FxRouteGuard"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$repo/dist"
archive="$repo/dist/FxSound-Mac-Ventura-preview-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
echo "$app"
echo "$archive"
