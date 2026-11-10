// Scene 6 (on-device and private), scene 7 (use-case montage), scene 8 (end card). Absolute times.
import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { E, lerp, ramp, schedule } from "../anim";
import { Buddy, Mood } from "../components/Buddy";
import { Planet } from "../components/Planet";
import { Words, gradText } from "../components/Words";
import { AURORA, BODY, C, DISPLAY } from "../theme";

// ---------- Private ----------
const Pill: React.FC<{ title: string; sub: string; side: "left" | "right"; k: number }> = ({ title, sub, side, k }) => (
  <div
    style={{
      position: "absolute",
      top: 522,
      [side]: 42,
      width: 248,
      transform: `translateY(-50%) translateX(${(1 - k) * (side === "left" ? -30 : 30)}px)`,
      opacity: k,
      padding: "18px 20px",
      borderRadius: 20,
      background: "rgba(16,18,28,0.82)",
      border: "1px solid rgba(255,255,255,0.12)",
      boxShadow: "inset 0 1px 0 rgba(255,255,255,0.07), 0 10px 30px rgba(0,0,0,0.4)",
      textAlign: side === "left" ? "right" : "left",
    }}
  >
    <div style={{ font: `600 28px ${DISPLAY}`, color: "#f5f6f8", letterSpacing: "-0.02em" }}>{title}</div>
    <div style={{ font: `400 19px ${BODY}`, color: C.muted, marginTop: 5 }}>{sub}</div>
  </div>
);

const Stat: React.FC<{ value: string; label: string; x: number; k: number }> = ({ value, label, x, k }) => (
  <div style={{ position: "absolute", left: x, top: 812, transform: `translate(-50%, ${(1 - k) * 24}px)`, opacity: k, textAlign: "center", width: 320 }}>
    <div style={{ font: `600 74px ${DISPLAY}`, letterSpacing: "-0.04em", lineHeight: 1, fontVariantNumeric: "tabular-nums", ...gradText, paddingBottom: 6 }}>{value}</div>
    <div style={{ font: `400 21px ${BODY}`, color: C.muted, marginTop: 8 }}>{label}</div>
  </div>
);

/** A die with pins and traces; the buddy sits on it. */
const ChipArt: React.FC<{ t: number; k: number; draw: number }> = ({ t, k, draw }) => {
  const size = 250;
  const x0 = 540 - size / 2;
  const y0 = 522 - size / 2;
  const pins = Array.from({ length: 9 }, (_, i) => 30 + i * ((size - 60) / 8));
  const traceL = `M${x0 - 14},522 H${x0 - 60} V${522 - 0} H${290}`;
  const traceR = `M${x0 + size + 14},522 H${x0 + size + 60} H${790}`;
  const traceLen = x0 - 14 - 290;
  const pulse = (len: number, phase: number) => ((t * 0.9 + phase) % 1) * len;
  return (
    <>
      <svg width={1080} height={1080} style={{ position: "absolute", inset: 0, opacity: k }}>
        <defs>
          <linearGradient id="trace" x1="0" x2="1">
            <stop offset="0" stopColor={C.mint} />
            <stop offset="1" stopColor={C.sky} />
          </linearGradient>
          <filter id="tglow" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="3" />
          </filter>
        </defs>
        {[traceL, traceR].map((d, i) => (
          <g key={i}>
            <path d={d} stroke="rgba(255,255,255,0.14)" strokeWidth={2} fill="none" strokeDasharray={`${traceLen * draw} 2000`} />
            {draw > 0.98 ? (
              <circle
                cx={i === 0 ? x0 - 14 - pulse(traceLen, 0) : x0 + size + 14 + pulse(traceLen, 0.5)}
                cy={522}
                r={4}
                fill={i === 0 ? C.mint : C.violet}
                filter="url(#tglow)"
              />
            ) : null}
          </g>
        ))}
        {pins.map((p, i) => (
          <g key={i} fill="rgba(200,210,230,0.32)">
            <rect x={x0 + p - 3} y={y0 - 14} width={6} height={10} rx={1.5} />
            <rect x={x0 + p - 3} y={y0 + size + 4} width={6} height={10} rx={1.5} />
            <rect x={x0 - 14} y={y0 + p - 3} width={10} height={6} rx={1.5} />
            <rect x={x0 + size + 4} y={y0 + p - 3} width={10} height={6} rx={1.5} />
          </g>
        ))}
      </svg>
      <div
        style={{
          position: "absolute",
          left: x0,
          top: y0,
          width: size,
          height: size,
          borderRadius: 46,
          padding: 2,
          opacity: k,
          transform: `translateY(${(1 - k) * 50}px) scale(${0.9 + 0.1 * k})`,
          background: `conic-gradient(from ${t * 50}deg, ${AURORA.join(", ")})`,
          boxShadow: `0 0 60px rgba(79,199,252,${0.25 * k}), 0 30px 60px rgba(0,0,0,0.5)`,
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            borderRadius: 44,
            background:
              "repeating-linear-gradient(0deg, rgba(255,255,255,0.025) 0 1px, transparent 1px 22px), repeating-linear-gradient(90deg, rgba(255,255,255,0.025) 0 1px, transparent 1px 22px), linear-gradient(145deg, #1d2029, #0b0c11)",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 4,
          }}
        >
          <Buddy size={92} t={t} mood="idle" glow={1.2} />
          <div style={{ font: `600 17px ${BODY}`, letterSpacing: "0.22em", color: "rgba(245,246,248,0.55)" }}>YOUR MAC</div>
        </div>
      </div>
    </>
  );
};

