# Future Japanese Pronunciation Audio Research (verified June 2026)

Non-authoritative research notes for a possible future replacement/augmentation of browser TTS.
No source listed here is approved or bundled merely because it appears in this document. Any
adoption requires a fresh terms check, import record, attribution, and runtime test.

## Recommended

### 1. VOICEVOX — generate our own pack (best fit)
- Free neural Japanese TTS engine with character voices; batch-generate via the local
  HTTP API (`voicevox_engine`). https://voicevox.hiroshiba.jp/
- Generated audio is free for commercial and non-commercial use. Per-voice terms apply;
  **Zundamon** and **Shikoku Metan** explicitly allow commercial use with credit.
- Required attribution (app credits): `VOICEVOX:ずんだもん` or `VOICEVOX:四国めたん`.
- If the MP3s are published as reusable material (public repo), the credit terms must be
  passed downstream — add a NOTICE next to the audio folder.

### 2. Kanji alive — ready-made human recordings (CC BY 4.0)
- 10,187 word-level MP3s (compound words for 1,235 kanji), male + female native speakers.
- https://github.com/kanjialive/kanji-data-media — CC BY 4.0; bundling + commercial OK.
- Attribution: "Audio from Kanji alive (kanjialive.com), CC BY 4.0".

### 3. Tatoeba — sentence audio (per-contributor licenses)
- Native-read sentences; license chosen per contributor (CC BY / BY-SA / BY-NC / none).
- Whitelist CC BY / BY-SA contributors from the "sentences with audio" CSV
  (https://tatoeba.org/en/downloads) and credit each username.

## Situational
- **Lingua Libre / Wikimedia Commons** — crowd word recordings, CC BY-SA mostly; Japanese
  coverage is modest; check per file. https://lingualibre.org
- **Mozilla Common Voice (ja)** — CC0, but variable-quality crowd-read *sentences*; raw
  material only. https://commonvoice.mozilla.org/en/datasets

## Not usable — do not bundle
- **JSUT / JVS corpora** — research-only; redistribution not permitted.
- **Core 2000/6000, Kaishi 1.5k deck audio** — iKnow/JapanesePod101/NHK-derived,
  proprietary. No open license exists; legally unsafe to redistribute.
