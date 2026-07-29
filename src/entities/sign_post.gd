extends Area2D
## A signpost you can actually read. Japanese text standing in the world, voiced aloud, with
## the English available on demand like every other line in the valley.
##
## Same interactable contract as Npc / TeacherNpc / LessonGate: an Area2D in group
## "interactable" on layer 8 exposing interact(player). Non-blocking — the visual post is a
## separate prop, so the sign itself never walls the player in.
##
## LEARNING_PROGRESSION.md lists "unlocked sign reading" as a reward and maps Routes/Gates to
## "directions, places, signs". Reading a sign is low-pressure by design: no quiz, no fail
## state. When `teaches_card` names a card, the first read UNLOCKS it into the shared SRS —
## so the world itself is what introduces vocabulary, and the schedule picks it up from
## there. Re-reading never re-grades; that would let a player farm a sign for easy XP and
## corrupt the spacing.

## Authored per-instance.
@export var sign_id: String = "sign"
## What the sign says, in Japanese. Shown and spoken.
@export var japanese: String = ""
## Plain-English translation, revealed with TAB or the settings toggle.
@export var english: String = ""
## Optional card id (data/learning/cards.json) this sign introduces. First read unlocks it.
@export var teaches_card: String = ""
## Draw the wooden post. Off for signs mounted on an existing prop (the village board),
## on for standalone ones — an invisible interactable gives the player nothing to walk up to.
@export var draw_post: bool = true

const POST_REGION := Rect2(112, 208, 16, 32)   # signpost in serene_village.png

var _busy := false


func _ready() -> void:
	add_to_group("interactable")
	if draw_post:
		_build_visual()


## Wooden post, drawn feet-on-origin so Y-sort treats it like every other prop.
func _build_visual() -> void:
	var post := Sprite2D.new()
	post.texture = preload("res://assets/tilesets/serene_village.png")
	post.region_enabled = true
	post.region_rect = POST_REGION
	post.offset = Vector2(0, -16)
	post.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(post)


func interact(player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	if player != null and player.has_method("face"):
		player.face("up")   # signs are read from below
	await _read()
	_busy = false


func _read() -> void:
	if japanese.is_empty():
		return

	var lines: Array[String] = ["%s|%s" % [japanese, english]]
	var newly_learned := _unlock_card()
	if not newly_learned.is_empty():
		lines.append("%s|New word: %s" % [newly_learned, _meaning_of(teaches_card)])

	Bus.dialogue_open.emit("", lines)   # no speaker name — a sign isn't talking to you
	await Bus.dialogue_closed

	if not newly_learned.is_empty():
		Bus.toast.emit("Learned from a sign: %s" % newly_learned)
		Bus.hud_refresh.emit()


## Unlock this sign's card the first time it's read. Returns the card's prompt when it was
## genuinely new, "" otherwise (already known, not configured, or unknown id).
func _unlock_card() -> String:
	if teaches_card.is_empty():
		return ""
	var card: Dictionary = Learning.profile.card(teaches_card)
	if card.is_empty() or card.get("unlocked", false):
		return ""
	card["unlocked"] = true
	Learning.profile.save()
	return String(card.get("prompt", ""))


func _meaning_of(card_id: String) -> String:
	var card: Dictionary = Learning.profile.card(card_id)
	var meaning := String(card.get("meaning", ""))
	return meaning if not meaning.is_empty() else String(card.get("answer", ""))
