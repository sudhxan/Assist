// Final render: 2x supersampled in Remotion, downscaled to 1080 × 1080 with Lanczos for crisp UI text,
// then the LinkedIn cover image.
//   npm run render
import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";

const run = (cmd, args) => execFileSync(cmd, args, { stdio: "inherit" });
const master = "out/master-2160.mp4";

run("npx", ["remotion", "render", "AssistLinkedIn", master, "--scale=2", "--crf=10", "--x264-preset=medium", "--audio-codec=aac", "--audio-bitrate=320k"]);
run("ffmpeg", [
  "-v", "error", "-stats", "-y", "-i", master,
  // Standard limited-range BT.709, which is what LinkedIn and every player expect.
  "-vf", "scale=1080:1080:flags=lanczos:out_range=tv:out_color_matrix=bt709,format=yuv420p",
  "-pix_fmt", "yuv420p", "-color_range", "tv",
  "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-profile:v", "high", "-level", "4.2",
  "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
  "-c:a", "copy", "-movflags", "+faststart",
  "out/assist-linkedin.mp4",
]);
rmSync(master);
// Cover image: the brand reveal, with the chips out.
run("npx", ["remotion", "still", "AssistLinkedIn", "out/assist-linkedin-thumbnail.png", "--frame=372"]);
