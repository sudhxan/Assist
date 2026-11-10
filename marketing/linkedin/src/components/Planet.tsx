import React, { useMemo } from "react";
import { random } from "remotion";
import { C } from "../theme";

/** A planet's horizon with an aurora rim and a sunrise flare at its crest. `horizon` is the crest's y. */
export const Planet: React.FC<{ horizon: number; light: number; t: number }> = ({ horizon, light, t }) => {
  const R = 1650;
  const cx = 540;
  const cy = horizon + R;
  const lights = useMemo(
    () =>
      Array.from({ length: 140 }, (_, i) => {
        const a = (random(`pa${i}`) - 0.5) * 0.62;
        const depth = Math.pow(random(`pd${i}`), 1.6) * 260;
        return { a, depth, r: 0.4 + random(`pr${i}`) * 1.1, o: 0.12 + random(`po${i}`) * 0.4 };
      }),
    [],
  );
  const pulse = 1 + 0.04 * Math.sin(t * 2.2);
  return (
    <svg width={1080} height={1080} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
      <defs>
        <radialGradient id="pl-body" cx={cx} cy={horizon} r={1100} gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#13213f" />
          <stop offset="0.35" stopColor="#070b18" />
          <stop offset="1" stopColor="#020306" />
        </radialGradient>
        <radialGradient id="pl-haze" cx={cx} cy={horizon} r={620} gradientUnits="userSpaceOnUse" gradientTransform={`translate(0 ${horizon}) scale(1 0.42) translate(0 ${-horizon})`}>
          <stop offset="0" stopColor="#5b8cff" stopOpacity={0.55 * light} />
          <stop offset="0.45" stopColor="#3b5bd6" stopOpacity={0.22 * light} />
          <stop offset="1" stopColor="#1b2a6b" stopOpacity="0" />
        </radialGradient>
        <linearGradient id="pl-rim" x1="0" x2="1080" y1="0" y2="0" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor={C.mint} stopOpacity="0" />
          <stop offset="0.18" stopColor={C.mint} stopOpacity={0.55} />
          <stop offset="0.38" stopColor={C.sky} stopOpacity={0.95} />
          <stop offset="0.5" stopColor="#ffffff" stopOpacity="1" />
          <stop offset="0.62" stopColor={C.violet} stopOpacity={0.95} />
          <stop offset="0.82" stopColor={C.pink} stopOpacity={0.55} />
          <stop offset="1" stopColor={C.pink} stopOpacity="0" />
        </linearGradient>
        <filter id="pl-b4" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="4" />
        </filter>
        <filter id="pl-b16" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="16" />
        </filter>
        <filter id="pl-b40" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="40" />
        </filter>
        <filter id="pl-streak" x="-10%" y="-400%" width="120%" height="900%">
          <feGaussianBlur stdDeviation="2.5" />
        </filter>
        <clipPath id="pl-clip">
          <circle cx={cx} cy={cy} r={R} />
        </clipPath>
      </defs>
      {/* Atmosphere haze above the crest */}
      <ellipse cx={cx} cy={horizon} rx={980} ry={420} fill="url(#pl-haze)" />
      {/* Body */}
      <circle cx={cx} cy={cy} r={R} fill="url(#pl-body)" />
      <g clipPath="url(#pl-clip)" opacity={light}>
        {lights.map((p, i) => {
          const ang = -Math.PI / 2 + p.a;
          const rr = R - 12 - p.depth;
          return <circle key={i} cx={cx + Math.cos(ang) * rr} cy={cy + Math.sin(ang) * rr} r={p.r} fill="#cfe0ff" opacity={p.o * (1 - p.depth / 300)} />;
        })}
        <ellipse cx={cx} cy={horizon + 8} rx={700} ry={60} fill="#4f7dff" opacity={0.12} filter="url(#pl-b16)" />
      </g>
      {/* Rim light */}
      <g opacity={light}>
        <circle cx={cx} cy={cy} r={R} fill="none" stroke="url(#pl-rim)" strokeWidth={34} opacity={0.35} filter="url(#pl-b16)" />
        <circle cx={cx} cy={cy} r={R} fill="none" stroke="url(#pl-rim)" strokeWidth={8} opacity={0.75} filter="url(#pl-b4)" />
        <circle cx={cx} cy={cy} r={R} fill="none" stroke="url(#pl-rim)" strokeWidth={2.2} />
      </g>
      {/* Sunrise flare */}
      <g opacity={light} transform={`translate(${cx} ${horizon}) scale(${pulse}) translate(${-cx} ${-horizon})`}>
        <circle cx={cx} cy={horizon - 4} r={230} fill="#7fa6ff" opacity={0.28} filter="url(#pl-b40)" />
        <ellipse cx={cx} cy={horizon - 2} rx={520} ry={3.5} fill="#ffffff" opacity={0.55} filter="url(#pl-streak)" />
        <circle cx={cx} cy={horizon - 3} r={46} fill="#ffffff" opacity={0.85} filter="url(#pl-b16)" />
        <circle cx={cx} cy={horizon - 2} r={11} fill="#ffffff" filter="url(#pl-b4)" />
      </g>
    </svg>
  );
};
