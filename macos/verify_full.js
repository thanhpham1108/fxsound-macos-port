// Compare macOS streaming output against FxSound's independent tutorial pipeline.
// Usage: node macos/verify_full.js input.f32 actual.f32
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const root = path.join(__dirname, 'dsp');
for (const file of ['sos.js', 'controls.js', 'aural.js', 'lex.js', 'wide.js', 'maximizer.js', 'play.js', 'pipeline.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(root, file), 'utf8'), { filename: file });
}
if (process.argv.length !== 4) throw Error('usage: node macos/verify_full.js input.f32 actual.f32');
function floats(filename) {
  const bytes = fs.readFileSync(filename);
  if (bytes.byteLength % 8) throw Error('expected interleaved stereo float32');
  return new Float32Array(bytes.buffer, bytes.byteOffset, bytes.byteLength / 4);
}
const input = floats(process.argv[2]);
const actual = floats(process.argv[3]);
const settings = { power: true, eq: true, gains: [0, 0, 0, 0, 0, 6, 0, 0, 0, 0],
  qMultiplier: 1, masterGainDb: 0, balanceDb: 0, normalizationDb: 0, volumeLeveling: 0,
  fidelity: 6, ambience: 3, surround: 3, dynamicBoost: 7, bass: 2 };
const expected = FxDsp.pipeline.render(input, settings, {}, { sampleRate: 44100, bufferFrames: 441 }).output;
if (actual.length !== expected.length) throw Error('length mismatch');
let maxError = 0, rmsError = 0, nonFinite = 0, clipped = 0;
for (let i = 0; i < actual.length; ++i) {
  const x = actual[i], y = expected[i];
  if (!Number.isFinite(x)) ++nonFinite;
  if (Math.abs(x) > 1) ++clipped;
  const d = x - y;
  maxError = Math.max(maxError, Math.abs(d));
  rmsError += d * d;
}
rmsError = Math.sqrt(rmsError / actual.length);
console.log(JSON.stringify({ samples: actual.length, maxError, rmsError, nonFinite, clipped }));
if (nonFinite || clipped || maxError > 1e-5) process.exitCode = 1;
