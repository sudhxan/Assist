// A port of the app's buddy (Sources/Assist/UI/Buddy.swift): same moods, motion, face and props.
import React from "react";
import { C, AURORA } from "../theme";

export type Mood = "sleeping" | "drowsy" | "waking" | "idle" | "listening" | "alert" | "thinking" | "happy";

type Motion = { x: number; y: number; sx: number; sy: number; tilt: number };
const still: Motion = { x: 0, y: 0, sx: 1, sy: 1, tilt: 0 };
const frac = (x: number) => x - Math.floor(x);

function hop(t: number, period: number, height: number, squash: number): Motion {
  const p = frac(t / period);
  if (p < 0.12) {
    const k = Math.sin((p / 0.12) * Math.PI);
    return { ...still, sx: 1 + 0.12 * k * squash, sy: 1 - 0.14 * k * squash };
  }
  if (p < 0.52) {
    const a = (p - 0.12) / 0.4;
    const air = Math.sin(a * Math.PI);
    const stretch = Math.abs(Math.cos(a * Math.PI)) * squash;
    return { ...still, y: -height * air, sx: 1 - 0.07 * stretch, sy: 1 + 0.1 * stretch };
  }
  if (p < 0.68) {
    const k = Math.sin(((p - 0.52) / 0.16) * Math.PI);
    return { ...still, sx: 1 + 0.16 * k * squash, sy: 1 - 0.18 * k * squash };
  }
  return still;
}

function motion(mood: Mood, level: number, s: number, t: number): Motion {
  switch (mood) {
    case "sleeping": {
      const b = Math.sin(t * 1.6);
      return { ...still, sx: 1 - 0.04 * b, sy: 1 + 0.06 * b, tilt: Math.sin(t * 0.8) * 5 };
    }
    case "drowsy": {
      const p = frac(t / 3.2);
      const droop = p < 0.8 ? Math.pow(p / 0.8, 2) : 1 - (p - 0.8) / 0.2;
      return { x: 0, y: droop * s * 0.08, sx: 1 + droop * 0.04, sy: 1 - droop * 0.06, tilt: droop * 10 };
    }
    case "waking": {
      const stretch = Math.max(0, Math.sin(t * 4));
      return { ...still, x: Math.sin(t * 45) * s * 0.02, sx: 1 - 0.06 * stretch, sy: 1 + 0.1 * stretch };
    }
    case "idle":
      return hop(t, 3.2, s * 0.18, 1);
    case "listening": {
      const m = hop(t, 0.62, s * 0.28 * level, level);
      return { ...m, tilt: Math.sin(t * 3.1) * 6 * level };
    }
    case "alert": {
      const m = hop(t, 0.46, s * 0.22, 1);
      return { ...m, tilt: Math.sin(t * 13) * 4 };
    }
    case "thinking": {
      const w = Math.sin(t * 7);
      return { x: 0, y: Math.sin(t * 3.5) * s * 0.05, sx: 1 + 0.08 * w, sy: 1 - 0.08 * w, tilt: Math.sin(t * 5) * 9 };
    }
    case "happy": {
      const period = 0.95;
      const m = hop(t, period, s * 0.3, 1.2);
      const phase = frac(t / period);
      if (phase > 0.12 && phase < 0.52) m.tilt = ((phase - 0.12) / 0.4) * 360;
      return m;
    }
  }
}

/** The "boing" when it perks up: crouch, spring up, wobble back. */
function boing(dt: number, s: number) {
  if (dt < 0 || dt > 1.2) return { sx: 1, sy: 1, y: 0 };
  if (dt < 0.09) {
    const k = dt / 0.09;
    return { sx: 1 + 0.25 * k, sy: 1 - 0.28 * k, y: 0 };
  }
  if (dt < 0.22) {
    const k = Math.sin(((dt - 0.09) / 0.13) * (Math.PI / 2));
    return { sx: 1.25 - 0.4 * k, sy: 0.72 + 0.5 * k, y: -s * 0.3 * k };
  }
  const d = dt - 0.22;
  const decay = Math.exp(-7 * d);
  return {
    sx: 1 - 0.15 * decay * Math.cos(16 * d),
    sy: 1 + 0.22 * decay * Math.cos(16 * d),
    y: -s * 0.3 * Math.exp(-9 * d) * Math.abs(Math.cos(9 * d)),
  };
}

type Eye = { kind: "open" | "lid"; h: number } | { kind: "closed" } | { kind: "happy" };
type Mouth =
  | { kind: "none" }
  | { kind: "smile"; w: number }
  | { kind: "grin" }
  | { kind: "o"; d: number }
  | { kind: "yawn"; open: number }
  | { kind: "wavy" };
type Face = { left: Eye; right: Eye; look: [number, number]; mouth: Mouth; blush: number };

