extends Node
## Static content tables, loaded once at boot.
##
## Port of the scattered `import x from '../data/x.json'` statements in the TS
## build. The JSON files are byte-identical to the ones the Phaser build shipped,
## so balance and content are preserved exactly — only the access path changed.
##
## Array tables are indexed by their "id" field but ALSO kept in authored order,
## because order is meaningful in places (the Compendium shows enemies in table
## order, as `allEnemies()` did in CombatSystem.ts).

const GAME_DIR := "res://data/game/"
const LEARNING_DIR := "res://data/learning/"

# --- game content: id -> Dictionary ---
var items: Dictionary = {}
var enemies: Dictionary = {}
var abilities: Dictionary = {}
var recipes: Dictionary = {}
var quests: Dictionary = {}
var crops: Dictionary = {}
var expeditions: Dictionary = {}
var raids: Dictionary = {}
var regions: Dictionary = {}

# --- authored order, for anything that displays a full roster ---
var enemy_order: Array[String] = []
var item_order: Array[String] = []
var ability_order: Array[String] = []

# --- keyed-object tables, kept as-is ---
var shops: Dictionary = {}
var world_events: Dictionary = {}

# --- learning content ---
var cards: Dictionary = {}          # card id -> definition (no scheduling state)
var card_order: Array[String] = []
var lessons: Dictionary = {}        # lesson id -> definition
var lesson_order: Array[String] = []
var learning_content: Dictionary = {}   # reading-material entries

## Anki decks imported into the card pool. Each pack carries a `source` block that
## is stamped onto every card for attribution — the TS `extractSourceCards()` rule.
const SOURCE_PACKS := [
	"essential-japanese-for-travelers",
	"japanese-basic-hiragana",
	"japanese-kana-hiragana-katakana-rmaji-audio-strokes",
	"japanese-kana-hiraganakatakanamnemonics2x-audiostroke",
	"kaishi-15k-basic-japanese-vocabulary",
	"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01",
	"japanese-core-2k-vocab-natural-audio-mnemonics-and-type",
	"japanese-common-words-and-phrases-with-audio-kanji-romaji",
	"japanese-travel-vocabulary",
	"travel-japanese-w-audio-nihongo-fun-easy-2nd-edition",
	"japanese-course-based-on-tae-kims-grammar-guide-anime",
]


var _loaded := false


func _ready() -> void:
	load_all()


## Populate every table. Public and idempotent so headless tests can load the
## content without a SceneTree — `add_child()` defers `_ready()`, which silently
## gave tests an empty DB when they relied on it.
func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	_load_game_content()
	_load_learning_content()
	print("[DB] %d items, %d enemies, %d abilities, %d recipes, %d quests | %d cards, %d lessons"
		% [items.size(), enemies.size(), abilities.size(), recipes.size(), quests.size(),
			cards.size(), lessons.size()])


func _load_game_content() -> void:
	var r := _index(_read_array(GAME_DIR + "items.json"))
	items = r[0]; item_order = r[1]
	r = _index(_read_array(GAME_DIR + "enemies.json"))
	enemies = r[0]; enemy_order = r[1]
	r = _index(_read_array(GAME_DIR + "abilities.json"))
	abilities = r[0]; ability_order = r[1]

	recipes = _index(_read_array(GAME_DIR + "recipes.json"))[0]
	quests = _index(_read_array(GAME_DIR + "quests.json"))[0]
	crops = _index(_read_array(GAME_DIR + "crops.json"))[0]
	expeditions = _index(_read_array(GAME_DIR + "expeditions.json"))[0]
	raids = _index(_read_array(GAME_DIR + "raids.json"))[0]
	regions = _index(_read_array(GAME_DIR + "world-regions.json"))[0]

	shops = _read_dict(GAME_DIR + "shops.json")
	world_events = _read_dict(GAME_DIR + "worldEvents.json")


func _load_learning_content() -> void:
	var r := _index(_read_array(LEARNING_DIR + "cards.json"))
	cards = r[0]; card_order = r[1]

	for pack_id in SOURCE_PACKS:
		_merge_source_pack(pack_id)

	r = _index(_read_array(LEARNING_DIR + "lessons.json"))
	lessons = r[0]; lesson_order = r[1]
	learning_content = _index(_read_array(LEARNING_DIR + "learning-content.json"))[0]


## Flatten one Anki source pack into the card pool, stamping deck attribution onto
## each card. `sourceNoteId` becomes `source.noteId`, matching the TS shape so the
## same cards.json / lessons.json card ids keep resolving.
func _merge_source_pack(pack_id: String) -> void:
	var pack := _read_dict(LEARNING_DIR + "sources/" + pack_id + ".json")
	if pack.is_empty():
		push_warning("[DB] missing source pack: %s" % pack_id)
		return
	var source: Dictionary = pack.get("source", {
		"provider": "AnkiWeb", "deckId": pack_id, "deckName": pack_id,
		"url": "", "mediaPolicy": "excluded",
	})
	for card in pack.get("cards", []):
		var id := String(card.get("id", ""))
		if id.is_empty():
			continue
		var entry: Dictionary = card.duplicate()
		var attribution: Dictionary = source.duplicate()
		attribution["noteId"] = entry.get("sourceNoteId", "")
		entry.erase("sourceNoteId")
		entry["source"] = attribution
		if not cards.has(id):
			card_order.append(id)
		cards[id] = entry


# --- lookups ---------------------------------------------------------------
# Return {} rather than null for a miss so callers can chain .get() safely; a
# missing id is a content bug, so it warns loudly instead of failing silently.

func item(id: String) -> Dictionary:
	return _lookup(items, id, "item")

func enemy(id: String) -> Dictionary:
	return _lookup(enemies, id, "enemy")

func ability(id: String) -> Dictionary:
	return _lookup(abilities, id, "ability")

func recipe(id: String) -> Dictionary:
	return _lookup(recipes, id, "recipe")

func quest(id: String) -> Dictionary:
	return _lookup(quests, id, "quest")

func card(id: String) -> Dictionary:
	return _lookup(cards, id, "card")

func lesson(id: String) -> Dictionary:
	return _lookup(lessons, id, "lesson")


func _lookup(table: Dictionary, id: String, kind: String) -> Dictionary:
	if table.has(id):
		return table[id]
	push_warning("[DB] unknown %s id: %s" % [kind, id])
	return {}


# --- json plumbing ---------------------------------------------------------

func _read(path: String) -> Variant:
	# load() goes through the resource system, which is what survives export.
	var res := load(path)
	if res is JSON:
		return (res as JSON).data
	# Fallback for files the importer skipped (e.g. added while the editor is open).
	if not FileAccess.file_exists(path):
		push_error("[DB] missing data file: %s" % path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _read_array(path: String) -> Array:
	var data: Variant = _read(path)
	if data is Array:
		return data
	push_error("[DB] expected an array in %s" % path)
	return []


func _read_dict(path: String) -> Dictionary:
	var data: Variant = _read(path)
	if data is Dictionary:
		return data
	push_error("[DB] expected an object in %s" % path)
	return {}


## Index an array of {"id": ...} records. Returns [by_id, ordered_ids].
func _index(rows: Array) -> Array:
	var by_id := {}
	var order: Array[String] = []
	for row in rows:
		if row is not Dictionary:
			continue
		var id := String(row.get("id", ""))
		if id.is_empty():
			continue
		if by_id.has(id):
			push_warning("[DB] duplicate id: %s" % id)
			continue
		by_id[id] = row
		order.append(id)
	return [by_id, order]
