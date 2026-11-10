// Renders stills at the given times (seconds) and tiles them into one contact sheet.
//   node scripts/stills.mjs 9 12.5 14.5 [--scale 0.5] [--sheet name]
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const flag = (n, d) => (args.includes(`--${n}`) ? args[args.indexOf(`--${n}`) + 1] : d);
const scale = Number(flag("scale", 0.5));
const sheet = flag("sheet", "sheet");
const times = args.filter((a, i) => !a.startsWith("--") && !args[i - 1]?.startsWith("--")).map(Number);
const browserExecutable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "AssistLinkedIn", browserExecutable });
const dir = path.resolve("out/stills");
mkdirSync(dir, { recursive: true });
const files = [];
for (const t of times) {
  const output = path.join(dir, `t${t.toFixed(2).padStart(6, "0")}.png`);
  await renderStill({ composition, serveUrl, output, frame: Math.round(t * composition.fps), scale, browserExecutable });
  files.push(output);
  console.log(output);
}
if (files.length > 1) {
  const cols = Math.min(4, files.length);
  const rows = Math.ceil(files.length / cols);
  const inputs = files.flatMap((f) => ["-i", f]);
  const labels = files.map((_, i) => `[${i}:v]null[v${i}]`);
  const pad = Array.from({ length: cols * rows - files.length }, (_, i) => `color=black:s=${Math.round(1080 * scale)}x${Math.round(1080 * scale)}[p${i}]`);
  const all = [...files.map((_, i) => `[v${i}]`), ...pad.map((_, i) => `[p${i}]`)].join("");
  const filter = [...labels, ...pad, `${all}xstack=inputs=${cols * rows}:layout=${Array.from({ length: cols * rows }, (_, i) => `${(i % cols) ? Array.from({ length: i % cols }, () => "w0").join("+") : "0"}_${Math.floor(i / cols) ? Array.from({ length: Math.floor(i / cols) }, () => "h0").join("+") : "0"}`).join("|")}`].join(";");
  const out = path.resolve(`out/${sheet}.jpg`);
  execFileSync("ffmpeg", ["-v", "error", "-y", ...inputs, "-filter_complex", filter, "-q:v", "3", out]);
  console.log(out);
}
