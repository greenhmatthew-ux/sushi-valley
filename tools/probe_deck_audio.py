#!/usr/bin/env python3
"""Report which imported cards the original Anki decks have audio for.

Read-only. Copies nothing and writes nothing into the project; it exists so the
audio question can be answered with numbers instead of guesses. Every deck's
media was excluded at import (`mediaPolicy: excluded`) pending a rights review,
and this says exactly what is behind that gate.

    python tools/probe_deck_audio.py [--deck-root D:\\Downloads]
"""
import json
import re
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "data/learning/sources"

## Our pack id -> the .apkg it was imported from.
DECK_FILES = {
    "travel-japanese-w-audio-nihongo-fun-easy-2nd-edition":
        "Travel_Japanese_w_Audio_Nihongo_Fun__Easy_2nd_Edition_.apkg",
    "japanese-travel-vocabulary": "Japanese_Travel_Vocabulary.apkg",
    "japanese-common-words-and-phrases-with-audio-kanji-romaji":
        "Japanese_Common_Words_and_Phrases_with_AUDIO__Kanji_Romaji.apkg",
    "essential-japanese-for-travelers": "Essential_Japanese_for_Travelers.apkg",
    "japanese-core-2k-vocab-natural-audio-mnemonics-and-type":
        "Japanese_Core_2K_Vocab__Natural_Audio_Mnemonics_and_Type.apkg",
    "core-2k6k-optimized-japanese-vocabulary-with-sound-part-01":
        "Core_2k6k_Optimized_Japanese_Vocabulary_with_Sound_Part_01.apkg",
    "kaishi-15k-basic-japanese-vocabulary": "Kaishi_15k_-_Basic_Japanese_Vocabulary.apkg",
    "japanese-course-based-on-tae-kims-grammar-guide-anime":
        "Japanese_course_based_on_Tae_Kims_grammar_guide__anime.apkg",
    "japanese-basic-hiragana": "Japanese_Basic_Hiragana.apkg",
    "japanese-kana-hiragana-katakana-rmaji-audio-strokes":
        "Japanese_Kana_Hiragana_Katakana_Rmaji_audio_strokes.apkg",
    "japanese-kana-hiraganakatakanamnemonics2x-audiostroke":
        "Japanese_Kana_HiraganaKatakanaMnemonics2x_AudioStroke.apkg",
}

SOUND_REF = re.compile(r"\[sound:([^\]]+)\]")


def note_sounds(apkg: Path) -> dict:
    """note id -> [media filenames], read straight from the deck's SQLite."""
    with zipfile.ZipFile(apkg) as archive:
        names = archive.namelist()
        db_name = next((n for n in ("collection.anki21", "collection.anki2")
                        if n in names), None)
        if db_name is None:
            return {}
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "collection.sqlite"
            db_path.write_bytes(archive.read(db_name))
            connection = sqlite3.connect(db_path)
            try:
                rows = connection.execute("SELECT id, flds FROM notes").fetchall()
            finally:
                connection.close()
    out = {}
    for note_id, fields in rows:
        found = SOUND_REF.findall(fields or "")
        if found:
            out[str(note_id)] = found
    return out


def main() -> int:
    deck_root = Path("D:/Downloads")
    if "--deck-root" in sys.argv:
        deck_root = Path(sys.argv[sys.argv.index("--deck-root") + 1])
    audio_map = json.loads((ROOT / "data/learning/pronunciation-audio.json")
                           .read_text(encoding="utf-8"))
    already = set(audio_map.get("cards", {}))

    total_cards = total_with_audio = total_new = 0
    print(f"{'deck':<52}{'cards':>6}{'has audio':>11}{'newly voiced':>14}")
    for pack_id, filename in DECK_FILES.items():
        pack_path = SOURCES / f"{pack_id}.json"
        apkg = deck_root / filename
        if not pack_path.is_file() or not apkg.is_file():
            print(f"{pack_id[:50]:<52}{'-':>6}{'missing deck':>11}")
            continue
        cards = json.loads(pack_path.read_text(encoding="utf-8"))["cards"]
        sounds = note_sounds(apkg)
        with_audio = [c for c in cards if str(c.get("sourceNoteId", "")) in sounds]
        new = [c for c in with_audio if c["id"] not in already]
        total_cards += len(cards)
        total_with_audio += len(with_audio)
        total_new += len(new)
        print(f"{pack_id[:50]:<52}{len(cards):>6}{len(with_audio):>11}{len(new):>14}")
    print(f"{'TOTAL':<52}{total_cards:>6}{total_with_audio:>11}{total_new:>14}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
