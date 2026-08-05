extends SceneTree
## The Expedition room shows exactly the stage the save is on.
##
##   godot --headless --path . --script res://tests/test_expedition_room.gd
##
## test_expedition.gd pins the state machine; this pins the room built on top
## of it. The room is a spine walked west to east, and the thing that makes it
## feel handcrafted rather than respawning is that a beaten guard stays down and
## a sleeping boss cannot be reached. These checks load the real scene at each
## stage and assert what is standing.

const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")
const RaidLogic = preload("res://src/systems/raid_logic.gd")

var failures: int = 0


func _initialize() -> void:
	await process_frame
	await _room_stages()
	await _gate_lock()
	_finish()


## Put the shared profile at a stage, then load the room and see what exists.
func _stage_room(stage: String) -> Node:
	var learning: Node = root.get_node("Learning")
	if stage.is_empty():
		learning.profile.data["expeditions"] = {}
	else:
		learning.profile.data["expeditions"] = {
			"forest_lunchbox": {"stage": stage, "startedAt": 1.0, "completions": 0}}
	var room: Node = load("res://src/scenes/expedition_forest.tscn").instantiate()
	root.add_child(room)
	await process_frame
	return room


func _room_stages() -> void:
	var room := await _stage_room("active")
	var guard: Node2D = room.get_node_or_null("Entities/TrailGuard")
	var boss: Node2D = room.get_node_or_null("Entities/ForestWraith")
	var lunchbox: Node = room.get_node_or_null("Entities/Lunchbox")
	check_true("the room has a trail guard", guard != null)
	check_true("the room has a boss", boss != null)
	check_true("the room has the lunchbox objective", lunchbox != null)
	check_true("the room places the player at the entry",
		room.get_node_or_null("Entities/Player") != null)
	check_true("a retreat door leads back out",
		room.get_node_or_null("Entities/RetreatDoor") != null)
	if guard == null or boss == null:
		room.queue_free()
		return

	check_true("at the first stage the guard blocks the trail", guard.visible)
	check_true("and the wraith is still asleep", not boss.visible)
	check_true("a sleeping wraith cannot be touched", boss.collision_layer == 0)
	_check_trail_is_walkable(room)
	room.queue_free()
	await process_frame

	room = await _stage_room("encounter-cleared")
	guard = room.get_node_or_null("Entities/TrailGuard")
	boss = room.get_node_or_null("Entities/ForestWraith")
	check_true("a beaten guard does not stand back up", not guard.visible)
	check_true("the wraith still sleeps before the recall", not boss.visible)
	room.queue_free()
	await process_frame

	room = await _stage_room("recall-cleared")
	guard = room.get_node_or_null("Entities/TrailGuard")
	boss = room.get_node_or_null("Entities/ForestWraith")
	check_true("the cleared recall wakes the wraith", boss.visible)
	check_eq("and it returns on the dedicated enemy layer", boss.collision_layer, 4)
	check_true("the guard stays down", not guard.visible)
	room.queue_free()
	await process_frame

	room = await _stage_room("complete")
	guard = room.get_node_or_null("Entities/TrailGuard")
	boss = room.get_node_or_null("Entities/ForestWraith")
	check_true("a finished run stands empty — no guard", not guard.visible)
	check_true("a finished run stands empty — no wraith", not boss.visible)
	room.queue_free()
	await process_frame


## The forest is generated, so nothing stops it growing across the route the
## player has to walk. A room whose trail is blocked still passes every stage
## check above while being unfinishable, so the geometry gets its own check:
## no generated tree may stand on a trail tile, and every stage placement must
## sit on one.
func _check_trail_is_walkable(room: Node) -> void:
	var route: Dictionary = room.get("_route_cells")
	var tile: int = room.get("TILE")
	var forest: Node = room.get_node_or_null("Entities/Forest")
	check_true("the forest actually generated",
		forest != null and forest.get_child_count() > 100)
	if forest == null or route == null:
		return

	var on_trail := 0
	for tree in forest.get_children():
		var cell := Vector2i(
			int(floor((tree as Node2D).position.x / tile)),
			int(floor(((tree as Node2D).position.y - 1) / tile)))
		if route.has(cell):
			on_trail += 1
	check_eq("no tree grew across the trail", on_trail, 0)

	for named in [["entry", "ExpeditionEntry"], ["guard", "TrailGuard"],
			["lunchbox", "Lunchbox"], ["wraith", "ForestWraith"]]:
		var node := room.get_node_or_null("Entities/" + String(named[1])) as Node2D
		if node == null:
			continue
		var cell := Vector2i(int(floor(node.position.x / tile)),
			int(floor(node.position.y / tile)))
		check_true("the %s stands on the walked trail" % String(named[0]),
			route.has(cell))


## The woods-side gate must refuse an unearned entry, and say why.
func _gate_lock() -> void:
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var learning: Node = root.get_node("Learning")
	learning.profile.data["expeditions"] = {}
	learning.profile.data["raids"] = {}
	learning.profile.data["flags"] = {}

	var exp: Dictionary = db.expedition("forest_lunchbox")
	check_true("with no raid done the gate is shut",
		not ExpeditionLogic.can_enter(learning.profile, exp))

	var spoken: Array = []
	bus.dialogue_open.connect(func(_who, lines): spoken.append(lines))
	var gate := Area2D.new()
	gate.set_script(load("res://src/entities/expedition_gate.gd"))
	gate.set("expedition_id", "forest_lunchbox")
	gate.set("room_scene", "res://src/scenes/expedition_forest.tscn")
	gate.set("locked_lines", PackedStringArray([
		"This forest route is sealed.",
		"Complete Hana's Sushi Prep Raid to unlock the Expedition."]))
	root.add_child(gate)
	await process_frame

	gate.interact(null)
	await process_frame
	check_eq("a locked gate opens dialogue rather than travelling", spoken.size(), 1)
	if spoken.size() == 1:
		check_true("and names the real prerequisite",
			String(spoken[0][1]).contains("Sushi Prep Raid"))
	bus.dialogue_closed.emit()
	await process_frame

	gate.queue_free()
	await process_frame


func _finish() -> void:
	print("")
	print(("PASS — the Expedition room matches its saved stage and the gate stays honest."
		if failures == 0 else "FAIL — %d expedition room check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
