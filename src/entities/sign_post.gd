extends Area2D
## A signpost you can read. Japanese standing in the world, voiced aloud, English on demand.
##
## Same interactable contract as Npc / TeacherNpc / LessonGate: an Area2D in group
## "interactable" on layer 8 exposing interact(player).
##
## SOURCING — the reason this takes a card id and NOT a Japanese string:
## LEARNING_PROGRESSION.md forbids inventing an uncited parallel deck or hardcoding lesson
## text in scenes, and SITE_WIDE_LEARNING_ARCHITECTURE.md requires curated content only, no
## auto-generated Japanese. An earlier version of this file had a free-text `japanese`
## export, and unsourced Japanese promptly ended up authored into world.tscn. There is now
## no field to type Japanese into: a sign displays the prompt/reading/meaning of a real card
## from data/learning/cards.json, which carries its deck attribution. Framing text is
## English only.
##
## Reading is low-pressure by design — no quiz, no fail state. The first read UNLOCKS the
## card into the shared SRS, so the world introduces vocabulary and the schedule takes over.
## Re-reading never re-grades; that would let a player farm a sign and corrupt their spacing.

## Authored per-instance.
@export var sign_id: String = "sign"
## Card id from data/learning/cards.json. The sign shows THIS card's Japanese — the only
## Japanese it can ever show.
@export var shows_card: String = ""
## English-only framing, e.g. "A weathered board beside the road." Never Japanese.
@export var caption: String = ""
## Draw the wooden post. Off for signs mounted on an existing prop.
@export var draw_post: bool = true

const POST_REGION := Rect2(112, 208, 16, 32)   # signpost in serene_village.png

var _busy := false


func _ready() -> void:
	add_to_group("interactable")
	if draw_post:
		_build_visual()


func interact(player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	if player != null and player.has_method("face"):
		player.face("up")   # signs are read from below
	await _read()
	_busy = false


func _read() -> void:
	var card: Dictionary = Learning.profile.card(shows_card)
	if card.is_empty():
		push_warning("[Sign %s] unknown card '%s'" % [sign_id, shows_card])
		return

	var japanese := String(card.get("prompt", ""))
	var meaning := String(card.get("meaning", ""))
	if meaning.is_empty():
		meaning = String(card.get("answer", ""))
	# reading is the kana gloss for kanji cards; skip it when it just repeats the prompt
	var reading := String(card.get("reading", ""))
	var english := meaning if reading.is_empty() or reading == japanese \
		else "%s — %s" % [reading, meaning]

	var lines: Array[String] = []
	if not caption.is_empty():
		lines.append(caption)          # English framing, no translation half
	lines.append("%s|%s" % [japanese, english])

	var newly_learned := _unlock_card(card)
	Bus.dialogue_open.emit("", lines)   # no speaker — a sign isn't talking to you
	await Bus.dialogue_closed

	if newly_learned:
		Bus.toast.emit("Learned from a sign: %s" % japanese)
		Bus.hud_refresh.emit()


## Unlock on the first read only. Returns whether this read was the one that did it.
func _unlock_card(card: Dictionary) -> bool:
	if card.get("unlocked", false):
		return false
	card["unlocked"] = true
	Learning.profile.save()
	return true


## Wooden post, drawn feet-on-origin so Y-sort treats it like every other prop.
func _build_visual() -> void:
	var post := Sprite2D.new()
	post.texture = preload("res://assets/tilesets/serene_village.png")
	post.region_enabled = true
	post.region_rect = POST_REGION
	post.offset = Vector2(0, -16)
	post.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(post)
