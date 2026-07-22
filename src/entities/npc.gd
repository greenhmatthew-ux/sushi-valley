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
## without ever walling the player in. Placeholder art — a small coloured body plus a name
## label, built in code so the .tscn stays tiny and no character atlas region is guessed.
## Swap the body for an AnimatedSprite2D once villager art is licensed.

@export var npc_id: String = "villager"
@export var speaker: String = "Villager"
## The dialogue, one entry per advanceable line. PackedStringArray keeps the .tscn override
## clean (`lines = PackedStringArray("a", "b")`) and is converted to Array[String] on emit.
@export var lines: PackedStringArray = PackedStringArray(["Hello."])

const BODY_COLOR := Color(0.42, 0.55, 0.78)

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
	for line in lines:
		typed.append(String(line))
	Bus.dialogue_open.emit(speaker, typed)
	await Bus.dialogue_closed
	_talking = false


func _facing_from(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


func _build_visual() -> void:
	var body := ColorRect.new()
	body.color = BODY_COLOR
	# A ~10x14 body standing on the feet (origin = bottom-center, like the player).
	body.offset_left = -5.0
	body.offset_top = -15.0
	body.offset_right = 5.0
	body.offset_bottom = -1.0
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
