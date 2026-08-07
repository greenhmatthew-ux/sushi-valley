extends SceneTree
## Crafting is station-scoped, independently levelled, discovery-aware, and atomic.

const Rules = preload("res://src/systems/crafting_logic.gd")
const Bag = preload("res://src/systems/inventory_logic.gd")

var failures := 0
var last_toast := ""
var rice_recipe := {"id": "craft_rice_ball", "station": "kitchen", "levelReq": 1,
	"inputs": [{"item": "rice", "qty": 2}],
	"output": {"item": "rice_ball", "qty": 3}, "xp": 8}


func _logical_ui_rect() -> Rect2:
	var settings: Node = root.get_node("Settings")
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))
	return Rect2(Vector2.ZERO, (base / maxf(settings.ui_scale, 0.1)).floor())


func _initialize() -> void:
	await process_frame
	_progression_and_discovery()
	_discovery_sources_are_wired()
	_atomic_transaction()
	_authored_station_access()
	_starter_weapon_paths_are_reachable()
	_tool_recipes_are_reachable_and_unique()
	_energy_tonic_path_is_reachable()
	await _one_time_ingredients()
	await _panel_contract()
	await _boss_kill_teaches_its_recipe()
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


## Guard: a recipe locked behind a `discoverySource` nobody ever fires is unreachable
## content that looks finished.
##
## `discover_from_source` is only ever called with a literal prefix, so the prefix is the
## contract between the data and the code. `boss:` sat in recipes.json from the port with no
## caller — the Flame Staff and the Oni Blade were priced and placed behind bosses that
## exist in scenes, and killing them taught nothing. `chest:MountainPass:summit_chest` was
## the same, against a chest that was never placed at all.
##
## This reads the source rather than the behaviour on purpose: firing every prefix for real
## would need each boss, raid and expedition driven to completion, and the thing that
## actually breaks is the wiring, not the state machine behind it.
const DISCOVERY_CALLERS: Array[String] = [
	"res://src/autoload/crafting.gd",
	"res://src/autoload/gathering.gd",
	"res://src/systems/raid_logic.gd",
	"res://src/systems/expedition_logic.gd",
]
## Prefixes authored ahead of the code that would fire them. MUST ONLY SHRINK.
##
## Empty, and meant to stay that way. `world-event:` was the last entry: it named two events,
## `mountain_starfall` and `valley_forager`, that were never in events.json. Matthew's call
## was to reinvent them rather than reconstruct the legacy pair, so they are now `pass_starfall`
## and `valley_windfall` — authored for the valley that exists, and fired from Gathering.
const KNOWN_UNWIRED: Array[String] = []


func _discovery_sources_are_wired() -> void:
	var db: Node = root.get_node("DB")
	var wired := ""
	for path in DISCOVERY_CALLERS:
		wired += FileAccess.get_file_as_string(path)

	var prefixes: Dictionary = {}
	for recipe in db.recipes.values():
		var source := String((recipe as Dictionary).get("discoverySource", ""))
		if source.is_empty():
			continue
		prefixes[source.get_slice(":", 0)] = String(recipe.get("name", ""))

	check_true("recipes declare discovery sources at all (%d prefixes)" % prefixes.size(),
		not prefixes.is_empty())

	var dead: Array[String] = []
	var revived: Array[String] = []
	for prefix in prefixes:
		var fired: bool = wired.contains('"%s:' % prefix)
		if fired and prefix in KNOWN_UNWIRED:
			revived.append(String(prefix))
		elif not fired and prefix not in KNOWN_UNWIRED:
			dead.append("%s: (%s)" % [prefix, prefixes[prefix]])
	check_true("every discovery prefix has something that fires it (%s)"
		% ("all wired" if dead.is_empty() else ", ".join(PackedStringArray(dead))),
		dead.is_empty())
	# A prefix that has since been wired must leave the list rather than outlive the problem.
	check_true("KNOWN_UNWIRED holds nothing that now works (%s)"
		% ("still accurate" if revived.is_empty() else ", ".join(PackedStringArray(revived))),
		revived.is_empty())


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
	check_true("Workshop uses a real Serene Village base", workshop.get("sprite") != null)
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