export const Private: React.FC<{ t: number }> = ({ t }) => {
  const exit = ramp(t, 36.65, 0.5, E.in);
  const chip = ramp(t, 31.55, 0.9, E.out);
  const draw = ramp(t, 32.1, 0.55, E.gentle);
  const pillL = ramp(t, 32.45, 0.6, E.out);
  const pillR = ramp(t, 32.6, 0.6, E.out);
  const s1 = ramp(t, 33.2, 0.6, E.out);
  const s2 = ramp(t, 33.45, 0.6, E.out);
  const s3 = ramp(t, 33.7, 0.6, E.out);
  const count = (from: number, to: number, start: number, dur = 1.0) => lerp(from, to, ramp(t, start, dur, E.out));
  return (
    <AbsoluteFill style={{ opacity: 1 - exit, filter: exit > 0.01 ? `blur(${exit * 12}px)` : undefined, transform: `translateY(${-exit * 30}px)` }}>
      <div style={{ position: "absolute", top: 70, left: 0, right: 0 }}>
        <Words text="PRIVATE BY DESIGN" t={t} start={31.0} stagger={0.03} size={22} weight={700} letterSpacing={0.28} font={BODY} gradient style={{ marginBottom: 14 }} />
        <Words text="Runs [100%] on your Mac." t={t} start={31.12} size={80} />
        <Words text="No cloud. No account. Nothing saved." t={t} start={31.6} stagger={0.05} size={31} weight={400} font={BODY} color="#a9aebb" letterSpacing={-0.01} style={{ marginTop: 16 }} />
      </div>
      <ChipArt t={t} k={chip} draw={draw} />
      <Pill title="Qwen3.5 9B" sub="on the GPU, via MLX" side="left" k={pillL} />
      <Pill title="Parakeet" sub="on the Neural Engine" side="right" k={pillR} />
      <Stat x={196} value={`${Math.round(count(0, 587, 33.2))}ms`} label="speech to first word" k={s1} />
      <Stat x={540} value={`${count(0, 1.7, 33.45).toFixed(1)}%`} label="word error rate" k={s2} />
      <Stat x={884} value="0 bytes" label="leave your Mac" k={s3} />
    </AbsoluteFill>
  );
};

// ---------- Montage ----------
const USES: [number, string][] = [
  [37.3, "sales calls."],
  [37.75, "pitches."],
  [38.2, "standups."],
  [38.65, "client meetings."],
  [39.1, "every call."],
];
const MONTAGE_MOODS: [number, Mood][] = [
  [37.0, "listening"],
  [37.3, "alert"],
  [37.75, "happy"],
  [38.2, "thinking"],
  [38.65, "alert"],
  [39.1, "happy"],
];

