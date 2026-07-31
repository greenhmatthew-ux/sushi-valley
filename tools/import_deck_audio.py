#!/usr/bin/env python3
r"""Import the native-speaker recordings that shipped with the imported Anki decks.

Every card was imported with `mediaPolicy: excluded`, so 852 of 1,330 cards were
silent even though their deck carried a recording for them. The cards kept
`sourceNoteId`, so each one maps to its own audio with no guessing: read the
deck's SQLite, pull the `[sound:...]` reference off that exact note, and resolve
it through the .apkg's media manifest.

Identical recordings are stored once and shared by checksum — decks repeat audio
across notes, and several of our decks overlap.

The Kanji alive manifest (`pronunciation-audio.json`) is left completely alone;
it is separately audited and pinned by tests. This writes `deck-audio.json`, and
`DB.pronunciation_for_card` prefers the audited clip and falls back to here.

    python tools/import_deck_audio.py [--deck-root D:\Downloads] [--dry-run]
"""
import hashlib
import json
import re
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "data/learning/sources"
OUT_DIR = ROOT / "assets/audio/japanese/decks"
MANIFEST = ROOT / "data/learning/deck-audio.json"

MANIFEST_VERSION = 1

## Our pack id -> the .apkg it was imported from, with the deck's display name.
DECKS = {
    "travel-japanese-w-audio-nihongo-fun-easy-2nd-edition": (
        "Travel_Japanese_w_Audio_Nihongo_Fun__Easy_2nd_Edition_.apkg",
        "Travel Japanese w Audio (Nihongo Fun & Easy 2nd Edition)"),
    "japanese-travel-vocabulary": (
        "Japanese_Travel_Vocabulary.apkg", "Japanese Travel Vocabulary"),
    "japanese-common-words-and-phrases-with-audio-kanji-romaji": (
        "Japanese_Common_Words_and_Phrases_with_AUDIO__Kanji_Romaji.apkg",
        "Japanese Common Words and Phrases with Audio (Kanji + Romaji)"),
    "essential-japanese-for-travelers": (
        "Essential_Japanese_for_Travelers.apkg", "Essential Japanese for Travelers"),
    "japanese-core-2k-vocab-natural-audio-mnemonics-and-type": (
        "Japanese_Core_2K_Vocab__Natural_Audio_Mnemonics_and_Type.apkg",
        "Japanese Core 2K Vocab (Natural Audio, Mnemonics and Type)"),
    "core-2k6k-optimized-japanese-vocabulary-with-sound-part-01": (
        "Core_2k6k_Optimized_Japanese_Vocabulary_with_Sound_Part_01.apkg",
        "Core 2k/6k Optimized Japanese Vocabulary with Sound, Part 01"),
    "kaishi-15k-basic-japanese-vocabulary": (
        "Kaishi_15k_-_Basic_Japanese_Vocabulary.apkg",
        "Kaishi 1.5k Basic Japanese Vocabulary"),
    "japanese-course-based-on-tae-kims-grammar-guide-anime": (
        "Japanese_course_based_on_Tae_Kims_grammar_guide__anime.apkg",
        "Japanese course based on Tae Kim's grammar guide (anime)"),
    "japanese-basic-hiragana": (
        "Japanese_Basic_Hiragana.apkg", "Japanese Basic Hiragana"),
    "japanese-kana-hiragana-katakana-rmaji-audio-strokes": (
        "Japanese_Kana_Hiragana_Katakana_Rmaji_audio_strokes.apkg",
        "Japanese Kana: Hiragana, Katakana, Romaji, audio, strokes"),
    "japanese-kana-hiraganakatakanamnemonics2x-audiostroke": (
        "Japanese_Kana_HiraganaKatakanaMnemonics2x_AudioStroke.apkg",
        "Japanese Kana: Hiragana/Katakana Mnemonics 2x, Audio, Stroke"),
}

SOUND_REF = re.compile(r"\[sound:([^\]]+)\]")
## Godot matches importers on a lowercase extension, so ".MP3" would be skipped.
AUDIO_SUFFIXES = {".mp3", ".ogg", ".wav", ".m4a", ".opus"}


def is_kana(text: str) -> bool:
    """True when every character is kana, so the prompt spells its own sound."""
    stripped = text.strip()
    if not stripped:
        return False
    return all(0x3040 <= ord(c) <= 0x30FF or c in "・ー" for c in stripped)


def link_twins(all_cards: dict, card_clips: dict) -> int:
    """Give a silent card the clip of an identically-written voiced card.

    The authored kana curriculum — the first thing a new player studies — is
    silent while the imported kana decks hold a recording of the very same
    character, because the authored cards were never part of a deck.

    Matching on the written form alone is only safe when that form determines
    the sound. Kana is phonetic, so あ is always "a" whether the card spells its
    reading `a` or `あ`. Kanji is not: 十分 is じゅうぶん or じゅっぷん, and handing
    one card the other's recording would teach the wrong word. So kanji prompts
    must also agree on a normalised reading, and refuse the link when they do not.
    """
    voiced_by_prompt = {}
    for card_id, digest in card_clips.items():
        card = all_cards.get(card_id)
        if not card:
            continue
        prompt = str(card.get("prompt", "")).strip()
        if prompt:
            voiced_by_prompt.setdefault(
                prompt, (digest, str(card.get("reading", "")), card_id))

    linked = {}
    for card_id, card in all_cards.items():
        if card_id in card_clips:
            continue
        prompt = str(card.get("prompt", "")).strip()
        twin = voiced_by_prompt.get(prompt)
        if twin is None:
            continue
        digest, twin_reading, twin_id = twin
        if not is_kana(prompt):
            mine = str(card.get("reading", "")).strip().lower()
            theirs = twin_reading.strip().lower()
            if not mine or not theirs or mine != theirs:
                continue
        card_clips[card_id] = digest
        linked[card_id] = twin_id
    return linked


