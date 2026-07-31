#!/usr/bin/env python3
"""Undo what HTML stripping left behind in the imported card text.

Anki notes are HTML, and the import that flattened them to plain text stopped
half way. Two kinds of residue reach the player:

  * HTML entities, never decoded. 73 of them survive in the Travel Vocabulary
    deck, so a rune button reads "I don&#x27;t have it" and "Sorry, I can&#x27;t"
    — visible on 36 of that deck's 100 cards, either in the answer or as a
    distractor copied onto another card.
  * enumerator spacing, eaten with the tag that carried it. "1. to cut<br>2. to
    put on clothes" became "1. to cut2. to put on clothes".

Both are decoding faults, not content decisions: the fix restores the text the
deck's author wrote, and nothing here rewrites meaning or invents wording. Runs
over every source pack plus cards.json, and is idempotent.

    python tools/clean_import_residue.py [--dry-run]
"""
import html
import json
import re
import sys
from pathlib import Path

LEARNING = Path(__file__).resolve().parent.parent / "data/learning"

TEXT_FIELDS = ("prompt", "answer", "reading", "meaning", "note")

## An enumerator glued onto the previous sense because the <br> before it was
## dropped: "to cut2." / "(formal)2.". Anchored to a letter or a closing paren so
## ordinary numbers ("4000 yen") are left alone.
GLUED_ENUMERATOR = re.compile(r"(?<=[a-z\)])(?=\d+\.\s)")


def clean(text: str) -> str:
    out = html.unescape(text)
    out = GLUED_ENUMERATOR.sub(" ", out)
    return out


def clean_card(card: dict) -> bool:
    changed = False
    for field in TEXT_FIELDS:
        if field not in card:
            continue
        fixed = clean(str(card[field]))
        if fixed != str(card[field]):
            card[field] = fixed
            changed = True
    choices = card.get("choices")
    if isinstance(choices, list):
        fixed_choices = [clean(str(c)) for c in choices]
        if fixed_choices != choices:
            card["choices"] = fixed_choices
            changed = True
    return changed


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    total = 0
    for path in sorted(LEARNING.glob("sources/*.json")) + [LEARNING / "cards.json"]:
        data = json.loads(path.read_text(encoding="utf-8"))
        cards = data["cards"] if isinstance(data, dict) else data
        touched = 0
        for card in cards:
            before = json.dumps(card, ensure_ascii=False, sort_keys=True)
            if clean_card(card):
                touched += 1
                if dry_run:
                    after = json.dumps(card, ensure_ascii=False, sort_keys=True)
                    if before != after:
                        print(f"{card['id']}\n  answer: {card.get('answer')}")
        if touched:
            total += touched
            print(f"  {path.name}: {touched} cards")
            if not dry_run:
                path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                                encoding="utf-8")
    print(f"{total} cards cleaned" + (" (dry run, nothing written)" if dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
