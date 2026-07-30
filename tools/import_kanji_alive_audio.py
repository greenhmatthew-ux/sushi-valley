#!/usr/bin/env python3
r"""Import the licensed Kanji alive recordings used by Sushi Valley cards.

The importer deliberately matches both the written prompt and its reading. It
does not use fuzzy matching: a card is mapped only when its normalized prompt
and at least one normalized reading exactly match a Kanji alive example.

Usage:
    python tools/import_kanji_alive_audio.py
    python tools/import_kanji_alive_audio.py --check
    python tools/import_kanji_alive_audio.py --source-root D:\path\to\source
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import subprocess
import sys
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SOURCE_REVISION = "2d2a4931eec6e0cb532d5102766273c2323f96db"
SOURCE_CSV_SHA256 = "ff55dedc2a8875007dbd01e72478bfe62d15c2a436c22fae2cbcb354308476df"
SOURCE_ARCHIVE_SHA256 = "138ccec5e7701a378642cb3f35727de964cc666351bb9f00765706583f89fe9d"
SOURCE_ARCHIVE_FILES = 10_187
EXPECTED_CARDS_SCANNED = 1_392
EXPECTED_CARDS_MAPPED = 459
EXPECTED_UNIQUE_CLIPS = 366

REPOSITORY_URL = "https://github.com/kanjialive/kanji-data-media"
PROJECT_URL = "https://kanjialive.com/"
ARCHIVE_URL = "https://media.kanjialive.com/examples_audio/audio-ogg.zip"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"

EXPECTED_MISMATCHED_ROWS = (
    ("臓", "zou(motsu)", 7, 8),
    ("秋", "aki", 4, 5),
    ("鈍", "nibu(i)", 7, 8),
    ("短", "mijika(i)", 5, 6),
    ("入", "hai(ru)", 10, 11),
    ("意", "(ketsu)i", 10, 11),
    ("覚", "kaku-obo(eru)", 8, 9),
    ("結", "musu(bu)", 10, 11),
    ("来", "rai-ku(ru)", 9, 10),
    ("住", "juu-su(mu)", 6, 7),
)

EXPECTED_READING_MISMATCHES = (
    (
        "core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-142",
        "十分",
        ("じゅうぶん",),
        ("じゅっぷん",),
    ),
    (
        "core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-148",
        "何",
        ("なん",),
        ("なに",),
    ),
    (
        "japanese-common-words-and-phrases-with-audio-kanji-romaji-62",
        "大きい",
        ("ooki",),
        ("おおきい",),
    ),
    (
        "kaishi-15k-basic-japanese-vocabulary-8",
        "人",
        ("じん",),
        ("ひと",),
    ),
)

EXAMPLE_PATTERN = re.compile(r"(.*?)（([^（）]+)）\s*")
AUDIO_NAME_PATTERN = re.compile(r"(.+)_06_([a-z])\.ogg", re.IGNORECASE)
READING_SPLIT_PATTERN = re.compile(r"\s*(?:/|,|、|・)\s*")
BRACKET_FURIGANA_PATTERN = re.compile(
    r"[々〇〆\u3400-\u9fff\uf900-\ufaff]+\[([^\]]+)\]"
)
ASCII_READING_PATTERN = re.compile(r"[a-z-]+")


@dataclass(frozen=True)
class CatalogRecord:
    prompt: str
    readings: tuple[str, ...]
    source_file: str


@dataclass(frozen=True)
class CardMatch:
    card_id: str
    record: CatalogRecord


HIRAGANA_ROMAJI = {
    "あ": "a",
    "い": "i",
    "う": "u",
    "え": "e",
    "お": "o",
    "か": "ka",
    "き": "ki",
    "く": "ku",
    "け": "ke",
    "こ": "ko",
    "が": "ga",
    "ぎ": "gi",
    "ぐ": "gu",
    "げ": "ge",
    "ご": "go",
    "さ": "sa",
    "し": "shi",
    "す": "su",
    "せ": "se",
    "そ": "so",
    "ざ": "za",
    "じ": "ji",
    "ず": "zu",
    "ぜ": "ze",
    "ぞ": "zo",
    "た": "ta",
    "ち": "chi",
    "つ": "tsu",
    "て": "te",
    "と": "to",
    "だ": "da",
    "ぢ": "ji",
    "づ": "zu",
    "で": "de",
    "ど": "do",
    "な": "na",
    "に": "ni",
    "ぬ": "nu",
    "ね": "ne",
    "の": "no",
    "は": "ha",
    "ひ": "hi",
    "ふ": "fu",
    "へ": "he",
    "ほ": "ho",
    "ば": "ba",
    "び": "bi",
    "ぶ": "bu",
    "べ": "be",
    "ぼ": "bo",
    "ぱ": "pa",
    "ぴ": "pi",
    "ぷ": "pu",
    "ぺ": "pe",
    "ぽ": "po",
    "ま": "ma",
    "み": "mi",
    "む": "mu",
    "め": "me",
    "も": "mo",
    "や": "ya",
    "ゆ": "yu",
    "よ": "yo",
    "ら": "ra",
    "り": "ri",
    "る": "ru",
    "れ": "re",
    "ろ": "ro",
    "わ": "wa",
    "ゐ": "i",
    "ゑ": "e",
    "を": "wo",
    "ん": "n",
    "ぁ": "a",
    "ぃ": "i",
    "ぅ": "u",
    "ぇ": "e",
    "ぉ": "o",
    "ゎ": "wa",
    "ゔ": "vu",
}

DIGRAPH_ROMAJI = {
    "きゃ": "kya",
    "きゅ": "kyu",
    "きょ": "kyo",
    "ぎゃ": "gya",
    "ぎゅ": "gyu",
    "ぎょ": "gyo",
    "しゃ": "sha",
    "しゅ": "shu",
    "しょ": "sho",
    "じゃ": "ja",
    "じゅ": "ju",
    "じょ": "jo",
    "ちゃ": "cha",
    "ちゅ": "chu",
    "ちょ": "cho",
    "ぢゃ": "ja",
    "ぢゅ": "ju",
    "ぢょ": "jo",
    "にゃ": "nya",
    "にゅ": "nyu",
    "にょ": "nyo",
    "ひゃ": "hya",
    "ひゅ": "hyu",
    "ひょ": "hyo",
    "びゃ": "bya",
    "びゅ": "byu",
    "びょ": "byo",
    "ぴゃ": "pya",
    "ぴゅ": "pyu",
    "ぴょ": "pyo",
    "みゃ": "mya",
    "みゅ": "myu",
    "みょ": "myo",
    "りゃ": "rya",
    "りゅ": "ryu",
    "りょ": "ryo",
    "ふぁ": "fa",
    "ふぃ": "fi",
    "ふぇ": "fe",
    "ふぉ": "fo",
    "てぃ": "ti",
    "でぃ": "di",
    "とぅ": "tu",
    "どぅ": "du",
    "うぃ": "wi",
    "うぇ": "we",
    "うぉ": "wo",
    "しぇ": "she",
    "じぇ": "je",
    "ちぇ": "che",
    "つぁ": "tsa",
    "つぃ": "tsi",
    "つぇ": "tse",
    "つぉ": "tso",
    "ゔぁ": "va",
    "ゔぃ": "vi",
    "ゔぇ": "ve",
    "ゔぉ": "vo",
    "ゔゅ": "vyu",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def verify_sources(source_root: Path) -> tuple[Path, Path]:
    csv_path = source_root / "language-data" / "ka_data.csv"
    archive_path = source_root / "audio-ogg.zip"
    require(csv_path.is_file(), f"Missing Kanji alive CSV: {csv_path}")
    require(archive_path.is_file(), f"Missing Kanji alive archive: {archive_path}")

    revision_result = subprocess.run(
        ["git", "-C", str(source_root), "rev-parse", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    require(
        revision_result.returncode == 0,
        f"Could not read source Git revision: {revision_result.stderr.strip()}",
    )
    revision = revision_result.stdout.strip()
    require(
        revision == SOURCE_REVISION,
        f"Source revision is {revision}; expected {SOURCE_REVISION}",
    )
    require(
        sha256_file(csv_path) == SOURCE_CSV_SHA256,
        "ka_data.csv does not match the pinned source revision",
    )
    require(
        sha256_file(archive_path) == SOURCE_ARCHIVE_SHA256,
        "audio-ogg.zip does not match the audited source archive",
    )
    return csv_path, archive_path


def normalize_prompt(value: object) -> str:
    prompt = unicodedata.normalize("NFKC", str(value or "")).strip()
    prompt = re.sub(r"^\*+\s*", "", prompt)
    prompt = re.sub(r"[\s。．.!！?？]+$", "", prompt)
    return prompt.strip()


def katakana_to_hiragana(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value)
    return "".join(
        chr(ord(character) - 0x60)
        if "\u30a1" <= character <= "\u30f6"
        else character
        for character in normalized
    )


def normalize_reading_options(value: object) -> tuple[str, ...]:
    reading = unicodedata.normalize("NFKC", str(value or "")).strip()
    reading = BRACKET_FURIGANA_PATTERN.sub(r"\1", reading)
    options: list[str] = []
    for raw_option in READING_SPLIT_PATTERN.split(reading):
        option = re.sub(r"[\s。．.!！?？]+", "", raw_option).lower()
        if option:
            options.append(option)
    return tuple(options)


def kana_to_hepburn(value: str) -> str:
    """Romanize kana deterministically for exact ASCII card comparisons."""

    reading = katakana_to_hiragana(value)
    result: list[str] = []
    index = 0
    geminate = False

    while index < len(reading):
        character = reading[index]
        if character == "っ":
            geminate = True
            index += 1
            continue

        if character == "ー":
            if result:
                vowels = re.findall(r"[aeiou]", result[-1])
                if vowels:
                    result.append(vowels[-1])
            index += 1
            continue

        pair = reading[index : index + 2]
        if pair in DIGRAPH_ROMAJI:
            syllable = DIGRAPH_ROMAJI[pair]
            index += 2
        else:
            syllable = HIRAGANA_ROMAJI.get(character, character)
            index += 1

        if geminate and syllable:
            if syllable.startswith("ch"):
                syllable = "t" + syllable
            elif syllable[0] not in "aeioun":
                syllable = syllable[0] + syllable
            geminate = False
        result.append(syllable)

    return "".join(result)


def archive_audio_entries(
    archive: zipfile.ZipFile,
) -> tuple[dict[str, zipfile.ZipInfo], dict[str, list[str]]]:
    entries_by_basename: dict[str, zipfile.ZipInfo] = {}
    files_by_kname: dict[str, list[str]] = {}

    for entry in archive.infolist():
        if entry.is_dir() or not entry.filename.lower().endswith(".ogg"):
            continue
        basename = Path(entry.filename).name
        require(
            basename not in entries_by_basename,
            f"Duplicate audio basename in archive: {basename}",
        )
        entries_by_basename[basename] = entry
        match = AUDIO_NAME_PATTERN.fullmatch(basename)
        require(match is not None, f"Unexpected audio filename: {entry.filename}")
        files_by_kname.setdefault(match.group(1), []).append(basename)

    require(
        len(entries_by_basename) == SOURCE_ARCHIVE_FILES,
        f"Archive has {len(entries_by_basename)} OGGs; expected {SOURCE_ARCHIVE_FILES}",
    )
    return entries_by_basename, files_by_kname


def load_catalog(
    csv_path: Path,
    files_by_kname: dict[str, list[str]],
) -> tuple[
    dict[tuple[str, str], CatalogRecord],
    dict[str, list[CatalogRecord]],
    tuple[tuple[str, str, int, int], ...],
    int,
    int,
]:
    by_prompt_reading: dict[tuple[str, str], CatalogRecord] = {}
    by_prompt: dict[str, list[CatalogRecord]] = {}
    mismatched_rows: list[tuple[str, str, int, int]] = []
    catalog_rows = 0
    catalog_examples = 0

    with csv_path.open("r", encoding="utf-8-sig", newline="") as source:
        for row in csv.DictReader(source):
            catalog_rows += 1
            examples = json.loads(row["examples"])
            require(isinstance(examples, list), f"Invalid examples for {row['kanji']}")
            catalog_examples += len(examples)

            audio_files = sorted(
                files_by_kname.get(row["kname"], []),
                key=lambda name: AUDIO_NAME_PATTERN.fullmatch(name).group(2),
            )
            if len(examples) != len(audio_files):
                mismatched_rows.append(
                    (row["kanji"], row["kname"], len(examples), len(audio_files))
                )
                continue

            expected_suffixes = [
                chr(ord("a") + index) for index in range(len(audio_files))
            ]
            actual_suffixes = [
                AUDIO_NAME_PATTERN.fullmatch(name).group(2).lower()
                for name in audio_files
            ]
            require(
                actual_suffixes == expected_suffixes,
                f"Non-sequential audio suffixes for {row['kanji']}: {actual_suffixes}",
            )

            for example, basename in zip(examples, audio_files, strict=True):
                require(
                    isinstance(example, list)
                    and len(example) >= 1
                    and isinstance(example[0], str),
                    f"Invalid example record for {row['kanji']}: {example!r}",
                )
                parsed = EXAMPLE_PATTERN.fullmatch(example[0])
                require(
                    parsed is not None,
                    f"Could not parse Kanji alive example: {example[0]!r}",
                )
                prompt = normalize_prompt(parsed.group(1))
                readings = tuple(
                    katakana_to_hiragana(option)
                    for option in normalize_reading_options(parsed.group(2))
                )
                require(readings, f"Example has no reading: {example[0]!r}")
                record = CatalogRecord(
                    prompt=prompt,
                    readings=readings,
                    source_file=f"audio-ogg/{basename}",
                )
                by_prompt.setdefault(prompt, []).append(record)
                for reading in readings:
                    # The CSV order is authoritative when exact duplicates exist.
                    by_prompt_reading.setdefault((prompt, reading), record)

    return (
        by_prompt_reading,
        by_prompt,
        tuple(mismatched_rows),
        catalog_rows,
        catalog_examples,
    )


def load_cards(repo_root: Path) -> list[dict[str, object]]:
    paths = [
        repo_root / "data" / "learning" / "cards.json",
        *sorted((repo_root / "data" / "learning" / "sources").glob("*.json")),
    ]
    cards: list[dict[str, object]] = []
    seen_ids: set[str] = set()

    for path in paths:
        payload = json.loads(path.read_text(encoding="utf-8"))
        file_cards = payload if isinstance(payload, list) else payload.get("cards")
        require(isinstance(file_cards, list), f"No card array in {path}")
        for card in file_cards:
            require(isinstance(card, dict), f"Invalid card in {path}: {card!r}")
            card_id = card.get("id")
            require(isinstance(card_id, str) and card_id, f"Card has no ID in {path}")
            require(card_id not in seen_ids, f"Duplicate card ID: {card_id}")
            seen_ids.add(card_id)
            cards.append(card)
    return cards


def match_cards(
    cards: Iterable[dict[str, object]],
    catalog: dict[tuple[str, str], CatalogRecord],
    catalog_by_prompt: dict[str, list[CatalogRecord]],
) -> tuple[list[CardMatch], tuple[tuple[str, str, tuple[str, ...], tuple[str, ...]], ...]]:
    matches: list[CardMatch] = []
    reading_mismatches: list[
        tuple[str, str, tuple[str, ...], tuple[str, ...]]
    ] = []

    for card in cards:
        card_id = str(card["id"])
        prompt = normalize_prompt(card.get("prompt"))
        card_readings = normalize_reading_options(card.get("reading"))
        matched_record: CatalogRecord | None = None

        for card_reading in card_readings:
            if ASCII_READING_PATTERN.fullmatch(card_reading):
                normalized_ascii = card_reading.replace("-", "")
                for candidate in catalog_by_prompt.get(prompt, []):
                    if any(
                        kana_to_hepburn(reading) == normalized_ascii
                        for reading in candidate.readings
                    ):
                        matched_record = candidate
                        break
            else:
                matched_record = catalog.get(
                    (prompt, katakana_to_hiragana(card_reading))
                )
            if matched_record is not None:
                break

        if matched_record is not None:
            matches.append(CardMatch(card_id=card_id, record=matched_record))
        elif prompt in catalog_by_prompt:
            available_readings = tuple(
                dict.fromkeys(
                    reading
                    for candidate in catalog_by_prompt[prompt]
                    for reading in candidate.readings
                )
            )
            reading_mismatches.append(
                (card_id, prompt, card_readings, available_readings)
            )

    return matches, tuple(reading_mismatches)


def stable_clip_id(source_file: str) -> str:
    identity = hashlib.sha256(source_file.encode("utf-8")).hexdigest()[:20]
    return f"ka-{identity}"


def build_outputs(
    repo_root: Path,
    csv_path: Path,
    archive_path: Path,
) -> tuple[bytes, dict[str, bytes], dict[str, object]]:
    with zipfile.ZipFile(archive_path, "r") as archive:
        entries_by_basename, files_by_kname = archive_audio_entries(archive)
        (
            catalog,
            catalog_by_prompt,
            mismatched_rows,
            catalog_rows,
            catalog_examples,
        ) = load_catalog(csv_path, files_by_kname)
        require(
            mismatched_rows == EXPECTED_MISMATCHED_ROWS,
            "Catalog/audio row mismatches changed:\n"
            f"actual={mismatched_rows!r}\nexpected={EXPECTED_MISMATCHED_ROWS!r}",
        )

        cards = load_cards(repo_root)
        matches, reading_mismatches = match_cards(
            cards, catalog, catalog_by_prompt
        )
        require(
            reading_mismatches == EXPECTED_READING_MISMATCHES,
            "Surface matches with incompatible readings changed:\n"
            f"actual={reading_mismatches!r}\n"
            f"expected={EXPECTED_READING_MISMATCHES!r}",
        )
        require(
            len(cards) == EXPECTED_CARDS_SCANNED,
            f"Scanned {len(cards)} cards; expected {EXPECTED_CARDS_SCANNED}",
        )
        require(
            len(matches) == EXPECTED_CARDS_MAPPED,
            f"Mapped {len(matches)} cards; expected {EXPECTED_CARDS_MAPPED}",
        )

        record_by_source_file: dict[str, CatalogRecord] = {}
        for match in matches:
            existing = record_by_source_file.setdefault(
                match.record.source_file, match.record
            )
            require(
                existing == match.record,
                f"One source file has conflicting catalog records: "
                f"{match.record.source_file}",
            )
        require(
            len(record_by_source_file) == EXPECTED_UNIQUE_CLIPS,
            f"Used {len(record_by_source_file)} clips; expected {EXPECTED_UNIQUE_CLIPS}",
        )

        clip_bytes: dict[str, bytes] = {}
        clips: dict[str, dict[str, object]] = {}
        clip_id_by_source_file: dict[str, str] = {}
        seen_clip_ids: set[str] = set()
        seen_casefolded_basenames: set[str] = set()

        for source_file, record in sorted(record_by_source_file.items()):
            basename = Path(source_file).name
            casefolded_basename = basename.casefold()
            require(
                casefolded_basename not in seen_casefolded_basenames,
                f"Audio basenames collide on Windows: {basename}",
            )
            seen_casefolded_basenames.add(casefolded_basename)
            entry = entries_by_basename[basename]
            data = archive.read(entry)
            clip_id = stable_clip_id(source_file)
            require(clip_id not in seen_clip_ids, f"Clip ID collision: {clip_id}")
            seen_clip_ids.add(clip_id)
            clip_id_by_source_file[source_file] = clip_id
            clip_bytes[basename] = data
            clips[clip_id] = {
                "path": f"res://assets/audio/japanese/kanji_alive/{basename}",
                "prompt": record.prompt,
                "reading": "/".join(record.readings),
                "sourceFile": source_file,
                "sha256": sha256_bytes(data),
            }

    card_map = {
        match.card_id: clip_id_by_source_file[match.record.source_file]
        for match in sorted(matches, key=lambda item: item.card_id)
    }
    ordered_clips = {clip_id: clips[clip_id] for clip_id in sorted(clips)}
    manifest: dict[str, object] = {
        "version": 1,
        "source": {
            "provider": "Kanji alive",
            "url": PROJECT_URL,
            "repository": REPOSITORY_URL,
            "revision": SOURCE_REVISION,
            "archive": ARCHIVE_URL,
            "archiveSha256": SOURCE_ARCHIVE_SHA256,
            "license": "CC BY 4.0",
            "licenseUrl": LICENSE_URL,
            "attribution": (
                "Audio from Kanji alive (kanjialive.com), licensed CC BY 4.0."
            ),
            "noTranscoding": True,
        },
        "stats": {
            "cardsScanned": len(cards),
            "cardsMapped": len(matches),
            "uniqueClips": len(ordered_clips),
            "cardsWithoutMatch": len(cards) - len(matches),
            "catalogRows": catalog_rows,
            "catalogExamples": catalog_examples,
            "excludedCatalogRows": len(mismatched_rows),
            "surfaceReadingMismatches": len(reading_mismatches),
        },
        "clips": ordered_clips,
        "cards": card_map,
    }
    manifest_bytes = (
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    ).encode("utf-8")
    return manifest_bytes, clip_bytes, manifest


def sync_outputs(
    manifest_path: Path,
    audio_dir: Path,
    manifest_bytes: bytes,
    clip_bytes: dict[str, bytes],
) -> None:
    audio_dir.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    expected_names = set(clip_bytes)
    for stale_path in audio_dir.glob("*.ogg"):
        if stale_path.name not in expected_names:
            stale_path.unlink()

    for basename, data in clip_bytes.items():
        destination = audio_dir / basename
        if not destination.is_file() or destination.read_bytes() != data:
            destination.write_bytes(data)

    if not manifest_path.is_file() or manifest_path.read_bytes() != manifest_bytes:
        manifest_path.write_bytes(manifest_bytes)


def verify_outputs(
    manifest_path: Path,
    audio_dir: Path,
    notice_path: Path,
    manifest_bytes: bytes,
    clip_bytes: dict[str, bytes],
) -> None:
    require(notice_path.is_file(), f"Missing attribution notice: {notice_path}")
    require(manifest_path.is_file(), f"Missing generated manifest: {manifest_path}")
    require(
        manifest_path.read_bytes() == manifest_bytes,
        f"Generated manifest is stale: {manifest_path}",
    )

    actual_names = {
        path.name for path in audio_dir.glob("*.ogg") if path.is_file()
    }
    expected_names = set(clip_bytes)
    require(
        actual_names == expected_names,
        "Generated audio file set is stale:\n"
        f"missing={sorted(expected_names - actual_names)!r}\n"
        f"extra={sorted(actual_names - expected_names)!r}",
    )
    for basename, expected_data in clip_bytes.items():
        actual_path = audio_dir / basename
        require(
            sha256_file(actual_path) == sha256_bytes(expected_data),
            f"Generated audio differs from source: {actual_path}",
        )


def parse_args() -> argparse.Namespace:
    default_repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path(r"D:\SushiValleyGodot-audio-source"),
        help="Pinned kanji-data-media checkout containing language-data and audio-ogg.zip",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=default_repo_root,
        help="Sushi Valley repository root",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify generated files without modifying them",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_root = args.source_root.resolve()
    repo_root = args.repo_root.resolve()
    csv_path, archive_path = verify_sources(source_root)
    manifest_bytes, clip_bytes, manifest = build_outputs(
        repo_root, csv_path, archive_path
    )

    manifest_path = repo_root / "data" / "learning" / "pronunciation-audio.json"
    audio_dir = (
        repo_root / "assets" / "audio" / "japanese" / "kanji_alive"
    )
    notice_path = audio_dir / "NOTICE.md"

    if not args.check:
        sync_outputs(manifest_path, audio_dir, manifest_bytes, clip_bytes)
    verify_outputs(
        manifest_path,
        audio_dir,
        notice_path,
        manifest_bytes,
        clip_bytes,
    )

    stats = manifest["stats"]
    action = "Verified" if args.check else "Imported and verified"
    print(
        f"{action} {stats['cardsMapped']} card mappings to "
        f"{stats['uniqueClips']} unmodified Kanji alive OGG files."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
