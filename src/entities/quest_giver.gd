extends Area2D
## A villager who hands out a simple "clear N slimes" quest. Same interactable contract
## as Npc/LessonGate (group "interactable", layer 8, interact(player)) — no player.gd
## changes. The branching lives in the pure QuestLogic; this node only wires it to the
## Bus (counting kills), to Learning flags (persisting accept/turn-in), and to Inv (the
## coin reward), then speaks the matching line through the shared dialogue box.

@export var quest_id: String = "clear_slimes"
@export var speaker: String = "Kenji"
@export var target_kills: int = 3
@export var reward_coins: int = 25
## The enemy_id whose deaths count toward the goal.
@export var target_enemy: String = "slime"
## Character sheet for the standing sprite (down-facing frame 0).
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/npc_villager.png")

var _kills: int = 0


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()
	Bus.enemy_died.connect(_on_enemy_died)


func _on_enemy_died(enemy_id: String) -> void:
	# Only count once the quest is accepted and before it is turned in.
	if enemy_id == target_enemy and _flag("started") and not _flag("done"):
		_kills += 1


func interact(_player: Node = null) -> void:
	match QuestLogic.stage(_flag("started"), _flag("done"), _kills, target_kills):
		"intro":
			_set_flag("started")
			_say(["The slimes have overrun the west field!",
				"Thin out %d of them and I'll make it worth your while." % target_kills])
		"active":
			_say(["%d slimes still bouncing about. Keep at it!" % QuestLogic.remaining(_kills, target_kills)])
		"turnin":
			_set_flag("done")
			Inv.add_coins(reward_coins)
			_say(["The field's clear — the whole village thanks you!",
				"Here, %d coins for your trouble." % reward_coins])
		"done":
			_say(["Thanks again, friend. Safe travels."])


# --- persistence via the learning profile's flag store -----------------------

func _flag(suffix: String) -> bool:
	return Learning.profile != null and Learning.profile.get_flag(_flag_name(suffix))


func _set_flag(suffix: String) -> void:
	if Learning.profile != null:
		Learning.profile.set_flag(_flag_name(suffix))
		Learning.profile.save()


func _flag_name(suffix: String) -> String:
	return "quest_%s_%s" % [quest_id, suffix]


func _say(lines: Array) -> void:
	Bus.npc_talked.emit(quest_id)
	var typed: Array[String] = []
	for line in lines:
		typed.append(String(line))
	Bus.dialogue_open.emit(speaker, typed)


func _build_visual() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = sprite_sheet
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 16, 16)   # column 0, row 0 — standing, facing down
	sprite.offset = Vector2(0, -8)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

	var label := Label.new()
	label.text = speaker
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 12)
	label.position = Vector2(-40, -32)
	add_child(label)
