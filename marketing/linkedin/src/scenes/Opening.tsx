// Scene 1 (hook) and scene 2 (brand reveal on a planet's horizon). Absolute times in seconds.
import React from "react";
import { AbsoluteFill } from "remotion";
import { E, lerp, ramp, schedule } from "../anim";
import { Buddy, Mood } from "../components/Buddy";
import { Planet } from "../components/Planet";
import { Words, gradText } from "../components/Words";
import { BODY, C, DISPLAY } from "../theme";

export const Hook: React.FC<{ t: number }> = ({ t }) => {
  const push = 1 + 0.035 * t;
  const out = ramp(t, 2.72, 0.35, E.in);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", transform: `scale(${push + out * 0.25})` }}>
      <div style={{ position: "absolute", top: 395, left: 0, right: 0 }}>
        <Words text={"Every call has\nthat one [question.]"} t={t} start={0.12} end={1.72} stagger={0.075} size={108} lineHeight={1.08} />
      </div>
      <div style={{ position: "absolute", top: 470, left: 0, right: 0, opacity: 1 - out, filter: out > 0.01 ? `blur(${out * 14}px)` : undefined }}>
        <Words text="Meet your [backup.]" t={t} start={2.0} stagger={0.08} size={108} />
      </div>
    </AbsoluteFill>
  );
};

// ---------- Brand ----------
type ChipKind = "call" | "ai" | "chip" | "wave";
const CHIPS: { label: string; kind: ChipKind; color: string; x: number; y: number; z: number; order: number }[] = [
  { label: "On-device", kind: "chip", color: C.mint, x: 540, y: 612, z: 1.08, order: 0 },
  { label: "Claude", kind: "ai", color: "#d97757", x: 318, y: 662, z: 1, order: 3 },
  { label: "Google Meet", kind: "call", color: "#1e8e3e", x: 772, y: 668, z: 1, order: 2 },
  { label: "Zoom", kind: "call", color: "#2d8cff", x: 168, y: 600, z: 0.84, order: 5 },
  { label: "Gemini", kind: "ai", color: "#5b7cfa", x: 920, y: 598, z: 0.84, order: 4 },
  { label: "Microsoft Teams", kind: "call", color: "#5b5fc7", x: 548, y: 724, z: 1.02, order: 1 },
  { label: "OpenRouter", kind: "ai", color: "#6467f2", x: 238, y: 742, z: 0.94, order: 7 },
  { label: "Webex", kind: "call", color: "#07a6c9", x: 868, y: 744, z: 0.92, order: 6 },
  { label: "Qwen3.5", kind: "ai", color: "#8a6cff", x: 388, y: 562, z: 0.74, order: 9 },
  { label: "Parakeet", kind: "wave", color: "#76b900", x: 700, y: 556, z: 0.74, order: 8 },
  { label: "Slack", kind: "call", color: "#e01e5a", x: 92, y: 690, z: 0.7, order: 10 },
  { label: "MLX", kind: "chip", color: "#ff9f0a", x: 996, y: 686, z: 0.7, order: 11 },
];

const Glyph: React.FC<{ kind: ChipKind; color: string; size: number }> = ({ kind, color, size }) => {
  const s = { fill: "none", stroke: color, strokeWidth: 1.9, strokeLinecap: "round", strokeLinejoin: "round" } as const;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24">
      {kind === "call" ? (
        <>
          <rect x="3" y="7" width="12" height="10" rx="2.5" {...s} />
          <path d="m15 11 5-3v8l-5-3" {...s} />
        </>
      ) : kind === "chip" ? (
        <>
          <rect x="6" y="6" width="12" height="12" rx="2.5" {...s} />
          <path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3" {...s} />
        </>
      ) : kind === "wave" ? (
        <path d="M4 12h1M8 8v8M12 5v14M16 9v6M20 12h0" {...s} strokeWidth={2.2} />
      ) : (
        <path d="M12 3c.6 4.4 2.6 6.4 7 7-4.4.6-6.4 2.6-7 7-.6-4.4-2.6-6.4-7-7 4.4-.6 6.4-2.6 7-7Z" fill={color} />
      )}
    </svg>
  );
};

