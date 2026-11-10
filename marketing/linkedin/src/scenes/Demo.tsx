// Scenes 3–5 on one continuous MacBook: answer a question live, read the screen, stay invisible on share.
// All times are absolute seconds in the video.
import React from "react";
import { AbsoluteFill } from "remotion";
import { E, clamp, lerp, ramp, schedule, swiftSpring, track, window01 } from "../anim";
import { MacBook, MB, MeetState } from "../components/MacBook";
import { Notch, NotchModel, SHAPES, NOTCH, Rich, Line, AnswerCard } from "../components/Notch";
import { Mood } from "../components/Buddy";
import { Words, gradText } from "../components/Words";
import { C, BODY, DISPLAY, SYS } from "../theme";

const K = 0.8; // MacBook screen px per app point

// ---------- Script ----------
const LINE1 = "Thanks for walking us through Bloom. The demo looked great.";
const LINE2 = "Happy to! It’s built for teams exactly like yours.";
const LINE3 = "We love the idea. But how does it actually save our team time?";
const LINE4 = "What’s the monthly cost for our 20-person team?";

const Q1_START = 9.9;
const Q1_END = 13.6;
const FIRST_WORD = Q1_END + 0.587; // measured: median 587 ms from end of speech to first word
const A1_CPS = 125;
const Q2_START = 20.4;
const Q2_END = 22.2;
const SCREEN_KEY = 22.3;
const SCAN = 22.45;
const PEEK = 23.4;

const ANSWER1: Rich[] = [
  [{ text: "Follow-ups write themselves", bold: true }, { text: ": notes, tasks and handoffs after every call." }],
  [{ text: "About 12 hours back", bold: true }, { text: " per person, every week." }],
  [{ text: "Start with one workflow", bold: true }, { text: " and measure it in two weeks." }],
];
const A1_LEN = ANSWER1.reduce((n, b) => n + b.reduce((m, p) => m + p.text.length, 0), 0);
const A1_DONE = FIRST_WORD + A1_LEN / A1_CPS;

const ANSWER2: Rich[] = [
  [{ text: "About 240 hours back", bold: true }, { text: " every week, by the slide’s 12h." }],
  [{ text: "Offer a two-week pilot", bold: true }, { text: " to prove it first." }],
];

const speaking = (t: number) => (t < 9.6 ? "you" : t > Q1_START && t < Q1_END ? "alex" : t > Q2_START && t < Q2_END ? "alex" : null);
const voiceLevel = (t: number) => (speaking(t) ? 0.45 + 0.42 * Math.abs(Math.sin(t * 6.3)) * (0.6 + 0.4 * Math.sin(t * 2.3)) : 0.06);

/** Words appear as they're recognized: whole words, at speech pace. */
const spoken = (text: string, t: number, a: number, b: number) => {
  const words = text.split(" ");
  const n = Math.floor(clamp((t - a) / (b - a)) * words.length + (t >= a ? 1 : 0));
  return words.slice(0, Math.min(words.length, n)).join(" ");
};

const clock = (secs: number) => `${Math.floor(secs / 60)}:${String(Math.floor(secs % 60)).padStart(2, "0")}`;

// ---------- Notch state machine ----------
type State = "collapsed" | "peek" | "expanded";
const STATES: [number, State][] = [
  [0, "collapsed"],
  [12.0, "expanded"],
  [19.3, "collapsed"],
  [PEEK, "peek"],
  [25.1, "expanded"],
];
const MOODS: [number, Mood][] = [
  [0, "listening"],
  [Q1_END, "alert"],
  [FIRST_WORD, "thinking"],
  [A1_DONE, "happy"],
  [A1_DONE + 1.7, "listening"],
  [SCREEN_KEY, "alert"],
  [SCAN + 0.15, "thinking"],
  [PEEK, "happy"],
  [PEEK + 1.6, "listening"],
];

const SEATS = {
  ear: { x: -SHAPES.collapsed.w / 2 + NOTCH.flare + 6 + 12.5, y: 16, size: NOTCH.h * 0.58 },
  header: { x: -350 + 21 + 13.5, y: 17, size: 20 },
};

