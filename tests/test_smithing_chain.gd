extends SceneTree
## Kaji's smithing line, and the ore economy underneath it.
##
##   godot --headless --path . --script res://tests/test_smithing_chain.gd
##
## Two faults are guarded here, and they are the same fault seen from both ends.
##
## 1. `raw_iron_ore` had no renewable source anywhere in the world. The only iron in
##    the shipped game was one village cache of 3 — exactly one ingot, collectable
##    once — plus Mako's stock during the builders_muster season. `tools_of_the_trail`
##    is wired to Kaji today and needs an Iron Ingot for its Herb Sickle, so a player
##    who smelted that cache into anything else had a live quest they could not finish
##    for most of the year. Headless tests all passed while that was true, because
##    every system worked: the world just never produced the input.
##
## 2. `smiths_first_order` and `kaji_copper_testing` were authored, complete with
##    goals, rewards and dialogue, and unreachable — no giver pointed at them.
##
## The general rule asserted below is the useful one: an item a reachable quest
## requires must be obtainable more than once. Authored content plus a working system
## is still not a playable loop if the raw material runs out.

const Journal = preload("res://src/systems/quest_journal.gd")

## Regions the player can actually walk to today.
const REGIONS := [
	"res://src/scenes/world.tscn",
	"res://src/scenes/wilds.tscn",
	"res://src/scenes/mountain_pass.tscn",
]

## Kaji's line, in the order his giver hands it out.
## Kaji's line, in the order the resolver hands it out. `scale_spectrum` joined the end once
## a Cliff Drake was placed on the Mountain Pass — before that its green scales dropped from
## two enemies that appear in no scene, so pointing Kaji at it would have stranded the player.
const KAJI_CHAIN := ["tools_of_the_trail", "smiths_first_order", "kaji_copper_testing",
	"scale_spectrum"]

var failures: int = 0
var db: Node


## Stands in for LearningProfile so the chain resolver is exercised without touching
## the real profile.json — dev scripts here write the actual save file otherwise.
class FakeProfile extends RefCounted:
	var flags := {}

	func get_flag(flag_name: String) -> bool:
		return bool(flags.get(flag_name, false))

	func complete(quest_id: String) -> void:
		flags[QuestJournal.done_flag(quest_id)] = true


func _initialize() -> void:
	await process_frame
	db = root.get_node("DB")

	_iron_has_a_renewable_source()
	_reachable_quest_items_are_repeatable()
	_kaji_hands_out_his_whole_line()
	_the_chain_is_makeable_from_renewable_ore()

	_finish()


## Scenes are instantiated but never added to the tree: `_ready` would register nodes
## with the Gathering autoload and write the real save. Exported values are all this
## needs, and they are readable straight off the instance.
func _renewable_items() -> Dictionary:
	var items := {}
	for region_path in REGIONS:
		var region: Node = load(region_path).instantiate()
		for node in _all_descendants(region):
			# A resource node is the only thing carrying all four of these.
			if node.get("node_id") == null or node.get("resource_kind") == null \
					or node.get("item_id") == null or node.get("base_qty") == null:
				continue
			var item_id := String(node.get("item_id"))
			if item_id.is_empty():
				continue
			if not items.has(item_id):
				items[item_id] = []
			items[item_id].append({
				"region": region_path.get_file().get_basename(),
				"node": String(node.name),
				"qty": int(node.get("base_qty")),
				"reset": int(node.get("reset_days")),
				"level": int(node.get("level_req")),
			})
		region.queue_free()
	return items


func _all_descendants(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_all_descendants(child))
	return out


func _iron_has_a_renewable_source() -> void:
	var renewable := _renewable_items()
	var iron: Array = renewable.get("raw_iron_ore", [])
	print("  ..   iron seams: %s" % str(iron))
	check_true("raw iron ore can be mined, not just found once (%d seam(s))" % iron.size(),
		iron.size() >= 1)
	check_true("the Mountain Pass has iron, as smiths_first_order tells the player it does",
		iron.any(func(seam): return String(seam["region"]) == "mountain_pass"))
	check_true("the woods have iron too, as kaji_copper_testing's lines claim",
		iron.any(func(seam): return String(seam["region"]) == "wilds"))

	# A seam gated above the starting station level would restore the same dead end.
	var starter := iron.filter(func(seam): return int(seam["level"]) <= 1)
	check_true("at least one iron seam is workable at the starting Forge level",
		not starter.is_empty())

	# The pass is the iron region; the woods only trickle. If the woods ever out-produced
	# the pass, the climb would stop being the reason to make it.
	var pass_rate := _best_daily_rate(iron, "mountain_pass")
	var woods_rate := _best_daily_rate(iron, "wilds")
	check_true("the pass out-produces the woods for iron (%.2f/day vs %.2f/day)"
		% [pass_rate, woods_rate], pass_rate > woods_rate)

	# 3 ore -> 1 ingot. A pass seam that yields the recipe's exact input in one visit
	# means the rate can be read off the recipe instead of guessed at.
	var refine: Dictionary = db.recipes["refine_iron_ingot"]
	var per_ingot := int(refine["inputs"][0]["qty"])
	var pass_seam: Array = iron.filter(func(seam): return String(seam["region"]) == "mountain_pass")
	check_eq("one visit to the pass seam smelts exactly one ingot",
		int(pass_seam[0]["qty"]) if not pass_seam.is_empty() else 0, per_ingot)


