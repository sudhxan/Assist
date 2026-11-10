import React from "react";
import { E, ramp } from "../anim";
import { DISPLAY, GRAD } from "../theme";

export const gradText: React.CSSProperties = {
  background: GRAD,
  WebkitBackgroundClip: "text",
  backgroundClip: "text",
  color: "transparent",
};

type Props = {
  /** Words split on spaces. `[lives_in_your_notch.]` is one gradient unit; `\n` breaks the line. */
  text: string;
  t: number;
  start: number;
  end?: number;
  stagger?: number;
  size: number;
  weight?: number;
  color?: string;
  font?: string;
  lineHeight?: number;
  letterSpacing?: number;
  align?: "left" | "center" | "right";
  style?: React.CSSProperties;
  /** Replaces a `{}` token with live content (e.g. a counter). */
  slot?: React.ReactNode;
  /** Every word in the aurora gradient. */
  gradient?: boolean;
};

/** Words rise into focus one after another, and blur away on the way out. */
export const Words: React.FC<Props> = ({
  text,
  t,
  start,
  end,
  stagger = 0.06,
  size,
  weight = 600,
  color = "#f5f6f8",
  font = DISPLAY,
  lineHeight = 1.06,
  letterSpacing = -0.035,
  align = "center",
  style,
  slot,
  gradient = false,
}) => {
  const lines = text.split("\n");
  let index = 0;
  return (
    <div style={{ fontFamily: font, fontSize: size, fontWeight: weight, color, lineHeight, letterSpacing: `${letterSpacing}em`, textAlign: align, ...style }}>
      {lines.map((line, li) => (
        <div key={li}>
          {line.split(" ").map((raw, wi) => {
            const i = index++;
            const marked = raw.startsWith("[") && raw.endsWith("]");
            const grad = gradient || marked;
            const word = marked ? raw.slice(1, -1).replace(/_/g, " ") : raw;
            const p = ramp(t, start + i * stagger, 0.75, E.out);
            const q = end === undefined ? 0 : ramp(t, end + i * stagger * 0.4, 0.4, E.in);
            const opacity = p * (1 - q);
            if (opacity <= 0.001) {
              return (
                <React.Fragment key={wi}>
                  <span style={{ display: "inline-block", opacity: 0 }}>{word === "{}" ? slot : word}</span>{" "}
                </React.Fragment>
              );
            }
            const y = (1 - p) * 0.38 - q * 0.22;
            const blur = (1 - p) * 14 + q * 12;
            return (
              <React.Fragment key={wi}>
                <span
                  style={{
                    display: "inline-block",
                    opacity,
                    transform: `translateY(${y}em)`,
                    filter: blur > 0.2 ? `blur(${blur}px)` : undefined,
                    ...(grad ? gradText : {}),
                    paddingBottom: grad ? "0.08em" : undefined,
                  }}
                >
                  {word === "{}" ? slot : word}
                </span>{" "}
              </React.Fragment>
            );
          })}
        </div>
      ))}
    </div>
  );
};
