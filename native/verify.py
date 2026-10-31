"""Offline PCM verification for the portable FxSound EQ slice (AGPL-3.0-or-later)."""
import math
import pathlib
import struct
import subprocess
import sys
import tempfile

exe = pathlib.Path(__file__).with_name("fxwav.exe" if sys.platform == "win32" else "fxwav")

def wave(samples, rate):
    pcm = struct.pack("<%sf" % len(samples), *samples)
    fmt = struct.pack("<HHIIHH", 3, 2, rate, rate * 8, 8, 32)
    return b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt " + struct.pack("<I", 16) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm

with tempfile.TemporaryDirectory(prefix="fxwav-") as tmp:
    folder = pathlib.Path(tmp)
    for rate in (44100, 48000):
        samples = [0.1 * math.sin(2 * math.pi * 1000 * (i // 2) / rate) for i in range(2 * rate // 10)]
        source = folder / "in.wav"
        source.write_bytes(wave(samples, rate))
        original = struct.unpack("<%sf" % len(samples), source.read_bytes()[44:])
        def run(name, *args):
            dest = folder / (name + ".wav")
            subprocess.run([str(exe), str(source), str(dest), *args], check=True, capture_output=True)
            return struct.unpack("<%sf" % len(samples), dest.read_bytes()[44:])
        assert run("bypass", "--bypass", "--band", "1000", "6", "1") == original
        assert run("flat") == original
        effect = run("effect", "--band", "1000", "6", "1")
        assert all(math.isfinite(x) for x in effect)
        input_energy = sum(x*x for x in original)
        output_energy = sum(x*x for x in effect)
        assert output_energy > input_energy * 1.5
        print(f"PASS {rate} Hz: bypass, flat, finite output, 1 kHz boost")
        hot = [0.8 * math.sin(2 * math.pi * 1000 * (i // 2) / rate) for i in range(2 * rate // 10)]
        source.write_bytes(wave(hot, rate))
        hot_effect = run("hot", "--band", "1000", "6", "1")
        above = sum(abs(x) > 1 for x in hot_effect)
        print(f"OBSERVED {rate} Hz: {above} samples above full scale with loud input and +6 dB EQ")