func _best_daily_rate(seams: Array, region: String) -> float:
	var best := 0.0
	for seam in seams:
		if String(seam["region"]) != region:
			continue
		best = maxf(best, float(seam["qty"]) / maxf(1.0, float(seam["reset"])))
	return best


## The general form of the bug: anything a reachable quest asks for, directly or as a
## recipe input, has to be obtainable again. One-time caches and season-locked shop
## stock are not a supply.
func _reachable_quest_items_are_repeatable() -> void:
	var renewable := _renewable_items()
	var stranded: Array[String] = []
	for quest_id in KAJI_CHAIN:
		for required in _raw_inputs_for(String(db.quest(quest_id).get("goal", {}).get("item", ""))):
			if not renewable.has(required) and not _is_enemy_drop(required):
				stranded.append("%s needs %s" % [quest_id, required])
		for objective in db.quest(quest_id).get("objectives", []):
			for required in _raw_inputs_for(String(objective.get("item", ""))):
				if not renewable.has(required) and not _is_enemy_drop(required):
					stranded.append("%s needs %s" % [quest_id, required])
	check_true("every material Kaji's line asks for can be obtained more than once (%s)"
		% str(stranded), stranded.is_empty())


## Walk an item back to the raw materials it is ultimately made of.
func _raw_inputs_for(item_id: String, depth: int = 0) -> Array[String]:
	var out: Array[String] = []
	if item_id.is_empty() or depth > 4:
		return out
	var recipe := _recipe_making(item_id)
	if recipe.is_empty():
		out.append(item_id)   # nothing crafts it, so it is raw
		return out
	for ingredient in recipe.get("inputs", []):
		out.append_array(_raw_inputs_for(String(ingredient.get("item", "")), depth + 1))
	return out


func _recipe_making(item_id: String) -> Dictionary:
	for recipe_id in db.recipes:
		var recipe: Dictionary = db.recipes[recipe_id]
		if String(recipe.get("output", {}).get("item", "")) == item_id:
			return recipe
	return {}


func _is_enemy_drop(item_id: String) -> bool:
	for enemy_id in db.enemies:
		for drop in db.enemies[enemy_id].get("drops", []):
			if String(drop.get("item", "")) == item_id:
				return true
	return false


## A giver keeps one root id in the scene and the data walks forward from it, so a
## dormant quest becomes live by being pointed at — not by editing a scene.
func _kaji_hands_out_his_whole_line() -> void:
	for quest_id in KAJI_CHAIN:
		check_true("%s is authored" % quest_id, not db.quest(quest_id).is_empty())
		check_eq("%s is Kaji's" % quest_id, String(db.quest(quest_id).get("giver", "")), "Kaji")

	var profile := FakeProfile.new()
	var root_id: String = KAJI_CHAIN[0]
	for expected in KAJI_CHAIN:
		var current := Journal.current_in_chain(profile, db, root_id)
		check_eq("Kaji next offers %s" % expected, String(current.get("id", "")), expected)
		profile.complete(expected)

	# After the last one there is nothing further to point at, and the resolver has to
	# settle rather than fall off the end or loop.
	var finished := Journal.current_in_chain(profile, db, root_id)
	check_eq("a finished line rests on its last quest",
		String(finished.get("id", "")), KAJI_CHAIN[-1])

	# The scene has to actually use that root, or the chain is data nobody reads.
	var village: Node = load("res://src/scenes/world.tscn").instantiate()
	var roots: Array[String] = []
	for node in _all_descendants(village):
		var quest_id: Variant = node.get("quest_id")
		if quest_id != null and not String(quest_id).is_empty():
			roots.append(String(quest_id))
	village.queue_free()
	check_true("a village giver is wired to the root of the line (%s)" % str(roots),
		roots.has(root_id))


## Each step has to be makeable when it is offered, or the chain stalls at whichever
## station level the player has not reached.
func _the_chain_is_makeable_from_renewable_ore() -> void:
	var bronze: Dictionary = db.recipes["refine_bronze_ingot"]
	var bronze_inputs: Array[String] = []
	for ingredient in bronze.get("inputs", []):
		bronze_inputs.append(String(ingredient.get("item", "")))
	check_true("bronze needs both ores (%s)" % str(bronze_inputs),
		bronze_inputs.has("copper_ore") and bronze_inputs.has("raw_iron_ore"))

	var renewable := _renewable_items()
	check_true("both bronze ores are renewable in the woods, where its lines send you",
		_has_seam_in(renewable, "copper_ore", "wilds")
		and _has_seam_in(renewable, "raw_iron_ore", "wilds"))

	# The last step is the only one gated on Forge progression, so it belongs last.
	var refine_level := int(db.recipes["refine_iron_ingot"].get("levelReq", 1))
	var bronze_level := int(bronze.get("levelReq", 1))
	check_true("the line ends on the harder smelt (Forge Lv %d then Lv %d)"
		% [refine_level, bronze_level], bronze_level > refine_level)


func _has_seam_in(renewable: Dictionary, item_id: String, region: String) -> bool:
	for seam in renewable.get(item_id, []):
		if String(seam["region"]) == region:
			return true
	return false


func _finish() -> void:
	print("")
	print(("PASS — Kaji's line runs end to end and the ore behind it renews."
		if failures == 0 else "FAIL — %d smithing-chain check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