function face(mood: Mood, level: number, t: number): Face {
  const blinking = t % 3.7 < 0.13;
  const open = (h: number): Eye => ({ kind: "open", h: blinking ? 0.04 : h });
  switch (mood) {
    case "sleeping":
      return { left: { kind: "closed" }, right: { kind: "closed" }, look: [0, 0], mouth: { kind: "none" }, blush: 0.4 };
    case "drowsy": {
      const p = frac(t / 3.2);
      const yp = frac(t / 5.5);
      const yawn = yp < 0.32 ? Math.sin((yp / 0.32) * Math.PI) * 0.2 : 0;
      const shut = (p > 0.55 && p < 0.82) || yawn > 0.08;
      const eye: Eye = shut ? { kind: "closed" } : { kind: "lid", h: 0.11 };
      return { left: eye, right: eye, look: [0, 0.03], mouth: yawn > 0.02 ? { kind: "yawn", open: yawn } : { kind: "none" }, blush: 0.35 };
    }
    case "waking": {
      const flutter = Math.max(0, Math.sin(t * 9));
      const eye: Eye = { kind: "lid", h: 0.07 + 0.16 * flutter };
      return { left: eye, right: eye, look: [0, 0], mouth: { kind: "o", d: 0.07 }, blush: 0.35 };
    }
    case "idle": {
      const winking = (t + 2) % 7.3 < 0.35;
      const glance = Math.sin(t * 0.6) > 0.75 ? 0.06 : 0;
      return { left: winking ? { kind: "happy" } : open(0.27), right: open(0.27), look: [glance, 0], mouth: { kind: "smile", w: 0.18 }, blush: 0.28 };
    }
    case "listening":
      return {
        left: open(0.27),
        right: open(0.27),
        look: [Math.sin(t * 0.9) * 0.07, 0],
        mouth: level > 0.35 ? { kind: "o", d: 0.07 + level * 0.06 } : { kind: "smile", w: 0.16 },
        blush: 0.22,
      };
    case "alert":
      return { left: { kind: "open", h: 0.36 }, right: { kind: "open", h: 0.36 }, look: [0, 0], mouth: { kind: "o", d: 0.1 }, blush: 0.2 };
    case "thinking":
      return { left: open(0.22), right: open(0.22), look: [Math.cos(t * 3) * 0.05 + 0.04, -0.06], mouth: { kind: "wavy" }, blush: 0.2 };
    case "happy":
      return { left: { kind: "happy" }, right: { kind: "happy" }, look: [0, 0], mouth: { kind: "grin" }, blush: 0.6 };
  }
}

const INK = "rgba(0,0,0,0.82)";

function roundedRect(x: number, y: number, w: number, h: number, rt: number, rb: number) {
  rt = Math.min(rt, w / 2, h / 2);
  rb = Math.min(rb, w / 2, h / 2);
  return `M${x + rt},${y} H${x + w - rt} Q${x + w},${y} ${x + w},${y + rt} V${y + h - rb} Q${x + w},${y + h} ${x + w - rb},${y + h} H${x + rb} Q${x},${y + h} ${x},${y + h - rb} V${y + rt} Q${x},${y} ${x + rt},${y} Z`;
}

function EyeShape({ eye, cx, cy, s }: { eye: Eye; cx: number; cy: number; s: number }) {
  if (eye.kind === "open") {
    const w = s * 0.15;
    const h = Math.max(s * 0.035, s * eye.h);
    return <rect x={cx - w / 2} y={cy - h / 2} width={w} height={h} rx={Math.min(w, h) / 2} fill={INK} />;
  }
  if (eye.kind === "lid") {
    const w = s * 0.17;
    const h = Math.max(s * 0.035, s * eye.h);
    const y = cy - h / 2 + (s * 0.27 - s * eye.h) / 2;
    return <path d={roundedRect(cx - w / 2, y, w, h, s * 0.015, s * 0.075)} fill={INK} />;
  }
  if (eye.kind === "closed") {
    const w = s * 0.18;
    const h = s * 0.07;
    const x0 = cx - w / 2;
    const y0 = cy - h / 2;
    return <path d={`M${x0},${y0} Q${cx},${y0 + h * 1.8} ${x0 + w},${y0}`} stroke={INK} strokeWidth={Math.max(1, s * 0.06)} strokeLinecap="round" fill="none" />;
  }
  const w = s * 0.19;
  const h = s * 0.11;
  const x0 = cx - w / 2;
  const y1 = cy + h / 2;
  return <path d={`M${x0},${y1} Q${cx},${cy - h / 2 - h * 0.6} ${x0 + w},${y1}`} stroke={INK} strokeWidth={Math.max(1, s * 0.07)} strokeLinecap="round" fill="none" />;
}

