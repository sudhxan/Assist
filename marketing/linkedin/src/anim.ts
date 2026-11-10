import { Easing } from "remotion";

export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, x: number) => a + (b - a) * x;

export const E = {
  out: Easing.bezier(0.16, 1, 0.3, 1),
  soft: Easing.bezier(0.22, 1, 0.36, 1),
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  gentle: Easing.bezier(0.45, 0, 0.55, 1),
  in: Easing.bezier(0.55, 0, 1, 0.45),
  pop: Easing.bezier(0.34, 1.56, 0.64, 1),
  linear: (x: number) => x,
};

/** 0→1 between `start` and `start + dur` seconds, eased. */
export const ramp = (t: number, start: number, dur: number, ease: (x: number) => number = E.out) =>
  ease(clamp((t - start) / dur));

/** Fades in at `a`, out at `b`. */
export const window01 = (t: number, a: number, b: number, fadeIn = 0.35, fadeOut = 0.35) =>
  ramp(t, a, fadeIn) * (1 - ramp(t, b - fadeOut, fadeOut, E.in));

/** SwiftUI's spring(response:dampingFraction:) from 0 to 1, `t` seconds after it starts. */
export const swiftSpring = (t: number, response = 0.5, damping = 0.7) => {
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / response;
  if (damping >= 1) return 1 - Math.exp(-w * t) * (1 + w * t);
  const wd = w * Math.sqrt(1 - damping * damping);
  return 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + ((damping * w) / wd) * Math.sin(wd * t));
};

type Num = Record<string, number>;

/** Piecewise keyframes over objects of numbers. A key's optional easing applies to the segment ending at it. */
export function track<T extends Num>(t: number, keys: [number, T, ((x: number) => number)?][], ease: (x: number) => number = E.inOut): T {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, segEase] = keys[i];
    if (t <= t1) {
      const [t0, v0] = keys[i - 1];
      const x = (segEase ?? ease)(clamp((t - t0) / (t1 - t0)));
      const out = {} as Num;
      for (const k in v0) out[k] = lerp(v0[k], v1[k], x);
      return out as T;
    }
  }
  return keys[keys.length - 1][1];
}

/** The last value whose start time has passed, plus when it started. */
export function schedule<T>(t: number, entries: [number, T][]): { value: T; since: number } {
  let pick = entries[0];
  for (const e of entries) if (t >= e[0]) pick = e;
  return { value: pick[1], since: pick[0] };
}

/** Typewriter: how many characters of `text` show at `t`, at `cps` characters per second. */
export const typed = (text: string, t: number, start: number, cps: number) =>
  text.slice(0, Math.max(0, Math.floor((t - start) * cps)));
