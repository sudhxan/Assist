// The Assist notch (Sources/Assist/UI/NotchRootView.swift + ExpandedView.swift), drawn in points.
// The caller scales it into the MacBook screen.
import React from "react";
import { AURORA, C, GRAD, SYS } from "../theme";
import { Buddy, Mood, Sparkle } from "./Buddy";

export const NOTCH = { w: 185, h: 32, ear: 54, flare: 8 };
export const SHAPES = {
  collapsed: { w: NOTCH.w + 2 * NOTCH.ear + 2 * NOTCH.flare, h: NOTCH.h, r: NOTCH.h * 0.36 },
  peek: { w: 460, h: NOTCH.h + 50, r: 18 },
  expanded: { w: 700, h: 480, r: 24 },
};
export type Shape = { w: number; h: number; r: number };

/** NotchShape: flares into the menu bar at the top corners, rounded at the bottom. */
export function notchPath({ w, h, r }: Shape) {
  const t = Math.min(NOTCH.flare, w / 4, h / 2);
  const b = Math.max(0, Math.min(r, h - t, (w - 2 * t) / 2));
  return [
    `M0,0`,
    `A${t},${t} 0 0 1 ${t},${t}`,
    `L${t},${h - b}`,
    `A${b},${b} 0 0 0 ${t + b},${h}`,
    `L${w - t - b},${h}`,
    `A${b},${b} 0 0 0 ${w - t},${h - b}`,
    `L${w - t},${t}`,
    `A${t},${t} 0 0 1 ${w},0`,
    `Z`,
  ].join(" ");
}

// ---------- Icons (SF Symbol stand-ins) ----------
const stroke = { fill: "none", stroke: "currentColor", strokeWidth: 1.5, strokeLinecap: "round", strokeLinejoin: "round" } as const;
type IconProps = { size?: number; color?: string };
const icon = (paths: React.ReactNode, vb = 16) =>
  function Icon({ size = 13, color = "currentColor" }: IconProps) {
    return (
      <svg width={size} height={size} viewBox={`0 0 ${vb} ${vb}`} style={{ color, display: "block", flexShrink: 0 }}>
        {paths}
      </svg>
    );
  };
export const Icons = {
  trash: icon(<path {...stroke} d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5M7 7v4M9 7v4" />),
  refresh: icon(<path {...stroke} d="M12.5 8a4.5 4.5 0 1 1-1.4-3.3M11.5 2.5v2.5H9" />),
  copy: icon(<path {...stroke} d="M5.5 5.5V3.5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-2M3.5 5.5h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1Z" />),
  pin: icon(<path fill="currentColor" d="M5.5 1.5h5l-.7 4.2 2.2 2.3v1.2H8.6V14l-.6 1-.6-1V9.2H4v-1.2l2.2-2.3z" />),
  gear: icon(
    <g fill="currentColor">
      <path d="M8 1.2 9.3 2.6l1.9-.3.5 1.8 1.8.6-.3 1.9L14.8 8l-1.4 1.4.3 1.9-1.8.6-.5 1.8-1.9-.3L8 14.8l-1.3-1.4-1.9.3-.5-1.8-1.8-.6.3-1.9L1.2 8l1.4-1.3-.3-1.9 1.8-.6.5-1.8 1.9.3z" />
      <circle cx="8" cy="8" r="2.4" fill="#000" />
    </g>,
  ),
  screen: icon(<path {...stroke} d="M2 5V3.5A1.5 1.5 0 0 1 3.5 2H5M11 2h1.5A1.5 1.5 0 0 1 14 3.5V5M14 11v1.5a1.5 1.5 0 0 1-1.5 1.5H11M5 14H3.5A1.5 1.5 0 0 1 2 12.5V11M5.5 6.5h5v4h-5zM7 6.5l.6-1h.8l.6 1" />),
  recap: icon(<path {...stroke} d="M4 1.8h8a.8.8 0 0 1 .8.8v10.8a.8.8 0 0 1-.8.8H4a.8.8 0 0 1-.8-.8V2.6a.8.8 0 0 1 .8-.8ZM5.5 5h5M5.5 7.5h5M5.5 10h3" />),
  bulb: icon(<path {...stroke} d="M8 3.5a3.5 3.5 0 0 0-2 6.4V11h4V9.9a3.5 3.5 0 0 0-2-6.4ZM6.5 13h3M8 .8v1M2.7 2.7l.7.7M13.3 2.7l-.7.7M1 8h1M14 8h1" />),
  book: icon(<path {...stroke} d="M3 2.5h7.5a1.5 1.5 0 0 1 1.5 1.5v9.5H4.5A1.5 1.5 0 0 1 3 12V2.5ZM3 12a1.5 1.5 0 0 1 1.5-1.5H12M5.5 5h4M5.5 7h3" />),
  mic: icon(<path {...stroke} d="M8 1.8a2 2 0 0 1 2 2v4a2 2 0 0 1-4 0v-4a2 2 0 0 1 2-2ZM4 7.5a4 4 0 0 0 8 0M8 11.5v2.5" />),
  up: icon(<path {...stroke} strokeWidth={1.8} d="M8 12.5v-9M4.5 7 8 3.5 11.5 7" />),
};

// ---------- Small indicators ----------
export const Waveform: React.FC<{ t: number; level: number; height: number }> = ({ t, level, height }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 2.5, height }}>
    {[0, 1, 2, 3].map((i) => {
      const wobble = 0.5 + 0.5 * Math.sin(t * 8 + i * 1.7);
      const fraction = Math.min(1, 0.2 + level * (0.5 + 0.5 * wobble) + 0.07 * wobble);
      return <div key={i} style={{ width: 3, height: Math.max(3, height * fraction), borderRadius: 2, background: `linear-gradient(to top, ${C.mint}, ${C.sky})` }} />;
    })}
  </div>
);

