#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_app="$repo/macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
target_app="/Applications/FxSound Mac.app"
test -d "$source_app"
if test -e "$target_app"; then
    osascript -e 'tell application id "dev.fxsound.port.app" to quit' 2>/dev/null || true
    sleep 1
    backup="$HOME/.Trash/FxSound Mac previous $(date +%Y%m%d-%H%M%S).app"
    mv "$target_app" "$backup"
    echo "Previous app moved to $backup"
fi
ditto "$source_app" "$target_app"
open "$target_app"
echo "$target_app"
