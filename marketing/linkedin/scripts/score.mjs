// Synthesizes the soundtrack (music + sound design), timed to the video, into public/score.wav.
// No samples and no dependencies: oscillators, filters, a Freeverb-style reverb, a ping-pong delay.
//   node scripts/score.mjs
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import path from "node:path";

const SR = 48000;
const DUR = 45;
const N = SR * DUR;
const TAU = Math.PI * 2;

const bus = () => ({ L: new Float32Array(N), R: new Float32Array(N) });
const music = bus();
const sfx = bus();
const verb = bus(); // reverb send
const echo = bus(); // delay send

let seed = 7;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const noise = () => rnd() * 2 - 1;
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));

function mix(target, mono, start, { gain = 1, pan = 0, rev = 0, del = 0, panFn = null } = {}) {
  const i0 = Math.round(start * SR);
  for (let i = 0; i < mono.length; i++) {
    const j = i0 + i;
    if (j < 0 || j >= N) continue;
    const p = panFn ? panFn(i / SR) : pan;
    const gl = Math.cos(((p + 1) * Math.PI) / 4) * gain;
    const gr = Math.sin(((p + 1) * Math.PI) / 4) * gain;
    const v = mono[i];
    target.L[j] += v * gl;
    target.R[j] += v * gr;
    if (rev) { verb.L[j] += v * gl * rev; verb.R[j] += v * gr * rev; }
    if (del) { echo.L[j] += v * gl * del; echo.R[j] += v * gr * del; }
  }
}

// RBJ biquad with per-sample cutoff updates (cheap enough at this length).
function biquad(type) {
  let b0, b1, b2, a1, a2, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x, fc, q = 0.707) => {
    const w = (TAU * clamp(fc, 20, SR * 0.45)) / SR;
    const c = Math.cos(w);
    const alpha = Math.sin(w) / (2 * q);
    const a0 = 1 + alpha;
    if (type === "lp") { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; }
    else if (type === "hp") { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; }
    else { b0 = alpha; b1 = 0; b2 = -alpha; }
    a1 = -2 * c; a2 = 1 - alpha;
    const y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

const blep = (t, dt) => (t < dt ? ((t /= dt), t + t - t * t - 1) : t > 1 - dt ? ((t = (t - 1) / dt), t * t + t + t + 1) : 0);

// ---------- Music ----------
const BEAT = 0.45; // 133.3 BPM, so the montage words land on beats
const GRID = 0.4; // beat k is at GRID + k * BEAT
const beatAt = (k) => GRID + k * BEAT;
const BAR = BEAT * 4;
const FIRST_BAR = 3.1; // the brand reveal lands on a downbeat

// vi – IV – I – V in D major, with added ninths
const CHORDS = [
  { root: 35, pad: [59, 62, 66, 73] }, // Bm(add9)
  { root: 31, pad: [55, 59, 62, 69] }, // G(add9)
  { root: 38, pad: [62, 66, 69, 76] }, // D(add9)
  { root: 33, pad: [57, 61, 64, 71] }, // A(add9)
];

// Kick positions: the demo (8.05–31) and the montage (37.3–40).
const kicks = [];
for (let k = 0; beatAt(k) < 45; k++) {
  const t = beatAt(k);
  if ((t >= 8.0 && t < 30.95) || (t >= 37.25 && t < 39.95)) kicks.push(t);
}
const duck = (t) => {
  let d = 1;
  for (const k of kicks) if (t >= k && t < k + 0.4) d = Math.min(d, 1 - 0.55 * Math.exp(-(t - k) / 0.09));
  return d;
};

// Section levels for the bed.
const padCut = (t) => (t < 3.1 ? 350 + 1400 * clamp(t / 3.1) ** 2 : t < 31 ? 2600 : t < 37.2 ? 900 + 2400 * clamp((t - 31) / 6.2) ** 2 : t < 40 ? 4200 : 3000 - 1800 * clamp((t - 40) / 5));
const padGain = (t) => (t < 3.1 ? 0.5 + 0.5 * clamp(t / 3) : t < 7.8 ? 1 : t < 31 ? 0.7 : t < 37.2 ? 0.95 : t < 40 ? 0.85 : 1.05 * (1 - clamp((t - 42.5) / 2.4)));

function padNote(midi, start, dur, gain) {
  const rel = 1.4;
  const len = Math.round((dur + rel) * SR);
  for (const side of [-1, 1]) {
    const out = new Float32Array(len);
    const detunes = side < 0 ? [-11, 2, 9] : [-6, -1, 12];
    const phases = detunes.map(() => rnd());
    const lp = biquad("lp");
    for (let i = 0; i < len; i++) {
      const t = i / SR;
      const abs = start + t;
      let v = 0;
      detunes.forEach((cents, d) => {
        const f = mtof(midi) * Math.pow(2, cents / 1200);
        const dt = f / SR;
        phases[d] = (phases[d] + dt) % 1;
        v += 2 * phases[d] - 1 - blep(phases[d], dt);
      });
      const env = Math.min(1, t / 0.5) * (t > dur ? Math.exp(-(t - dur) / 0.45) : 1);
      out[i] = lp(v / 3, padCut(abs), 0.6) * env * padGain(abs) * duck(abs);
    }
    mix(music, out, start, { gain: gain * 0.5, pan: side * 0.6, rev: 0.35 });
  }
}

function pluck(midi, start, gain, pan) {
  const len = Math.round(0.6 * SR);
  const out = new Float32Array(len);
  const lp = biquad("lp");
  let ph = 0;
  const f = mtof(midi);
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    ph = (ph + f / SR) % 1;
    const tone = 0.6 * Math.sin(TAU * ph) + 0.4 * (2 * ph - 1 - blep(ph, f / SR));
    out[i] = lp(tone, 900 + 5200 * Math.exp(-t / 0.07), 0.9) * Math.min(1, t / 0.003) * Math.exp(-t / 0.16) * duck(start + t);
  }
  mix(music, out, start, { gain, pan, rev: 0.25, del: 0.35 });
}

