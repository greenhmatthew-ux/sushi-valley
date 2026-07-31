#!/usr/bin/env python3
"""Normalize the Travel Japanese (Nihongo Fun & Easy) source pack in place.

The Anki export glued each card's romaji onto the end of the Japanese prompt
("はいhai", "英語は話せますか。Eigo wa hanasemasu ka.") and left `reading` unset for
all 100 cards. That costs the player twice: the prompt renders as broken
Japanese, and `recall_panel`'s hint scaffolding — which shows the reading after
two misses and reading + meaning after three — silently has nothing to show for
the entire travel phrasebook.

A few cards also carry the deck's usage notes glued onto the end of a field,
either after a "*" separator or as a trailing "(...)" with no space before it.
Those notes are worth keeping, but not inside an answer that has to fit on a
rune button, so they move to `note` instead of being deleted.

Nothing is invented here: every character written back already existed in the
imported deck, only in the wrong field. Card ids, choices ordering, tags, and
source attribution are untouched, so lessons.json keeps resolving. Re-run this
after any re-import of the deck; it is idempotent.

    python tools/normalize_travel_deck.py [--dry-run]
"""
import json
import re
import sys
from pathlib import Path

PACK = (Path(__file__).resolve().parent.parent
        / "data/learning/sources/travel-japanese-w-audio-nihongo-fun-easy-2nd-edition.json")

## A usage note glued onto the end of a field with no separating space, e.g.
## "Ee, asoko ni arimasu yo.(The particle "yo" is used to emphasize...)".
## Anchored to the end and preceded by a non-space so genuinely parenthesised
## content survives: "(o)kuni" and "Is there anyone (here) who speaks English?"
## must not be touched.
GLUED_NOTE = re.compile(r"^(?P<body>.*[^\s(])\((?P<note>[^()]*)\)$")


def is_japanese(ch: str) -> bool:
    """Kana, kanji, and the CJK/full-width punctuation that sits between them."""
    cp = ord(ch)
    return (0x3000 <= cp <= 0x303F      # 。、「」・
            or 0x3040 <= cp <= 0x309F   # hiragana
            or 0x30A0 <= cp <= 0x30FF   # katakana, ー
            or 0x4E00 <= cp <= 0x9FFF   # kanji
            or 0xFF01 <= cp <= 0xFF60)  # （）？ full-width forms


def split_prompt(card: dict) -> bool:
    """Move the romaji tail out of `prompt` and into `reading`.

    The split point is the last Japanese character, not the first latin one:
    "（お）つとめ / かいしゃ(o)tsutome / kaisha" has to break after かいしゃ, and a
    leading-letter rule breaks it in the middle of "(o)" instead.
    """
    if str(card.get("reading", "")).strip():
        return False
    prompt = str(card.get("prompt", ""))
    last = -1
    for i, ch in enumerate(prompt):
        if is_japanese(ch):
            last = i
    if last < 0:
        return False
    japanese, romaji = prompt[:last + 1], prompt[last + 1:].strip()
    if not romaji or not any(ch.isalpha() for ch in romaji):
        return False
    # A trailing-off ellipsis belongs to the phrase, not to its romaji:
    # "すみません、ちょっと...Sumimasen, chotto..." keeps its dots on both halves.
    ellipsis = re.match(r"^\.+", romaji)
    if ellipsis:
        japanese += ellipsis.group(0)
        romaji = romaji[ellipsis.end():].strip()
    card["prompt"] = japanese
    card["reading"] = romaji
    return True


def strip_note(text: str) -> tuple:
    """Return (clean_text, note). Note is "" when the field carries none."""
    notes = []
    body = text.strip()
    if "*" in body:
        body, _, tail = body.partition("*")
        body = body.strip()
        if tail.strip():
            notes.append(tail.strip())
    glued = GLUED_NOTE.match(body)
    if glued:
        body = glued.group("body").strip()
        if glued.group("note").strip():
            notes.append(glued.group("note").strip())
    return body, " ".join(notes)


def extract_notes(card: dict) -> bool:
    """Pull usage notes out of the recallable fields and onto `note`."""
    found = []
    changed = False
    for field in ("prompt", "reading", "answer", "meaning"):
        if field not in card:
            continue
        clean, note = strip_note(str(card[field]))
        if clean != str(card[field]):
            card[field] = clean
            changed = True
        if note and note not in found:
            found.append(note)
    # Choices are copies of other cards' answers, so they carry the same glue.
    # Their notes already live on the card they came from; drop them here.
    choices = card.get("choices")
    if isinstance(choices, list):
        cleaned = [strip_note(str(c))[0] for c in choices]
        if cleaned != choices:
            card["choices"] = cleaned
            changed = True
    if found:
        existing = str(card.get("note", "")).strip()
        merged = " ".join([existing] + [n for n in found if n != existing]).strip()
        if merged != existing:
            card["note"] = merged
            changed = True
    return changed


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    pack = json.loads(PACK.read_text(encoding="utf-8"))
    cards = pack.get("cards", [])
    readings = 0
    noted = 0
    for card in cards:
        before = json.dumps(card, ensure_ascii=False, sort_keys=True)
        if split_prompt(card):
            readings += 1
        if extract_notes(card):
            noted += 1
        after = json.dumps(card, ensure_ascii=False, sort_keys=True)
        if dry_run and before != after:
            print(f"{card.get('id')}\n  prompt : {card.get('prompt')}"
                  f"\n  reading: {card.get('reading')}"
                  f"\n  answer : {card.get('answer')}"
                  + (f"\n  note   : {card.get('note')}" if card.get("note") else ""))
    print(f"{len(cards)} cards: {readings} readings split out of the prompt, "
          f"{noted} cards had usage notes moved to `note`"
          + (" (dry run, nothing written)" if dry_run else ""))
    if not dry_run:
        PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
