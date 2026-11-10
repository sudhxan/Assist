import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

loadFont({ family: "Outfit", url: staticFile("outfit.woff2"), weight: "100 900" });
loadFont({ family: "DM Sans", url: staticFile("dm-sans.woff2"), weight: "100 1000" });

// The app's own palette (Sources/Assist/UI/Components.swift).
export const C = {
  bg: "#05060a",
  mint: "#5ef2c2",
  sky: "#4fc7fc",
  violet: "#9478ff",
  pink: "#ff80b8",
  highlight: "#a8fade",
  text: "#f5f6f8",
  muted: "#9a9eaa",
};

export const AURORA = [C.mint, C.sky, C.violet, C.pink, C.mint];
export const GRAD = `linear-gradient(100deg, ${C.mint} 0%, ${C.sky} 34%, ${C.violet} 68%, ${C.pink} 100%)`;

export const DISPLAY = "Outfit, system-ui, sans-serif";
export const BODY = '"DM Sans", system-ui, sans-serif';
// The Mac app draws with SF Pro; headless Chrome on macOS resolves it from the system font.
export const SYS = '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif';

export const W = 1080;
export const H = 1080;
export const FPS = 60;
export const DURATION = 45;
