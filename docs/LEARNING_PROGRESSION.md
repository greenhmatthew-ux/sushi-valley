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
  Do not import a deck's audio or images unless their separate asset rights are reviewed; the current
  game source pack intentionally keeps media excluded.

## Imported Travel Source
- **Essential Japanese for Travelers** by Nihongo Picnic, AnkiWeb deck `1203744822`:
  20 notes split into Arrival Essentials, Dining Out, Stay & Payment, and Transit Navigator.
  The Tall House library is the first study point for Arrival Essentials. Run
  `npm.cmd run learning:validate` whenever its source data or lesson assignments change.

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
