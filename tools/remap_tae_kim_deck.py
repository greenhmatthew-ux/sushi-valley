#!/usr/bin/env python3
"""Put Tae Kim's imported cards back in the right fields.

This deck's import mapped every field to the wrong role. The Japanese landed in
`reading`, an English study note landed in `prompt`, and `answer` holds the
romaji and gloss glued to more study notes:

    prompt   Note that the Japanese "ha"-character (は) is pronounced "wa"...
    reading  こんにちは
    answer   konnichiha: hello; good day; good afternoonThere are many more...

So the two grammar lessons ask the player to read an English paragraph and pick
a paragraph, with the Japanese never shown. This rebuilds each card as
prompt = Japanese, reading = romaji, answer = short gloss, note = study note.
Every piece of text is moved, never rewritten, and the study notes are kept on
`note` rather than dropped.

Ten of the twenty cards are not flashcards at all — they are the deck author's
prose remarks, with no Japanese and `answer` set to the page number "14". They
cannot be rebuilt from anything, so the script reports them and leaves them
alone; they are dropped from the lessons in data/learning/lessons.json instead.

    python tools/remap_tae_kim_deck.py [--dry-run]
"""
import json
import re
import sys
from pathlib import Path

PACK = (Path(__file__).resolve().parent.parent
        / "data/learning/sources/japanese-course-based-on-tae-kims-grammar-guide-anime.json")

MAX_ANSWER_LENGTH = 60

## "konnichiha: hello; good day..." — a romaji headword before the gloss. Lower
## case only, which is what separates it from an English gloss that happens to
## contain a colon ("As for today - thank you (or less literal: ...)").
ROMAJI_HEADWORD = re.compile(r"^(?P<romaji>[a-z][a-z'\- ]*):\s*(?P<rest>.+)$", re.S)

## Where the gloss stops and a glued-on study note starts.
NOTE_STARTS = (
    re.compile(r"[.?!](?=[a-z']+:)"),        # "...a dream.kidsuku: to notice"
    re.compile(r"(?<=[a-z\)\]])(?=[A-Z])"),  # "...good afternoonThere are many"
    re.compile(r'\.(?=")'),                  # '...a dream."janakatta" is the...'
)

PARENTHETICAL = re.compile(r"\s*\([^()]*\)")


def has_japanese(text: str) -> bool:
    return any(0x3040 <= ord(c) <= 0x30FF or 0x4E00 <= ord(c) <= 0x9FFF for c in text)


def split_note(text: str):
    """Cut the gloss free of the study note glued to its end."""
    cut = len(text)
    for pattern in NOTE_STARTS:
        found = pattern.search(text)
        if found and found.end() < cut:
            cut = found.end()
    return text[:cut].strip(), text[cut:].strip()


def shorten(gloss: str):
    """Drop parenthetical asides, last one first, until the gloss fits a button."""
    notes = []
    while len(gloss) > MAX_ANSWER_LENGTH:
        matches = list(PARENTHETICAL.finditer(gloss))
        if not matches:
            break
        last = matches[-1]
        notes.insert(0, last.group(0).strip())
        gloss = (gloss[:last.start()] + gloss[last.end():])
        gloss = re.sub(r"\s{2,}", " ", gloss).replace(" ]", "]").strip()
    return gloss, notes


def remap(card: dict) -> bool:
    japanese = str(card.get("reading", "")).strip()
    if not has_japanese(japanese):
        return False

    notes = []
    study_note = str(card.get("prompt", "")).strip()
    if study_note:
        notes.append(study_note)

    romaji = ""
    body = str(card.get("answer", "")).strip()
    headword = ROMAJI_HEADWORD.match(body)
    if headword:
        romaji = headword.group("romaji").strip()
        body = headword.group("rest").strip()

    gloss, trailing = split_note(body)
    if trailing:
        notes.append(trailing)
    gloss, dropped = shorten(gloss)
    notes.extend(dropped)

    card["prompt"] = japanese
    card["reading"] = romaji
    card["answer"] = gloss
    card["meaning"] = gloss
    card["note"] = " ".join(n for n in notes if n)
    return True


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    pack = json.loads(PACK.read_text(encoding="utf-8"))
    cards = pack.get("cards", [])

    # Old answer -> new answer, so each card's distractor list still points at
    # the other cards in the deck instead of at text that no longer exists.
    previous = {str(c.get("answer", "")): c["id"] for c in cards}

    remapped = []
    prose = []
    for card in cards:
        if remap(card):
            remapped.append(card)
        else:
            prose.append(card["id"])

    by_id = {c["id"]: c for c in cards}
    for card in cards:
        rebuilt = []
        for choice in card.get("choices", []):
            owner = previous.get(str(choice))
            if owner is None:
                continue
            answer = str(by_id[owner].get("answer", ""))
            if answer and answer != str(card.get("answer", "")) and answer not in rebuilt:
                rebuilt.append(answer)
        card["choices"] = rebuilt

    for card in remapped:
        flag = "  <-- still too long" if len(card["answer"]) > MAX_ANSWER_LENGTH else ""
        print(f"{card['id'].split('-')[-1]:>3}  {card['prompt']}")
        print(f"     reading: {card['reading'] or '(none in the deck)'}")
        print(f"     answer : {card['answer']}{flag}")
    print(f"\n{len(remapped)} cards rebuilt, {len(prose)} prose remarks left alone:")
    print("     " + ", ".join(p.split("-")[-1] for p in prose))
    if dry_run:
        print("(dry run, nothing written)")
    else:
        PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
