class_name LearningProfile
extends RefCounted
## The persistent, cross-surface player learning state. Port of
## src/shared/learning/LearningProfile.ts.
##
## Holds one big `data` Dictionary — cards, flags, stats, and the classless build.
## Static card and lesson definitions come from a content provider (the DB
## autoload in-game, an injected DB in tests); saved data carries only the
## per-card scheduling STATE and re-hydrates around those definitions on load, so
## saves stay small and content edits flow through without a migration.
##
## `data` intentionally stays an untyped Dictionary. Later slices (inventory,
## equipment, quests, farm, ...) add their own keys and default them in their own
## constructors' guards; anything present in `data` is persisted by save(), so a
## new field needs no schema migration.

const PROFILE_VERSION := 1
const AbilityRules = preload("res://src/systems/ability_logic.gd")

## Card scheduling fields — the only per-card data that is persisted. Static def
## fields (prompt, answer, choices, tags, ...) are re-hydrated from content.
const SCHEDULING_FIELDS := [
	"unlocked", "dueAt", "intervalDays", "ease",
	"correctCount", "incorrectCount", "lastReviewedAt",
]

const DEFAULT_SKILLS := ["strike", "guard", "focus"]

var data: Dictionary
## Optional persistence sink, set by the Learning autoload to SaveGame.save_profile.
## Left unset in tests, where save() is a no-op — the pure model does no file IO.
var saver: Callable = Callable()

## Content provider: exposes `cards`, `card_order`, `lessons`, `lesson_order`, and
## `lesson(id)`. The DB autoload satisfies this; tests inject a hand-built DB so
## the model has no hidden autoload coupling.
var _content


func _init(saved: Dictionary = {}, content = null) -> void:
	_content = content
	data = saved if not saved.is_empty() else _empty_profile()
	_hydrate_cards()
	_ensure_build()
	# Learning-core defaults only. Inventory/equipment/quests/etc. are defaulted in
	# the slices that introduce them; save() persists whatever keys exist.
	if not data.has("flags"): data["flags"] = {}
	if not data.has("stats"):
		data["stats"] = {"totalReviews": 0, "totalCorrect": 0, "xp": 0, "lastActiveAt": _now_ms()}


func _empty_profile() -> Dictionary:
	return {
		"version": PROFILE_VERSION,
		"cards": {},
		"flags": {},
		"stats": {"totalReviews": 0, "totalCorrect": 0, "xp": 0, "lastActiveAt": _now_ms()},
	}


## Default the classless build for older/fresh saves (migration-safe, additive).
## Mirrors ensureBuild(), including the legacy `deck` -> `skills` rename: regular
## combat is menu-based; the deckbuilder is a separate Expeditions system.
func _ensure_build() -> void:
	if not data.has("build") or typeof(data["build"]) != TYPE_DICTIONARY:
		data["build"] = {
			"allocations": {"vitality": 0, "power": 0, "agility": 0},
			"skills": DEFAULT_SKILLS.duplicate(),
			"unlockedAbilities": [],
		}
		_sanitize_abilities(data["build"])
		return
	var b: Dictionary = data["build"]
	if not b.has("skills"):
		var legacy: Array = b.get("deck", DEFAULT_SKILLS)
		# de-dup while preserving order
		var seen := {}
		var skills: Array = []
		for s in legacy:
			if not seen.has(s):
				seen[s] = true
				skills.append(s)
		b["skills"] = skills
	b.erase("deck")
	if not b.has("allocations"):
		b["allocations"] = {"vitality": 0, "power": 0, "agility": 0}
	if not b.has("unlockedAbilities"):
		b["unlockedAbilities"] = []
	_sanitize_abilities(b)


func _sanitize_abilities(b: Dictionary) -> void:
	if _content != null and "abilities" in _content:
		AbilityRules.sanitize_build(b, _content.abilities)


func build() -> Dictionary:
	_ensure_build()
	return data["build"]


## Ensure every static card has a live scheduling entry, preserving saved state.
## The stored def is the full card (static fields + scheduling) so callers see one
## object, exactly like the TS SrsCard.
func _hydrate_cards() -> void:
	if _content == null:
		return
	var saved_cards: Dictionary = data.get("cards", {})
	var live := {}
	for id in _content.card_order:
		var def: Dictionary = _content.cards[id]
		var card: Dictionary = def.duplicate(true)
		var prev: Dictionary = saved_cards.get(id, {})
		if prev.is_empty():
			card.merge(Srs.new_card_defaults(), true)
			card["unlocked"] = false
		else:
			card["unlocked"] = prev.get("unlocked", false)
			card["dueAt"] = prev.get("dueAt", 0.0)
			card["intervalDays"] = prev.get("intervalDays", 0.0)
			card["ease"] = prev.get("ease", Srs.DEFAULT_EASE)
			card["correctCount"] = prev.get("correctCount", 0)
			card["incorrectCount"] = prev.get("incorrectCount", 0)
			card["lastReviewedAt"] = prev.get("lastReviewedAt", null)
		live[id] = card
	data["cards"] = live


# --- card access -----------------------------------------------------------

func all_cards() -> Array:
	return data["cards"].values()


## The live card dict, mutated in place by the SRS. {} means "no such card".
func card(id: String) -> Dictionary:
	return data["cards"].get(id, {})


func unlocked_cards() -> Array:
	return all_cards().filter(func(c): return c.get("unlocked", false))


func unlock_lesson(lesson_id: String) -> void:
	if _content == null:
		return
	var lesson: Dictionary = _content.lesson(lesson_id)
	for id in lesson.get("cardIds", []):
		if data["cards"].has(id):
			data["cards"][id]["unlocked"] = true


func unlock_card(card_id: String) -> void:
	if data["cards"].has(card_id):
		data["cards"][card_id]["unlocked"] = true


# --- flags -----------------------------------------------------------------

func get_flag(flag: String) -> bool:
	return data["flags"].get(flag, false)


func set_flag(flag: String, value: bool = true) -> void:
	data["flags"][flag] = value


# --- reading-material tracking ---------------------------------------------

func has_read_content(content_id: String) -> bool:
	return content_id in data.get("readContent", [])


func mark_content_read(content_id: String) -> bool:
	if not data.has("readContent"):
		data["readContent"] = []
	if content_id in data["readContent"]:
		return false
	data["readContent"].append(content_id)
	return true


# --- persistence -----------------------------------------------------------

## Serialize for saving: cards keep only their scheduling fields, matching
## serializeLearningProfileData(). The static def is rebuilt from content on load.
func to_save_dict() -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var slim := {}
	for id in data["cards"]:
		var c: Dictionary = data["cards"][id]
		var s := {}
		for field in SCHEDULING_FIELDS:
			s[field] = c.get(field)
		slim[id] = s
	out["cards"] = slim
	return out


func save() -> void:
	data["stats"]["lastActiveAt"] = _now_ms()
	if saver.is_valid():
		saver.call(to_save_dict())


static func _now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0
