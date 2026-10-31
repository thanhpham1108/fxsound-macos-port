#!/bin/sh
set -eu
app="$HOME/fxsound-port/macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
shot="/tmp/fxsound-mac-gui.png"
pkill -TERM -x "FxSound Mac" 2>/dev/null || true
rm -f "$shot"
open -n "$app" --args --snapshot "$shot"
sleep 6
pid=$(pgrep -n -x "FxSound Mac")
test -s "$shot"
echo "pid=$pid screenshot=$shot"
log show --last 1m --style compact --predicate 'process == "FxSound Mac"' 2>/dev/null | tail -n 30
