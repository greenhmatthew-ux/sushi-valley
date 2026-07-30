extends Area2D
## A villager you can talk to. Same interactable contract as LessonGate / ItemPickup:
## an Area2D in the "interactable" group, on collision layer 8, exposing interact(player).
## The player's InteractProbe finds the nearest one and calls it — so an NPC needs zero
## changes to player.gd.
##
## On interact it opens the shared dialogue box (Bus.dialogue_open, which DialogueBox
## already listens for) and announces Bus.npc_talked so quests / HUD can react later
## without holding a reference to this node.
##
## Non-blocking on purpose: there is no StaticBody, so villagers add life to the village
## without ever walling the player in. Art is a standing character frame (column 0, row 0
## of a project npc sheet) plus a name label, built in code so the .tscn stays tiny.

@export var npc_id: String = "villager"
@export var speaker: String = "Villager"
## The dialogue, one entry per advanceable line. PackedStringArray keeps the .tscn override
## clean (`lines = PackedStringArray("a", "b")`) and is converted to Array[String] on emit.
@export var lines: PackedStringArray = PackedStringArray(["Hello."])
## Optional card id (data/learning/cards.json) this villager opens with, so the valley greets
## you in Japanese before switching to English. Takes an ID rather than text for the same
## reason signs and teachers do: there is then nowhere to type an unsourced phrase, and the
## meaning shown on TAB comes from the card itself. Leave empty for a silent opener.
@export var greeting_card: String = ""
## Character sheet for the standing sprite. Swap per-instance so each villager differs.
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/npc_villager2.png")

var _talking := false


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()


## Called by the player's interaction probe when they press interact nearby.
func interact(player: Node = null) -> void:
	if _talking or lines.is_empty():
		return
	_talking = true
	# Turn the player toward the villager, the way dialogue framed conversations in the
	# TS build. Cosmetic; villagers have no facing of their own yet.
	if player != null and player.has_method("face"):
		player.face(_facing_from(global_position - player.global_position))
	Bus.npc_talked.emit(npc_id)
	# The Bus signal is typed Array[String]; convert so a PackedStringArray export still fits.
	var typed: Array[String] = []
	var opener := _greeting_line()
	if not opener.is_empty():
		typed.append(opener)
	for line in lines:
		typed.append(String(line))
	Bus.dialogue_open.emit(speaker, typed)
	await Bus.dialogue_closed
	_talking = false


## "japanese|meaning" from the configured card, or "" when none is set or the id is unknown.
func _greeting_line() -> String:
	if greeting_card.is_empty():
		return ""
	var card: Dictionary = Learning.profile.card(greeting_card)
	if card.is_empty():
		return ""
	var ja := String(card.get("prompt", ""))
	if ja.is_empty():
		return ""
	var meaning := String(card.get("meaning", ""))
	if meaning.is_empty():
		meaning = String(card.get("answer", ""))
	return "%s|%s" % [ja, meaning]


func _facing_from(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


func _build_visual() -> void:
	var body := Sprite2D.new()
	body.texture = sprite_sheet
	body.region_enabled = true
	body.region_rect = Rect2(0, 0, 16, 16)   # column 0, row 0 — standing, facing down
	body.offset = Vector2(0, -8)              # feet on the node origin
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)

	var label := Label.new()
	label.text = speaker
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 12)
	label.position = Vector2(-40, -30)
	add_child(label)