const SparkleSpinner: React.FC<{ t: number; size: number }> = ({ t, size }) => (
  <div style={{ transform: `rotate(${t * 120}deg) scale(${1 + 0.12 * Math.sin(t * 6)})` }}>
    <Sparkle size={size * 1.25} color={AURORA[Math.floor((t * 3) % 4)]} />
  </div>
);

const PulseDot: React.FC<{ t: number }> = ({ t }) => {
  const phase = (t / 1.4) % 1;
  return (
    <div style={{ position: "relative", width: 20, height: 20 }}>
      <div style={{ position: "absolute", left: 10 - (4 + phase * 6), top: 10 - (4 + phase * 6), width: 8 + phase * 12, height: 8 + phase * 12, borderRadius: "50%", border: `1.5px solid rgba(94,242,194,${1 - phase})` }} />
      <div style={{ position: "absolute", left: 6, top: 6 - Math.abs(Math.sin(phase * Math.PI * 2)) * 3, width: 8, height: 8, borderRadius: "50%", background: C.mint, boxShadow: `0 0 8px ${C.mint}` }} />
    </div>
  );
};

const gradText: React.CSSProperties = { background: GRAD, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent" };

// ---------- Panel content ----------
export type Line = { who: "Them" | "You"; time: string; text: string };
export type Rich = { text: string; bold?: boolean }[];

export type AnswerCard = {
  label: string;
  counter?: string;
  question: string;
  /** Optional big calculation line, shown above the bullets. */
  calc?: { text: string; unit: string };
  bullets: Rich[];
  /** Characters revealed so far (streaming), across calc + bullets. */
  shown: number;
  footer: string;
  /** Live end-of-speech → first-word timer. */
  latency?: { ms: number; final: boolean };
};

export type PanelModel = {
  status: string;
  listening: boolean;
  transcript: Line[];
  answer: AnswerCard | null;
  pressed?: { button: "Screen" | "Answer"; k: number };
};

const card: React.CSSProperties = {
  position: "absolute",
  background: "rgba(255,255,255,0.055)",
  border: "0.5px solid rgba(255,255,255,0.08)",
  borderRadius: 14,
  overflow: "hidden",
};
const label: React.CSSProperties = { fontSize: 10, fontWeight: 800, letterSpacing: 2.2 };

function richSlice(parts: Rich, budget: number) {
  const out: React.ReactNode[] = [];
  let used = 0;
  parts.forEach((p, i) => {
    const take = Math.max(0, Math.min(p.text.length, budget - used));
    used += p.text.length;
    if (take <= 0) return;
    const s = p.text.slice(0, take);
    out.push(
      p.bold ? (
        <span key={i} style={{ color: "#8ff5d6", fontWeight: 700 }}>
          {s}
        </span>
      ) : (
        <span key={i}>{s}</span>
      ),
    );
  });
  return out;
}
const richLen = (r: Rich) => r.reduce((n, p) => n + p.text.length, 0);

const Answer: React.FC<{ a: AnswerCard | null; t: number }> = ({ a, t }) => {
  if (!a) {
    return (
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6 }}>
        <Sparkle size={22} color={C.sky} style={{ opacity: 0.7, marginBottom: 6 }} />
        <div style={{ fontSize: 13, fontWeight: 700, color: "rgba(255,255,255,0.85)" }}>Hey! I’m your notch buddy.</div>
        <div style={{ fontSize: 11, fontWeight: 500, color: "rgba(255,255,255,0.4)" }}>Invisible to screen share. Answers land right here.</div>
      </div>
    );
  }
  let budget = a.shown;
  const calcLen = a.calc ? a.calc.text.length : 0;
  const calcShown = a.calc ? a.calc.text.slice(0, Math.max(0, Math.min(calcLen, budget))) : "";
  budget -= calcLen;
  const streaming = a.shown > 0 && a.shown < calcLen + a.bullets.reduce((n, b) => n + richLen(b), 0);
  return (
    <div style={{ position: "absolute", inset: 0, padding: "14px 16px" }}>
      <div style={{ display: "flex", alignItems: "center", height: 16 }}>
        <Sparkle size={12} color={C.sky} style={{ marginRight: 7 }} />
        <span style={{ ...label, ...gradText }}>{a.label}</span>
        {a.counter ? <span style={{ fontSize: 10, fontWeight: 600, color: "rgba(255,255,255,0.35)", marginLeft: 8 }}>{a.counter}</span> : null}
        <span style={{ flex: 1 }} />
        {a.latency ? (
          <span
            style={{
              display: "flex",
              alignItems: "center",
              gap: 5,
              fontSize: 10.5,
              fontWeight: 700,
              fontVariantNumeric: "tabular-nums",
              color: a.latency.final ? C.mint : "rgba(255,255,255,0.75)",
              background: a.latency.final ? "rgba(94,242,194,0.12)" : "rgba(255,255,255,0.07)",
              border: `0.5px solid ${a.latency.final ? "rgba(94,242,194,0.45)" : "rgba(255,255,255,0.1)"}`,
              borderRadius: 9,
              padding: "2px 7px",
              marginRight: 10,
            }}
          >
            <span style={{ width: 5, height: 5, borderRadius: 3, background: C.mint, opacity: a.latency.final ? 1 : 0.5 + 0.5 * Math.abs(Math.sin(t * 10)) }} />
            {Math.round(a.latency.ms)} ms
          </span>
        ) : null}
        <span style={{ color: "rgba(255,255,255,0.45)", display: "flex", gap: 14 }}>
          <Icons.refresh size={13} />
          <Icons.copy size={13} />
        </span>
      </div>
      <div style={{ fontSize: 11.5, lineHeight: "14.5px", fontWeight: 500, color: "rgba(255,255,255,0.45)", marginTop: 12 }}>{a.question}</div>
      <div style={{ height: 0.5, background: "rgba(255,255,255,0.1)", margin: "10px 0 9px" }} />
      {a.calc && calcShown ? (
        <div style={{ display: "flex", alignItems: "baseline", gap: 6, margin: "2px 0 10px" }}>
          <span style={{ fontSize: 25, fontWeight: 800, letterSpacing: -0.6, color: "#8ff5d6" }}>{calcShown}</span>
          {calcShown.length === calcLen ? <span style={{ fontSize: 12, fontWeight: 600, color: "rgba(255,255,255,0.5)" }}>{a.calc.unit}</span> : null}
        </div>
      ) : null}
      {a.bullets.map((b, i) => {
        const before = a.bullets.slice(0, i).reduce((n, x) => n + richLen(x), 0);
        const local = budget - before;
        if (local <= 0) return null;
        return (
          <div key={i} style={{ display: "flex", gap: 8, fontSize: 13.5, lineHeight: "17px", fontWeight: 500, color: "rgba(255,255,255,0.93)", marginBottom: 8 }}>
            <span style={{ ...gradText, fontWeight: 900 }}>•</span>
            <span>{richSlice(b, local)}</span>
          </div>
        );
      })}
      {streaming ? <span style={{ display: "inline-block", width: 6, height: 13, borderRadius: 2, background: C.mint, marginLeft: 16, opacity: 0.85 }} /> : null}
      {a.shown > 0 && !streaming ? (
        <div style={{ position: "absolute", left: 16, bottom: 12, fontSize: 10, fontWeight: 500, color: "rgba(255,255,255,0.3)" }}>{a.footer}</div>
      ) : null}
    </div>
  );
};

