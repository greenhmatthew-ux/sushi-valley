# Learning Progression

What the player learns, when it unlocks, and how rewards feel. Curated content only; respectful
and practical (travel-useful), never stereotype/flashcard-dump.

## What unlocks first (implemented)
- On first Valley entry: **kana vowels** (あいうえお) unlock (`valley_started`).
- Talk to **Hana** (first time): unlocks **greetings** + **food words**, then a micro-recall.
- **Sushi pickup**: unlocks the `food-sushi` card (すし).
- **Tea study-spot**: a quick optional review of due cards.

## Lesson tracks (data-driven, `cards.json`/`lessons.json`)
1. Kana recognition (hiragana first: vowels, kana-for-sushi す・し・た)
2. Greetings (こんにちは, ありがとう, おはよう)
3. Food & drink (すし, おちゃ, みず, ごはん)
4. Travel Essentials (source-backed arrival, dining, stay/payment, and transit phrases)
Future: katakana signs, numbers/prices, directions/places, nature/verbs, signs/warnings.

## Active one-month travel focus
- Prioritize useful travel recognition and recall: kana/katakana, arrival and transit, lodging,
  ordering, directions, numbers/payment, common signs, and urgent-help phrases.
- Learning content must come from the project's attributable flashcard sources. Do not invent an
  uncited parallel deck or hardcode lesson text in scenes, gates, dialogue, or UI components.
- Build each addition as a playable loop: sourced cards -> short practice -> repeated recall gate ->
  new LDtk destination or route -> useful travel interaction/reward -> later spaced repetition.
- Prefer several encounters with a small high-value card set over one gate followed by permanent
  completion. Mix recognition, meaning, and route-context prompts without making failure punitive.
- Author destinations, gates, signs, NPCs, and rewards through LDtk Master/World Builder. Keep
  curriculum data in the shared learning profile so every surface uses the same progress.
- Imported travel packs retain provider, deck, source URL, and original Anki note ID per card.
  Their media remains excluded unless separate asset rights are reviewed. Pronunciation audio is
  sourced independently: approved Kanji alive recordings are joined by explicit card id only when
  the written form and reading both match, and unsupported or ambiguous cards remain silent.

## Imported Travel Source
- **Essential Japanese for Travelers** by Nihongo Picnic, AnkiWeb deck `1203744822`:
  20 notes split into Arrival Essentials, Dining Out, Stay & Payment, and Transit Navigator.
  The Tall House library is the first study point for Arrival Essentials. Run
  `npm.cmd run learning:validate` whenever its source data or lesson assignments change.

## Import normalization (2026-07)

An Anki export is not automatically usable card data, and a badly mapped field is
invisible until a player hits it. **Travel Japanese w Audio (Nihongo Fun & Easy 2nd
Edition)** arrived with the romaji glued onto the end of every Japanese prompt
(`はいhai`, `英語は話せますか。Eigo wa hanasemasu ka.`) and `reading` unset on all 100
cards, which broke two things at once: prompts rendered as broken Japanese, and
`recall_panel`'s hint scaffolding — reading after two misses, reading + meaning
after three — had nothing to show for the whole travel phrasebook.

`tools/normalize_travel_deck.py` splits those fields apart in place (idempotent;
re-run it after any re-import) and moves the deck's glued usage notes to a `note`
field rather than deleting them; the recall reveal shows `note` when present.
Nothing is authored — every character written back was already in the deck, in the
wrong field. `tests/test_card_content.gd` asserts the result, since data fixes are
exactly what a silent re-import undoes.

`tools/rescue_long_answers.py` fixes the second import defect, across every deck
except Tae Kim's. An answer over `LearningProgression.MAX_CHOICE_LENGTH` (60) is
skipped in prompts, distractors, due counts, and mastery, so 21 cards were
unreachable content rather than a visible failure — 13 phrase cards with an
explanation glued onto the gloss, and 8 vocab cards pushed just over the limit by
a trailing qualifier (`to shine, sparkle, glow, emit light, glitter (no direct
object)`). The tool trims trailing clauses onto `note` until the answer fits, and
only ever runs on answers that are already over the limit, so the ~1,300 healthy
cards cannot be touched. It rescued 20 and reports the one it will not guess at
(`...-type-69`, a 63-character synonym list with no clause to trim).

