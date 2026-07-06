# On-Device iOS TTS Research — Closing the Kokoro-Quality Gap (Backlog #12)

**Date:** 2026-07-06
**Status:** Research complete — recommendation: FluidAudio upgrade spike (Option 1 below)
**Prior decisions honored:** K23 (GPL-3/espeak-ng blocks direct-linking), D13 (Path Z ruled out; Path Y = Piper AU extension previously scoped), K22 (license-first, Constraints & Direction-of-Travel required)
**Cross-refs:** K6, K24, K37, K38, K32

## Problem

Patter's Kokoro provider (FluidAudio 0.13.5, CoreML) is hard-disabled on iOS: the single-graph Kokoro CoreML model crashes Apple's on-device ML stack — libBNNS SME2 segfault on iOS 26 (K6), MPSGraph/MLIR assertion on iOS 27 (K37). iOS users are left choosing between System voice ("pretty bad") and OpenAI (cloud, ~¢0.6/segment). Goal: high-quality, realistic, zero-cost, fully on-device voice on iOS.

## Headline finding

**FluidAudio already shipped the fix.** The mono-Kokoro model Patter pins (0.13.5) was deprecated and removed upstream (v0.14.6, PR #602). Its replacement, **`KokoroAneManager`** (v0.14.2+, PR #547), is a 7-stage re-converted CoreML chain derived from [laishere/kokoro-coreml](https://github.com/laishere/kokoro-coreml) that splits the graph so ANE-hostile ops route to CPU/GPU — the exact mitigation for the K6/K37 crash class. It is benchmarked on a **physical iPhone 17e running iOS 26.4.2** (~6× real-time default, ~20× cpuOnly — [FluidAudio issue #587](https://github.com/FluidInference/FluidAudio/issues/587)) and powers a **shipping App Store app** (Local Narrator, listed in FluidAudio's README showcase). The crash was never a Kokoro problem — it was a "one monolithic CoreML graph through ANE/BNNS" problem.

---

## Constraints & Direction-of-Travel (K22)

### (a) What the SDKs/models actually do

**Option 1 — FluidAudio 0.15.4 `KokoroAneManager` (CoreML, ANE+CPU/GPU hybrid)**
- Same SPM package Patter already wraps; API differs from `KokoroTtsManager` (swap required).
- Kokoro-82M weights, 7-stage chain, per-stage compute-unit routing. v0.13.6 already added configurable `computeUnits` as an iOS 26 ANE-regression workaround; v0.15.3 made "ane-tail-gpu" the default after the M5/macOS 26.5 libBNNS crash (#667).
- English G2P is CoreML BART + misaki-lexicon-first (PR #692) — **no espeak-ng anywhere in this path**; README states "GPL dependencies: None" for Kokoro ([KokoroAne.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/KokoroAne.md)).
- **Hard limitations:** single English voice (`af_heart`) — no voice selection; ≤510 phonemes/call (fine — Patter already sentence-chunks); no SSML.
- **Known residual crash (#587):** input-specific `EXC_BAD_ACCESS` in libBNNS (SME `st1w`) on iOS 26.4.2 for certain short OOV proper-noun/number inputs ("Saville", "1801") — crashes on *all* compute-unit configs including `.cpuOnly`. Closed unresolved; maintainer hoped iOS 26.5 fixes it, unconfirmed. **DJ chatter is full of artist/track names — exactly this input shape. This is the spike gate.**
- **iOS 27:** no KokoroAne load-crash reports. Open issue [#738](https://github.com/FluidInference/FluidAudio/issues/738): iOS 27 restricts **background ANE access** (radar 174796039 / FB23457001). Patter renders DJ segments while music plays, including backgrounded (K32 added `UIBackgroundModes: audio`) — needs verification that render falls back to CPU/GPU in background rather than failing.

**Option 2 — Kokoro-82M via MLX Swift (Metal GPU, sidesteps CoreML entirely)**
- [mlalma/kokoro-ios](https://github.com/mlalma/kokoro-ios) (MIT): **3.3× real-time on a physical iPhone 13 Pro** (release build, post-warmup), iOS 18+. An A19-class phone will do considerably better.
- Default G2P is [MisakiSwift](https://github.com/mlalma/MisakiSwift) — Swift port of misaki, **Apache-2.0**; eSpeakNG exists only as a commented-out alternative → **GPL-free path exists** (contrary to the generic "MLX ports use espeak" assumption — verified in this repo specifically).
- **Multi-voice supported** (voice embedding files) — preserves Patter's persona/voice-picker product surface, which Option 1 breaks.
- Costs: fp32/bf16 weights ~330 MB in memory (int8 ~90 MB exists); GPU-only (no ANE) → higher energy draw alongside continuous music playback; you own model/asset download; new dependency stack; no major shipping App Store app found using MLX Kokoro. [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) is the more maintained SDK targeting iOS.

**Option 3 — Chatterbox (Resemble AI) — the quality *upgrade* path**
- **MIT end to end** ([HF](https://huggingface.co/ResembleAI/chatterbox), [repo](https://github.com/resemble-ai/chatterbox)); own tokenizer, no espeak.
- Quality *above* Kokoro (Resemble blind test: 65% preferred over ElevenLabs; emotion tags).
- **App Store precedent:** [Chinny: Offline Voice Cloner](https://apps.apple.com/us/app/chinny-offline-voice-cloner/id6753816417) runs Chatterbox fully offline on iPhone ([dev insights](https://huggingface.co/ResembleAI/chatterbox/discussions/42)).
- Costs: ~0.5B params, **~3.2 GB peak RAM on iPhone** (Pro-class devices only), slow decode ("still on the slow side" after 90% attention optimization — workable only because Patter pre-renders ~35s ahead), community ONNX export (CoreML conversion blocked on unsupported ops). Highest engineering effort by far.

**Surveyed and not shortlisted** (license from primary source; iOS evidence = physical device only):

| Model | License | Why not |
|---|---|---|
| Kitten TTS nano/micro (15–40M) | Apache-2.0, but Python frontend uses GPL `phonemizer`/espeak ([HN](https://news.ycombinator.com/item?id=44809541)) | Quality below Kokoro (tinny/flat); only candidate small enough for an AU extension though |
| NeuTTS Air (Neuphonic, 0.5B) | Apache-2.0 weights, **mandatory espeak-ng/phonemizer** ([HF card](https://huggingface.co/neuphonic/neutts-air)) | GPL frontend, no iPhone evidence, Perth-watermarked output |
| Marvis TTS 250M | Apache-2.0, official MLX Swift package | [marvis-tts-swift](https://github.com/Marvis-Labs/marvis-tts-swift) documents **macOS 14+ only**; no confirmed iPhone run; hallucinates on short sentences/novel words — worst possible failure mode for artist-name-dense DJ chatter |
| Orpheus (Canopy, 3B/400M/150M) | Apache-2.0 | 3B (the good one) not phone-viable; small variants have no quality evidence; SNAC-in-llama.cpp still DIY |
| Supertonic-3 (Supertone, 99M) | Code MIT, **weights OpenRAIL-M** (use-restriction) | Shipping iOS precedent (PageEcho) + official Swift sample + no GPL, but naturalness measurably below Kokoro ([benchmark](https://heyneo.com/blog/kokoro-tts-vs-supertonic-3-tts)) — fails the quality bar |
| Piper / piper1-gpl | **Code now GPL-3.0 outright** ([OHF-Voice/piper1-gpl](https://github.com/OHF-Voice/piper1-gpl), old MIT repo archived Oct 2025) | Quality below Kokoro; GPL got *worse* since K23 — see Path Y note below |
| Zonos (1.6B), F5-TTS (CC-BY-NC weights), KaniTTS | various | Too big / non-commercial weights / no mobile path |
| sherpa-onnx Kokoro (ONNX) | Apache runtime, but its Kokoro English frontend **requires espeak-ng-data** ([docs](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html)) | K23 GPL block unchanged — confirmed still blocked, not re-litigated |

### (b) Licenses (checked first, primary sources)

- Kokoro-82M weights: **Apache-2.0** ([HF card](https://huggingface.co/hexgrad/Kokoro-82M)); FluidInference CoreML conversion Apache-2.0 ([HF](https://huggingface.co/FluidInference/kokoro-82m-coreml)); FluidAudio Apache-2.0; misaki/MisakiSwift Apache-2.0.
- Options 1–3 are all fully permissive, main-binary-safe. No GPL isolation needed for any recommended path.
- espeak-ng-dependent paths (sherpa-onnx English, NeuTTS, Kitten's default frontend, Piper) remain GPL-blocked for the main binary per K23 — unchanged, and Piper's own code went GPL-3 in 2025, further burying Path Z.

### (c) Precedents (named shipping apps)

- **Local Narrator** — FluidAudio KokoroAne on iOS (FluidAudio README showcase) → Option 1 proof.
- **Chinny** — Chatterbox fully offline on iPhone → Option 3 proof.
- **PageEcho** — Supertonic on iPhone; **Piper – Neural TTS** (id 6759636010) — Piper via AVSpeech AU extension (the Path Y pattern, still working).
- sherpa-onnx ecosystem apps (Kokoro/Piper/Matcha) — multiple, but GPL-extension-pattern territory.

### (d) Direction of travel (mid-2024 → mid-2026)

- **Apple: stagnant for developers.** No new synthesis API in iOS 26 or 27. WWDC25's speech story was SpeechAnalyzer (STT only); WWDC26's expressive "Siri AI" voices (on-device speech-generating model, expressiveness sliders) are **system-app-exclusive and hardware-gated** (iPhone 17 Pro/Air+); Foundation Models opened up LLM/vision but pointedly not speech output. Premium voice roster frozen since ~iOS 16/17, still manual downloads buried in Settings → Accessibility → Read & Speak, and reviewers now rate even Piper above them ("Premium refers more to model size than listening quality" — [Speech Central](https://speechcentral.net/2026/04/07/offline-system-voices-on-ios-are-finally-becoming-practical/)). **K23's "the gap is narrowing, just nudge users to Premium voices" finding has aged badly — the gap stopped narrowing.** Path X remains a floor, not a destination.
- **Open models: rapidly improving and converging on Apple silicon.** Kokoro-82M peaked #1 on TTS-Arena (Jan 2026); the 2025–26 crop (Chatterbox, Marvis, Supertonic, Orpheus) brought MIT/Apache licensing, mobile-first sizes, and real App Store shipments. FluidAudio actively maintains iOS compatibility (three crash classes worked around via compute-unit routing in 2026 alone) and files Apple radars.
- **Risk trend:** Apple's ML stack keeps breaking CoreML TTS graphs across OS updates (K6 → K37 → #587 → #667 → iOS 27 background-ANE restriction #738). Per-stage compute-unit control (KokoroAne architecture) is the practical mitigation; an MLX path avoids the stack entirely. Underlying Apple bugs remain open (radars 174796039, 179282606).

---

## Ranked recommendation

1. **Spike: FluidAudio 0.13.5 → 0.15.4, `KokoroTtsManager` → `KokoroAneManager`.** (effort: low-medium — SPM bump + manager swap + device spike, ~1–2 sessions)
   Gate criteria on physical iPhone (iOS 26.5+, ideally also iOS 27 beta):
   - Hammer with real Patter DJ scripts — artist names, track titles, numbers, OOV proper nouns — specifically hunting the #587 crash class.
   - Verify segment render while backgrounded (K32 scenario) survives iOS 27's background-ANE restriction (#738) — confirm CPU/GPU fallback, not failure.
   - If both pass → re-enable Kokoro on iOS (remove/condition `applyIOS26KokoroDowngradeIfNeeded` + picker disable), closing K6/K24/K37 UX debt.
   - **Accepted trade-off:** single `af_heart` voice on this path. If persona-voice variety on iOS matters, that's Option 2's job, or FluidAudio's PocketTTS (streaming, voice cloning, GPL-free per FluidAudio #300) as a companion — evaluate during spike.
2. **Fallback: MLX Swift Kokoro (mlalma/kokoro-ios pattern + MisakiSwift).** (effort: medium — new dependency stack, asset management, fourth provider in `DJVoiceRouter`) Use if the #587 crash class survives in the spike — MLX bypasses CoreML/BNNS entirely and is the only path that both keeps Kokoro quality *and* multi-voice, GPL-free. Battery cost vs ANE accepted.
3. **Later / quality-upgrade track: Chatterbox (MIT).** Above-Kokoro quality with App Store proof (Chinny), but 3.2 GB RAM + slow decode + community-ONNX effort. Revisit only if Options 1–2 land and "better than Kokoro" becomes the ask — pairs naturally with K38's segment pre-render latency work.
4. **Path Y (Piper AU extension): deprioritize.** Piper code is now GPL-3 outright (piper1-gpl), quality is below Kokoro, and the permissive Kokoro paths above beat it on every axis. Keep only as the "system-wide voice for other apps" play, which is not Patter's problem.
5. **Path X (Premium-voice nudge): keep as shipped floor.** Apple trajectory gives no reason to expect it improves.

## Verification notes

- Every license above cites the license file / HF card / repo LICENSE directly.
- All "runs on iOS" claims are physical-device: iPhone 17e (#587 benchmarks), iPhone 13 Pro (mlalma), Chinny/Local Narrator/PageEcho (App Store). macOS/simulator demos were excluded.
- Conflict reconciled during synthesis: one survey source generically flagged "MLX Kokoro ports use espeak (GPL)"; repo-level check of mlalma/kokoro-ios shows MisakiSwift (Apache-2.0) is the default and espeak is commented out — GPL-free MLX path confirmed.