function notchAt(t: number): NotchModel {
  let i = 0;
  while (i + 1 < STATES.length && t >= STATES[i + 1][0]) i++;
  const [since, cur] = STATES[i];
  const prev = i > 0 ? STATES[i - 1][1] : cur;
  const dt = t - since;
  const k = swiftSpring(dt, 0.46, 0.66);
  const a = SHAPES[prev];
  const b = SHAPES[cur];
  const shape = { w: lerp(a.w, b.w, k), h: lerp(a.h, b.h, k), r: lerp(a.r, b.r, k) };

  const earsOn = (s: State) => s !== "expanded";
  const layer = (on: (s: State) => boolean, inDelay = 0.06, inDur = 0.22) => {
    if (on(cur)) return on(prev) ? 1 : ramp(dt, inDelay, inDur);
    return on(prev) ? 1 - ramp(dt, 0, 0.1) : 0;
  };
  const ears = layer(earsOn);
  const peek = layer((s) => s === "peek", 0.1, 0.25);
  const panel = layer((s) => s === "expanded", 0.04, 0.3);

  // The buddy hops between the ear and the header with a little arc.
  const seatOf = (s: State) => (s === "expanded" ? SEATS.header : SEATS.ear);
  const sa = seatOf(prev);
  const sb = seatOf(cur);
  const ks = swiftSpring(dt, 0.6, 0.62);
  const moved = sa !== sb;
  const arc = moved ? -26 * Math.sin(Math.PI * clamp(dt / 0.55)) : 0;
  const { value: mood, since: moodSince } = schedule(t, MOODS);

  const generating = window01(t, FIRST_WORD, A1_DONE + 0.15, 0.15, 0.4) + window01(t, SCAN, PEEK + 0.1, 0.15, 0.3);
  const rightEar = t >= SCAN - 0.1 && t < PEEK ? "spinner" : t >= PEEK && t < 25.1 ? "pulse" : "wave";

  // Panel content
  const session = 74 + (t - Q1_END);
  const transcript: Line[] =
    t < 19.3
      ? [
          { who: "Them", time: "1:02", text: LINE1 },
          { who: "You", time: "1:09", text: LINE2 },
          ...(t >= Q1_START ? [{ who: "Them" as const, time: "1:14", text: spoken(LINE3, t, Q1_START, Q1_END) }] : []),
        ]
      : [
          { who: "Them", time: "1:02", text: LINE1 },
          { who: "You", time: "1:09", text: LINE2 },
          { who: "Them", time: "1:14", text: LINE3 },
          ...(t >= Q2_START ? [{ who: "Them" as const, time: "1:20", text: spoken(LINE4, t, Q2_START, Q2_END) }] : []),
        ];
  let answer: AnswerCard | null = null;
  if (t >= Q1_END && t < 19.3) {
    answer = {
      label: "ANSWER",
      question: LINE3,
      bullets: ANSWER1,
      shown: Math.max(0, (t - FIRST_WORD) * A1_CPS),
      footer: "Qwen3.5 9B · on-device · 1:14 PM",
      latency: { ms: Math.min(587, (t - Q1_END) * 1000), final: t >= FIRST_WORD },
    };
  } else if (t >= 19.3) {
    answer = {
      label: "SCREEN",
      counter: "2/2",
      question: LINE4,
      calc: { text: "20 × $49 = $980", unit: "/ month" },
      bullets: ANSWER2,
      shown: 999,
      footer: "Qwen3.5 9B · read from your screen · 1:20 PM",
    };
  }

  return {
    t,
    shape,
    ears,
    peek,
    panel,
    glow: clamp(generating),
    shadow: clamp((shape.h - NOTCH.h) / 40),
    buddy: {
      x: lerp(sa.x, sb.x, ks),
      y: lerp(sa.y, sb.y, ks) + arc,
      size: lerp(sa.size, sb.size, ks),
      mood,
      since: moodSince,
      level: voiceLevel(t),
    },
    rightEar,
    level: voiceLevel(t),
    peekContent: { title: LINE4, text: [{ text: "20 × $49 = $980 / month", bold: true }, { text: " for your team" }] },
    panelModel: {
      status: `Listening · mic + call · Parakeet · ${clock(session)}`,
      listening: true,
      transcript,
      answer,
    },
  };
}

