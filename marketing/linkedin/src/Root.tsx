import { Composition } from "remotion";
import "./theme";
import { AssistVideo } from "./AssistVideo";
import { DURATION, FPS, H, W } from "./theme";

export const RemotionRoot: React.FC = () => {
  return <Composition id="AssistLinkedIn" component={AssistVideo} durationInFrames={DURATION * FPS} fps={FPS} width={W} height={H} />;
};
