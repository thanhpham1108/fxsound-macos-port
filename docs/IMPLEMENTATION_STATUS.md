# FxSound Mac implementation status

## Working and verified

- Apple Silicon application bundle targeting macOS 14.2 or later.
- System audio capture through a device-scoped Core Audio process tap, source muting, private aggregate output, and own-process exclusion.
- JUCE interface with the Windows layout, factory preset and output selectors, five effect sliders, ten EQ gain controls, ten adjustable EQ frequencies, and power control.
- Thirteen factory presets converted from the installed FxSound 1.2.16 `.fac` files. Voice reproduces the values and frequencies shown in the supplied Windows screenshot.
- Full FxSound stereo chain: graphic EQ, Clarity, Ambience, Surround Sound, Bass Boost, Dynamic Boost, and Maximizer. The full chain currently runs through JavaScriptCore using FxSound's golden-tested JavaScript DSP port; the earlier C++ EQ slice remains available in `native/`.
- Offline 44.1 kHz full-chain output matched the independent upstream tutorial pipeline sample for sample (`maxError=0`) with all five effects enabled.
- Live 48 kHz GUI test captured and modified audio from a separate `afplay` process. The final packaged-source run reported 836 callbacks, zero bad layouts, zero DSP failures, zero measured callback overruns, and zero samples above full scale; its slowest measured callback was 8.399 ms.
- In v0.1.1, the red window button quits the app. A continuous 150-second 48 kHz live test reported 14,334 callbacks, zero bad layouts, DSP failures, non-finite blocks, measured callback overruns, or clipped samples. The listener reported no audible crackling during this test. Three-minute offline DSP state tests passed for Music, Voice, and General.
- In v0.1.2, the output selector follows macOS's default output until the user chooses a different one. With 3.5 mm headphones selected as the default, Core Audio enumerated `External Headphones`, the tap processed headphone audio with no DSP failures or clipping in the short test, and the listener confirmed audible preset and power changes. Unplugging and replugging switched the UI between speakers and headphones; the device handoff briefly interrupted the tap as it restarted.
- Device and sample-rate change listeners validate the current physical device before restarting. The private tap uses `CATapMuted` to suppress the original playback route and excludes this app to avoid feedback.

## Known limits

- Exact parity with the installed FxSound 1.2.16 binary is not established. The audited source project reports 1.2.15, and the full DSP comparison uses the upstream golden-tested port of that source.
- The tap processes apps routed to the selected physical output. It does not capture applications routed to another output.
- Only interleaved stereo float32 output at 44.1 or 48 kHz is accepted. Bluetooth, USB hot unplug, multichannel output, sleep/wake, and sustained playback on other hardware still need testing. The 150-second test does not prove all videos and presets will remain glitch-free.
- Control changes rebuild the tap and DSP, producing a short interruption. Preset editing/import/export and spectrum animation are not implemented yet.
- The development package is ad hoc signed. Public distribution requires a Developer ID certificate and notarization; Gatekeeper rejects the current development signature when treated as a downloaded public release.
- JUCE 9.0.4 is fetched during the build and used under its AGPL option. The app bundle includes FxSound/port AGPL, JUCE, and Apple sample notices.
