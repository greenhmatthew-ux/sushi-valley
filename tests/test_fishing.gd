extends SceneTree
## Exact fishing control math plus the live reward, saved cooldown, input hint,
## and cancellation contracts.

const PROFILE_PATH := "user://profile.json"
const Rules = preload("res://src/systems/fishing_logic.gd")

var failures := 0
var _backup_text := ""
var _had_backup := false
var bus: Node
var inv: Node
var learning: Node
var fishing: Node
var save: Node
var input_hints: Node


func _initialize() -> void:
	_stash_real_save()
	await process_frame
	bus = root.get_node("Bus")
	inv = root.get_node("Inv")
	learning = root.get_node("Learning")
	fishing = root.get_node("Fishing")
	save = root.get_node("SaveGame")
	input_hints = root.get_node("InputHints")

	_pure_control_contract()
	_runtime_reward_and_cooldown()
	await _cancellation_and_input_contract()

	_restore_real_save()
	_finish()


func _pure_control_contract() -> void:
	check_eq("below 62% is a normal catch", Rules.catch_quality(0.61), "normal")
	check_eq("62% begins silver quality", Rules.catch_quality(0.62), "silver")
	check_eq("82% begins gold quality", Rules.catch_quality(0.82), "gold")
	check_eq("accuracy is clamped above one", Rules.catch_quality(5.0), "gold")

	var held: RefCounted = Rules.new(0.1, 42)
	var released: RefCounted = Rules.new(0.1, 42)
	var initial_progress: float = held.progress
	held.step(1.2, true)
	released.step(1.2, false)
	check_true("the 1.2-second cast grace changes no progress", held.progress == initial_progress)
	for i in 30:
		held.step(1.0 / 60.0, true)
		released.step(1.0 / 60.0, false)
	check_true("holding Interact lifts the catch bar", held.bar_y < released.bar_y)

	var winner: RefCounted = Rules.new(0.1, 7)
	winner.in_grace = false
	winner.elapsed = 2.0
	winner.progress = 99.9
	winner.fish_y = 0.0
	winner.bar_y = 0.0
	winner.step(1.0 / 60.0, false)
	check_true("overlap at full progress wins", winner.finished and winner.success)

	var loser: RefCounted = Rules.new(0.1, 7)
	loser.in_grace = false
	loser.elapsed = 2.0
	loser.progress = 0.1
	loser.fish_y = 68.0
	loser.bar_y = -56.0
	loser.step(1.0 / 60.0, true)
	check_true("empty progress outside the bar loses", loser.finished and not loser.success)

	var calm: RefCounted = Rules.new(0.1, 11)
	var storm: RefCounted = Rules.new(0.1, 11)
	for model in [calm, storm]:
		model.in_grace = false
		model.elapsed = 2.0
		model.progress = 50.0
		model.fish_y = 68.0
		model.bar_y = -56.0
	calm.step(1.0 / 60.0, true, false)
	storm.step(1.0 / 60.0, true, true)
	check_true("storm misses drain progress faster than calm water",
		storm.progress < calm.progress)


func _runtime_reward_and_cooldown() -> void:
	save.clear()
	learning.reload()
	inv.reset()
	root.get_node("Farm").reset(false)
	learning.profile.data.erase("crafting")
	learning.profile.data.erase("resourceNodes")
	var catches_before: int = learning.profile.activity_count(
		LearningProfile.ACTIVITY_FISH_CATCH)
	fishing.register_site("test_pond", "Test Pond", 120,
		["spring", "summer", "autumn"])
	var result: Dictionary = fishing.complete("test_pond", 2, "gold", 120, 0.1, 1000.0)
	check_true("a successful catch transaction commits", bool(result.get("ok", false)))
	check_eq("a successful catch records one authored activity",
		learning.profile.activity_count(LearningProfile.ACTIVITY_FISH_CATCH),
		catches_before + 1)
	check_eq("gold quality adds two bonus fish", inv.count("river_fish"), 4)
	check_eq("starter fishing grants five Kitchen XP",
		int(CraftingLogic.ensure_state(learning.profile.data)["xp"]["kitchen"]), 5)
	check_eq("the successful site saves a two-minute cooldown",
		fishing.remaining_seconds("test_pond", 120, 1000.0), 120)
	var blocked: Dictionary = fishing.status("test_pond", 120, 4,
		["spring", "summer", "autumn"], 1001.0)
	check_true("the saved cooldown prevents an immediate repeat", not bool(blocked.get("ok", true)))
	check_eq("one elapsed second leaves 119 seconds", int(blocked.get("remaining", 0)), 119)
	var cooling: Dictionary = fishing.daily_status(1001.0)
	check_eq("daily fishing status counts the cooling pond", cooling["cooling"], 1)
	check_eq("daily fishing status exposes the shortest wait",
		cooling["min_remaining"], 119)
	var renewed: Dictionary = fishing.daily_status(1120.0)
	check_eq("daily fishing status sees the pond ready again", renewed["ready"], 1)
	check_eq("only a previously fished site becomes a returning-player alert",
		renewed["renewed_names"], ["Test Pond"])


func _cancellation_and_input_contract() -> void:
	fishing.reset_site("cancel_pond", false)
	var fish_before: int = inv.count("river_fish")
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/fishing_panel.gd"))
	root.add_child(panel)
	await process_frame

	input_hints.set_input_method("gamepad")
	bus.fishing_open.emit("cancel_pond", "Test Pond", 2, 120, 0.1)
	await process_frame
	check_true("opening fishing pauses the world", paused)
	check_true("the controller prompt names the real A binding",
		"Hold A" in String((panel.get("_hint") as Label).text))
	panel.call("_cancel")
	await process_frame
	check_true("cancel unpauses the world", not paused)
	check_eq("cancel awards no fish", inv.count("river_fish"), fish_before)
	check_eq("cancel starts no cooldown", fishing.remaining_seconds("cancel_pond", 120, 1000.0), 0)

	input_hints.set_input_method("keyboard_mouse")
	panel.queue_free()
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
		root.get_node("Farm").reload_from_save()
	else:
		save.clear()
		learning.reload()
		inv.reset()
		root.get_node("Farm").reset(false)


func _finish() -> void:
	print("")
	print("PASS - fishing can be won, rewarded, cooled down, and cancelled."
		if failures == 0 else "FAIL - %d fishing check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