function bassNote(midi, start, dur, gain) {
  const len = Math.round((dur + 0.1) * SR);
  const out = new Float32Array(len);
  let ph = 0;
  const f = mtof(midi);
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    ph = (ph + f / SR) % 1;
    const env = Math.min(1, t / 0.01) * (t > dur ? Math.exp(-(t - dur) / 0.03) : 1);
    out[i] = Math.tanh(1.6 * (Math.sin(TAU * ph) + 0.18 * Math.sin(2 * TAU * ph))) * env * duck(start + t);
  }
  mix(music, out, start, { gain });
}

function kick(start, gain = 1) {
  const len = Math.round(0.5 * SR);
  const out = new Float32Array(len);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    ph += (46 + 110 * Math.exp(-t / 0.035)) / SR;
    out[i] = Math.tanh(1.4 * Math.sin(TAU * ph)) * Math.exp(-t / 0.16) + (t < 0.003 ? noise() * 0.4 : 0);
  }
  mix(music, out, start, { gain });
}

function hat(start, gain, pan = 0.2) {
  const len = Math.round(0.08 * SR);
  const out = new Float32Array(len);
  const hp = biquad("hp");
  for (let i = 0; i < len; i++) out[i] = hp(noise(), 8000, 0.8) * Math.exp(-(i / SR) / 0.022);
  mix(music, out, start, { gain, pan });
}

function clap(start, gain) {
  const len = Math.round(0.35 * SR);
  const out = new Float32Array(len);
  const bp = biquad("bp");
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const env = [0, 0.011, 0.022].reduce((e, o) => e + (t >= o ? Math.exp(-(t - o) / (o === 0.022 ? 0.12 : 0.008)) : 0), 0);
    out[i] = bp(noise(), 1300, 1.2) * env;
  }
  mix(music, out, start, { gain, rev: 0.2 });
}

