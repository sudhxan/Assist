import React, { useMemo } from "react";
import { AbsoluteFill, random } from "remotion";
import { C } from "../theme";

type Star = { x: number; y: number; r: number; a: number; tw: number; depth: number };

/** A deterministic star field that drifts slowly, plus soft aurora glows. */
export const Backdrop: React.FC<{ t: number; stars?: number; aurora?: number; tint?: number }> = ({ t, stars = 1, aurora = 1, tint = 0 }) => {
  const field = useMemo<Star[]>(
    () =>
      Array.from({ length: 320 }, (_, i) => ({
        x: random(`x${i}`) * 1080,
        y: random(`y${i}`) * 1080,
        r: 0.35 + Math.pow(random(`r${i}`), 3) * 1.5,
        a: 0.15 + random(`a${i}`) * 0.75,
        tw: random(`t${i}`) * Math.PI * 2,
        depth: 0.3 + random(`d${i}`) * 0.7,
      })),
    [],
  );
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <AbsoluteFill
        style={{
          opacity: aurora,
          background: [
            `radial-gradient(ellipse 620px 420px at ${30 + 6 * Math.sin(t * 0.21)}% ${52 + 5 * Math.cos(t * 0.17)}%, rgba(67,126,113,${0.26 + 0.14 * tint}), transparent 70%)`,
            `radial-gradient(ellipse 620px 440px at ${74 + 5 * Math.cos(t * 0.19)}% ${48 + 6 * Math.sin(t * 0.23)}%, rgba(126,76,140,${0.24 + 0.14 * tint}), transparent 70%)`,
            `radial-gradient(ellipse 700px 380px at 52% ${66 + 4 * Math.sin(t * 0.13)}%, rgba(55,83,139,${0.2 + 0.1 * tint}), transparent 70%)`,
          ].join(", "),
        }}
      />
      <svg width={1080} height={1080} style={{ position: "absolute", inset: 0, opacity: stars }}>
        {field.map((s, i) => {
          const y = (s.y - t * 6 * s.depth + 1080 * 4) % 1080;
          const twinkle = 0.65 + 0.35 * Math.sin(t * (1.1 + s.depth) + s.tw);
          return <circle key={i} cx={s.x} cy={y} r={s.r} fill="#dfe8ff" opacity={s.a * twinkle} />;
        })}
      </svg>
    </AbsoluteFill>
  );
};
