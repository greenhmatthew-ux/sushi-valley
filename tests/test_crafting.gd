extends SceneTree
## Crafting is station-scoped, independently levelled, discovery-aware, and atomic.

const Rules = preload("res://src/systems/crafting_logic.gd")
const Bag = preload("res://src/systems/inventory_logic.gd")

var failures := 0
var rice_recipe := {"id": "craft_rice_ball", "station": "kitchen", "levelReq": 1,
	"inputs": [{"item": "rice", "qty": 2}],
	"output": {"item": "rice_ball", "qty": 3}, "xp": 8}


func _initialize() -> void:
	await process_frame
	_progression_and_discovery()
	_atomic_transaction()
	_authored_station_access()
	_starter_weapon_paths_are_reachable()
	await _one_time_ingredients()
	await _panel_contract()
	_finish()


func _progression_and_discovery() -> void:
	var profile := {}
	check_eq("fresh kitchen starts at level 1", Rules.station_level(profile, "kitchen"), 1)
	check_true("recipes without a discovery gate are starters", Rules.is_known(rice_recipe, profile))
	var locked := rice_recipe.duplicate(true)
	locked["id"] = "secret"
	locked["discovery"] = "boss"
	check_true("boss recipe starts unknown", not Rules.is_known(locked, profile))
	Rules.ensure_state(profile)["discovered"].append("secret")
	check_true("discovered recipe becomes known", Rules.is_known(locked, profile))
	check_eq("legacy quadratic curve reaches level 2 at 30 XP", Rules.level_from_xp(30), 2)
	check_eq("station XP is separate from learning XP", Rules.station_level({"stats": {"xp": 9999}}, "kitchen"), 1)


func _atomic_transaction() -> void:
	var bag := Bag.new()
	bag.add("rice", 2)
	var profile := {}
	check_true("ready recipe passes every check",
		Rules.status(rice_recipe, "kitchen", profile, bag)["ok"])
	check_true("craft transaction succeeds", bag.craft_transaction(
		rice_recipe["inputs"], "rice_ball", 3))
	check_eq("ingredients are consumed", bag.count("rice"), 0)
	check_eq("all outputs are produced", bag.count("rice_ball"), 3)

	var missing := Bag.new()
	missing.add("rice", 1)
	check_true("missing-material transaction fails",
		not missing.craft_transaction(rice_recipe["inputs"], "rice_ball", 3))
	check_eq("failed craft preserves ingredients", missing.count("rice"), 1)
	var full := Bag.new()
	full.add("rice", 2)
	full.add("rice_ball", Bag.MAX_STACK - 1)
	check_true("full output stack rejects the whole craft",
		not full.craft_transaction(rice_recipe["inputs"], "rice_ball", 3))
	check_eq("capacity failure preserves ingredients", full.count("rice"), 2)


func _authored_station_access() -> void:
	var village: Node = load("res://src/scenes/world.tscn").instantiate()
	var forge: Node = village.find_child("ForgeStation", true, false)
	var workshop: Node = village.find_child("WorkshopStation", true, false)
	var ore: Node = village.find_child("ForgeOreCache", true, false)
	check_true("village exposes a Forge station", forge != null)
	check_true("village exposes a Workshop station", workshop != null)
	check_eq("Forge interaction is station-scoped", forge.get("station"), "forge")
	check_eq("Workshop interaction is station-scoped", workshop.get("station"), "workshop")
	check_true("Forge uses the audited anvil art", forge.get("sprite") != null)
	check_true("Workshop uses the audited hammer art", workshop.get("overlay_sprite") != null)
	check_eq("Forge cache grants one ingot's ore", ore.get("item_id"), "raw_iron_ore")
	check_eq("Forge cache grants the required ore quantity", ore.get("qty"), 3)
	check_eq("Forge cache has a save-safe identity", ore.get("pickup_id"),
		"village_forge_intro_ore")
	village.free()

	var wilds: Node = load("res://src/scenes/wilds.tscn").instantiate()
	var bamboo: Node = wilds.find_child("BambooCache", true, false)
	check_true("Wilds exposes the Workshop's missing starter material", bamboo != null)
	check_eq("Bamboo cache grants the first recipe quantity", bamboo.get("qty"), 2)
	check_eq("Bamboo cache has a save-safe identity", bamboo.get("pickup_id"),
		"wilds_workshop_intro_bamboo")
	wilds.free()

	var forge_bag := Bag.new()
	forge_bag.add("raw_iron_ore", 3)
	var forge_recipe := {
		"id": "refine_iron_ingot", "station": "forge", "levelReq": 1,
		"inputs": [{"item": "raw_iron_ore", "qty": 3}],
		"output": {"item": "iron_ingot", "qty": 1}}
	check_true("Forge cache unlocks its first level-1 recipe",
		Rules.status(forge_recipe, "forge", {}, forge_bag)["ok"])

	var workshop_bag := Bag.new()
	workshop_bag.add("bamboo_shoot", 2)
	workshop_bag.add("raccoon_tail", 1)
	var workshop_recipe := {
		"id": "craft_straw_sandals", "station": "workshop", "levelReq": 1,
		"inputs": [
			{"item": "bamboo_shoot", "qty": 2},
			{"item": "raccoon_tail", "qty": 1}],
		"output": {"item": "straw_sandals", "qty": 1}}
	check_true("Bamboo cache plus a local Raccoon unlocks a Workshop recipe",
		Rules.status(workshop_recipe, "workshop", {}, workshop_bag)["ok"])


