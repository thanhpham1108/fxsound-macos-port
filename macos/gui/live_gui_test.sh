#!/bin/sh
set -eu
app="$HOME/fxsound-port/macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
tone="/tmp/fxsound-tap-tone.wav"
shot="/tmp/fxsound-mac-gui.png"
pkill -TERM -x "FxSound Mac" 2>/dev/null || true
rm -f "$shot"
open -n "$app" --args --snapshot "$shot"
sleep 5
pid=$(pgrep -n -x "FxSound Mac")
afplay "$tone"
sleep 1
osascript -e 'tell application id "dev.fxsound.port.app" to quit'
sleep 2
log show --last 2m --style compact --predicate 'process == "FxSound Mac"' 2>/dev/null | \
    grep -E 'Running at|callbacks=|overload|skipping cycle' | tail -n 20
