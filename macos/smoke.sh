#!/bin/sh
set -eu
cd "$HOME/fxsound-port"
open -n --stderr /tmp/fxtap-smoke.log -a "$HOME/fxsound-port/macos/FxTap.app" --args --run
sleep 2
python3 - <<'PY'
import math, struct, wave
with wave.open('/tmp/fxsound-tap-tone.wav', 'wb') as out:
    out.setnchannels(2)
    out.setsampwidth(2)
    out.setframerate(48000)
    out.writeframes(b''.join(struct.pack('<hh', int(4000*math.sin(2*math.pi*1000*i/48000)), int(4000*math.sin(2*math.pi*1000*i/48000))) for i in range(3*48000)))
PY
afplay /tmp/fxsound-tap-tone.wav
sleep 1
pkill -TERM -x FxTap || true
sleep 1
cat /tmp/fxtap-smoke.log
