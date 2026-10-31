# Portable FxSound DSP slice

This is a native C++17 processor for interleaved stereo float32 PCM. `FxEq.cpp` ports the parameter and sample equations of FxSound's `filtCalcParametric` and stereo `sosProcessBuffer` at upstream commit `4383180e02ff435d191f71220e8da41f9fa06951`. It does not yet port the complete GraphicEq settings, volume leveling, or the five enhancement effects. `--bypass` is transparent dry bypass, which differs from some FxSound power-off configurations.

Build on Apple Silicon with Xcode Command Line Tools:

```sh
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build native/build --config Release
native/build/fxwav input.wav output.wav --band 1000 6 1
native/build/fxwav input.wav bypass.wav --bypass
node native/verify.js
```

`fxwav` accepts interleaved stereo PCM16 or IEEE float32 RIFF WAV. It writes float32 WAV and prints peak amplitude plus the count of samples over full scale. This is offline file processing; the same EQ slice is also connected to the macOS Core Audio prototype in `macos/`.

A 0.8-amplitude 1 kHz sine with +6 dB EQ produced 4,984 samples above full scale at 44.1 kHz and 5,188 at 48 kHz in a 0.1-second stereo test. The original Maximizer has not been ported, so this prototype can clip on loud input. Keep playback volume modest until the Maximizer and output limiting are integrated and compared.

The code is AGPL-3.0-or-later, derived from FxSound's AGPL-3.0-or-later DSP source. See root `LICENSE`. No runtime third-party library is needed for this slice.

On Windows, the two translation units also compiled as `aarch64-macos` objects with Zig 0.13.0. This checks portable C++ compilation, not an Apple SDK link, an Apple Silicon run, or capture from other apps.
