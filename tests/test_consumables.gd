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
	_structured_meal_actions()
	_direct_damage_actions()
	_finish()


func _pure_rules() -> void:
	var db: Node = root.get_node("DB")
	var rice := {"id": "rice_ball", "kind": "consumable", "heal": 12}
	var hybrid := {"id": "stone_soup", "kind": "consumable", "heal": 15,
		"buffType": "def", "buffValue": 4, "buffDuration": 4}
	var meal := {"id": "forest_lunchbox", "kind": "consumable", "heal": 48}
	var energy := {"id": "bamboo_tonic", "kind": "consumable",
		"buffType": "energy", "buffValue": 3}
	var fire_oil := {"id": "fire_oil", "kind": "consumable", "attackDmg": 25}
	check_true("pure healing consumable is supported", ConsumableRules.is_supported_healing(rice))
	check_true("hybrid meal stays combat-only",
		not ConsumableRules.is_supported_healing(hybrid)
		and ConsumableRules.is_supported_timed_buff(hybrid))
	check_true("meal waits for the preparation loop",
		not ConsumableRules.is_supported_healing(meal))
	check_true("a pure Energy tonic is supported",
		ConsumableRules.is_supported_energy(energy))
	check_true("authored direct-damage consumable is supported",
		ConsumableRules.is_supported_attack(fire_oil))
	for item_id in ["fire_oil", "scroll_fire", "scroll_ice"]:
		check_true("real %s data is a usable damage item" % item_id,
			ConsumableRules.is_supported_attack(db.item(item_id)))
	check_eq("healing clamps to missing HP", ConsumableRules.restored_hp(rice, 7, 12), 5)
	check_eq("full HP wastes nothing", ConsumableRules.restored_hp(rice, 12, 12), 0)
	check_eq("Energy recovery clamps to the five-point budget",
		ConsumableRules.restored_energy(energy, 4, 5), 1)
	check_eq("full Energy wastes nothing", ConsumableRules.restored_energy(energy, 5, 5), 0)
	check_eq("attack item preview names fixed damage",
		ConsumableRules.effect_summary(fire_oil), "Deals 25 damage")
	check_eq("hybrid preview names both effects",
		ConsumableRules.effect_summary(hybrid), "Restores 15 HP · +4 DEF for 4 rounds")


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


func _structured_meal_actions() -> void:
	var enemy := {"id": "mushroom", "name": "Mushroom", "maxHp": 100,
		"atk": 6, "def": 1, "speed": 3}
	var curry := {"id": "spicy_curry", "kind": "consumable",
		"buffType": "atk", "buffValue": 6, "buffDuration": 3}
	var offense := CombatEncounter.new(enemy, 12, 12, 6, 2, 5)
	offense.begin_player_round()
	var curry_result := offense.use_combat_item(curry, false)
	check_eq("curry applies authored ATK and duration",
		Vector2i(curry_result.buff_value, curry_result.buff_rounds), Vector2i(6, 3))
	check_eq("curry changes combat attack math", offense.effective_atk(), 12)
	check_true("active curry cannot be wasted", not offense.can_use_combat_item(curry))

	var sushi := {"id": "salmon_sushi", "kind": "consumable", "heal": 35,
		"buffType": "shield", "buffValue": 20}
	var guarded := CombatEncounter.new(enemy, 80, 100, 6, 2, 5)
	guarded.begin_player_round()
	var sushi_result := guarded.use_combat_item(sushi, false)
	check_eq("sushi reports clamped healing", sushi_result.player_healed, 20)
	check_eq("sushi grants its authored Shield", sushi_result.shield_gained, 20)
	check_true("full HP and full Shield reject sushi",
		not guarded.can_use_combat_item(sushi))

	var soup := {"id": "stone_soup", "kind": "consumable", "heal": 15,
		"buffType": "def", "buffValue": 4, "buffDuration": 4}
	var fortified := CombatEncounter.new(enemy, 100, 100, 6, 2, 5)
	fortified.begin_player_round()
	var soup_result := fortified.use_combat_item(soup, false)
	check_eq("soup remains useful at full HP through its DEF buff", soup_result.player_healed, 0)
	check_eq("soup applies authored DEF and duration",
		Vector2i(soup_result.buff_value, soup_result.buff_rounds), Vector2i(4, 4))
	check_eq("soup changes defense math", fortified.effective_def(), 6)


func _direct_damage_actions() -> void:
	var enemy := {"id": "mushroom", "name": "Mushroom", "maxHp": 18,
		"atk": 99, "def": 99, "speed": 3}
	var fire_oil := {"id": "fire_oil", "kind": "consumable", "attackDmg": 25}
	var finisher := CombatEncounter.new(enemy, 12, 12, 6, 2, 5)
	finisher.begin_player_round()
	var result := finisher.use_combat_item(fire_oil)
	check_eq("direct damage reports only enemy HP actually removed",
		result.player_damage_dealt, 18)
	check_true("damage item can finish the encounter", result.enemy_defeated and finisher.player_won())
	check_true("defeated enemy cannot answer a damage item", not result.enemy_acted)
	check_eq("damage item bypasses DEF exactly as authored", finisher.enemy_hp, 0)
	check_true("combat-over state rejects another item", not finisher.can_use_combat_item(fire_oil))

	var durable_enemy := enemy.duplicate(true)
	durable_enemy["maxHp"] = 100
	var one_per_turn := CombatEncounter.new(durable_enemy, 12, 12, 6, 2, 5)
	one_per_turn.begin_player_round()
	check_true("first damage item resolves",
		one_per_turn.use_combat_item(fire_oil, false).action_resolved)
	check_true("one-item limit rejects a second damage item",
		not one_per_turn.use_combat_item(fire_oil, false).action_resolved)


func _finish() -> void:
	print("")
	print("PASS — supported recovery and status items resolve honestly and atomically." \
		if failures == 0 else "FAIL — %d consumable check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
