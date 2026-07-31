#!/usr/bin/env python3
"""Bring over-long imported answers back under the recall length limit.

`LearningProgression.recall_eligible` rejects any answer longer than 60
characters, because a paragraph cannot sit on a rune button — one of them stretched
the combat panel to 11,000px before that limit existed. Rejected cards are then
skipped everywhere: prompts, distractors, due counts, and lesson mastery. They are
not broken loudly, they are simply unreachable content the player paid for.

Twenty-one cards are stuck that way, in two shapes:

  * an explanation glued onto the gloss, after a "(...)", an em dash, "Ex.",
    "eg.", "Literal:", or a red-dot marker —
    "to think, believe— believe in the sense of personal opinion..."
  * a legitimate multi-gloss answer pushed just over the limit by a trailing
    qualifier — "to shine, sparkle, glow, emit light, glitter (no direct object)"

Both are fixed by trimming trailing clauses until the answer fits. The rule only
ever runs on answers that are *already* over the limit, so the ~1,300 cards that
are fine cannot be touched, and the trimmed text is kept on `note` (shown in the
recall reveal) rather than deleted. Nothing is rewritten or invented.

Tae Kim's deck is excluded on purpose: its import mapped fields to the wrong
roles entirely, so it needs a remap, not a trim. See docs/LEARNING_PROGRESSION.md.

    python tools/rescue_long_answers.py [--dry-run]
"""
import json
import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "data/learning/sources"

## Mirrors LearningProgression.MAX_CHOICE_LENGTH. Keep the two in step.
MAX_ANSWER_LENGTH = 60

## Tae Kim's deck used to be skipped here: its fields were mapped to the wrong
## roles, so trimming its answers would have hidden that rather than fixed it.
## `tools/remap_tae_kim_deck.py` has since rebuilt it, and it now trims like any
## other deck. If that deck is ever re-imported raw, run the remap first.
SKIP_DECKS = set()

## A trailing parenthetical qualifier or aside: "..., glitter (no direct object)".
TRAILING_PAREN = re.compile(r"^(?P<body>.*?)\s*\((?P<note>[^()]*)\)$")

## Markers these decks use to start an aside mid-field. Ordered longest-first so
## "e.g." is not matched as "eg". Applied only after parentheticals, since some
## asides contain a marker inside them: "(requires a direct object ex. doors...)".
NOTE_MARKERS = ("🔴", "—", "Literal:", "literal:", "e.g.", "Ex.", "ex.", "eg.")


def trim_once(text: str):
    """Remove one trailing clause. Returns (body, removed) or None if there is none."""
    paren = TRAILING_PAREN.match(text)
    if paren and paren.group("body").strip():
        return paren.group("body").strip(), paren.group("note").strip()
    for marker in NOTE_MARKERS:
        idx = text.find(marker)
        if idx > 0:
            body = text[:idx].strip()
            if body:
                return body, text[idx + len(marker):].strip()
    return None


def shorten(text: str):
    """Trim trailing clauses until the answer fits. Returns (body, notes)."""
    body = text.strip()
    notes = []
    while len(body) > MAX_ANSWER_LENGTH:
        step = trim_once(body)
        if step is None:
            break
        body, removed = step
        if removed:
            notes.insert(0, removed)
    return body, notes


def rescue(card: dict) -> bool:
    changed = False
    notes = []
    answer = str(card.get("answer", "")).strip()
    if len(answer) > MAX_ANSWER_LENGTH:
        body, removed = shorten(answer)
        if body != answer:
            card["answer"] = body
            notes.extend(removed)
            changed = True
    # Choices are copies of other cards' answers and carry the same overflow;
    # trimming them here makes them usable distractors again. Their explanations
    # already live on the card they came from, so they are dropped, not merged.
    choices = card.get("choices")
    if isinstance(choices, list):
        cleaned = [shorten(str(c))[0] if len(str(c).strip()) > MAX_ANSWER_LENGTH
                   else str(c) for c in choices]
        if cleaned != choices:
            card["choices"] = cleaned
            changed = True
    if notes:
        existing = str(card.get("note", "")).strip()
        merged = " ".join([existing] + [n for n in notes if n != existing]).strip()
        if merged != existing:
            card["note"] = merged
    return changed


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    rescued = 0
    stubborn = []
    for path in sorted(SOURCES.glob("*.json")):
        if path.stem in SKIP_DECKS:
            continue
        pack = json.loads(path.read_text(encoding="utf-8"))
        touched = False
        for card in pack.get("cards", []):
            was = str(card.get("answer", "")).strip()
            if rescue(card):
                touched = True
            now = str(card.get("answer", "")).strip()
            if was != now:
                rescued += 1
                if dry_run:
                    print(f"{card['id']}\n  was: {was}\n  now: {now}"
                          + (f"\n  note: {card.get('note')}" if card.get("note") else ""))
            if len(now) > MAX_ANSWER_LENGTH:
                stubborn.append((card["id"], now))
        if touched and not dry_run:
            path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8")
    print(f"{rescued} answers brought under {MAX_ANSWER_LENGTH} characters"
          + (" (dry run, nothing written)" if dry_run else ""))
    for cid, text in stubborn:
        print(f"  still unreachable ({len(text)} chars): {cid}\n    {text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