def read_deck(apkg: Path):
    """Return (note id -> [media filenames], media filename -> zip entry name)."""
    with zipfile.ZipFile(apkg) as archive:
        names = archive.namelist()
        db_name = next((n for n in ("collection.anki21", "collection.anki2")
                        if n in names), None)
        if db_name is None:
            return {}, {}, None
        media = {}
        if "media" in names:
            # {"0": "some file.mp3"} — zip entries are numbered, not named.
            for entry, filename in json.loads(archive.read("media").decode("utf-8")).items():
                media[filename] = entry
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "collection.sqlite"
            db_path.write_bytes(archive.read(db_name))
            connection = sqlite3.connect(db_path)
            try:
                rows = connection.execute("SELECT id, flds FROM notes").fetchall()
            finally:
                connection.close()
    sounds = {}
    for note_id, fields in rows:
        found = SOUND_REF.findall(fields or "")
        if found:
            sounds[str(note_id)] = found
    return sounds, media, db_name


def main() -> int:
    argv = sys.argv
    dry_run = "--dry-run" in argv
    deck_root = Path("D:/Downloads")
    if "--deck-root" in argv:
        deck_root = Path(argv[argv.index("--deck-root") + 1])

    audited = json.loads((ROOT / "data/learning/pronunciation-audio.json")
                         .read_text(encoding="utf-8")).get("cards", {})

    if not dry_run:
        OUT_DIR.mkdir(parents=True, exist_ok=True)

    clips = {}          # sha256 -> clip record
    card_clips = {}     # card id -> sha256
    decks_used = []
    skipped_format = 0

    for pack_id, (filename, deck_name) in DECKS.items():
        pack_path = SOURCES / f"{pack_id}.json"
        apkg = deck_root / filename
        if not pack_path.is_file() or not apkg.is_file():
            print(f"  skip {pack_id}: deck file not found")
            continue
        cards = json.loads(pack_path.read_text(encoding="utf-8"))["cards"]
        sounds, media, _ = read_deck(apkg)
        mapped = 0
        with zipfile.ZipFile(apkg) as archive:
            for card in cards:
                note_id = str(card.get("sourceNoteId", ""))
                refs = sounds.get(note_id)
                if not refs:
                    continue
                source_name = refs[0]
                entry = media.get(source_name)
                if entry is None:
                    continue
                suffix = Path(source_name).suffix.lower()
                if suffix not in AUDIO_SUFFIXES:
                    skipped_format += 1
                    continue
                payload = archive.read(entry)
                digest = hashlib.sha256(payload).hexdigest()
                if digest not in clips:
                    out_name = f"{digest[:16]}{suffix}"
                    if not dry_run:
                        (OUT_DIR / out_name).write_bytes(payload)
                    clips[digest] = {
                        "path": f"res://assets/audio/japanese/decks/{out_name}",
                        "sha256": digest,
                        "bytes": len(payload),
                        "sourceFile": source_name,
                        "deck": deck_name,
                        "deckId": pack_id,
                    }
                card_clips[card["id"]] = digest
                mapped += 1
        decks_used.append({"deckId": pack_id, "deckName": deck_name,
                           "archive": filename, "cardsMapped": mapped})
        print(f"  {pack_id[:52]:<54}{mapped:>5} cards")

    # Every card in the project, so the authored curriculum can borrow a recording
    # of a word an imported deck already voices.
    all_cards = {c["id"]: c for c in
                 json.loads((ROOT / "data/learning/cards.json").read_text(encoding="utf-8"))}
    for pack_path in sorted(SOURCES.glob("*.json")):
        for card in json.loads(pack_path.read_text(encoding="utf-8"))["cards"]:
            all_cards.setdefault(card["id"], card)
    linked = link_twins(all_cards, card_clips)
    print(f"\n{len(linked)} silent cards linked to an identically-written voiced card")

    clip_ids = {digest: f"deck-{digest[:16]}" for digest in clips}
    manifest = {
        "version": MANIFEST_VERSION,
        "source": {
            "provider": "AnkiWeb shared decks",
            "license": "unstated by the deck authors",
            "note": ("Native-speaker audio shipped inside the .apkg files these cards "
                     "were imported from, matched to cards by the Anki note id kept "
                     "on each card. The decks declare no license; used by project "
                     "decision (see CLAUDE.md, Licensing)."),
        },
        "stats": {
            "cardsMapped": len(card_clips),
            "uniqueClips": len(clips),
            "newlyVoiced": len([c for c in card_clips if c not in audited]),
            "linkedByWrittenForm": len(linked),
            "bytes": sum(c["bytes"] for c in clips.values()),
        },
        "decks": decks_used,
        # Which card borrowed which card's recording, so the rule that allowed it
        # can be re-checked instead of taken on trust.
        "linkedCards": dict(sorted(linked.items())),
        "clips": {clip_ids[d]: clips[d] for d in clips},
        "cards": {cid: clip_ids[d] for cid, d in sorted(card_clips.items())},
    }
    total_mb = manifest["stats"]["bytes"] / 1_048_576
    print(f"\n{len(card_clips)} cards mapped to {len(clips)} unique clips "
          f"({total_mb:.1f} MB), {manifest['stats']['newlyVoiced']} newly voiced")
    if skipped_format:
        print(f"{skipped_format} references skipped: unsupported audio format")
    if dry_run:
        print("(dry run, nothing written)")
    else:
        MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