// Bed: intro chord, then the progression from the brand reveal.
padNote(CHORDS[0].pad[0], 0, 3.1, 0.18);
padNote(CHORDS[0].pad[1], 0, 3.1, 0.18);
padNote(CHORDS[0].pad[2], 0, 3.1, 0.15);
let bar = 0;
for (let t0 = FIRST_BAR; t0 < 40; t0 += BAR, bar++) {
  const c = CHORDS[bar % 4];
  const dur = Math.min(BAR, 40 - t0);
  c.pad.forEach((m, i) => padNote(m, t0, dur, i === 3 ? 0.11 : 0.15));
  // Arp: eighth notes over the chord, an octave up.
  const tones = [...c.pad, c.pad[0] + 12, c.pad[1] + 12];
  const pattern = [0, 2, 1, 3, 4, 2, 5, 3];
  for (let s = 0; s < 8; s++) {
    const at = t0 + s * (BEAT / 2);
    if (at >= 40) break;
    const inBreak = at >= 31 && at < 37.2;
    const arpGain = at < 7.8 ? 0.11 : inBreak ? 0.1 : 0.075;
    pluck(tones[pattern[s]] + 12, at, arpGain * (s % 2 ? 0.75 : 1), s % 2 ? 0.35 : -0.35);
  }
  // Bass: offbeat pulses in the groove sections, held in the breakdown.
  const groove = t0 >= 6.7 && t0 < 31;
  const mont = t0 >= 37.2;
  if (groove || mont) for (let s = 0; s < 4; s++) bassNote(c.root + 12, t0 + s * BEAT + BEAT / 2, BEAT / 2 - 0.02, 0.2);
  else if (t0 >= 31) bassNote(c.root + 12, t0, dur - 0.05, 0.12);
}
// Final chord on the end card, held to the end.
[50, 57, 62, 66, 69, 76].forEach((m, i) => padNote(m, 40.0, 3.8, i ? 0.14 : 0.18));
bassNote(38, 40.0, 3.2, 0.2);
for (let s = 0; s < 10; s++) pluck([74, 78, 81, 86, 90][s % 5], 40.0 + s * (BEAT / 2), 0.08 * Math.exp(-s / 6), s % 2 ? 0.4 : -0.4);

kicks.forEach((t) => kick(t, t >= 37.25 ? 0.62 : 0.5));
for (let k = 0; beatAt(k) < 40; k++) {
  const t = beatAt(k);
  if (t >= 4.9 && t < 30.95) hat(t + BEAT / 2, t < 7.8 ? 0.05 : 0.07, 0.25);
  if (t >= 37.25 && t < 39.95) { clap(t, 0.16); hat(t + BEAT / 2, 0.08); }
  if (t >= 8.0 && t < 30.95 && k % 2 === 1) clap(t, 0.07);
}

// ---------- Sound design ----------
function sweepNoise(start, dur, { from, to, q = 1.2, gain, shape = "bell", pan = 0, panFn = null, rev = 0.3 }) {
  const len = Math.round(dur * SR);
  const out = new Float32Array(len);
  const bp = biquad("bp");
  for (let i = 0; i < len; i++) {
    const x = i / len;
    const fc = from * Math.pow(to / from, x);
    const env = shape === "bell" ? Math.sin(Math.PI * x) ** 2 : shape === "rise" ? x ** 2.2 : (1 - x) ** 2;
    out[i] = bp(noise(), fc, q) * env;
  }
  mix(sfx, out, start, { gain, pan, panFn, rev });
}

function impact(start, gain) {
  const len = Math.round(3 * SR);
  const out = new Float32Array(len);
  const lp = biquad("lp");
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    ph += (30 + 40 * Math.exp(-t / 0.25)) / SR;
    out[i] = Math.sin(TAU * ph) * Math.exp(-t / 0.9) * 0.9 + lp(noise(), 1800, 0.7) * Math.exp(-t / 0.18) * 0.5;
  }
  mix(sfx, out, start, { gain, rev: 0.45 });
}