const Chip: React.FC<{ c: (typeof CHIPS)[number]; t: number; start: number; exit: number }> = ({ c, t, start, exit }) => {
  const at = start + c.order * 0.075;
  const p = ramp(t, at, 0.7, E.pop);
  const o = ramp(t, at, 0.3);
  if (o <= 0.001) return null;
  const far = c.z < 0.8;
  const bob = Math.sin(t * 0.9 + c.order * 1.3) * 5 * c.z;
  const drift = (t - at) * -3 * c.z;
  const h = 52 * c.z;
  return (
    <div
      style={{
        position: "absolute",
        left: c.x,
        top: c.y + bob + drift - exit * 40 * c.z,
        transform: `translate(-50%, -50%) scale(${0.6 + 0.4 * p})`,
        opacity: o * (far ? 0.7 : 1) * (1 - exit),
        filter: far || exit > 0.01 ? `blur(${(far ? 1.2 : 0) + exit * 8}px)` : undefined,
        display: "flex",
        alignItems: "center",
        gap: 10 * c.z,
        height: h,
        padding: `0 ${18 * c.z}px 0 ${8 * c.z}px`,
        borderRadius: h / 2,
        background: c.kind === "chip" && c.label === "On-device" ? "rgba(18,40,36,0.85)" : "rgba(16,18,28,0.8)",
        border: `1px solid ${c.label === "On-device" ? "rgba(94,242,194,0.55)" : "rgba(255,255,255,0.13)"}`,
        boxShadow: `inset 0 1px 0 rgba(255,255,255,0.08), 0 8px 24px rgba(0,0,0,0.45)${c.label === "On-device" ? ", 0 0 28px rgba(94,242,194,0.25)" : ""}`,
        whiteSpace: "nowrap",
      }}
    >
      <div style={{ width: 36 * c.z, height: 36 * c.z, borderRadius: "50%", background: "#f4f6fa", display: "grid", placeItems: "center" }}>
        <Glyph kind={c.kind} color={c.color} size={22 * c.z} />
      </div>
      <span style={{ font: `500 ${23 * c.z}px ${BODY}`, color: "rgba(245,246,248,0.92)", letterSpacing: "-0.01em" }}>{c.label}</span>
    </div>
  );
};

const BUDDY_MOODS: [number, Mood][] = [
  [0, "sleeping"],
  [3.3, "waking"],
  [3.95, "happy"],
  [5.0, "idle"],
];

export const Brand: React.FC<{ t: number }> = ({ t }) => {
  const exit = ramp(t, 7.45, 0.55, E.in);
  const horizon = lerp(1260, 846, ramp(t, 2.95, 1.5, E.out)) + exit * 320;
  const light = ramp(t, 3.05, 0.9, E.soft) * (1 - exit * 0.7);
  const rise = ramp(t, 3.2, 1.35, E.out);
  const buddyY = lerp(1040, 200, rise);
  const { value: mood, since } = schedule(t, BUDDY_MOODS);

  const title = "Assist";
  const sweep = ramp(t, 4.5, 1.1, E.gentle);
  const groupStyle: React.CSSProperties = {
    transform: `scale(${1 + exit * 0.18})`,
    transformOrigin: "50% 45%",
    opacity: 1 - exit,
    filter: exit > 0.01 ? `blur(${exit * 14}px)` : undefined,
  };

  return (
    <AbsoluteFill>
      {/* The buddy rises from behind the planet like a sunrise */}
      <AbsoluteFill style={groupStyle}>
        <div style={{ position: "absolute", left: 540, top: buddyY, transform: "translate(-50%, -50%)" }}>
          <div style={{ position: "absolute", left: "50%", top: "50%", width: 360, height: 360, transform: "translate(-50%, -50%)", borderRadius: "50%", background: "radial-gradient(circle, rgba(79,199,252,0.28), rgba(148,120,255,0.1) 45%, transparent 70%)", opacity: rise }} />
          <Buddy size={150} t={t} mood={mood} moodSince={since} glow={1.4} />
        </div>
      </AbsoluteFill>
      <Planet horizon={horizon} light={light} t={t} />
      <AbsoluteFill style={groupStyle}>
        {/* Wordmark */}
        <div style={{ position: "absolute", top: 292, left: 0, right: 0, textAlign: "center", font: `600 176px ${DISPLAY}`, letterSpacing: "-0.045em", lineHeight: 1 }}>
          <span style={{ position: "relative", display: "inline-block" }}>
            {title.split("").map((ch, i) => {
              const p = ramp(t, 3.55 + i * 0.05, 0.8, E.out);
              return (
                <span
                  key={i}
                  style={{
                    display: "inline-block",
                    opacity: p,
                    transform: `translateY(${(1 - p) * 40}px)`,
                    filter: p < 0.99 ? `blur(${(1 - p) * 16}px)` : undefined,
                    background: "linear-gradient(180deg, #ffffff 30%, #aeb3c2 100%)",
                    WebkitBackgroundClip: "text",
                    backgroundClip: "text",
                    color: "transparent",
                  }}
                >
                  {ch}
                </span>
              );
            })}
            {/* Aurora shimmer sweeping across once */}
            <span
              style={{
                position: "absolute",
                inset: 0,
                ...gradText,
                opacity: sweep > 0 && sweep < 1 ? 1 : 0,
                WebkitMaskImage: `linear-gradient(100deg, transparent ${sweep * 160 - 50}%, black ${sweep * 160 - 25}%, transparent ${sweep * 160}%)`,
                maskImage: `linear-gradient(100deg, transparent ${sweep * 160 - 50}%, black ${sweep * 160 - 25}%, transparent ${sweep * 160}%)`,
              }}
            >
              {title}
            </span>
          </span>
        </div>
        <div style={{ position: "absolute", top: 482, left: 0, right: 0 }}>
          <Words text="The AI meeting copilot that lives in your MacBook’s notch." t={t} start={4.0} stagger={0.035} size={33} weight={400} font={BODY} color="#a9aebb" letterSpacing={-0.01} />
        </div>
      </AbsoluteFill>
      {/* Ecosystem chips floating above the horizon */}
      {CHIPS.map((c) => (
        <Chip key={c.label} c={c} t={t} start={4.35} exit={exit} />
      ))}
    </AbsoluteFill>
  );
};

