// Original, deterministic electronic score. No samples or network calls.
import { mkdir, writeFile } from "node:fs/promises";
const rate = 48000,
  duration = 18,
  n = rate * duration;
const left = new Float64Array(n),
  right = new Float64Array(n);
const tau = 2 * Math.PI;
let seed = 982451653;
function noise() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return ((seed >>> 0) / 4294967296) * 2 - 1;
}
function add(start, length, fn, pan = 0) {
  const at = Math.round(start * rate),
    count = Math.round(length * rate);
  for (let i = 0; i < count && at + i < n; i++) {
    const v = fn(i / rate, i);
    left[at + i] += v * (1 - pan * 0.3);
    right[at + i] += v * (1 + pan * 0.3);
  }
}
// A quiet suspended harmony, with a quarter-note sidechain breath.
for (const freq of [110, 164.8138, 220, 261.6256])
  add(
    0,
    duration,
    (t) => {
      const env = Math.min(1, t / 1.8) * Math.min(1, (duration - t) / 0.7);
      const breath = 0.45 + 0.55 * Math.pow(Math.min(1, (t % 0.5) / 0.2), 2);
      return (
        (Math.sin(tau * freq * t) + 0.3 * Math.sin(tau * (freq + 0.32) * t)) *
        0.023 *
        env *
        breath
      );
    },
    freq === 110 ? -0.5 : 0.5,
  );
for (let beat = 6; beat < 34; beat++) {
  const at = beat * 0.5;
  add(
    at,
    0.28,
    (t) =>
      Math.sin(tau * (46 * t + 30 * 0.025 * (1 - Math.exp(-t / 0.025)))) *
      Math.exp(-t * 17) *
      0.42,
  );
  if (beat % 2 === 1)
    add(
      at,
      0.14,
      (t) =>
        (noise() * 0.7 + Math.sin(tau * 182 * t) * 0.3) *
        Math.exp(-t * 31) *
        0.14,
    );
  for (const off of [0, 0.25])
    add(
      at + off,
      0.07,
      (t) => noise() * Math.exp(-t * 95) * 0.025,
      off === 0 ? -0.4 : 0.4,
    );
}
// Sparse glass notes; the rhythm follows the reveal/hold/exit of the film.
const notes = [440, 659.255, 523.251, 880, 659.255, 587.33, 523.251, 659.255];
for (let k = 0; k < 56; k++) {
  const at = 3 + k * 0.25,
    freq = notes[k % notes.length],
    volume = k % 4 === 0 ? 0.048 : 0.025;
  add(
    at,
    0.8,
    (t) =>
      (Math.sin(tau * freq * t) + 0.24 * Math.sin(tau * freq * 2 * t)) *
      Math.exp(-t * 8) *
      Math.min(1, t / 0.008) *
      volume,
    k % 2 ? -0.6 : 0.6,
  );
}
for (const at of [0, 3, 7, 11.5, 15]) {
  add(
    at,
    0.7,
    (t) => (Math.sin(tau * 55 * t) * 0.15 + noise() * 0.016) * Math.exp(-t * 8),
  );
  if (at > 0)
    add(at - 0.28, 0.28, (t) => noise() * 0.045 * Math.pow(t / 0.28, 2));
}
// Short stereo echoes without extending the deliverable's duration.
const delay = Math.round(rate * 0.375);
for (let i = delay; i < n; i++) {
  left[i] += right[i - delay] * 0.12;
  right[i] += left[i - delay] * 0.1;
}
let peak = 0;
for (let i = 0; i < n; i++)
  peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
const out = Buffer.alloc(44 + n * 4);
out.write("RIFF");
out.writeUInt32LE(out.length - 8, 4);
out.write("WAVE", 8);
out.write("fmt ", 12);
out.writeUInt32LE(16, 16);
out.writeUInt16LE(1, 20);
out.writeUInt16LE(2, 22);
out.writeUInt32LE(rate, 24);
out.writeUInt32LE(rate * 4, 28);
out.writeUInt16LE(4, 32);
out.writeUInt16LE(16, 34);
out.write("data", 36);
out.writeUInt32LE(n * 4, 40);
for (let i = 0; i < n; i++) {
  const t = i / rate,
    fade = Math.min(1, t / 0.015, (duration - t) / 0.35);
  out.writeInt16LE(
    Math.round((left[i] / peak) * 0.8 * fade * 32767),
    44 + i * 4,
  );
  out.writeInt16LE(
    Math.round((right[i] / peak) * 0.8 * fade * 32767),
    46 + i * 4,
  );
}
await mkdir("out", { recursive: true });
await writeFile("out/original-score.wav", out);
console.log("out/original-score.wav");