function riser(start, end, gain) {
  sweepNoise(start, end - start, { from: 300, to: 7000, q: 2.5, gain, shape: "rise", rev: 0.2 });
  const len = Math.round((end - start) * SR);
  const out = new Float32Array(len);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const x = i / len;
    const f = 180 * Math.pow(6, x);
    ph = (ph + f / SR) % 1;
    out[i] = (2 * ph - 1) * x ** 2.5 * 0.25;
  }
  const lp = biquad("lp");
  for (let i = 0; i < len; i++) out[i] = lp(out[i], 600 + 5000 * (i / len) ** 2, 1.5);
  mix(sfx, out, start, { gain, rev: 0.3 });
}

function bell(midi, start, gain, pan = 0, decay = 1.1) {
  const len = Math.round(decay * 3 * SR);
  const out = new Float32Array(len);
  const f = mtof(midi);
  const partials = [[1, 1], [2.0, 0.42], [3.01, 0.22], [4.17, 0.1], [5.43, 0.05]];
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    let v = 0;
    for (const [m, a] of partials) v += a * Math.sin(TAU * f * m * t) * Math.exp(-t / (decay / m ** 0.7));
    out[i] = v * Math.min(1, t / 0.002);
  }
  mix(sfx, out, start, { gain, pan, rev: 0.45, del: 0.15 });
}

function pop(start, midi, gain, pan = 0) {
  const len = Math.round(0.14 * SR);
  const out = new Float32Array(len);
  let ph = 0;
  const f = mtof(midi);
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    ph += (f * (1 + 0.8 * Math.exp(-t / 0.012))) / SR;
    out[i] = Math.sin(TAU * ph) * Math.exp(-t / 0.045);
  }
  mix(sfx, out, start, { gain, pan, rev: 0.25 });
}

function click(start, gain, pan = 0) {
  const len = Math.round(0.03 * SR);
  const out = new Float32Array(len);
  const hp = biquad("hp");
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    out[i] = hp(noise(), 2500, 0.7) * Math.exp(-t / 0.004) + Math.sin(TAU * 1900 * t) * Math.exp(-t / 0.008) * 0.5;
  }
  mix(sfx, out, start, { gain, pan });
}

function thump(start, gain) {
  const len = Math.round(0.4 * SR);
  const out = new Float32Array(len);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    ph += (70 + 60 * Math.exp(-t / 0.04)) / SR;
    out[i] = Math.sin(TAU * ph) * Math.exp(-t / 0.12);
  }
  mix(sfx, out, start, { gain });
}

const PENTA = [74, 76, 78, 81, 83, 86, 88, 90, 93, 95, 98, 100];

