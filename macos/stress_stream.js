// Exercise persistent DSP state beyond the reported 1-2 minute failure window.
// Usage: node macos/stress_stream.js [seconds] [preset]
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const seconds = Number(process.argv[2] || 180);
const name = process.argv[3] || 'Music';
if (!Number.isFinite(seconds) || seconds <= 0) throw Error('invalid duration');
for (const file of ['sos.js', 'controls.js', 'aural.js', 'lex.js', 'wide.js',
                    'maximizer.js', 'play.js', 'stream.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'dsp', file), 'utf8'), {filename: file});
}
const presets = JSON.parse(fs.readFileSync(path.join(__dirname, 'presets', 'factory.json')));
const preset = presets.find(p => p.name === name);
const settings = preset && {qMultiplier: 1, masterGainDb: 0, balanceDb: 0,
  normalizationDb: 0, volumeLeveling: 0, ...preset};
if (!settings) throw Error(`unknown preset ${name}`);
const rate = 48000, block = 512, total = Math.ceil(seconds * rate / block);
const stream = FxDsp.createStream(rate, settings);
const samples = new Float32Array(block * 2);
let peak = 0, nonFinite = 0, clipped = 0;
for (let cycle = 0; cycle < total; ++cycle) {
  for (let i = 0; i < block; ++i) {
    const frame = cycle * block + i;
    const amplitude = frame % (rate * 13) < rate * 2 ? 0.02 : 0.35;
    samples[2 * i] = amplitude * (Math.sin(2 * Math.PI * 440 * frame / rate)
      + 0.3 * Math.sin(2 * Math.PI * 1771 * frame / rate));
    samples[2 * i + 1] = amplitude * (Math.sin(2 * Math.PI * 660 * frame / rate)
      + 0.3 * Math.sin(2 * Math.PI * 2141 * frame / rate));
  }
  stream.process(samples, block);
  for (const sample of samples) {
    if (!Number.isFinite(sample)) ++nonFinite;
    else {
      peak = Math.max(peak, Math.abs(sample));
      if (Math.abs(sample) > 1) ++clipped;
    }
  }
}
console.log(JSON.stringify({preset: name, seconds, peak, nonFinite, clipped}));
if (nonFinite || clipped) process.exitCode = 1;
