extends SceneTree
## The village farm is a saved, inventory-safe daily loop.
##
##   godot --headless --path . --script res://tests/test_farm.gd

const PROFILE_PATH := "user://profile.json"
const FarmRules = preload("res://src/systems/farm_logic.gd")

var failures := 0
var _backup_text := ""
var _had_backup := false
var inv: Node
var farm: Node
var save: Node


func _initialize() -> void:
	_stash_real_save()
	await process_frame
	inv = root.get_node("Inv")
	farm = root.get_node("Farm")
	save = root.get_node("SaveGame")

	_pure_calendar_and_growth_rules()
	_saved_inventory_transaction()

	_restore_real_save()
	_finish()


func _pure_calendar_and_growth_rules() -> void:
	var logic = FarmRules.new()
	var crops := {
		"herb": {"id": "herb", "days": 1, "seasons": ["spring"]},
		"cucumber": {"id": "cucumber", "days": 2, "seasons": ["spring", "summer"]},
	}
	check_eq("a new calendar starts on Spring Day 1", logic.clock_text(), "Spring - Day 1")
	check_true("planting an in-season seed succeeds", logic.plant("plot_a", crops["herb"]))
	check_true("planting waters the plot for today", bool(logic.plot("plot_a")["watered"]))
	check_eq("a one-day crop starts as a sprout", logic.stage("plot_a", crops), 1)
	var one_day_preview: Dictionary = logic.preview_advance(crops)
	check_eq("sleep preview counts one advancing crop", one_day_preview["advancing"], 1)
	check_eq("sleep preview predicts the crop becoming ready",
		one_day_preview["ready_tomorrow"], 1)
	logic.advance_day()
	check_eq("a watered one-day crop matures after sleep", logic.stage("plot_a", crops), 3)
	check_true("mature crop is harvest-ready", logic.is_ready("plot_a", crops))
	check_eq("a mature crop is promised to wait safely",
		logic.preview_advance(crops)["ready_now"], 1)

	logic.reset()
	check_true("two-day cucumber plants", logic.plant("plot_b", crops["cucumber"]))
	logic.advance_day()
	check_eq("first watered day advances cucumber growth", logic.stage("plot_b", crops), 2)
	var dry_preview: Dictionary = logic.preview_advance(crops)
	check_eq("sleep preview counts a dry crop as paused", dry_preview["paused"], 1)
	check_eq("a paused crop is not falsely promised ready",
		dry_preview["ready_tomorrow"], 0)
	logic.advance_day()
	check_eq("a dry day pauses instead of withering", logic.stage("plot_b", crops), 2)
	check_true("the paused crop can be watered", logic.water("plot_b"))
	logic.advance_day()
	check_true("watering resumes growth to harvest", logic.is_ready("plot_b", crops))

	logic.reset()
	logic.day = 28
	check_eq("the final spring date reads Day 28", logic.clock_text(), "Spring - Day 28")
	logic.advance_day()
	check_eq("day 29 rolls to Summer Day 1", logic.clock_text(), "Summer - Day 1")
	check_true("spring-only crops are rejected in summer",
		not logic.plant("plot_c", crops["herb"]))

	var world: Dictionary = logic.to_world_dict()
	var restored = FarmRules.new()
	restored.load_world_dict(world)
	check_eq("calendar round-trips through world state", restored.clock_text(), "Summer - Day 1")
	check_eq("empty plots remain empty after round-trip", restored.plots.size(), 0)
	restored.load_world_dict({"player": {"x": 5.0, "y": 6.0}})
	check_eq("a v4 world defaults the missing calendar safely",
		restored.clock_text(), "Spring - Day 1")
	check_eq("a v4 world defaults missing plots to empty", restored.plots.size(), 0)


func _saved_inventory_transaction() -> void:
	save.clear()
	inv.reset()
	farm.reset(false)
	farm.register_plot("test_plot")
	inv.add("herb_seed", 1)
	check_eq("starter seed enters the bag", inv.count("herb_seed"), 1)

	var planted: Dictionary = farm.plant("test_plot", "herb")
	check_true("runtime planting succeeds", bool(planted.get("ok", false)))
	check_eq("planting consumes exactly one seed", inv.count("herb_seed"), 0)
	var world: Dictionary = save.load_world_state()
	check_eq("plant autosave records the calendar", int(world["calendar"]["day"]), 1)
	check_eq("plant autosave records the stable plot id",
		String(world["farm"]["plots"]["test_plot"]["cropId"]), "herb")
	check_eq("daily farm status sees the watered crop growing",
		farm.daily_status()["growing"], 1)

	# A normal world-position save must merge, not erase the feature-owned farm state.
	save.save_snapshot({}, Vector2(72, 96), "left", inv.to_dict())
	world = save.load_world_state()
	check_true("position saves preserve planted crops",
		(world["farm"]["plots"] as Dictionary).has("test_plot"))
	check_eq("position saves still update player placement",
		float(world["player"]["x"]), 72.0)

	farm.advance_day()
	check_true("the watered herb is ready tomorrow", farm.is_ready("test_plot"))
	check_eq("daily farm status calls out the ready harvest",
		farm.daily_status()["ready"], 1)
	var harvested: Dictionary = farm.harvest("test_plot")
	check_true("ready produce harvests", bool(harvested.get("ok", false)))
	check_eq("harvest awards exactly one authored produce", inv.count("wild_herb"), 1)
	check_eq("harvest clears the saved plot", farm.plot("test_plot")["cropId"], "")
	check_true("the cleared plot is absent from disk",
		not (save.load_world_state()["farm"]["plots"] as Dictionary).has("test_plot"))


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
		var snapshot: Dictionary = save.load_snapshot()
		inv.load_dict(snapshot.get("inventory", {}))
		farm.reload_from_save()
	else:
		save.clear()
		inv.reset()
		farm.reset(false)


func _finish() -> void:
	print("")
	print("PASS - farm calendar, growth, inventory, and save transactions hold."
		if failures == 0 else "FAIL - %d farm check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