// ---------- Camera ----------
type Cam = { s: number; fx: number; fy: number; cx: number; cy: number; rx: number; op: number; blur: number };
const full: Cam = { s: 0.95, fx: 560, fy: 330, cx: 540, cy: 618, rx: 0, op: 1, blur: 0 };
const panelFocus = { fx: 560, fy: MB.screenY + 240 * K };
const cardFocus = { fx: 560 + (280 + 199.5 - 350) * K, fy: MB.screenY + 211 * K };
const CAMERA: [number, Cam, ((x: number) => number)?][] = [
  [7.8, { ...full, s: 0.6, cy: 680, rx: 32, op: 0, blur: 16 }],
  [9.1, full, E.out],
  [9.9, full],
  [11.9, { ...full, s: 1.3, fy: 210, cy: 560 }],
  [12.9, { ...full, s: 1.74, ...panelFocus, cy: 612 }],
  [15.6, { ...full, s: 1.74, ...panelFocus, cy: 612 }],
  [16.8, { ...full, s: 2.55, ...cardFocus, cy: 622 }],
  [18.7, { ...full, s: 2.55, ...cardFocus, cy: 622 }],
  [19.9, full],
  [23.3, full],
  [24.3, { ...full, s: 2.3, fy: MB.screenY + 41 * K, cy: 545 }],
  [25.0, { ...full, s: 2.3, fy: MB.screenY + 41 * K, cy: 545 }],
  [26.1, { ...full, s: 0.88, cy: 588 }],
  [30.5, { ...full, s: 0.88, cy: 588 }],
  [31.3, { ...full, s: 0.78, cy: 760, rx: -12, op: 0, blur: 14 }, E.in],
];

// ---------- Screen overlays ----------
const CURSOR: [number, { x: number; y: number; o: number }][] = [
  [11.1, { x: 860, y: 560, o: 0 }],
  [11.25, { x: 820, y: 490, o: 1 }],
  [12.0, { x: 512, y: 18, o: 1 }],
  [12.5, { x: 600, y: 44, o: 1 }],
  [12.8, { x: 610, y: 48, o: 0 }],
  [18.85, { x: 600, y: 250, o: 0 }],
  [19.0, { x: 640, y: 300, o: 1 }],
  [19.45, { x: 880, y: 540, o: 1 }],
  [19.6, { x: 890, y: 550, o: 0 }],
  [24.45, { x: 720, y: 130, o: 0 }],
  [24.6, { x: 680, y: 105, o: 1 }],
  [25.05, { x: 528, y: 44, o: 1 }],
  [25.7, { x: 540, y: 50, o: 1 }],
  [26.0, { x: 545, y: 52, o: 0 }],
];

const Cursor: React.FC<{ x: number; y: number; o: number }> = ({ x, y, o }) =>
  o > 0.01 ? (
    <svg width="22" height="30" viewBox="0 0 22 30" style={{ position: "absolute", left: x, top: y, opacity: o, zIndex: 80, filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.5))" }}>
      <path d="M1.5 1.5v22l5.3-5 3.6 8.4 3.6-1.5-3.6-8.3h7.4z" fill="#000" stroke="#fff" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  ) : null;

const ScanBeam: React.FC<{ t: number }> = ({ t }) => {
  const o = window01(t, SCAN, SCAN + 1.0, 0.1, 0.25);
  if (o <= 0.001) return null;
  const y = lerp(28, MB.screenH + 10, E.gentle(clamp((t - SCAN) / 0.9)));
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: MB.screenH, opacity: o, zIndex: 30, pointerEvents: "none" }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: y - 140, height: 140, background: "linear-gradient(rgba(94,242,194,0), rgba(94,242,194,0.16))" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: y - 1, height: 2, background: C.mint, boxShadow: `0 0 18px 4px rgba(94,242,194,0.7)` }} />
    </div>
  );
};

/** Scene 5: "what they see" — right of the divider, the shared screen has no Assist panel. */
const SharedSide: React.FC<{ x: number; t: number }> = ({ x, t }) => (
  <>
    <div
      style={{
        position: "absolute",
        inset: 0,
        clipPath: `inset(0 0 0 ${x}px)`,
        boxShadow: "inset 0 0 0 3px rgba(255,69,58,0.9)",
        borderRadius: "15px 15px 2px 2px",
        zIndex: 55,
      }}
    />
    <div
      style={{
        position: "absolute",
        right: 18,
        top: 36,
        zIndex: 56,
        display: "flex",
        alignItems: "center",
        gap: 6,
        padding: "5px 10px",
        borderRadius: 12,
        background: "rgba(20,8,8,0.85)",
        border: "1px solid rgba(255,69,58,0.6)",
        color: "#ffd9d6",
        font: `600 11px ${BODY}`,
        opacity: clamp((MB.screenW - 150 - x) / 120),
      }}
    >
      <span style={{ width: 7, height: 7, borderRadius: 4, background: "#ff453a", opacity: 0.6 + 0.4 * Math.abs(Math.sin(t * 3)) }} />
      Sharing your screen
    </div>
    <div style={{ position: "absolute", left: x - 1, top: 0, bottom: 0, width: 2, zIndex: 70, background: `linear-gradient(${C.mint}, ${C.sky}, ${C.violet}, ${C.pink})`, boxShadow: "0 0 16px 3px rgba(148,120,255,0.6)" }} />
    <div
      style={{
        position: "absolute",
        left: x - 17,
        top: MB.screenH / 2 - 17,
        width: 34,
        height: 34,
        borderRadius: 17,
        zIndex: 71,
        background: "#f5f6f8",
        boxShadow: "0 4px 14px rgba(0,0,0,0.5), 0 0 0 4px rgba(148,120,255,0.35)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 3,
        color: "#111",
        font: `700 14px ${SYS}`,
      }}
    >
      ‹ ›
    </div>
  </>
);