func _energy_tonic_path_is_reachable() -> void:
	var db: Node = root.get_node("DB")
	var recipe: Dictionary = db.recipe("brew_bamboo_tonic")
	check_eq("Bamboo Tonic opens at the Kitchen", recipe.get("station", ""), "kitchen")
	check_eq("Bamboo Tonic is a level-1 recipe", recipe.get("levelReq", 0), 1)
	var stock := {}
	for entry in db.shops.get("forest_trader", {}).get("stock", []):
		stock[String(entry.get("item", ""))] = true
	var bag := Bag.new()
	for input in recipe.get("inputs", []):
		var item_id := String(input.get("item", ""))
		check_true("Bamboo Tonic input %s has a renewable playable source" % item_id,
			stock.has(item_id))
		bag.add(item_id, int(input.get("qty", 0)))
	check_true("Bamboo Tonic can complete atomically",
		Rules.status(recipe, "kitchen", {}, bag)["ok"])
	check_true("Bamboo Tonic ships its audited repo-local icon",
		FileAccess.file_exists("res://assets/icons/items/bamboo_tonic.png"))


func _tool_recipes_are_reachable_and_unique() -> void:
	var db: Node = root.get_node("DB")
	var expected := {
		"craft_copper_pick": ["copper_pick", "forge", 1],
		"craft_trail_hatchet": ["trail_hatchet", "workshop", 1],
		"craft_herb_sickle": ["herb_sickle", "workshop", 2],
	}
	for recipe_id in expected:
		var recipe: Dictionary = db.recipe(recipe_id)
		var tool_id := String(expected[recipe_id][0])
		var tool: Dictionary = db.item(tool_id)
		check_eq("%s has its intended station" % recipe_id,
			recipe.get("station", ""), expected[recipe_id][1])
		check_eq("%s has its intended level" % recipe_id,
			int(recipe.get("levelReq", 0)), expected[recipe_id][2])
		check_true("%s is a permanent unique tool" % tool_id,
			tool.get("kind", "") == "tool" and bool(tool.get("unique", false)))
		check_true("%s ships audited native art" % tool_id,
			ResourceLoader.exists("res://assets/icons/items/%s.png" % tool_id))

	var inv: Node = root.get_node("Inv")
	var crafting: Node = root.get_node("Crafting")
	inv.reset()
	inv.add("copper_ore", 2)
	inv.add("bamboo_shoot", 1)
	var crafted: Dictionary = crafting.craft("craft_copper_pick", "forge")
	check_true("starter gathered materials craft the Copper Pick",
		bool(crafted.get("ok", false)))
	check_eq("the crafted permanent tool enters the Bag", inv.count("copper_pick"), 1)
	inv.add("copper_ore", 2)
	inv.add("bamboo_shoot", 1)
	var copper_before: int = inv.count("copper_ore")
	var duplicate: Dictionary = crafting.craft("craft_copper_pick", "forge")
	check_true("a duplicate permanent tool is rejected",
		not bool(duplicate.get("ok", true))
		and String(duplicate.get("reason", "")) == "Already owned.")
	check_eq("duplicate rejection preserves its materials",
		inv.count("copper_ore"), copper_before)
	inv.reset()


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
	var cache_sprite: Sprite2D = first.find_child("CacheSprite", false, false)
	check_true("ingredient cache uses real treasure-chest art", cache_sprite != null)
	var cache_frame := cache_sprite.texture as AtlasTexture
	check_eq("cache art comes from the audited CC0 Ninja sheet",
		cache_frame.atlas.resource_path,
		"res://assets/objects/ninja_little_treasure_chest.png")
	check_eq("cache uses one native 16px frame", cache_frame.region.size, Vector2(16, 16))
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
	bus.toast.connect(_capture_toast)
	inv.reset()
	inv.add("rice", 2)
	var kitchen_xp_before := int(Rules.ensure_state(learning.profile.data)["xp"]["kitchen"])
	var crafts_before: int = learning.profile.activity_count(
		LearningProfile.ACTIVITY_CRAFT_COMPLETE)
	var crafted: Dictionary = crafting.craft("craft_rice_ball", "kitchen")
	check_true("runtime coordinator crafts a valid recipe", crafted.get("ok", false))
	check_eq("runtime craft consumes saved inventory", inv.count("rice"), 0)
	check_eq("runtime craft produces the full output", inv.count("rice_ball"), 3)
	check_eq("runtime craft awards station XP",
		Rules.ensure_state(learning.profile.data)["xp"]["kitchen"],
		kitchen_xp_before + Rules.earned_xp(db.recipe("craft_rice_ball")))
	check_eq("a committed recipe records one authored craft activity",
		learning.profile.activity_count(LearningProfile.ACTIVITY_CRAFT_COMPLETE),
		crafts_before + 1)
	var rejected: Dictionary = crafting.craft("craft_rice_ball", "kitchen")
	check_true("a recipe without materials is rejected", not bool(rejected.get("ok", true)))
	check_eq("a rejected recipe records no craft activity",
		learning.profile.activity_count(LearningProfile.ACTIVITY_CRAFT_COMPLETE),
		crafts_before + 1)
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/crafting_panel.gd"))
	root.add_child(panel)
	await process_frame
	bus.crafting_open.emit("kitchen")
	await process_frame
	var shell: Control = panel.find_child("CraftingShell", true, false)
	var list: Control = panel.find_child("RecipeList", true, false)
	check_true("station interaction opens crafting", bool(panel.get("_open")))
	check_true("crafting shell fits the scaled UI canvas",
		_logical_ui_rect().encloses(shell.get_global_rect()))
	check_eq("kitchen hides its three undiscovered recipes", list.get_child_count(), 24)
	panel.call("_close")

	var bow_recipe: Dictionary = db.recipe("craft_wrist_bow")
	var bow_row: Control = panel.call("_recipe_row", bow_recipe)
	var bow_detail: Label = bow_row.find_child("CraftOutputDetail", true, false)
	check_true("crafting previews a weapon's family", "Ranged weapon" in bow_detail.text)
	check_true("crafting previews a weapon's stat bonus", "ATK +2" in bow_detail.text)
	bow_row.free()

	inv.reset()
	inv.add("bamboo_shoot", 3)
	inv.add("spider_silk", 2)
	panel.set("_station", "workshop")
	last_toast = ""
	panel.call("_on_craft", "craft_wrist_bow")
	check_eq("crafted gear remains in the bag", inv.count("wrist_bow"), 1)
	check_true("crafted gear points to the equip screen", "Menu > Bag" in last_toast)
	inv.reset()
	panel.queue_free()
	await process_frame