`tools/clean_import_residue.py` fixes the third: Anki notes are HTML, and the
import that flattened them to plain text stopped half way. 73 entities were never
decoded, so a rune button read `I don&#x27;t have it` — 36 of the Travel
Vocabulary deck's 100 cards showed it, in their own answer or as a distractor
copied onto another card. Five more cards lost the spacing that a dropped `<br>`
carried (`1. to cut2. to put on clothes`). 55 cards cleaned, verified as decoding
and spacing only: no card, field, or wording changed.

**Pronunciation coverage is a sourcing limit, not a bug.** 279 of the 425
travel/phrase cards are silent, and only 4 of them have a written form Kanji alive
even has a recording for — all 4 blocked because the deck's reading is romaji
(`chuushajo`) against the catalogue's kana (`ちゅうしゃじょう`, which that romaji does
not actually spell). Kanji alive is a per-kanji example database; it has nothing
for `すみません`. Voicing the phrasebook needs a new licensed source, not a looser
matcher — `import_kanji_alive_audio.py` refuses fuzzy matches on purpose, because
a confidently wrong recording teaches wrong pronunciation.

Known remaining import defects:

- **Tae Kim's Grammar Guide**: the import mapped fields to the wrong roles —
  `prompt` holds an English study note, `reading` holds the Japanese, and `answer`
  holds `romaji: meaning`. The two grammar lessons ask the player to read a
  paragraph and pick a gloss. Needs a field remap, not a split.

## Reviewed Source Queue
- **Asking for Directions - Japanese language islands**, AnkiWeb deck `374921815`:
  127 direction and transit production cards. Candidate for the route/gate slice after its actual
  fields and media rights are reviewed.
- **Japanese Travel Vocabulary**, AnkiWeb deck `1811081813`:
  1,005 travel words and phrases with readings. Keep it for later expansion after the small
  arrival route is playable; it is intentionally too broad for the one-month starting loop.

## Zone → content mapping (long-term)
- Starter/Hub: kana, food words, greetings.
- Market Street: numbers, prices, ordering.
- Routes/Gates: directions, places, signs.
- Farm/Pier: nature words, verbs/actions.
- Forest/adventure: simple commands, item names, warnings.

## SRS feel (see SITE_WIDE_LEARNING_ARCHITECTURE.md)
- Micro-reviews only (1/3/5 cards). Wrong = gentle hint (show reading/meaning) + soon re-show,
  never shame. Correct = small XP + interval growth.

## Rewards (cozy, small)
Recipe Stamp, recipe card, food item, shop token, notebook entry, unlocked sign reading,
small area access, NPC relationship point, Raid unlock, Expedition unlock. (Slice-1 ships the
Recipe Stamp + XP + card unlock + sushi item.)

## Current guardrails
- Do not flashcard-dump a broad deck without a playable route and repetition plan.
- Do not use romaji-first progression or unsourced travel phrases.
- Keep grammar and kanji subordinate to immediate travel usefulness for this one-month push.

## Sourcing is enforced, not trusted (2026-07)

Every Japanese character shown to the player must be a `prompt`/`reading` from
`data/learning/cards.json`, which carries deck attribution from
`data/learning/sources/*.json`. This is checked by `tests/test_japanese_sourcing.gd`,
which scans every scene and script and fails on unsourced kana/kanji.

The rule above was previously broken in practice: 19 invented Japanese strings were
hardcoded into `world.tscn` and the NPC scripts, including an incorrect use of
いただきます as a greeting and a literal calque of an English idiom. Teaching wrong
Japanese is worse than teaching none, so the entities no longer accept Japanese text at
all — they take card ids:

- `sign_post.gd` -> `shows_card` (a card id) + English-only `caption`
- `teacher_npc.gd` -> `intro_lines` are English; the Japanese greeting is derived from the
  taught lesson's own cards

NPC narration is English. Japanese is curriculum, and curriculum comes from the decks.
