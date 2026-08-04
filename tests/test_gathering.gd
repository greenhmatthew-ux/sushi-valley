extends SceneTree
## Renewable regional resources obey saved daily resets, skill gates, weather
## yield rules, bag capacity, and station XP without duplicating rewards.

const PROFILE_PATH := "user://profile.json"
const Rules = preload("res://src/systems/gathering_logic.gd")

var failures := 0
var _backup_text := ""
var _had_backup := false
var bus: Node
var inv: Node
var learning: Node
var farm: Node
var gathering: Node
var save: Node


func _initialize() -> void:
	_stash_real_save()
	await process_frame
	bus = root.get_node("Bus")
	inv = root.get_node("Inv")
	learning = root.get_node("Learning")
	farm = root.get_node("Farm")
	gathering = root.get_node("Gathering")
	save = root.get_node("SaveGame")

	_pure_reset_and_weather_contract()
	await _runtime_transaction_contract()

	_restore_real_save()
	_finish()


func _pure_reset_and_weather_contract() -> void:
	var rules: RefCounted = Rules.new()
	check_true("an unseen common node begins ready", rules.is_ready("herb_a", 1, 1))
	check_true("gathering records a stable node id", rules.mark_gathered("herb_a", 1))
	check_true("a common node depletes for the current day",
		not rules.is_ready("herb_a", 1, 1))
	check_eq("a common node reports one day remaining",
		rules.remaining_days("herb_a", 1, 1), 1)
	check_true("a common node returns on the next day", rules.is_ready("herb_a", 2, 1))

	rules.mark_gathered("rare_ore", 7)
	check_eq("a rare three-day node reports its explicit reset",
		rules.remaining_days("rare_ore", 8, 3), 2)
	check_true("a rare node remains depleted before its reset",
		not rules.is_ready("rare_ore", 9, 3))
	check_true("a rare node returns on its authored day", rules.is_ready("rare_ore", 10, 3))

	var saved: Dictionary = rules.to_world_dict()
	var restored: RefCounted = Rules.new()
	restored.load_world_dict(saved)
	check_eq("node days round-trip through world state",
		int(restored.nodes["rare_ore"]), 7)
	restored.load_world_dict({"calendar": {"day": 22, "season": "autumn"}})
	check_eq("a v5 save defaults absent gathering state safely", restored.nodes.size(), 0)

	check_eq("rain adds one herb", Rules.weather_bonus("herb", true), 1)
	check_eq("dry weather adds one ore", Rules.weather_bonus("ore", false), 1)
	check_eq("rain gives ore no bonus", Rules.weather_bonus("ore", true), 0)
	check_eq("bamboo stays weather-neutral", Rules.weather_bonus("bamboo", true), 0)
	check_eq("a starter action earns the archived five-XP floor", Rules.earned_xp(1), 5)
	check_eq("a level-four action earns twelve XP", Rules.earned_xp(4), 12)


func _runtime_transaction_contract() -> void:
	save.clear()
	learning.reload()
	inv.reset()
	farm.reset(false)
	gathering.reset(false)
	learning.profile.data.erase("crafting")

	var expected_bonus := Rules.weather_bonus("herb", root.get_node("WeatherSystem").is_raining())
	var gathered: Dictionary = gathering.gather("test_herb", "wild_herb", 2, 1,
		"kitchen", 1, "herb")
	check_true("an eligible runtime gather commits", bool(gathered.get("ok", false)))
	check_eq("the exact weather-adjusted yield enters the bag",
		inv.count("wild_herb"), 2 + expected_bonus)
	check_eq("gathering grants Kitchen XP through shared progression",
		int(CraftingLogic.ensure_state(learning.profile.data)["xp"]["kitchen"]), 5)
	var world: Dictionary = save.load_world_state()
	check_eq("the gathered stable id saves the global calendar day",
		int(world["gathering"]["nodes"]["test_herb"]), farm.day())

	var repeated: Dictionary = gathering.gather("test_herb", "wild_herb", 2, 1,
		"kitchen", 1, "herb")
	check_true("the same node cannot reward twice in one day",
		not bool(repeated.get("ok", true)))
	check_eq("a blocked repeat adds no items", inv.count("wild_herb"), 2 + expected_bonus)

	var forge_xp_before := int(CraftingLogic.ensure_state(learning.profile.data)["xp"]["forge"])
	var gated: Dictionary = gathering.gather("gated_ore", "copper_ore", 4, 2,
		"forge", 3, "ore")
	check_true("a node above the station level is blocked", not bool(gated.get("ok", true)))
	check_true("a skill-gated node is not depleted",
		gathering.is_ready("gated_ore", 2))
	check_eq("a skill-gated node grants no XP",
		int(CraftingLogic.ensure_state(learning.profile.data)["xp"]["forge"]), forge_xp_before)

	inv.add("wild_herb", 99 - inv.count("wild_herb"))
	var kitchen_xp_before := int(CraftingLogic.ensure_state(learning.profile.data)["xp"]["kitchen"])
	var full: Dictionary = gathering.gather("full_patch", "wild_herb", 2, 1,
		"kitchen", 1, "herb")
	check_true("a full matching stack blocks the entire transaction",
		not bool(full.get("ok", true)))
	check_true("capacity failure leaves the node ready", gathering.is_ready("full_patch", 1))
	check_eq("capacity failure awards no XP",
		int(CraftingLogic.ensure_state(learning.profile.data)["xp"]["kitchen"]), kitchen_xp_before)

	var bamboo: Dictionary = gathering.gather("saved_bamboo", "bamboo_shoot", 3, 1,
		"workshop", 1, "bamboo")
	check_true("a second station can gather its regional material",
		bool(bamboo.get("ok", false)))
	gathering.logic.reset()
	check_true("the in-memory reset forgets the node", gathering.is_ready("saved_bamboo", 1))
	gathering.reload_from_save()
	check_true("reloading restores the saved depletion",
		not gathering.is_ready("saved_bamboo", 1))

	var visual: Node = load("res://src/entities/resource_node.tscn").instantiate()
	visual.node_id = "saved_bamboo"
	visual.display_name = "Test Bamboo"
	visual.item_id = "bamboo_shoot"
	visual.skill_station = "workshop"
	visual.resource_kind = "bamboo"
	root.add_child(visual)
	await process_frame
	check_true("a depleted node label explains the daily reset",
		"tomorrow" in String(visual.interaction_label()).to_lower())
	farm.advance_day()
	await process_frame
	check_eq("the same visible node becomes actionable after sleep",
		visual.interaction_label(), "Gather Test Bamboo")
	check_true("the next day makes every common node ready again",
		gathering.is_ready("test_herb", 1))
	visual.queue_free()
	await process_frame


func _stash_real_save() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		_backup_text = FileAccess.get_file_as_string(PROFILE_PATH)
		_had_backup = true


func _restore_real_save() -> void:
	if _had_backup:
		var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup_text)
			file.close()
		learning.reload()
		var snapshot: Dictionary = save.load_snapshot()
		inv.load_dict(snapshot.get("inventory", {}))
		farm.reload_from_save()
		gathering.reload_from_save()
	else:
		save.clear()
		learning.reload()
		inv.reset()
		farm.reset(false)
		gathering.reset(false)


func _finish() -> void:
	print("")
	print("PASS - gathering renews, saves, gates, and rewards atomically."
		if failures == 0 else "FAIL - %d gathering check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