// Hook
impact(0.05, 0.35);
sweepNoise(0.1, 0.9, { from: 2000, to: 500, gain: 0.05 });
sweepNoise(1.72, 0.5, { from: 600, to: 3000, gain: 0.05 });
riser(1.6, 3.1, 0.22);
sweepNoise(2.2, 0.9, { from: 1200, to: 9000, q: 0.8, gain: 0.08, shape: "rise", rev: 0.1 }); // reverse cymbal
// Brand reveal
impact(3.1, 0.75);
bell(86, 3.12, 0.16, 0, 1.6);
bell(81, 3.12, 0.12, 0, 1.6);
for (let i = 0; i < 12; i++) pop(4.35 + i * 0.075, PENTA[i] - 12, 0.12, ((i * 7) % 11) / 5.5 - 1);
bell(90, 4.55, 0.06, 0.3, 0.8); // title shimmer
sweepNoise(7.3, 1.0, { from: 400, to: 6000, gain: 0.22 }); // into the demo
impact(7.95, 0.3);
// Demo
click(11.98, 0.18, 0.1);
sweepNoise(12.0, 0.45, { from: 500, to: 2600, q: 1.5, gain: 0.12, rev: 0.15 });
thump(12.02, 0.25);
bell(88, 13.62, 0.12, 0.2, 0.5); // the question: "!"
bell(93, 13.72, 0.1, 0.25, 0.5);
for (let tt = 14.19, i = 0; tt < 15.85; tt += 0.045 + 0.02 * rnd(), i++) bell(PENTA[4 + Math.floor(rnd() * 8)], tt, 0.022, rnd() * 1.4 - 0.7, 0.18); // streaming
[86, 90, 93, 98].forEach((m, i) => bell(m, 15.92 + i * 0.07, 0.09, -0.3 + i * 0.2, 0.9)); // answer ready
sweepNoise(15.6, 1.2, { from: 300, to: 1800, gain: 0.07 });
sweepNoise(18.8, 0.9, { from: 2600, to: 400, gain: 0.1 });
thump(19.32, 0.15);
[22.42, 22.47, 22.52].forEach((tt) => click(tt, 0.3, 0));
bell(93, 22.62, 0.07, 0, 0.4);
sweepNoise(22.45, 0.95, { from: 500, to: 7000, q: 3, gain: 0.16, shape: "bell", rev: 0.15 }); // scan
for (let i = 0; i < 4; i++) bell(PENTA[6 + i], 22.67 + i * 0.12, 0.035, 0.4 - i * 0.25, 0.2); // OCR hits
[88, 93].forEach((m, i) => bell(m, 23.42 + i * 0.09, 0.09, 0.1, 0.8)); // peek
sweepNoise(23.3, 1.0, { from: 300, to: 2000, gain: 0.07 });
click(25.05, 0.16);
sweepNoise(25.1, 0.5, { from: 500, to: 2600, q: 1.5, gain: 0.1, rev: 0.15 });
thump(25.12, 0.2);
sweepNoise(26.4, 1.2, { from: 700, to: 4000, gain: 0.16, panFn: (s) => 0.9 - 1.6 * clamp(s / 1.2) });
sweepNoise(27.6, 1.0, { from: 2500, to: 900, gain: 0.1, panFn: (s) => -0.7 + 0.7 * clamp(s / 1.0) });
bell(81, 28.65, 0.07, 0, 1.2);
// Private
sweepNoise(30.7, 0.9, { from: 5000, to: 400, gain: 0.16 });
impact(31.05, 0.28);
sweepNoise(31.5, 0.9, { from: 150, to: 900, q: 0.8, gain: 0.12, rev: 0.2 });
sweepNoise(32.1, 0.55, { from: 2000, to: 8000, q: 4, gain: 0.05, pan: -0.5 });
sweepNoise(32.1, 0.55, { from: 2000, to: 8000, q: 4, gain: 0.05, pan: 0.5 });
pop(32.45, 81, 0.1, -0.6);
pop(32.6, 86, 0.1, 0.6);
[33.2, 33.45, 33.7].forEach((tt, i) => {
  pop(tt, 83 + i * 4, 0.11, i - 1);
  for (let k = 0; k < 9; k++) click(tt + 0.05 + 0.9 * (k / 9) ** 1.8, 0.05, i - 1);
});
riser(35.6, 37.3, 0.28);
for (let k = 0; k < 16; k++) {
  const tt = 36.4 + 0.9 * (1 - Math.pow(1 - k / 16, 1.5));
  clap(tt, 0.03 + 0.07 * (k / 16));
}
// Montage word swaps
[37.3, 37.75, 38.2, 38.65, 39.1].forEach((tt, i) => sweepNoise(tt - 0.05, 0.3, { from: 900, to: 3500, q: 1.4, gain: 0.07, pan: i % 2 ? 0.3 : -0.3, rev: 0.05 }));
// End card
impact(40.0, 0.7);
bell(86, 40.02, 0.12, 0, 2);
bell(93, 40.3, 0.08, 0.2, 1.5);
pop(41.62, 86, 0.1, 0);

// ---------- Effects ----------
function pingPong(src, time = BEAT * 0.75, fb = 0.38) {
  const d = Math.round(time * SR);
  const lp = [biquad("lp"), biquad("lp")];
  const L = new Float32Array(N);
  const R = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const inL = src.L[i] + src.R[i];
    L[i] = (i >= d ? lp[0](R[i - d] * fb, 3500) : 0) + inL * 0.5;
    R[i] = i >= d ? lp[1](L[i - d] * fb, 3500) : 0;
  }
  return { L, R };
}