export const Montage: React.FC<{ t: number }> = ({ t }) => {
  const enter = ramp(t, 37.0, 0.5, E.out);
  const exit = ramp(t, 40.0, 0.35, E.in);
  const { value: mood, since } = schedule(t, MONTAGE_MOODS);
  const beat = USES.reduce((b, [at]) => (t >= at ? at : b), 0);
  const flash = beat ? Math.exp(-(t - beat) * 5) : 0;
  return (
    <AbsoluteFill style={{ opacity: enter * (1 - exit), filter: exit > 0.01 ? `blur(${exit * 14}px)` : undefined }}>
      <AbsoluteFill style={{ background: `radial-gradient(circle at 50% 42%, rgba(148,120,255,${0.16 + 0.22 * flash}), rgba(79,199,252,${0.06 + 0.08 * flash}) 35%, transparent 62%)` }} />
      <div style={{ position: "absolute", left: 540, top: 395, transform: `translate(-50%, -50%) scale(${0.85 + 0.15 * enter + 0.04 * flash})` }}>
        <Buddy size={210} t={t} mood={mood} moodSince={since} glow={1.5} />
      </div>
      <div style={{ position: "absolute", top: 625, left: 0, right: 0, textAlign: "center", font: `500 44px ${DISPLAY}`, color: "#a9aebb", letterSpacing: "-0.02em" }}>Your backup for</div>
      <div style={{ position: "absolute", top: 690, left: 0, right: 0, height: 150, overflow: "hidden" }}>
        {USES.map(([at, word], i) => {
          const next = USES[i + 1]?.[0] ?? 99;
          const p = ramp(t, at + 0.08, 0.32, E.out);
          const q = ramp(t, next, 0.12, E.in);
          if (p <= 0 || q >= 1) return null;
          const last = i === USES.length - 1;
          return (
            <div
              key={word}
              style={{
                position: "absolute",
                left: 0,
                right: 0,
                top: 0,
                textAlign: "center",
                font: `600 ${last ? 118 : 108}px ${DISPLAY}`,
                letterSpacing: "-0.045em",
                lineHeight: 1.15,
                transform: `translateY(${(1 - p) * 150 - q * 150}px)`,
                opacity: Math.min(1, p * 1.6) * (1 - q),
                filter: (1 - p) + q > 0.05 ? `blur(${(1 - p) * 6 + q * 6}px)` : undefined,
                ...(last ? gradText : { color: "#f5f6f8" }),
              }}
            >
              {word}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ---------- End card ----------
export const End: React.FC<{ t: number }> = ({ t }) => {
  const horizon = lerp(1250, 880, ramp(t, 40.0, 1.6, E.out));
  const light = ramp(t, 40.1, 1.0, E.soft);
  const icon = ramp(t, 40.25, 1.0, E.out);
  const pill = ramp(t, 41.6, 0.7, E.out);
  const sign = ramp(t, 42.0, 0.8, E.out);
  const fade = ramp(t, 44.62, 0.38, E.in);
  return (
    <AbsoluteFill style={{ opacity: 1 - fade }}>
      <Planet horizon={horizon} light={light} t={t} />
      <div
        style={{
          position: "absolute",
          left: 540,
          top: 265,
          width: 176,
          height: 176,
          transform: `translate(-50%, -50%) translateY(${(1 - icon) * 60 + Math.sin(t * 1.4) * 6}px) rotate(${-8 + Math.sin(t * 1.1) * 3}deg) scale(${0.8 + 0.2 * icon})`,
          opacity: icon,
          filter: `drop-shadow(0 0 40px rgba(79,199,252,${0.35 * icon})) drop-shadow(0 20px 30px rgba(0,0,0,0.5))`,
        }}
      >
        <Img src={staticFile("icon.png")} style={{ width: "100%", height: "100%" }} />
      </div>
      <div style={{ position: "absolute", top: 410, left: 0, right: 0 }}>
        <Words text="You’ve got this." t={t} start={40.55} size={88} />
        <Words text="And you’ve got [Assist.]" t={t} start={40.95} size={88} color="#8f96a5" />
      </div>
      <div style={{ position: "absolute", top: 655, left: 0, right: 0, display: "flex", justifyContent: "center", opacity: pill, transform: `translateY(${(1 - pill) * 20}px)` }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 16,
            padding: "15px 28px",
            borderRadius: 40,
            background: "#f0f2f5",
            color: "#16181a",
            font: `600 26px ${BODY}`,
            boxShadow: "inset 0 1px 0 white, 0 0 40px rgba(186,208,255,0.25)",
          }}
        >
          Free for Mac
          <span style={{ width: 1, height: 22, background: "#16181a33" }} />
          <span style={{ fontWeight: 500, color: "#4a4f5a" }}>Apple silicon · macOS 26</span>
        </div>
      </div>
      <div style={{ position: "absolute", bottom: 42, left: 0, right: 0, textAlign: "center", font: `400 22px ${BODY}`, color: "rgba(169,174,187,0.85)", opacity: sign }}>
        Made with ❤️ by Hariharasudhan
      </div>
    </AbsoluteFill>
  );
};