## Each permanent Talent path has a level-1 weapon recipe, and every ingredient is sold
## by the playable material trader or dropped by a foe already in the playable Woods.
func _starter_weapon_paths_are_reachable() -> void:
	var db: Node = root.get_node("DB")
	var trader_stock := {}
	for entry in db.shops.get("forest_trader", {}).get("stock", []):
		trader_stock[String(entry.get("item", ""))] = true
	for material in ["bamboo_shoot", "slime_gel", "spider_silk"]:
		check_true("Forest Trader renewably stocks %s" % material, trader_stock.has(material))

	var local_drops := {}
	var wilds: Node = load("res://src/scenes/wilds.tscn").instantiate()
	for node_name in ["Snake", "Owl"]:
		var enemy: Node = wilds.find_child(node_name, true, false)
		check_true("playable Woods contains %s" % node_name, enemy != null)
		var enemy_id := String(enemy.get("enemy_id"))
		for drop in db.enemy(enemy_id).get("drops", []):
			local_drops[String(drop.get("item", ""))] = true
	wilds.free()
	check_true("local Snake supplies spear fangs", local_drops.has("snake_fang"))
	check_true("local Owl supplies brush feathers", local_drops.has("owl_feather"))

	var expected := {
		"craft_wooden_katana": ["blade", "forge"],
		"craft_bamboo_spear": ["heavy", "forge"],
		"craft_wrist_bow": ["ranged", "workshop"],
		"craft_calligraphy_brush": ["kana", "workshop"],
	}
	for recipe_id in expected:
		var recipe: Dictionary = db.recipe(recipe_id)
		var output: Dictionary = db.item(String(recipe.get("output", {}).get("item", "")))
		check_eq("%s has the intended weapon family" % recipe_id,
			output.get("weaponType", ""), expected[recipe_id][0])
		check_eq("%s opens at the intended station" % recipe_id,
			recipe.get("station", ""), expected[recipe_id][1])
		check_eq("%s is a level-1 recipe" % recipe_id, recipe.get("levelReq", 0), 1)
		var bag := Bag.new()
		for input in recipe.get("inputs", []):
			var item_id := String(input.get("item", ""))
			check_true("%s input %s has a playable source" % [recipe_id, item_id],
				trader_stock.has(item_id) or local_drops.has(item_id))
			bag.add(item_id, int(input.get("qty", 0)))
		check_true("%s can complete atomically" % recipe_id,
			Rules.status(recipe, String(expected[recipe_id][1]), {}, bag)["ok"])


func _one_time_ingredients() -> void:
	await process_frame
	var inv: Node = root.get_node("Inv")
	var learning: Node = root.get_node("Learning")
	inv.reset()
	learning.set_flag("pickup_test_kitchen_rice_taken", false)
	var first := Area2D.new()
	first.set_script(load("res://src/entities/item_pickup.gd"))
	first.set("item_id", "rice")
	first.set("qty", 2)
	first.set("pickup_id", "test_kitchen_rice")
	root.add_child(first)
	await process_frame
	first.call("interact")
	await process_frame
	check_eq("intro ingredients are granted once", inv.count("rice"), 2)
	check_true("one-time pickup writes its save flag",
		learning.get_flag("pickup_test_kitchen_rice_taken"))
	var second := Area2D.new()
	second.set_script(load("res://src/entities/item_pickup.gd"))
	second.set("item_id", "rice")
	second.set("qty", 2)
	second.set("pickup_id", "test_kitchen_rice")
	root.add_child(second)
	await process_frame
	check_true("saved pickup does not respawn", not is_instance_valid(second))
	check_eq("re-entering cannot duplicate ingredients", inv.count("rice"), 2)
	inv.reset()


func _panel_contract() -> void:
	await process_frame
	var bus: Node = root.get_node("Bus")
	var inv: Node = root.get_node("Inv")
	var crafting: Node = root.get_node("Crafting")
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	inv.reset()
	inv.add("rice", 2)
	var crafted: Dictionary = crafting.craft("craft_rice_ball", "kitchen")
	check_true("runtime coordinator crafts a valid recipe", crafted.get("ok", false))
	check_eq("runtime craft consumes saved inventory", inv.count("rice"), 0)
	check_eq("runtime craft produces the full output", inv.count("rice_ball"), 3)
	check_eq("runtime craft awards station XP",
		Rules.ensure_state(learning.profile.data)["xp"]["kitchen"],
		Rules.earned_xp(db.recipe("craft_rice_ball")))
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/crafting_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.crafting_open.emit("kitchen")
	await process_frame
	var shell: Control = panel.find_child("CraftingShell", true, false)
	var list: Control = panel.find_child("RecipeList", true, false)
	check_true("station interaction opens crafting", bool(panel.get("_open")))
	check_true("crafting shell fits the 640x360 viewport",
		root.get_viewport().get_visible_rect().encloses(shell.get_global_rect()))
	check_eq("kitchen hides its three undiscovered recipes", list.get_child_count(), 23)
	panel.call("_close")
	inv.reset()
	panel.queue_free()
	await process_frame


func _finish() -> void:
	print("")
	print("PASS — crafting progression, station UI, and atomic inventory changes hold." \
		if failures == 0 else "FAIL — %d crafting check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok: failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
