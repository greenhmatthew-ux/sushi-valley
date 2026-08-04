extends Area2D
## A villager who hands out a real quest from data/game/quests.json.
##
## Same interactable contract as Npc / TeacherNpc (group "interactable", layer 8,
## interact(player)) — no player.gd changes. The branching lives in the pure QuestLogic; this
## node wires it to the DB (the quest definition), Inv (goal items and rewards), and the
## learning profile's flag store (persisting accept/turn-in), then speaks the AUTHORED lines
## through the shared dialogue box.
##
## Previously this was a hardcoded "clear 3 slimes" quest that never read the DB, so authored
## quests — with their goals, rewards, and offer/progress/turn-in dialogue — were dead data.
## Existing item quests consume their goal at turn-in. An objective-list quest can instead mark
## a permanent item non-consumable when the giver only needs to inspect it.

const Journal = preload("res://src/systems/quest_journal.gd")

## Quest id from data/game/quests.json.
@export var quest_id: String = "stock_the_stall"
## Shown above the sprite. Defaults to the quest's authored `giver` when left empty.
@export var speaker: String = ""
## Optional shop this giver opens after their quest is complete. This keeps a character such
## as Mako from needing a duplicate vendor NPC beside them, while leaving ordinary quest
## givers unchanged. The reward interaction stays focused; trade opens on the next visit.
@export var shop_id: String = ""
## Optional card id this giver opens with, so the valley greets you in Japanese before the
## quest's authored English. A card ID rather than text, matching Npc/SignPost — there is then
## nowhere to type an unsourced phrase.
@export var greeting_card: String = ""
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/npc_villager.png")

var _busy := false


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()


func quest() -> Dictionary:
	return DB.quest(quest_id)


func goal_item() -> String:
	return String(_current_objective().get("item", ""))


func goal_qty() -> int:
	return int(_current_objective().get("goal", 1))


## How many of the goal item the player is carrying, capped at the goal so progress text
## never reads "5 of 3".
func progress() -> int:
	return int(_current_objective().get("progress", 0))


func objectives() -> Array:
	return Journal.objectives(quest(), DB, Inv)


func _current_objective() -> Dictionary:
	return Journal.next_objective(objectives())


func is_accepted() -> bool:
	return _flag("started")


func is_complete() -> bool:
	return _flag("done")


## Current stage, reusing the pure resolver with item count standing in for kills.
func current_stage() -> String:
	return QuestLogic.stage(_flag("started"), _flag("done"),
		1 if Journal.objectives_met(objectives()) else 0, 1)


func interact(player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	if player != null and player.has_method("face"):
		player.face(_facing_from(global_position - player.global_position))
	await _run()
	_busy = false


func _run() -> void:
	var q := quest()
	if q.is_empty():
		Bus.dialogue_open.emit(_name(), ["I have nothing for you right now."])
		await Bus.dialogue_closed
		return

	var stage := current_stage()
	if stage == "done" and not shop_id.is_empty():
		Bus.shop_open.emit(shop_id)
		return
	if stage == "intro":
		_set_flag("started")
		Bus.quest_accepted.emit(quest_id)
	await _say(QuestLogic.lines_for(q, stage))

	# Reward only after the turn-in dialogue, so the lines read as cause then effect.
	if stage == "turnin":
		_complete(q)
	Bus.hud_refresh.emit()


## Take the consumable objective items, pay out, and remember it. Ordinary fetch
## quests still consume their goal. A checklist row can opt out for permanent
## tools/gear a commissioner only needs to inspect.
func _complete(q: Dictionary) -> void:
	for raw_objective in objectives():
		var objective: Dictionary = raw_objective
		if bool(objective.get("consume", true)):
			Inv.remove(String(objective.get("item", "")), int(objective.get("goal", 1)))

	var reward: Dictionary = q.get("reward", {})
	var coins := int(reward.get("coins", 0))
	if coins > 0:
		Inv.add_coins(coins)
	for entry in reward.get("items", []):
		if entry is Dictionary and not String(entry.get("id", "")).is_empty():
			Inv.add(String(entry["id"]), int(entry.get("qty", 1)))

	_set_flag("done")
	var summary := QuestLogic.describe_reward(reward, func(id): return DB.item(id).get("name", id))
	Bus.toast.emit("Quest complete: %s%s" % [
		String(q.get("title", quest_id)),
		("  +" + summary) if not summary.is_empty() else ""])
	Bus.quest_completed.emit(quest_id)


# --- persistence via the learning profile's flag store -----------------------

func _flag(suffix: String) -> bool:
	return Learning.profile != null and Learning.profile.get_flag(_flag_name(suffix))


func _set_flag(suffix: String) -> void:
	if Learning.profile != null:
		Learning.profile.set_flag(_flag_name(suffix))
		Learning.profile.save()


func _flag_name(suffix: String) -> String:
	return "quest_%s_%s" % [quest_id, suffix]


# --- presentation ------------------------------------------------------------

func _name() -> String:
	return speaker if not speaker.is_empty() else String(quest().get("giver", "Villager"))


func _say(lines: Array) -> void:
	if lines.is_empty():
		return
	Bus.npc_talked.emit(quest_id)
	var typed: Array[String] = []
	var opener := _greeting_line()
	if not opener.is_empty():
		typed.append(opener)
	for line in lines:
		typed.append(QuestLogic.fill(String(line), progress(), goal_qty()))
	Bus.dialogue_open.emit(_name(), typed)
	await Bus.dialogue_closed


## "japanese|meaning" from the configured card, or "" when unset/unknown.
func _greeting_line() -> String:
	if greeting_card.is_empty():
		return ""
	var card: Dictionary = Learning.profile.card(greeting_card)
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
	var sprite := Sprite2D.new()
	sprite.texture = sprite_sheet
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 16, 16)   # column 0, row 0 — standing, facing down
	sprite.offset = Vector2(0, -8)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

	var label := Label.new()
	label.text = _name()
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	label.add_theme_color_override("font_outline_color", UiTheme.SURFACE_DEEP)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 12)
	label.position = Vector2(-40, -32)
	add_child(label)