const Keycaps: React.FC<{ t: number; at: number; keys: string[]; label: string }> = ({ t, at, keys, label }) => {
  const o = window01(t, at, at + 1.1, 0.12, 0.3);
  if (o <= 0.001) return null;
  const pop = swiftSpring(t - at, 0.35, 0.55);
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: 952, display: "flex", justifyContent: "center", opacity: o }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, transform: `scale(${0.7 + 0.3 * pop})` }}>
        {keys.map((k, i) => {
          const press = ramp(t, at + 0.12 + i * 0.05, 0.08) * (1 - ramp(t, at + 0.45, 0.15));
          return (
            <div
              key={i}
              style={{
                minWidth: 64,
                height: 64,
                padding: "0 14px",
                borderRadius: 14,
                background: "linear-gradient(#2a2d35, #1a1c22)",
                border: "1px solid rgba(255,255,255,0.14)",
                boxShadow: `0 ${6 - 4 * press}px 0 #0b0c10, 0 10px 24px rgba(0,0,0,0.5)${press > 0.1 ? `, 0 0 22px rgba(94,242,194,${0.35 * press})` : ""}`,
                transform: `translateY(${4 * press}px)`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                font: `500 30px ${SYS}`,
                color: "#f5f6f8",
              }}
            >
              {k}
            </div>
          );
        })}
        <div style={{ marginLeft: 10, font: `600 30px ${BODY}`, color: "rgba(245,246,248,0.85)" }}>{label}</div>
      </div>
    </div>
  );
};

