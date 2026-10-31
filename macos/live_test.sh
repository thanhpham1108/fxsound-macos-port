#!/bin/sh
# Live separate-application routing check; run in a logged-in Mac desktop session.
set -eu
app="$HOME/fxsound-port/macos/FxTap.app"
tone="/tmp/fxsound-tap-tone.wav"
test -f "$tone"
open -n -a "$app" --args --run --effect clarity 6 --effect ambience 3 \
    --effect surround 3 --effect dynamic 7 --effect bass 2 --eq-band 5 6
sleep 3
pid=$(pgrep -n -x FxTap)
afplay "$tone"
sleep 1
kill -TERM "$pid"
sleep 2
log show --last 2m --style compact --predicate 'process == "FxTap"' 2>/dev/null | tail -n 35