const Transcript: React.FC<{ lines: Line[] }> = ({ lines }) => (
  <div style={{ position: "absolute", inset: 0, padding: "14px 13px" }}>
    <div style={{ display: "flex", alignItems: "center", height: 16 }}>
      <span style={{ ...label, color: "rgba(255,255,255,0.5)" }}>LIVE</span>
      <span style={{ flex: 1 }} />
      <span style={{ color: "rgba(255,255,255,0.4)" }}>
        <Icons.trash size={13} />
      </span>
    </div>
    <div style={{ position: "absolute", left: 13, right: 13, top: 40, display: "flex", flexDirection: "column", gap: 11 }}>
      {lines.map((l, i) => (
        <div key={i}>
          <div style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11, fontWeight: 700, color: l.who === "Them" ? C.sky : C.mint, marginBottom: 3 }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: "currentColor" }} />
            {l.who}
            <span style={{ fontSize: 10, fontWeight: 500, color: "rgba(255,255,255,0.35)", marginLeft: 3 }}>{l.time}</span>
          </div>
          <div style={{ fontSize: 12.5, lineHeight: "15.5px", fontWeight: 500, color: "rgba(255,255,255,0.92)" }}>{l.text}</div>
        </div>
      ))}
    </div>
  </div>
);

const Chip: React.FC<{ icon: React.ReactNode; text: string; keys?: string; on?: number }> = ({ icon: i, text, keys, on = 0 }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 6,
      height: 26,
      padding: "0 10px",
      borderRadius: 13,
      background: `rgba(255,255,255,${0.07 + 0.1 * on})`,
      border: `0.5px solid ${on > 0.01 ? `rgba(94,242,194,${0.3 + 0.5 * on})` : "rgba(255,255,255,0.08)"}`,
      boxShadow: on > 0.01 ? `0 0 ${14 * on}px rgba(94,242,194,${0.35 * on})` : undefined,
      transform: `scale(${1 - 0.05 * Math.sin(Math.min(1, on) * Math.PI)})`,
      fontSize: 12,
      fontWeight: 600,
      color: "rgba(255,255,255,0.92)",
    }}
  >
    <span style={{ color: C.sky }}>{i}</span>
    {text}
    {keys ? <span style={{ fontSize: 9, fontWeight: 600, color: "rgba(255,255,255,0.35)" }}>{keys}</span> : null}
  </div>
);