function MouthShape({ mouth, cx, top, s, id }: { mouth: Mouth; cx: number; top: number; s: number; id: string }) {
  switch (mouth.kind) {
    case "none":
      return null;
    case "smile": {
      const w = s * mouth.w;
      const h = s * 0.07;
      return <path d={`M${cx - w / 2},${top} Q${cx},${top + h * 1.8} ${cx + w / 2},${top}`} stroke={INK} strokeWidth={Math.max(1, s * 0.055)} strokeLinecap="round" fill="none" />;
    }
    case "grin": {
      const w = s * 0.26;
      const h = s * 0.13;
      const d = `M${cx - w / 2},${top} L${cx + w / 2},${top} Q${cx},${top + h * 1.9} ${cx - w / 2},${top} Z`;
      return (
        <g>
          <clipPath id={`grin-${id}`}>
            <path d={d} />
          </clipPath>
          <path d={d} fill={INK} />
          <ellipse cx={cx} cy={top + h - s * 0.02} rx={s * 0.065} ry={s * 0.04} fill={C.pink} clipPath={`url(#grin-${id})`} />
        </g>
      );
    }
    case "o": {
      const w = s * mouth.d;
      const h = w * 1.2;
      return <ellipse cx={cx} cy={top + h / 2} rx={w / 2} ry={h / 2} fill={INK} />;
    }
    case "yawn": {
      const h = Math.max(s * 0.03, s * mouth.open);
      return <ellipse cx={cx} cy={top + h / 2} rx={s * 0.075} ry={h / 2} fill={INK} />;
    }
    case "wavy": {
      const w = s * 0.16;
      const h = s * 0.05;
      const mid = top + h / 2;
      let d = `M${cx - w / 2},${mid}`;
      for (let i = 1; i <= 12; i++) d += ` L${cx - w / 2 + (w * i) / 12},${mid + (Math.sin((i / 12) * Math.PI * 3) * h) / 2}`;
      return <path d={d} stroke={INK} strokeWidth={Math.max(1, s * 0.045)} strokeLinecap="round" strokeLinejoin="round" fill="none" />;
    }
  }
}

/** The SF Symbol "sparkle": a four-point star with concave sides. */
export function Sparkle({ size, color, style }: { size: number; color: string; style?: React.CSSProperties }) {
  const r = size / 2;
  const k = r * 0.16;
  return (
    <svg width={size} height={size} viewBox={`${-r} ${-r} ${size} ${size}`} style={{ overflow: "visible", ...style }}>
      <path d={`M0,${-r} Q${k},${-k} ${r},0 Q${k},${k} 0,${r} Q${-k},${k} ${-r},0 Q${-k},${-k} 0,${-r} Z`} fill={color} />
    </svg>
  );
}

function Extras({ mood, t, s }: { mood: Mood; t: number; s: number }) {
  const at = (x: number, y: number, child: React.ReactNode, extra: React.CSSProperties = {}) => (
    <div style={{ position: "absolute", left: s / 2 + x, top: s / 2 + y, transform: "translate(-50%, -50%)", ...extra }}>{child}</div>
  );
  const z = (delay: number, opacity = 1) => {
    const phase = frac((t + delay) / 2.2);
    return at(
      s * 0.5 + phase * s * 0.18 + Math.sin(phase * 6) * s * 0.04,
      -s * 0.32 - phase * s * 0.32,
      <span style={{ font: `900 ${s * 0.36}px ui-rounded, -apple-system, sans-serif`, color: "rgba(255,255,255,0.9)" }}>z</span>,
      { opacity: (1 - phase) * opacity, transform: `translate(-50%, -50%) scale(${0.6 + 0.5 * phase})` },
    );
  };
  const mark = (text: string, wiggle: boolean) => {
    const pop = 0.85 + 0.15 * Math.abs(Math.sin(t * 6));
    return at(
      s * 0.56,
      -s * 0.5,
      <span style={{ font: `900 ${s * 0.38}px ui-rounded, -apple-system, sans-serif`, color: C.mint, textShadow: "0 0 2px rgba(0,0,0,0.6)" }}>{text}</span>,
      { transform: `translate(-50%, -50%) scale(${pop}) rotate(${wiggle ? Math.sin(t * 10) * 12 : 0}deg)` },
    );
  };
  switch (mood) {
    case "sleeping": {
      const cycle = frac(t / 8.8);
      const breath = 0.5 + 0.5 * Math.sin(t * 1.6);
      const radius = s * (0.035 + 0.08 * breath * Math.min(1, cycle / 0.25));
      const popped = cycle > 0.9;
      return (
        <>
          {at(
            s * 0.16 + radius * 0.6,
            s * 0.2,
            <div style={{ width: radius * 2, height: radius * 2, borderRadius: "50%", background: "rgba(79,199,252,0.25)", border: `${Math.max(0.6, s * 0.025)}px solid rgba(255,255,255,0.75)` }} />,
            { opacity: popped ? 0 : 1 },
          )}
          {z(0)}
          {z(1.1)}
        </>
      );
    }
    case "drowsy":
      return z(0, 0.5);
    case "waking":
      return mark("!?", true);
    case "alert":
      return mark("!", false);
    case "thinking": {
      const step = Math.floor(t * 2.5) % 4;
      return at(
        s * 0.62,
        -s * 0.5,
        <div style={{ display: "flex", alignItems: "flex-end", gap: s * 0.05 }}>
          {[0, 1, 2].map((i) => {
            const d = s * (0.07 + i * 0.025);
            return <div key={i} style={{ width: d, height: d, borderRadius: "50%", background: "rgba(255,255,255,0.9)", opacity: i < step ? 1 : 0.15 }} />;
          })}
        </div>,
      );
    }
    case "happy":
      return (
        <>
          {[0, 1, 2].map((i) => {
            const phase = frac(t * 1.6 + i * 0.33);
            const angle = i * 2.1 + 0.6;
            const size = s * (0.18 + 0.1 * (i % 2)) * 1.25;
            return (
              <React.Fragment key={i}>
                {at(Math.cos(angle) * s * 0.68, Math.sin(angle) * s * 0.6 - s * 0.12, <Sparkle size={size} color={AURORA[i + 1]} />, {
                  transform: `translate(-50%, -50%) scale(${Math.sin(phase * Math.PI)})`,
                })}
              </React.Fragment>
            );
          })}
        </>
      );
    default:
      return null;
  }
}