## The other half of the guard above: `boss:` is wired, and killing the boss actually pays out.
##
## This drives the real `enemy_died` signal instead of calling `discover()` directly, because
## the part that was missing was the listener, not the lookup — a direct call would still pass
## with `_ready()`'s connection deleted.
##
## The negative checks look for "Recipe learned" rather than an empty toast: a kill also
## records an activity, and that can award enough XP to fire a level-up toast of its own.
func _boss_kill_teaches_its_recipe() -> void:
	await process_frame
	var bus: Node = root.get_node("Bus")
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	if not bus.toast.is_connected(_capture_toast):
		bus.toast.connect(_capture_toast)

	var staff: Dictionary = db.recipe("craft_flame_staff")
	check_eq("the Flame Staff is still the Forest Wraith's recipe",
		staff.get("discoverySource", ""), "boss:forest_wraith")
	var discovered: Array = Rules.ensure_state(learning.profile.data)["discovered"]
	discovered.erase("craft_flame_staff")
	check_true("the Flame Staff starts undiscovered",
		not Rules.is_known(staff, learning.profile.data))

	last_toast = ""
	bus.enemy_died.emit("forest_wraith")
	check_true("killing the Forest Wraith discovers the Flame Staff",
		Rules.is_known(staff, learning.profile.data))
	check_true("the discovery announces the recipe by name (%s)" % last_toast,
		"Flame Staff" in last_toast)

	last_toast = ""
	bus.enemy_died.emit("forest_wraith")
	check_true("a second kill teaches nothing twice (%s)" % last_toast,
		not ("Recipe learned" in last_toast))

	var known_before := discovered.size()
	last_toast = ""
	bus.enemy_died.emit("slime")
	check_eq("an ordinary foe teaches nothing", discovered.size(), known_before)
	check_true("an ordinary foe stays quiet about recipes (%s)" % last_toast,
		not ("Recipe learned" in last_toast))
	discovered.erase("craft_flame_staff")
	learning.profile.save()


func _capture_toast(text: String) -> void:
	last_toast = text


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
