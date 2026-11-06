# macOS 13 Ventura preview

This is an **unreleased** Apple Silicon build for macOS 13 only. The supported FxSound Mac app on macOS 14.2 or later continues to use Core Audio process taps and needs no BlackHole driver. The Ventura edition refuses to start routing on macOS 14 or later.

## Build

On a Mac with Xcode Command Line Tools and CMake:

```sh
sh macos/package_ventura.sh
```

The script builds a separate `FxSound Mac Ventura.app` with a 13.0 deployment target and writes `dist/FxSound-Mac-Ventura-preview-arm64.zip`. It does not install the app or the driver. The binary has a different bundle ID from the supported edition, so testing does not replace that edition.

## Ventura setup

Install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) from its publisher, then open FxSound Mac Ventura and choose **Set Up Audio** from its menu. Confirm the system-output switch when prompted. FxSound sends system output to BlackHole, reads its stereo input, applies the existing DSP, and plays the processed result through the chosen physical output. The UI excludes BlackHole from the physical-output selector. Do not create a Multi-Output device containing both BlackHole and speakers: that would play an unprocessed copy.

When FxSound quits normally, it restores the previous default output if BlackHole is still selected. The bundled `FxRouteGuard` helper also attempts restoration if the app exits unexpectedly. If sound is absent after a crash, select your speakers or headphones in **System Settings → Sound → Output**. The helper is not a persistent login item. If you change the Mac's output yourself while FxSound is active, FxSound pauses routing and does not switch it back without another confirmation.

BlackHole is installed and licensed independently under GPL-3.0. FxSound does not bundle it. See its [license and installation instructions](https://github.com/ExistentialAudio/BlackHole).

## Validation gate

The Ventura-targeted app and helper compile on an Apple Silicon Mac running a newer macOS version. The ring buffer passed basic buffering, 48 kHz to 47,999.8 Hz drift, underrun, and overrun checks. The test Mac has no BlackHole installed, and **no live macOS 13 routing, crash recovery, device-change, or long-playback test has been performed**. Do not distribute this as a supported Ventura release until those tests pass on a real Ventura host. The supported public ZIP and Homebrew Cask remain macOS 14.2+.
