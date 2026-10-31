/* FxSound macOS streaming adapter. AGPL-3.0-or-later.
 * The processing stages are the FxSound DSP tutorial's golden-tested ports.
 * Keep their state between buffers, as the Windows engine does.
 */
(function (root) {
  "use strict";
  var ns = root.FxDsp;
  ns.createStream = function (sampleRate, settings) {
    var eq = new ns.sos.EqStage(sampleRate, settings);
    var params = ns.controls.effectParams(settings, sampleRate);
    var play = new ns.Play(sampleRate, params);
    return {
      process: function (buffer, frames) {
        if (settings.power) {
          if (settings.eq) eq.process(buffer, frames);
          play.process(buffer, frames, params);
        } else if (settings.eq) {
          var gain = eq.masterGain;
          for (var i = 0; i < frames * 2; ++i) buffer[i] = Math.fround(buffer[i] * gain);
        }
        // The tutorial records these for plots. Live processing has no plot consumer.
        eq.trace.length = 0;
        play.maxi.trace.length = 0;
      }
    };
  };
})(typeof globalThis !== "undefined" ? globalThis : window);
