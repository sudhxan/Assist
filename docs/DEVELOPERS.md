# Building Assist

How to build Assist from source, how it works inside, and how to reproduce its speed numbers. For using the app, see the [README](../README.md).

## Run it

Requires macOS 26 (Tahoe), Xcode 26 or later, and Xcode's Metal Toolchain (MLX compiles its GPU kernels with it):

```bash
xcodebuild -downloadComponent MetalToolchain
```

Then:

```bash
./scripts/run.sh
```

This builds `build/Assist.app` with `xcodebuild` (the first build compiles MLX and takes a few minutes), signs it with your Apple Development certificate (or ad-hoc if you don't have one), and launches it.

To see the full UI with sample data (other launch flags are listed in `Sources/Assist/App/Main.swift`):

```bash
./scripts/run.sh --demo
```

## How it works

| Piece | File |
|---|---|
| Notch window (`sharingType = .none`, sits above the menu bar, hover and click-through) | `Sources/Assist/App/NotchWindowController.swift` |
| Mic (AVAudioEngine) and system audio (ScreenCaptureKit) | `Sources/Assist/Audio/Capture.swift` |
| Speech recognition: Parakeet (default, English) or Apple SpeechAnalyzer (every language) | `Sources/Assist/Audio/ParakeetTranscriber.swift`, `LiveTranscriber.swift` |
| Transcript, turn-taking, speculative answers, echo filtering, cards | `Sources/Assist/Model/AppModel.swift` |
| Conversation memory: every question asked, what you said back, whose turn it is | `Sources/Assist/Model/Conversation.swift` |
| On-device engine (MLX): warm KV cache, MTP decoding, turn check | `Sources/Assist/Local/LocalEngine.swift` |
| On-device model catalog and downloader | `Sources/Assist/Local/LocalModels.swift` |
| Claude, OpenRouter and Gemini streaming clients, model lists, prompts | `Sources/Assist/AI/` |
| Benchmarks | `Sources/Assist/Local/Bench.swift`, `E2EBench.swift`, `Audio/STTBench.swift` |
| Buddy, notch shape, panel UI | `Sources/Assist/UI/` |

With Claude, Assist defaults to **Opus 5.5** at low effort for fast replies (Fable 5.2, Sonnet 5.5 and Haiku 5.5 are in the picker), and caches the system prompt (your profile and pasted context) so it isn't reprocessed on every answer. On Fable, Opus and Sonnet, requests set `fallbacks: "default"`, so if Claude declines a request it's retried on a fallback model instead of failing. OpenRouter uses its OpenAI-compatible chat completions API, and Gemini uses `streamGenerateContent`. All providers stream into the same answer card.

### Following the conversation

Assist keeps a small memory of the meeting next to the transcript: each question the other side asked, what you said back, and who is waiting on whom. It's rebuilt from the transcript every time it's needed, so dropped echoes, merged lines and late punctuation can't leave it stale.

- A new question becomes the current one. A follow-up ("and why did you pick that?") is sent with the earlier questions and your replies, so the model resolves "that" against what you actually said.
- **Answer** (⌘↩) goes by that state. If they're waiting on you, it answers their question. If you've already started replying, it helps you finish that answer instead of answering from scratch. "Mm-hm" and "okay" from either side don't count as a turn.
- The transcript keeps the last 500 lines and cloud prompts the last 16,000 characters, but the memory keeps the questions, so the first thing they asked is still there an hour in.
- Cloud models get the memory as a `<conversation_state>` block. On-device, the transcript in the warm cache is the memory, and the task carries just the last exchange you answered (about 60 tokens), which is what stops a small model answering a bare follow-up about its own earlier suggestion.

### Who said what

The call's audio (ScreenCaptureKit) is "Them" and your mic is "You". Without headphones the mic hears the call too, so there are two layers:

1. **Echo cancellation.** The mic runs through macOS voice processing, which subtracts what the Mac is playing from the mic signal. Ducking is set to minimum so the call stays as loud as it was. If voice processing can't start or delivers no audio, the plain mic takes over. It's a toggle in Settings → General, and it's off in Room mode (mic only), where the mic is the only source.
2. **Text check.** Whatever still leaks through is compared with what the other side said in the last few seconds: most of its words in one of their lines, or half of its word pairs in their recent speech taken together (the two channels cut utterances at different points). This runs on in-progress text as well, so their words never flash up as yours.

Lines are placed by when the speaker started, not when recognition finished, so a long turn from them doesn't land below your short reply to it.

### On-device answers

The model is **Qwen3.5 9B** (4-bit, MLX), the strongest model under 10B parameters, running in-process on the GPU; Macs with less than 24 GB get Qwen3.5 4B by default. Bigger models such as Qwen3.6 35B-A3B (19.5 GB) or Gemma 4 26B (15 GB) don't leave room for a meeting app on a 24 GB Mac. Latency comes from the harness around the model, one technique per stage:

| Stage | Technique | What it does |
|---|---|---|
| Hearing them | **Parakeet Unified 0.6B** (NVIDIA), 320 ms streaming tier, on the Neural Engine | Transcribes with a third of Apple's errors and finalizes in ~0.7 s instead of ~3.4 s. It runs on the ANE, so it never competes with the LLM for the GPU. |
| Knowing they're done | **Endpoint anticipation** ([arXiv 2606.13450](https://arxiv.org/abs/2606.13450)) from the recognizer's own signals | A stall in new words plus quiet audio, or a `?` from the decoder's punctuation, marks a pause about 0.35 s after they stop. Assist starts answering right there, before the turn is final. |
| Knowing it's for you | **SpeculativeETD**-style two-stage check ([arXiv 2503.23439](https://arxiv.org/abs/2503.23439)) | A cheap question detector runs first. When it says no, the model scores "is this waiting on me?" in one forward pass (~130 ms). |
| Reading the conversation | **Append-mode streaming prefill** ([Stream2LLM, arXiv 2604.16395](https://arxiv.org/abs/2604.16395)) | The system prompt, settled transcript lines, and Assist's own earlier suggestions stay prefilled in a KV cache that grows in the background as people talk. A request only prefills the last line or two plus the task. |
| Branching off it | **Copy-on-write fork** of the warm cache | Qwen3.5's linear-attention layers carry recurrent state that can't be rewound, so each answer runs on a copy of the cache. MLX arrays are copy-on-write, so a fork costs well under a millisecond. |
| Writing | **MTP self-speculative decoding** (Qwen3.5's multi-token-prediction head) | The model drafts its next token with its own MTP head and verifies it in the same pass. |

If the final transcript has the same words as the one the draft started from, the draft simply is the answer. Otherwise the draft is replaced. Assist also implements **PredGen** input-time verification ([arXiv 2506.15556](https://arxiv.org/abs/2506.15556)), which keeps the prefix of a draft the model would write again. It's measured in `--bench` but not used: with greedy decoding, any real change to the question changes the answer within a few tokens, so regenerating (~0.1 s) beats verifying.

On-device, **Screen** reads your screen with Apple's Vision OCR (Neural Engine) and answers from the text on the warm, cached path. Cloud providers still receive the screenshot.

### Speed

Measured on a MacBook Pro M5 Pro, 24 GB, with `./scripts/run.sh` built app:

| | Result |
|---|---|
| **End of their speech → first word of the answer** (whole app, real-time speech) | **median 587 ms**, worst 613 ms |
| Time to first token, warm prefix vs. full prefill (2,100-token meeting) | **118 ms** vs. 1,747 ms (14.8×) |
| Decode, Qwen3.5 9B with MTP / without | 65 / 53 tok/s (1.24×) |
| Decode, Qwen3.5 4B with MTP | 95 tok/s, 98 ms to first token |
| Speech: Parakeet vs. Apple SpeechAnalyzer, word error rate | **1.7%** vs. 5.2% |
| Speech: final transcript after end of speech | **690 ms** vs. 3,366 ms |
| Turn check ("is this waiting on me?") | ~130 ms |
| Memory: Qwen3.5 9B loaded | ~5 GB GPU, plus ~0.6 GB per Parakeet stream on the ANE |

Reproduce them with:

```bash
build/Assist.app/Contents/MacOS/Assist --bench        # LLM: prefill, warm vs cold, MTP, PredGen, turn check
build/Assist.app/Contents/MacOS/Assist --bench-stt    # Parakeet vs Apple on the same real-time audio
build/Assist.app/Contents/MacOS/Assist --bench-e2e    # the whole app, speech to answer
build/Assist.app/Contents/MacOS/Assist --bench-logic  # question tracking, memory, echo and ordering checks (sends nothing)
build/Assist.app/Contents/MacOS/Assist --bench-mic    # does echo cancellation start and deliver audio on this Mac
build/Assist.app/Contents/MacOS/Assist --bench-echo   # plays "their" lines out of the speakers and checks none land under "You" (audible, ~1 min)
```

The benchmarks use their own settings and never change yours. `--demo`, `--provider=<id>` and `--snapshot=<file.png>` likewise run with throwaway settings.