// ---------- Scene ----------
export const Demo: React.FC<{ t: number }> = ({ t }) => {
  const cam = track(t, CAMERA);
  const notch = notchAt(t);

  const sp = speaking(t);
  const meet: MeetState = {
    t,
    presenting: ramp(t, 19.5, 0.7),
    caption:
      t < 9.75
        ? { who: "You", text: LINE2 }
        : t < 19.5
          ? t >= Q1_START
            ? { who: "Alex", text: spoken(LINE3, t, Q1_START, Q1_END) }
            : null
          : t >= Q2_START
            ? { who: "Alex", text: spoken(LINE4, t, Q2_START, Q2_END) }
            : null,
    youSpeaking: sp === "you",
    alexSpeaking: sp === "alex",
    timer: clock(862 + t),
    dof: clamp((cam.s - 1.25) / 1.1) * 2.6,
    ocr: {
      headline: ramp(t, SCAN + 0.22, 0.12) * (1 - ramp(t, 23.9, 0.4)),
      hours: ramp(t, SCAN + 0.4, 0.12) * (1 - ramp(t, 23.9, 0.4)),
      price: ramp(t, SCAN + 0.42, 0.12) * (1 - ramp(t, 23.9, 0.4)),
      question: ramp(t, SCAN + 0.68, 0.12) * (1 - ramp(t, 23.9, 0.4)),
    },
  };

  // Scene 5's divider, in screen px.
  const divider =
    t < 26.4 ? MB.screenW + 4 : t < 27.6 ? lerp(MB.screenW + 4, 140, E.inOut(clamp((t - 26.4) / 1.2))) : lerp(140, MB.screenW / 2, E.inOut(clamp((t - 27.6) / 1.0)));
  const showShare = t >= 26.3;

  const cursor = track(t, CURSOR, E.inOut);
  const notchLeft = MB.screenW / 2 - (notch.shape.w * K) / 2;

  const overlay = (
    <>
      <ScanBeam t={t} />
      <div style={{ position: "absolute", inset: 0, zIndex: 40, clipPath: showShare ? `inset(0 ${MB.screenW - divider}px 0 0)` : undefined }}>
        <div style={{ position: "absolute", left: notchLeft, top: 0, transform: `scale(${K})`, transformOrigin: "0 0" }}>
          <Notch m={notch} />
        </div>
      </div>
      {showShare ? <SharedSide x={divider} t={t} /> : null}
      <Cursor {...cursor} />
    </>
  );

  // Frame-space position of a screen point, for labels that follow the divider.
  const toFrameX = (sx: number) => cam.cx + (MB.screenX + sx - cam.fx) * cam.s;
  const dividerX = toFrameX(divider);
  const labels = ramp(t, 28.3, 0.5) * (1 - ramp(t, 30.4, 0.35, E.in));

  const latencyMs = Math.min(587, Math.max(0, (t - Q1_END) * 1000));
  const scrim = window01(t, 9.2, 30.8, 0.6, 0.5);

  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ perspective: 1800, perspectiveOrigin: "50% 40%" }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: MB.width,
            height: MB.height,
            transformOrigin: "0 0",
            transform: `translate(${cam.cx}px, ${cam.cy}px) rotateX(${cam.rx}deg) scale(${cam.s}) translate(${-cam.fx}px, ${-cam.fy}px)`,
            opacity: cam.op,
            filter: cam.blur > 0.2 ? `blur(${cam.blur}px)` : undefined,
          }}
        >
          <MacBook meet={meet} screenOverlay={overlay} />
        </div>
      </AbsoluteFill>

      {/* Legibility scrim for the captions */}
      <AbsoluteFill style={{ background: "linear-gradient(rgba(5,6,10,0.92) 0px, rgba(5,6,10,0.75) 180px, rgba(5,6,10,0) 300px)", opacity: scrim }} />

      {/* Captions */}
      <div style={{ position: "absolute", left: 40, right: 40, top: 78 }}>
        <Words text="It listens [along.]" t={t} start={9.4} end={13.2} size={76} />
      </div>
      <div style={{ position: "absolute", left: 40, right: 40, top: 58 }}>
        <Words text="Hears the question." t={t} start={13.5} end={18.6} size={64} color="rgba(245,246,248,0.62)" />
        <Words
          text="Answers in {}"
          t={t}
          start={13.62}
          end={18.6}
          size={76}
          slot={
            <span style={{ ...gradText, fontVariantNumeric: "tabular-nums", display: "inline-block", minWidth: "3.2em", textAlign: "left" }}>
              {(latencyMs / 1000).toFixed(2)}s
            </span>
          }
        />
      </div>
      <div style={{ position: "absolute", left: 40, right: 40, top: 78 }}>
        <Words text="Reads your [screen,] too." t={t} start={20.05} end={24.9} size={76} />
      </div>
      <div style={{ position: "absolute", left: 40, right: 40, top: 66 }}>
        <Words text="INVISIBLE ON SCREEN SHARE" t={t} start={25.6} end={30.5} stagger={0.03} size={22} weight={700} letterSpacing={0.28} font={BODY} gradient style={{ marginBottom: 14 }} />
        <Words text="[You] see it. They don’t." t={t} start={25.75} end={30.5} size={76} />
      </div>

      <Keycaps t={t} at={SCREEN_KEY} keys={["⌘", "⇧", "↩"]} label="Screen" />

      {/* Scene 5 labels, following the divider */}
      {labels > 0.001 ? (
        <>
          <div style={{ position: "absolute", top: 945, right: 1080 - dividerX + 26, textAlign: "right", opacity: labels, transform: `translateY(${(1 - labels) * 16}px)` }}>
            <div style={{ font: `600 30px ${DISPLAY}`, color: "#f5f6f8" }}>What you see</div>
            <div style={{ font: `400 20px ${BODY}`, color: C.muted, marginTop: 4 }}>Your screen, with Assist</div>
          </div>
          <div style={{ position: "absolute", top: 945, left: dividerX + 26, opacity: labels, transform: `translateY(${(1 - labels) * 16}px)` }}>
            <div style={{ font: `600 30px ${DISPLAY}`, color: "#f5f6f8" }}>What they see</div>
            <div style={{ font: `400 20px ${BODY}`, color: C.muted, marginTop: 4 }}>Same screen, no trace of it</div>
          </div>
        </>
      ) : null}
    </AbsoluteFill>
  );
};
