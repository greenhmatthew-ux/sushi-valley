extends SceneTree
## Healing-item contract: only fully implemented effects consume stock, healing clamps to
## missing HP, and a combat item still gives the enemy its response.

const ConsumableRules = preload("res://src/systems/consumable_logic.gd")

var failures := 0


func _initialize() -> void:
	await process_frame
	_pure_rules()
	_autoload_consumption()
	_combat_item_action()
	_finish()


func _pure_rules() -> void:
	var rice := {"id": "rice_ball", "kind": "consumable", "heal": 12}
	var hybrid := {"id": "stone_soup", "kind": "consumable", "heal": 15,
		"buffType": "def"}
	var meal := {"id": "forest_lunchbox", "kind": "consumable", "heal": 48}
	check_true("pure healing consumable is supported", ConsumableRules.is_supported_healing(rice))
	check_true("hybrid waits until its buff is implemented",
		not ConsumableRules.is_supported_healing(hybrid))
	check_true("meal waits for the preparation loop",
		not ConsumableRules.is_supported_healing(meal))
	check_eq("healing clamps to missing HP", ConsumableRules.restored_hp(rice, 7, 12), 5)
	check_eq("full HP wastes nothing", ConsumableRules.restored_hp(rice, 12, 12), 0)


func _autoload_consumption() -> void:
	var inv: Node = root.get_node("Inv")
	inv.reset()
	inv.add("rice_ball", 2)
	check_eq("one item restores only missing HP", inv.use_healing_item("rice_ball", 7, 12), 5)
	check_eq("successful use removes exactly one", inv.count("rice_ball"), 1)
	check_eq("full-health use is rejected", inv.use_healing_item("rice_ball", 12, 12), 0)
	check_eq("rejected use preserves stock", inv.count("rice_ball"), 1)
	inv.reset()


func _combat_item_action() -> void:
	var enemy := {"id": "mushroom", "name": "Mushroom", "maxHp": 30, "atk": 6, "def": 1}
	var encounter := CombatEncounter.new(enemy, 3, 12, 6, 2)
	encounter.roll = 0.5
	var result := encounter.use_healing_item("rice_ball", 12)
	check_eq("combat item reports actual healing", result.player_healed, 9)
	check_true("enemy responds after the item", result.enemy_damage_dealt > 0)
	check_true("item action leaves player better off", encounter.player_hp > 3)


func _finish() -> void:
	print("")
	print("PASS — supported healing items consume atomically in and out of combat." \
		if failures == 0 else "FAIL — %d consumable check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
