# FxSound Mac

An unofficial Apple Silicon port of FxSound that processes audio from other macOS applications. It uses a Core Audio process tap for system-audio routing, FxSound's open-source stereo DSP behavior, and a JUCE interface modeled on the Windows application.

## Current build

- macOS 14.2 or later, Apple Silicon
- Physical output selection and automatic restart after a real device or sample-rate change
- Clarity, Ambience, Surround Sound, Dynamic Boost, Bass Boost, Maximizer, and ten-band EQ
- Thirteen factory presets converted from the installed FxSound 1.2.16 preset files
- Source muting and own-process exclusion to prevent double playback and feedback

## Install

If Homebrew is available, install the app with:

```sh
brew install --cask thanhpham1108/fxsound/fxsound-mac
```

Homebrew currently supports macOS 15 or later. The FxSound app itself supports Apple Silicon Macs running macOS 14.2 or later; on macOS 14, download the ZIP from the [releases page](https://github.com/thanhpham1108/fxsound-macos-port/releases), unpack it, and move **FxSound Mac.app** into Applications.

Open **FxSound Mac** from Applications and allow **System Audio Recording** when macOS prompts. This development preview is not Apple-notarized; if Gatekeeper blocks the first launch, try opening it once and then choose **Open Anyway** in **System Settings > Privacy & Security**.

Upgrade or remove it with:

```sh
brew upgrade --cask fxsound-mac
brew uninstall --cask fxsound-mac
```

## Build from source

Build and package on a Mac with Xcode Command Line Tools and CMake:

```sh
sh macos/package.sh
open "macos/gui/build/FxSoundMac_artefacts/Release/FxSound Mac.app"
```

Allow **System Audio Recording** when macOS prompts. For a local install:

```sh
sh macos/install_local.sh
```

## Verification

The offline full-chain test matched FxSound's upstream golden-tested JavaScript reference sample for sample for the tested 44.1 kHz scenario. A live 48 kHz run processed a separate application's audio with zero bad layouts, DSP failures, measured callback overruns, or clipped samples. These results do not establish exact parity with the installed 1.2.16 Windows executable or all output hardware.

See [implementation status](docs/IMPLEMENTATION_STATUS.md), [source audit and signal path](docs/PORT_PLAN.md), and [macOS build details](macos/README.md).

For macOS 13, see the [unreleased Ventura preview](macos/VENTURA_PREVIEW.md) and [legacy audio routing investigation](docs/OLDER_MACOS_SUPPORT.md). The supported release still requires macOS 14.2 or later.

## Licensing

FxSound source and this derivative are AGPL-3.0-or-later. The app fetches JUCE 9.0.4 and uses its AGPL licensing option. The bundle includes the AGPL, JUCE, and Apple sample notices. REA was used for investigation and is not a runtime dependency.

FxSound is a trademark of FxSound LLC. This port is not an official FxSound LLC release.
