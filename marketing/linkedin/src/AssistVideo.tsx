import React from "react";
import { AbsoluteFill, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Audio } from "@remotion/media";
import { LightLeak } from "@remotion/light-leaks";
import { lerp, ramp } from "./anim";
import { Backdrop } from "./components/Backdrop";
import { Hook, Brand } from "./scenes/Opening";
import { Demo } from "./scenes/Demo";
import { Private, Montage, End } from "./scenes/Closing";

/** Scenes mount only while they're on screen; each one reads the absolute time `t`. */
const Scene: React.FC<{ from: number; to: number; children: React.ReactNode }> = ({ from, to, children }) => {
  const { fps } = useVideoConfig();
  return (
    <Sequence from={Math.round(from * fps)} durationInFrames={Math.round((to - from) * fps)} layout="none">
      {children}
    </Sequence>
  );
};

/** How much of the soft aurora backdrop each part of the video wants. */
const auroraAt = (t: number) =>
  t < 3 ? lerp(0.25, 0.45, ramp(t, 0, 2.5)) : t < 7.8 ? 0.3 : t < 31 ? 1 : t < 37 ? 0.8 : t < 40 ? 0.5 : 0.3;

export const AssistVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  return (
    <AbsoluteFill style={{ background: "#05060a" }}>
      <Audio src={staticFile("score.wav")} />
      <Backdrop t={t} stars={ramp(t, 0, 0.8) * (1 - ramp(t, 44.62, 0.38))} aurora={auroraAt(t)} />
      <Scene from={0} to={3.2}>
        <Hook t={t} />
      </Scene>
      <Scene from={2.9} to={8.1}>
        <Brand t={t} />
      </Scene>
      <Scene from={7.8} to={31.4}>
        <Demo t={t} />
      </Scene>
      <Scene from={30.95} to={37.3}>
        <Private t={t} />
      </Scene>
      <Scene from={36.95} to={40.45}>
        <Montage t={t} />
      </Scene>
      <Scene from={39.95} to={45}>
        <End t={t} />
      </Scene>
      {/* Light leaks over the big cuts, tinted to the aurora (hue 200 = sky, 160 = violet) */}
      {(
        [
          [2.55, 0.9, 3, 200],
          [7.35, 1.0, 7, 160],
          [39.7, 0.9, 11, 200],
        ] as const
      ).map(([at, dur, seed, hue]) => (
        <Sequence key={seed} from={Math.round(at * fps)} durationInFrames={Math.round(dur * fps)}>
          <AbsoluteFill style={{ opacity: 0.5, mixBlendMode: "screen" }}>
            <LightLeak seed={seed} hueShift={hue} />
          </AbsoluteFill>
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
