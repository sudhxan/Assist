# Assist · LinkedIn launch video

The 45-second product video for LinkedIn, 1080 × 1080 at 60 fps. I built it with [Remotion](https://www.remotion.dev), so every frame is React and the whole thing re-renders from code.

**Output:** `out/assist-linkedin.mp4` (H.264 + AAC, -14 LUFS), plus `out/assist-linkedin-thumbnail.png` to upload as the LinkedIn cover image.

## What's in it

| Time | Scene |
|---|---|
| 0–3 s | Hook: "Every call has that one question." → "Meet your backup." |
| 3–8 s | Brand reveal: the buddy rises over a planet's horizon, with the apps and models Assist works with |
| 8–20 s | The MacBook from the Assist website on a Google Meet call. The notch opens into the real panel, hears the question and starts answering 587 ms after they stop talking |
| 20–25 s | **Screen**: ⌘⇧↩ reads the slide and the peek shows "20 × $49 = $980 / month" |
| 25–31 s | Invisible on screen share: a divider wipes the panel off "what they see" |
| 31–37 s | Runs 100% on your Mac: Qwen3.5 9B on the GPU, Parakeet on the Neural Engine, the real benchmark numbers |
| 37–40 s | "Your backup for sales calls, pitches, standups, client meetings, every call." |
| 40–45 s | End card |

The buddy is a port of the app's own `Sources/Assist/UI/Buddy.swift` (same moods, motion and face), and the panel follows `ExpandedView.swift`. The numbers are the measured ones from `docs/DEVELOPERS.md`.

The soundtrack is original: `scripts/score.mjs` synthesizes the music and every sound effect from oscillators and noise, timed to the picture (133 BPM so the montage words land on the beat). No samples, so there's nothing to license.

## Edit and render

```bash
npm install
npm run dev                   # Remotion Studio, to scrub and tweak
node scripts/score.mjs        # rebuild public/score.wav after changing timings
npm run render                # out/assist-linkedin.mp4 and the thumbnail
```

All scene timings are absolute seconds in `src/scenes/*.tsx`. If you move a beat, move its sound cue in `scripts/score.mjs` too.

## Credits

- Call footage: Antoni Shkraba, [Pexels video 8048241](https://www.pexels.com/video/woman-talking-and-looking-at-the-camera-8048241/), under the [Pexels license](https://www.pexels.com/license/). Illustrative only; the dialogue and the Bloom pitch are fictional.
- Fonts: Outfit and DM Sans, under the SIL Open Font License (`public/*-license.txt`).
- Remotion is free for individuals and teams of up to 3. See [remotion.pro/license](https://www.remotion.pro/license).

Made with ❤️ by Hariharasudhan