export type BuddyProps = {
  size: number;
  t: number;
  mood: Mood;
  /** When the current mood started, for the "boing" as it perks up. */
  moodSince?: number;
  level?: number;
  glow?: number;
  style?: React.CSSProperties;
};

/** Footprint is size × 1.35, like BuddyView.footprintRatio. The blob sits centered in it. */
export const Buddy: React.FC<BuddyProps> = ({ size: s, t, mood, moodSince = -10, level = 0, glow = 1, style }) => {
  const lvl = Math.min(level, 1);
  const m = motion(mood, lvl, s, t);
  const f = face(mood, lvl, t);
  const perk = mood !== "sleeping" && mood !== "drowsy" ? boing(t - moodSince, s) : { sx: 1, sy: 1, y: 0 };
  const fp = s * 1.35;
  const id = `${Math.round(s * 10)}`;

  const eyeY = -0.035 * s + f.look[1] * s;
  const eyeDX = f.look[0] * s;
  const mouthTop = 0.175 * s + f.look[1] * s;

  // Rotation about the center, scale about the bottom (SwiftUI's anchor: .bottom).
  const sx = m.sx * perk.sx;
  const sy = m.sy * perk.sy;
  const transform = `translate(${m.x}px, ${m.y + perk.y}px) rotate(${m.tilt}deg) translate(0, ${s / 2}px) scale(${sx}, ${sy}) translate(0, ${-s / 2}px)`;

  return (
    <div style={{ position: "relative", width: fp, height: fp, ...style }}>
      <div style={{ position: "absolute", left: (fp - s) / 2, top: (fp - s) / 2, width: s, height: s, transform }}>
        <div
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "42%",
            background: `conic-gradient(from ${t * 45 + 90}deg, ${AURORA.join(", ")})`,
            boxShadow: `0 0 ${s * 0.55}px rgba(79,199,252,${(mood === "sleeping" ? 0.4 : 0.55) * glow})`,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              position: "absolute",
              left: s * 0.14,
              top: s * 0.12,
              width: s * 0.32,
              height: s * 0.16,
              borderRadius: "50%",
              background: "rgba(255,255,255,0.45)",
              transform: "rotate(-20deg)",
              filter: `blur(${s * 0.03}px)`,
            }}
          />
        </div>
        <svg width={s} height={s} viewBox={`${-s / 2} ${-s / 2} ${s} ${s}`} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
          <defs>
            <filter id={`cheek-${id}`} x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation={s * 0.02} />
            </filter>
          </defs>
          {[-1, 1].map((side) => (
            <ellipse key={side} cx={side * 0.295 * s} cy={0.13 * s} rx={0.085 * s} ry={0.045 * s} fill={C.pink} opacity={f.blush} filter={`url(#cheek-${id})`} />
          ))}
          <EyeShape eye={f.left} cx={-0.17 * s + eyeDX} cy={eyeY} s={s} />
          <EyeShape eye={f.right} cx={0.17 * s + eyeDX} cy={eyeY} s={s} />
          <MouthShape mouth={f.mouth} cx={eyeDX} top={mouthTop} s={s} id={id} />
        </svg>
        <Extras mood={mood} t={t} s={s} />
      </div>
    </div>
  );
};
