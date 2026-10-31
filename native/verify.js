// AGPL-3.0-or-later. Checks the file processor with actual PCM rather than UI state.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const assert = require('assert');
const exe = path.join(__dirname, process.platform === 'win32' ? 'fxwav.exe' : 'fxwav');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fxwav-'));
function wav(samples, rate = 48000) {
  const b = Buffer.alloc(44 + samples.length * 4);
  b.write('RIFF', 0); b.writeUInt32LE(b.length - 8, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(3, 20); b.writeUInt16LE(2, 22);
  b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 8, 28);
  b.writeUInt16LE(8, 32); b.writeUInt16LE(32, 34);
  b.write('data', 36); b.writeUInt32LE(samples.length * 4, 40);
  samples.forEach((s, i) => b.writeFloatLE(s, 44 + i * 4)); return b;
}
function run(name, args) {
  const dest = path.join(dir, name + '.wav');
  const p = spawnSync(exe, [path.join(dir, 'input.wav'), dest, ...args], { encoding: 'utf8' });
  assert.strictEqual(p.status, 0, p.stderr); return fs.readFileSync(dest);
}
const input = Array.from({ length: 4800 * 2 }, (_, i) => Math.fround(.1 * Math.sin(2 * Math.PI * 1000 * Math.floor(i / 2) / 48000)));
fs.writeFileSync(path.join(dir, 'input.wav'), wav(input));
const dry = run('dry', ['--bypass', '--band', '1000', '6', '1']);
const flat = run('flat', []);
const boosted = run('boost', ['--band', '1000', '6', '1']);
for (let i = 0; i < input.length; ++i) {
  assert.strictEqual(dry.readFloatLE(44 + i * 4), input[i], 'dry bypass must be sample exact');
  assert.strictEqual(flat.readFloatLE(44 + i * 4), input[i], 'flat EQ must be sample exact');
  assert(Number.isFinite(boosted.readFloatLE(44 + i * 4)), 'effect output must be finite');
}
let inputPower = 0, outputPower = 0;
for (let i = 0; i < input.length; ++i) { inputPower += input[i] ** 2; outputPower += boosted.readFloatLE(44 + i * 4) ** 2; }
assert(outputPower > inputPower * 1.5, '1 kHz boost must increase 1 kHz energy');
console.log('PASS dry bypass, flat EQ, finite effect, 1 kHz boost');
fs.rmSync(dir, { recursive: true, force: true });
