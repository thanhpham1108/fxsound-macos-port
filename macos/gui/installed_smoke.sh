#!/bin/sh
set -eu
app="/Applications/FxSound Mac.app"
test -d "$app"
test -f "$app/Contents/Resources/presets/factory.json"
test -f "$app/Contents/Resources/dsp/stream.js"
open "$app"
sleep 4
pid=$(pgrep -n -x "FxSound Mac")
echo "installed app running pid=$pid"
