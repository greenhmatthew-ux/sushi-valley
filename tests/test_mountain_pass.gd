extends SceneTree
## The Mountain Pass: the third region, and the route that connects it.
##
##   godot --headless --path . --script res://tests/test_mountain_pass.gd
##
## `world-regions.json` had listed this route as planned since the TypeScript build,
## and the mid-tier enemy roster it uses was authored but never placed in a scene.
## The point of the area is not just more map: its drops are the only source for the
## mid-tier crafting recipes, which had ingredients no region produced.
##
## A region is only content if you can actually reach it and get back, so the link in
## both directions is asserted here rather than left to be discovered by walking.

var failures: int = 0
var db: Node
var scene: Node


func _initialize() -> void:
	await process_frame
	db = root.get_node("DB")
	scene = load("res://src/scenes/mountain_pass.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_terrain_is_built()
	_the_pass_is_walled_in()
	_route_runs_both_ways()
	_enemies_are_real_and_hostile()
	_quests_and_pickups_resolve()
	_drops_feed_the_crafting_tree()

	scene.queue_free()
	await process_frame
	_finish()


func _terrain_is_built() -> void:
	var ground: TileMapLayer = scene.get_node("Ground")
	var expected: int = scene.W * scene.H
	check_eq("the whole pass is tiled", ground.get_used_cells().size(), expected)
	check_true("a detail layer exists for scree", scene.get_node_or_null("Detail") != null)

	# A region painted from one repeated tile reads as a flat void at this scale.
	var distinct := {}
	for cell in ground.get_used_cells():
		distinct[ground.get_cell_atlas_coords(cell)] = true
	check_true("the ground uses varied stone, not one stamped tile (%d kinds)"
		% distinct.size(), distinct.size() >= 5)

	# The worn route has to actually be laid, or the pass is trackless.
	var trail := 0
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) == scene.TRAIL:
			trail += 1
	check_true("a worn route is laid through the pass (%d tiles)" % trail, trail > 120)


## The pass is a corridor. Its north end is rock the player must not walk into, so the
## cliff band is drawn and the bounds body is placed to cover exactly that band.
func _the_pass_is_walled_in() -> void:
	var ground: TileMapLayer = scene.get_node("Ground")
	var rim_row := 0
	for x in scene.W:
		if ground.get_cell_atlas_coords(Vector2i(x, 0)) == scene.CLIFF_RIM:
			rim_row += 1
	check_eq("a cliff rim runs the full width", rim_row, scene.W)

	var bounds: StaticBody2D = scene.get_node_or_null("Bounds")
	check_true("the pass has a bounds body", bounds != null)
	var top: CollisionShape2D = bounds.get_node_or_null("Top")
	check_true("the north wall exists", top != null)
	var cliff_h: float = float(scene.CLIFF_ROWS + 1) * scene.TILE
	var covered := top.position.y + (top.shape as RectangleShape2D).size.y / 2.0
	check_true("the north wall covers the drawn cliff (%.0f >= %.0f)" % [covered, cliff_h],
		covered >= cliff_h - 0.5)


## Reachability, in both directions. A region you cannot walk into is not content, and
## one you cannot walk out of is a trap.
func _route_runs_both_ways() -> void:
	var exit_door := scene.get_node_or_null("Entities/ExitDoor")
	check_true("the pass has a way out", exit_door != null)
	check_eq("it leads back to the wilds", String(exit_door.target_scene),
		"res://src/scenes/wilds.tscn")

	var wilds: Node = load("res://src/scenes/wilds.tscn").instantiate()
	var pass_door: Node = null
	var north_marker: Node = null
	for child in wilds.get_node("Entities").get_children():
		if child.get("target_scene") != null \
				and String(child.get("target_scene")).ends_with("mountain_pass.tscn"):
			pass_door = child
		if child.get("spawn_id") != null and String(child.get("spawn_id")) == "wilds_north":
			north_marker = child
	check_true("the wilds has a gate north to the pass", pass_door != null)
	check_true("the wilds has somewhere to arrive back at", north_marker != null)

	# The two ends have to agree, or the player lands at the scene's default corner.
	if pass_door != null:
		check_eq("the gate aims at the pass entry marker",
			String(pass_door.target_spawn), "pass_entry")
		var entry := scene.get_node_or_null("Entities/PassEntry")
		check_true("that entry marker exists in the pass", entry != null)
	check_eq("coming back aims at the wilds marker",
		String(exit_door.target_spawn), "wilds_north")
	wilds.queue_free()