const Panel: React.FC<{ m: PanelModel; t: number }> = ({ m, t }) => {
  const pad = 21;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: 700, height: 480 }}>
      {/* Header row, level with the camera housing */}
      <div style={{ position: "absolute", left: pad + 30, top: 4, height: 28, display: "flex", flexDirection: "column", justifyContent: "center" }}>
        <div style={{ fontSize: 12.5, fontWeight: 800, color: "white", lineHeight: "14px" }}>Assist</div>
        <div style={{ fontSize: 10, fontWeight: 500, lineHeight: "13px", color: m.listening ? "rgba(94,242,194,0.9)" : "rgba(255,255,255,0.45)", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>{m.status}</div>
      </div>
      <div style={{ position: "absolute", right: pad, top: 6, height: 22, display: "flex", alignItems: "center", gap: 10 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 5, height: 22, padding: "0 9px", borderRadius: 11, background: "rgba(255,255,255,0.09)", fontSize: 11, fontWeight: 800, color: "white" }}>
          <span style={{ width: 7, height: 7, borderRadius: 4, background: m.listening ? "#ff453a" : GRAD }} />
          {m.listening ? "Stop" : "Listen"}
        </div>
        <span style={{ color: C.sky, marginLeft: 4 }}>
          <Icons.pin size={14} />
        </span>
        <span style={{ color: "rgba(255,255,255,0.6)" }}>
          <Icons.gear size={15} />
        </span>
      </div>
      {/* Columns */}
      <div style={{ ...card, left: pad, top: 44, width: 249, height: 334 }}>
        <Transcript lines={m.transcript} />
      </div>
      <div style={{ ...card, left: pad + 259, top: 44, width: 399, height: 334 }}>
        <Answer a={m.answer} t={t} />
      </div>
      {/* Actions */}
      <div style={{ position: "absolute", left: pad, top: 390, display: "flex", gap: 7 }}>
        <Chip icon={<Sparkle size={12} color={C.sky} />} text="Answer" keys="⌘↩" on={m.pressed?.button === "Answer" ? m.pressed.k : 0} />
        <Chip icon={<Icons.screen size={13} />} text="Screen" keys="⌘⇧↩" on={m.pressed?.button === "Screen" ? m.pressed.k : 0} />
        <Chip icon={<Icons.recap size={13} />} text="Recap" />
        <Chip icon={<Icons.bulb size={13} />} text="Follow-ups" />
        <Chip icon={<Icons.book size={13} />} text="Explain" />
      </div>
      {/* Ask anything */}
      <div
        style={{
          position: "absolute",
          left: pad,
          right: pad,
          top: 428,
          height: 38,
          borderRadius: 12,
          background: "rgba(255,255,255,0.06)",
          border: "0.5px solid rgba(255,255,255,0.07)",
          display: "flex",
          alignItems: "center",
          padding: "0 6px 0 12px",
          gap: 7,
          fontSize: 13,
          fontWeight: 500,
          color: "rgba(255,255,255,0.4)",
        }}
      >
        <Sparkle size={14} color={C.sky} />
        Type or hold
        <span style={{ fontSize: 9.5, fontWeight: 700, color: "rgba(255,255,255,0.75)", background: "rgba(255,255,255,0.12)", borderRadius: 4, padding: "2px 5px" }}>command</span>
        to speak
        <span style={{ flex: 1 }} />
        <span style={{ width: 26, height: 26, borderRadius: 13, background: "rgba(255,255,255,0.1)", display: "grid", placeItems: "center", color: "rgba(255,255,255,0.75)" }}>
          <Icons.mic size={13} />
        </span>
        <span style={{ width: 26, height: 26, borderRadius: 13, background: "rgba(255,255,255,0.07)", display: "grid", placeItems: "center", color: "rgba(255,255,255,0.3)" }}>
          <Icons.up size={13} />
        </span>
      </div>
    </div>
  );
};

