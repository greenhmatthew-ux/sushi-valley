# Site-Wide Learning Architecture

Japanese learning is **site-wide**, not trapped in the Valley. One profile, one card DB, one
SRS, many surfaces (webapp lessons, kana practice, flashcards, dashboard/notebook, Sushi Valley
NPCs/signs/shops, combat, Raids, Expeditions).

## Source of truth (implemented)
`src/shared/learning/`
- **`LearningTypes.ts`** — `SrsCard`, `Lesson`, `LearningProfileData`, grades.
- **`SrsSystem.ts`** — gentle SM-lite scheduler (again→~1 min, hard/good/easy grow interval by
  ease). No punishment; wrong answers reschedule soon.
- **`LearningProfile.ts`** — hydrates static card/lesson defs with saved scheduling; uses the
  active character's local cache key; flags + composite account/character stats.
- **`LearningProgressionSystem.ts`** — facade every surface calls: `buildPrompt()`, `nextDue()`,
  `dueCount()`, `answer()`, `grade()`, `awardXp()`. `learning()` returns one shared instance.

Data: `src/shared/data/cards.json`, `lessons.json` (curated; kana vowels, kana-for-sushi,
greetings, food words).

## Schemas
**SrsCard:** id, lessonId, type(kana|vocab|phrase|reading|number), prompt, answer, choices?,
reading?, meaning?, tags[], unlocked, dueAt, intervalDays, ease, correctCount, incorrectCount,
lastReviewedAt.
**Lesson:** id, title, category, description, cardIds[], unlockFlags?.
**Runtime profile:** version, cards{}, flags{}, stats{ totalReviews, totalCorrect, xp, lastActiveAt }.
Cloud serialization splits this composite view: card scheduling, review counters, and read-content
history belong to the account; RPG XP, flags, build, inventory, gear, quests, and world systems belong
to the selected character.

## How surfaces connect
- **Sushi Valley (implemented):** NPCs, study spots, pickups, recall gates, the Notebook,
  regular combat, Raids, and Expeditions all read/write the shared profile. Flags, unlocks,
  rewards, and instance progress persist through that profile.
- **Recall surfaces (implemented):** use the same `buildPrompt()`/`LearnPrompt` path and feed
  results back to the same SRS. Combat does not own a separate card deck or scheduler.
- **Legacy webapp (reference only):** its study/cards/SRS and storage remain standalone legacy
  material. Do not wire new reboot features into that code or create bidirectional sync between
  the old and new schedulers.
- **Supabase accounts (implemented, configuration optional):** email/password sessions and a
  pre-Phaser three-slot roster establish persistence context before the shared learning singleton is
  created. Account learning is rehydrated into each selected character's composite runtime profile;
  optimistic revisions reject stale cloud or admin writes.

The synchronous profile and world-save systems remain the gameplay hot path. Without Supabase
configuration they use the original local keys. With account mode enabled they use per-character local
caches and asynchronously sync a sparse account-learning document plus separate character/world
documents. See [`SUPABASE_ACCOUNTS.md`](SUPABASE_ACCOUNTS.md). Never write reboot data into the legacy
`public.profiles.progress` document.

## Legacy rebuild boundary
1. Inventory a useful legacy activity and its learning content before selecting it for a new slice.
2. Rebuild that activity in Vite/TypeScript using `LearningProfile`, the shared SRS, XP, flags,
   and curated card data; do not transplant the old activity runtime.
3. A one-time legacy-save importer, if wanted, is a separate migration slice with fixtures and
   rollback-safe tests. Do not add implicit two-way synchronization.
4. Raid terminology and reboot systems are already established; legacy Quest/deckbuilder code
   cannot silently redefine them.

## Rules
- One SrsSystem everywhere; never fork it per surface.
- Micro-reviews only (1/3/5 questions); never a forced review wall.
- Curated content only — no auto-generated Japanese. Romaji optional/tutorial only.
