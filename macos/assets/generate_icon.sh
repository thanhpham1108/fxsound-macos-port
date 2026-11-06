#!/bin/sh
set -eu
assets=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
swift "$assets/generate_icon.swift" "$assets/FxSoundMac.png"
iconset=$(mktemp -d "${TMPDIR:-/tmp}/fxsound-icon.XXXXXX")
trap 'rm -rf "$iconset"' EXIT HUP INT TERM
mkdir "$iconset/FxSoundMac.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$assets/FxSoundMac.png" --out "$iconset/FxSoundMac.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$assets/FxSoundMac.png" --out "$iconset/FxSoundMac.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset/FxSoundMac.iconset" -o "$assets/FxSoundMac.icns"
