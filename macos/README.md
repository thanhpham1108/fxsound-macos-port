# FxSound Mac

This macOS 14.2+ Apple Silicon app captures audio from other applications on the selected output, applies FxSound's stereo DSP chain, and plays the processed result once through the same physical device. The JUCE interface follows FxSound's Windows layout and includes its factory presets, five effects, ten-band EQ, power control, and device selection.

Build with Xcode Command Line Tools and CMake:

```sh
cd ~/fxsound-port
sh macos/package.sh
open "macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
```

Allow **System Audio Recording** when macOS asks. Copy the app to `/Applications` for normal use. The app releases its private tap and aggregate on shutdown. Apps playing to other output devices remain outside the selected device's tap.

The command-line `FxTap` target remains available for routing diagnostics. `sh macos/build.sh` builds it, and `--list-devices`, `--list-presets`, `--preset`, `--effect`, `--eq-band`, and `--bypass` support focused tests.

The latest full-chain GUI run at 48 kHz processed audio from a separate app with 836 callbacks, zero bad layouts, zero DSP failures, zero callback overruns, and zero clipped samples. Offline output with all five effects enabled matched the upstream reference sample for sample. See `docs/IMPLEMENTATION_STATUS.md` for precise limits.

The package is ad hoc signed for local development. Public distribution still needs Developer ID signing and notarization. The bundle includes the AGPL, JUCE, and Apple sample notices. No FxSound font files are bundled.