// ---------- The notch ----------
export type NotchModel = {
  t: number;
  shape: Shape;
  /** Opacity of each content layer. */
  ears: number;
  peek: number;
  panel: number;
  glow: number;
  shadow: number;
  buddy: { x: number; y: number; size: number; mood: Mood; since: number; level: number };
  rightEar: "wave" | "spinner" | "pulse" | "none";
  level: number;
  peekContent: { title: string; text: Rich } | null;
  panelModel: PanelModel;
};

export const Notch: React.FC<{ m: NotchModel }> = ({ m }) => {
  const { w, h } = m.shape;
  const d = notchPath(m.shape);
  const col = SHAPES.collapsed;
  const peek = SHAPES.peek;
  return (
    <div style={{ position: "relative", width: w, height: h, fontFamily: SYS, WebkitFontSmoothing: "antialiased" }}>
      <svg width={w} height={h} style={{ position: "absolute", inset: 0, overflow: "visible", filter: m.shadow > 0.01 ? `drop-shadow(0 8px 18px rgba(0,0,0,${0.45 * m.shadow}))` : undefined }}>
        <path d={d} fill="#000" />
      </svg>
      <div style={{ position: "absolute", inset: 0, clipPath: `path('${d}')` }}>
        {/* Collapsed ears, centered (also the top row of the peek) */}
        {m.ears > 0.001 ? (
          <div style={{ position: "absolute", left: (w - col.w) / 2, top: 0, width: col.w, height: col.h, opacity: m.ears }}>
            <div style={{ position: "absolute", right: NOTCH.flare + 10, top: 0, height: col.h, display: "flex", alignItems: "center" }}>
              {m.rightEar === "wave" ? <Waveform t={m.t} level={m.level} height={col.h * 0.42} /> : null}
              {m.rightEar === "spinner" ? <SparkleSpinner t={m.t} size={col.h * 0.38} /> : null}
              {m.rightEar === "pulse" ? <PulseDot t={m.t} /> : null}
            </div>
          </div>
        ) : null}
        {/* Peek: a one-line glance at the newest answer */}
        {m.peek > 0.001 && m.peekContent ? (
          <div style={{ position: "absolute", left: (w - peek.w) / 2, top: NOTCH.h, width: peek.w, height: 50, opacity: m.peek, display: "flex", alignItems: "center", gap: 10, padding: `0 ${NOTCH.flare + 14}px` }}>
            <span style={{ color: C.sky }}>
              <Icons.screen size={15} />
            </span>
            <div style={{ display: "flex", flexDirection: "column", gap: 1, minWidth: 0 }}>
              <div style={{ fontSize: 10.5, fontWeight: 500, color: "rgba(255,255,255,0.45)", whiteSpace: "nowrap" }}>{m.peekContent.title}</div>
              <div style={{ fontSize: 12.5, fontWeight: 500, color: "white", whiteSpace: "nowrap" }}>{richSlice(m.peekContent.text, 999)}</div>
            </div>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 9.5, fontWeight: 500, color: "rgba(255,255,255,0.3)", whiteSpace: "nowrap" }}>hover to open</span>
          </div>
        ) : null}
        {/* Expanded panel, scaling in from the top */}
        {m.panel > 0.001 ? (
          <div style={{ position: "absolute", left: (w - 700) / 2, top: 0, opacity: m.panel, transform: `scale(${0.97 + 0.03 * m.panel})`, transformOrigin: "50% 0" }}>
            <Panel m={m.panelModel} t={m.t} />
          </div>
        ) : null}
      </div>
      {/* Glow rim while an answer is being written */}
      {m.glow > 0.001 ? (
        <svg width={w} height={h} style={{ position: "absolute", inset: 0, overflow: "visible", opacity: m.glow }}>
          <defs>
            <linearGradient id="rim" gradientUnits="objectBoundingBox" gradientTransform={`rotate(${(m.t * 90) % 360} 0.5 0.5)`}>
              {AURORA.map((c, i) => (
                <stop key={i} offset={i / (AURORA.length - 1)} stopColor={c} />
              ))}
            </linearGradient>
            <linearGradient id="rimfade" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#fff" stopOpacity="0" />
              <stop offset="0.35" stopColor="#fff" stopOpacity="1" />
            </linearGradient>
            <mask id="rimmask" maskUnits="userSpaceOnUse" x={-20} y={-20} width={w + 40} height={h + 40}>
              <rect x={-20} y={0} width={w + 40} height={h + 20} fill="url(#rimfade)" />
            </mask>
            <filter id="rimblur" x="-10%" y="-10%" width="120%" height="120%">
              <feGaussianBlur stdDeviation="1.2" />
            </filter>
            <filter id="rimglow" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="6" />
            </filter>
          </defs>
          <g mask="url(#rimmask)">
            <path d={d} fill="none" stroke="url(#rim)" strokeWidth={5} filter="url(#rimglow)" opacity={0.55} />
            <path d={d} fill="none" stroke="url(#rim)" strokeWidth={1.6} filter="url(#rimblur)" />
          </g>
        </svg>
      ) : null}
      {/* The one buddy, hopping between its seats */}
      <div style={{ position: "absolute", left: w / 2 + m.buddy.x, top: m.buddy.y, transform: "translate(-50%, -50%)" }}>
        <Buddy size={m.buddy.size} t={m.t} mood={m.buddy.mood} moodSince={m.buddy.since} level={m.buddy.level} />
      </div>
      {/* Camera lens in the housing */}
      <div style={{ position: "absolute", left: w / 2 - 3, top: 13, width: 6, height: 6, borderRadius: 3, background: "radial-gradient(circle at 60% 35%, #2d3f56, #05080c)", boxShadow: "0 0 0 2px #0f1114" }} />
    </div>
  );
};
