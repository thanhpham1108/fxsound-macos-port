#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
cmake_bin=${CMAKE_BIN:-cmake}
if ! command -v "$cmake_bin" >/dev/null 2>&1; then
    cmake_bin="$HOME/Library/Python/3.9/bin/cmake"
fi
if ! test -x "$cmake_bin" && ! command -v "$cmake_bin" >/dev/null 2>&1; then
    echo "CMake is required. Set CMAKE_BIN to its path." >&2
    exit 1
fi
"$cmake_bin" -S macos/gui -B macos/gui/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
"$cmake_bin" --build macos/gui/build --target FxSoundMac -j 4
app="$repo/macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$repo/dist"
archive="$repo/dist/FxSound-Mac-0.1.1-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
echo "$app"
echo "$archive"