func _enemies_are_real_and_hostile() -> void:
	var ids: Array[String] = []
	var passive: Array[String] = []
	for child in scene.get_node("Entities").get_children():
		var id: Variant = child.get("enemy_id")
		if id == null or not child.has_method("take_damage"):
			continue
		ids.append(String(id))
		if int(child.get("behavior")) != 2:   # Behavior.AGGRO
			passive.append(String(child.name))
	check_true("the pass is populated (%d foes)" % ids.size(), ids.size() >= 8)
	check_true("this is a hostile frontier, not a petting zoo (%s)" % str(passive),
		passive.is_empty())

	var unknown: Array[String] = []
	for id in ids:
		if not db.enemies.has(id):
			unknown.append(id)
	check_true("every foe is a real authored enemy (%s)" % str(unknown), unknown.is_empty())
	check_true("the mid-tier roster is what shows up here",
		ids.has("tengu") and ids.has("bear") and ids.has("lizard"))


func _quests_and_pickups_resolve() -> void:
	var quest_ids: Array[String] = []
	var bad_items: Array[String] = []
	for child in scene.get_node("Entities").get_children():
		var quest_id: Variant = child.get("quest_id")
		if quest_id != null and not String(quest_id).is_empty():
			quest_ids.append(String(quest_id))
		var item_id: Variant = child.get("item_id")
		if item_id != null and not String(item_id).is_empty() \
				and not db.items.has(String(item_id)):
			bad_items.append(String(item_id))
	check_true("the pass gives the player something to do (%s)" % str(quest_ids),
		quest_ids.size() >= 2)
	var unknown_quests: Array[String] = []
	for id in quest_ids:
		if not db.quests.has(id):
			unknown_quests.append(id)
	check_true("every quest offered here is authored (%s)" % str(unknown_quests),
		unknown_quests.is_empty())
	check_true("every cache holds a real item (%s)" % str(bad_items), bad_items.is_empty())

	# A quest whose goal item nothing here drops would send the player somewhere else.
	var drops := _pass_drop_ids()
	var unreachable: Array[String] = []
	for id in quest_ids:
		var goal := String(db.quest(id).get("goal", {}).get("item", ""))
		if not goal.is_empty() and not drops.has(goal):
			unreachable.append("%s wants %s" % [id, goal])
	check_true("its quests ask for what its own foes drop (%s)" % str(unreachable),
		unreachable.is_empty())


## The reason this region exists: the mid-tier recipes had ingredients that no
## reachable enemy dropped, so they could be read in the crafting UI and never made.
func _drops_feed_the_crafting_tree() -> void:
	var drops := _pass_drop_ids()
	var unlocked: Array[String] = []
	for recipe_id in db.recipes:
		var recipe: Dictionary = db.recipes[recipe_id]
		for ingredient in recipe.get("inputs", recipe.get("ingredients", [])):
			if drops.has(String(ingredient.get("item", ""))):
				unlocked.append(String(recipe_id))
				break
	print("  ..   recipes fed by pass drops: %s" % str(unlocked))
	check_true("the pass supplies the mid-tier crafting tree (%d recipes)" % unlocked.size(),
		unlocked.size() >= 5)


func _pass_drop_ids() -> Dictionary:
	var drops := {}
	for child in scene.get_node("Entities").get_children():
		var id: Variant = child.get("enemy_id")
		if id == null or not child.has_method("take_damage"):
			continue
		for drop in db.enemy(String(id)).get("drops", []):
			drops[String(drop.get("item", ""))] = true
	return drops


func _finish() -> void:
	print("")
	print(("PASS — the Mountain Pass is reachable, hostile, and worth the climb."
		if failures == 0 else "FAIL — %d mountain-pass check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