function freeverb(src) {
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((n) => Math.round((n * SR) / 44100));
  const aps = [556, 441, 341, 225].map((n) => Math.round((n * SR) / 44100));
  const out = { L: new Float32Array(N), R: new Float32Array(N) };
  for (const [ch, spread] of [["L", 0], ["R", 23]]) {
    const x = src[ch];
    const y = out[ch];
    for (const len0 of combs) {
      const len = len0 + spread;
      const buf = new Float32Array(len);
      let idx = 0;
      let store = 0;
      for (let i = 0; i < N; i++) {
        const o = buf[idx];
        store = o * 0.62 + store * 0.38; // damping
        buf[idx] = x[i] * 0.015 + store * 0.86; // room size
        y[i] += o;
        idx = (idx + 1) % len;
      }
    }
    for (const len0 of aps) {
      const len = len0 + spread;
      const buf = new Float32Array(len);
      let idx = 0;
      for (let i = 0; i < N; i++) {
        const b = buf[idx];
        const o = -y[i] + b;
        buf[idx] = y[i] + b * 0.5;
        y[i] = o;
        idx = (idx + 1) % len;
      }
    }
  }
  return out;
}

const delayed = pingPong(echo);
for (let i = 0; i < N; i++) { verb.L[i] += delayed.L[i] * 0.3; verb.R[i] += delayed.R[i] * 0.3; }
const wet = freeverb(verb);

// ---------- Master ----------
const L = new Float32Array(N);
const R = new Float32Array(N);
let peak = 0;
for (let i = 0; i < N; i++) {
  const t = i / SR;
  const fadeOut = 1 - clamp((t - 43.6) / 1.35) ** 1.5;
  const fadeIn = clamp(t / 0.02);
  const l = (music.L[i] * 0.9 + sfx.L[i] + delayed.L[i] * 0.55 + wet.L[i] * 0.9) * fadeOut * fadeIn;
  const r = (music.R[i] * 0.9 + sfx.R[i] + delayed.R[i] * 0.55 + wet.R[i] * 0.9) * fadeOut * fadeIn;
  L[i] = Math.tanh(l * 1.1);
  R[i] = Math.tanh(r * 1.1);
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}

function wav(file, L, R, norm) {
  const data = Buffer.alloc(N * 4);
  for (let i = 0; i < N; i++) {
    data.writeInt16LE(Math.round(clamp(L[i] * norm, -1, 1) * 32767), i * 4);
    data.writeInt16LE(Math.round(clamp(R[i] * norm, -1, 1) * 32767), i * 4 + 2);
  }
  const h = Buffer.alloc(44);
  h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVE", 8); h.write("fmt ", 12);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(2, 22); h.writeUInt32LE(SR, 24);
  h.writeUInt32LE(SR * 4, 28); h.writeUInt16LE(4, 32); h.writeUInt16LE(16, 34); h.write("data", 36); h.writeUInt32LE(data.length, 40);
  writeFileSync(file, Buffer.concat([h, data]));
}

const raw = path.resolve("out/score-raw.wav");
const final = path.resolve("public/score.wav");
wav(raw, L, R, 0.89 / peak);
// Loudness-normalize for social video: -14 LUFS integrated, -1.5 dBTP.
const report = execFileSync("sh", ["-c", `ffmpeg -hide_banner -i "${raw}" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | sed -n '/{/,/}/p'`]).toString();
const m = JSON.parse(report);
execFileSync("ffmpeg", [
  "-v", "error", "-y", "-i", raw, "-af",
  `loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=${m.input_i}:measured_TP=${m.input_tp}:measured_LRA=${m.input_lra}:measured_thresh=${m.input_thresh}:offset=${m.target_offset}:linear=true,aresample=48000`,
  "-c:a", "pcm_s16le", final,
]);
console.log(`${final}  (input ${m.input_i} LUFS → -14 LUFS)`);
