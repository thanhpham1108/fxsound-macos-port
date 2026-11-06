// Generates one continuous stereo test file to avoid afplay startup overloads.
// Usage: node macos/make_test_tone.js output.wav [seconds]
const fs = require('fs');
const filename = process.argv[2];
const seconds = Number(process.argv[3] || 150);
if (!filename || !Number.isFinite(seconds) || seconds < 1 || seconds > 600) throw Error('invalid arguments');
const rate = 48000, frames = Math.floor(rate * seconds), channels = 2, bytes = frames * channels * 2;
const wav = Buffer.allocUnsafe(44 + bytes);
wav.write('RIFF', 0); wav.writeUInt32LE(36 + bytes, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(channels, 22);
wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * channels * 2, 28);
wav.writeUInt16LE(channels * 2, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(bytes, 40);
for (let i = 0; i < frames; ++i) {
  const value = Math.round(6000 * Math.sin(2 * Math.PI * 440 * i / rate));
  wav.writeInt16LE(value, 44 + i * 4);
  wav.writeInt16LE(value, 46 + i * 4);
}
fs.writeFileSync(filename, wav);
