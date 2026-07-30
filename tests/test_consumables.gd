extends SceneTree
## Consumable contract: only fully implemented effects consume stock, recovery clamps to
## what is missing, and one item can be used per full combat turn.

const ConsumableRules = preload("res://src/systems/consumable_logic.gd")

var failures := 0


func _initialize() -> void:
	await process_frame
	_pure_rules()
	_autoload_consumption()
	_combat_item_action()
	_energy_item_action()
	_finish()


func _pure_rules() -> void:
	var rice := {"id": "rice_ball", "kind": "consumable", "heal": 12}
	var hybrid := {"id": "stone_soup", "kind": "consumable", "heal": 15,
		"buffType": "def"}
	var meal := {"id": "forest_lunchbox", "kind": "consumable", "heal": 48}
	var energy := {"id": "bamboo_tonic", "kind": "consumable",
		"buffType": "energy", "buffValue": 3}
	check_true("pure healing consumable is supported", ConsumableRules.is_supported_healing(rice))
	check_true("hybrid waits until its buff is implemented",
		not ConsumableRules.is_supported_healing(hybrid))
	check_true("meal waits for the preparation loop",
		not ConsumableRules.is_supported_healing(meal))
	check_true("a pure Energy tonic is supported",
		ConsumableRules.is_supported_energy(energy))
	check_eq("healing clamps to missing HP", ConsumableRules.restored_hp(rice, 7, 12), 5)
	check_eq("full HP wastes nothing", ConsumableRules.restored_hp(rice, 12, 12), 0)
	check_eq("Energy recovery clamps to the five-point budget",
		ConsumableRules.restored_energy(energy, 4, 5), 1)
	check_eq("full Energy wastes nothing", ConsumableRules.restored_energy(energy, 5, 5), 0)


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


func _energy_item_action() -> void:
	var enemy := {"id": "mushroom", "name": "Mushroom", "maxHp": 100,
		"atk": 6, "def": 1, "speed": 3}
	var encounter := CombatEncounter.new(enemy, 12, 12, 6, 2, 5)
	encounter.roll = 0.5
	encounter.begin_player_round()
	encounter.spend_and_resolve("mi", "mi",
		{"id": "sweep", "type": "attack", "power": 14, "cost": 3})
	check_eq("setup spends three Energy", encounter.energy, 2)
	var result := encounter.use_energy_item("bamboo_tonic", 3, false)
	check_eq("tonic reports the real Energy restored", result.energy_restored, 3)
	check_eq("tonic refills without overflowing", encounter.energy, 5)
	check_true("Energy item does not invite an interrupt", not result.enemy_acted)
	check_true("one-item limit rejects a second tonic",
		not encounter.use_energy_item("bamboo_tonic", 3, false).action_resolved)


func _finish() -> void:
	print("")
	print("PASS — supported HP and Energy items resolve honestly and atomically." \
		if failures == 0 else "FAIL — %d consumable check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
