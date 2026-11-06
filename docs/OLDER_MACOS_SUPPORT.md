# Older macOS support investigation (November 2026)

## Decision

Target macOS 13 Ventura as the first legacy build. A separate BlackHole-based preview now compiles, but keep the supported release's 14.2 minimum until live system-audio processing works on Ventura. The existing FxSound DSP and JUCE interface are shared; changing `LSMinimumSystemVersion` alone cannot enable system-audio processing.

## Evidence

- `macos/FxTap.mm` creates a `CATapDescription` and calls `AudioHardwareCreateProcessTap`, then routes its muted source through a private aggregate device. Apple's Core Audio tap sample requires macOS 14.2 or later: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- The minimum is declared in `macos/gui/CMakeLists.txt`, `macos/gui/Info.plist`, `macos/build.sh`, and `macos/Info.plist`.
- The JavaScriptCore DSP in `macos/FxJsDsp.mm` and `macos/dsp/` and the preset handling in `macos/FxPreset.mm` do not depend on process taps. A legacy backend can call the same DSP bridge.
- BlackHole is an open-source virtual Core Audio driver supporting macOS 10.10 and later, including Apple Silicon. Its 2-channel version offers a system-output-to-app-input route: https://github.com/ExistentialAudio/BlackHole . Its installer is a separate system component; do not install it without the Mac owner's knowledge. Review its GPL-3.0 license alongside this app's AGPL-3.0 license before bundling or modifying it.
- ScreenCaptureKit can capture audio, but the current app also needs to suppress original playback and send processed output once. The verified pre-14.2 approach is a virtual output device, not simply lowering the deployment target.

## Legacy backend outline

1. Detect the OS at launch. Keep the existing Core Audio process-tap engine on macOS 14.2+.
2. On Ventura, require an installed stereo virtual loopback device such as BlackHole 2ch. Set that device as the macOS output only after presenting the routing change clearly. Remember the prior default output and restore it on normal quit and recoverable startup failure. Never overwrite a device change the user makes while the app is running.
3. Open the virtual device's input stream, process its stereo float samples with the existing `fxport::JsDsp`, and play once to the chosen physical output. Do **not** use a Multi-Output device containing speakers/headphones: its dry path would play alongside the processed path.
4. Keep the capture device and physical output out of the same feedback path. Handle clock drift between devices with a bounded ring buffer and resampler, report underruns/overruns, and fall back to safe routing when the app crashes or output disappears.
5. Test bypass, effects, source muting, latency, clipping, hotplug, sleep/wake, and restore-on-exit on an actual macOS 13 host. Only then lower the legacy build's minimum and publish a separate artifact with clear installation instructions. Consider macOS 12 after Ventura is stable.

## Current limit

No Ventura or Monterey machine is connected for runtime validation, and BlackHole is not installed on the working Mac. The preview has only been compiled and tested for missing-driver behavior on a newer Mac. No release currently claims support below macOS 14.2. See [Ventura preview status](../macos/VENTURA_PREVIEW.md).
