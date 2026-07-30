# Japanese Pronunciation Audio Sources (verified July 2026)

Source and policy record for recorded Japanese pronunciation. A source is not approved merely
because it appears below: adoption requires a terms check, deterministic import record,
attribution, reading-aware mapping, and runtime validation.

## Adopted

### Kanji alive — human recordings (CC BY 4.0)
- The source catalog contains 10,187 example-word recordings for 1,235 kanji, spoken by
  male and female native Japanese speakers.
- Source: <https://github.com/kanjialive/kanji-data-media>, pinned at
  `2d2a4931eec6e0cb532d5102766273c2323f96db`.
- Sushi Valley extracts 366 unmodified Ogg files and maps them to 459 current cards only
  when the normalized written form and reading agree. Runtime lookup uses the card id,
  never a prompt-text guess.
- Attribution: "Audio from Kanji alive (kanjialive.com), licensed CC BY 4.0."
- Rebuild with `tools/import_kanji_alive_audio.py`; the generated manifest records source
  filenames and SHA-256 checksums.

## Candidates

### Tatoeba — sentence audio (per-contributor licenses)
- Native-read sentences; license chosen per contributor (CC BY / BY-SA / BY-NC / none).
- Whitelist CC BY / BY-SA contributors from the "sentences with audio" CSV
  (https://tatoeba.org/en/downloads) and credit each username.

- **Lingua Libre / Wikimedia Commons** — crowd word recordings, CC BY-SA mostly; Japanese
  coverage is modest; check per file. https://lingualibre.org
- **Mozilla Common Voice (ja)** — CC0, but variable-quality crowd-read *sentences*; raw
  material only. https://commonvoice.mozilla.org/en/datasets

## Blocked or excluded
- **VOICEVOX, OS text-to-speech, and other generated voices** — incompatible with this
  project's human-recording-only teaching policy, regardless of whether a generator's
  output license would otherwise permit use.
- **JSUT / JVS corpora** — research-only; redistribution not permitted.
- **Core 2000/6000, Kaishi 1.5k deck audio** — iKnow/JapanesePod101/NHK-derived,
  proprietary. No open license exists; legally unsafe to redistribute.
- **All current Anki source-pack media** — `mediaPolicy: excluded`. A `[sound:...]` field
  or local `.apkg` proves technical availability, not permission to redistribute.
