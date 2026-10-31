#!/bin/sh
set -u
app="$HOME/fxsound-port/macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
echo "processes"
pgrep -x "FxSound Mac" || true
echo "signature"
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 || true
echo "gatekeeper"
spctl -a -vv "$app" 2>&1 || true
echo "recent-log"
log show --last 3m --style compact --predicate 'process == "FxSound Mac"' 2>/dev/null | tail -n 50
