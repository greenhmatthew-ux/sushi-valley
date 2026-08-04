class_name CombatEncounter
extends RefCounted
## One turn-based fight, as pure state + math. Node-free and headless-testable: the panel
## renders this and feeds it choices, but every rule lives here.
##
## The learning contract (COMBAT_DESIGN.md): recall is the input method, not a toll booth.
## Each round the enemy raises a guard word; your four moves are labelled in Japanese and
## picking the matching one IS the recall. A wrong pick still swings — CombatLogic halves
## the damage rather than cancelling the action — so a miss costs tempo, never agency.
##
## Damage, the wrong-answer penalty, and Recall Flow all come from the ported CombatLogic,
## so combat keeps the balance the TS build was actually playtested with.

## Result of resolving one player choice.
class RoundResult extends RefCounted:
	var action_resolved: bool
	var correct: bool
	var action_id: String
	var action_type: String
	var player_damage_dealt: int
	var player_healed: int
	var energy_restored: int
	var shield_gained: int
	var buff_type: String
	var buff_value: int
	var buff_rounds: int
	var debuff_type: String
	var debuff_value: int
	var debuff_rounds: int
	var counter_damage_armed: int
	var counter_damage_dealt: int
	var parry_armed: bool
	var shield_absorbed: int
	var enemy_damage_dealt: int
	var flow_after: int
	var enemy_defeated: bool
	var player_defeated: bool
	var enemy_acted: bool
	var bonus_turn_granted: bool
	var answer: String        ## the right Japanese, for revealing on a miss

const MAX_ENERGY := 5
const BASIC_ATTACK_COST := 1
const SPEED_EXTRA_TURN_GAP := 4

var player_hp: int
var player_max_hp: int
var player_atk: int
var player_def: int
var player_speed: int

var enemy_id: String
var enemy_name: String
var enemy_hp: int
var enemy_max_hp: int
var enemy_atk: int
var enemy_def: int
var enemy_speed: int

## Energy budgets repeatable actions inside one full turn. A large enough Speed lead gives
## one second full turn (and therefore a fresh Energy budget) before the enemy responds.
var energy: int = 0
var turns_left: int = 0
var bonus_turn: bool = false
var item_used_this_turn: bool = false
var ability_uses_this_turn: Dictionary = {}
var ability_cooldowns: Dictionary = {}
## One strongest effect per stat: { "atk": {"value": 4, "rounds": 3}, ... }.
## Rounds tick only after an enemy response, so a defensive buff cannot expire during a
## Speed-only bonus turn where there was nothing to defend against.
var timed_buffs: Dictionary = {}
## Enemy-side counterpart to timed_buffs, populated only by authored attack riders.
var timed_debuffs: Dictionary = {}
## One reactive stance can wait across Speed bonus turns. It is consumed only by a real
## enemy response, never by End Turn when the player immediately receives another turn.
var pending_counter_damage: int = 0
var full_parry_ready: bool = false

## Consecutive correct recalls. Drives CombatLogic.flow_multiplier — accurate recall
## literally hits harder, and a miss resets it.
var flow: int = 0
## Guard is a one-hit buffer. Any remainder is discarded after the enemy's next attack.
var shield: int = 0

## Deterministic variance for tests. -1 draws a fresh roll at runtime like the TS build.
var roll: float = -1.0


func _init(enemy_def_dict: Dictionary, hp: int, max_hp: int, atk: int = 6,
		def_stat: int = 2, speed_stat: int = 5) -> void:
	enemy_id = String(enemy_def_dict.get("id", "enemy"))
	enemy_name = String(enemy_def_dict.get("name", enemy_id))
	enemy_max_hp = int(enemy_def_dict.get("maxHp", 30))
	enemy_hp = enemy_max_hp
	enemy_atk = int(enemy_def_dict.get("atk", 6))
	enemy_def = int(enemy_def_dict.get("def", 1))
	enemy_speed = maxi(1, int(enemy_def_dict.get("speed", 1)))
	player_hp = hp
	player_max_hp = max_hp
	player_atk = atk
	player_def = def_stat
	player_speed = maxi(1, speed_stat)


## Kana's authored Speed mode: ties favour the player, and a lead of four or more grants
## exactly one extra full turn. The cap is deliberate so extreme gear cannot lock enemies out.
static func player_acts_first(player_spd: int, enemy_spd: int) -> bool:
	return player_spd >= enemy_spd


static func player_turn_count(player_spd: int, enemy_spd: int) -> int:
	return 2 if player_spd - enemy_spd >= SPEED_EXTRA_TURN_GAP else 1


static func action_cost(ability: Dictionary) -> int:
	return BASIC_ATTACK_COST if ability.is_empty() \
		else maxi(0, int(ability.get("cost", BASIC_ATTACK_COST)))


func can_afford(ability: Dictionary) -> bool:
	return not is_over() and energy >= action_cost(ability)


func can_use_ability(ability: Dictionary) -> bool:
	if not can_afford(ability):
		return false
	if ability.is_empty():
		return true
	var ability_id := String(ability.get("id", ""))
	if ability_id.is_empty() or int(ability_cooldowns.get(ability_id, 0)) > 0:
		return false
	var use_limit := maxi(0, int(ability.get("maxUsesPerTurn", 0)))
	if use_limit > 0 and int(ability_uses_this_turn.get(ability_id, 0)) >= use_limit:
		return false
	if String(ability.get("type", "")) == "buff" \
			and String(ability.get("buffType", "")) == "shield" \
			and shield >= int(ability.get("buffValue", 0)):
		return false
	if String(ability.get("type", "")) == "buff" \
			and String(ability.get("buffType", "")) in ["atk", "def", "speed"]:
		var buff_type := String(ability.get("buffType", ""))
		var active: Dictionary = timed_buffs.get(buff_type, {})
		if int(active.get("value", 0)) > int(ability.get("buffValue", 0)):
			return false
		if int(active.get("value", 0)) == int(ability.get("buffValue", 0)) \
				and int(active.get("rounds", 0)) >= int(ability.get("buffDuration", 1)):
			return false
	var debuff_type := String(ability.get("debuffType", ""))
	if debuff_type in ["atk", "def", "speed"]:
		var active: Dictionary = timed_debuffs.get(debuff_type, {})
		if int(active.get("value", 0)) > int(ability.get("debuffValue", 0)):
			return false
		if int(active.get("value", 0)) == int(ability.get("debuffValue", 0)) \
				and int(active.get("rounds", 0)) >= int(ability.get("debuffDuration", 1)):
			return false
	if String(ability.get("type", "")) in ["counter", "parry"] \
			and pending_counter_damage >= int(ability.get("counterDamage", 0)):
		return false
	return String(ability.get("type", "")) != "heal" or player_hp < player_max_hp


## Short state for action-bar labels. Cooldown N means N complete player turns must pass
## before the action returns; max-use limits reset at the start of every full player turn.
func ability_status(ability: Dictionary) -> String:
	if ability.is_empty():
		return ""
	var ability_id := String(ability.get("id", ""))
	var cooldown_state := int(ability_cooldowns.get(ability_id, 0))
	if cooldown_state > 0:
		return "CD %d" % maxi(1, cooldown_state - 1)
	var use_limit := maxi(0, int(ability.get("maxUsesPerTurn", 0)))
	if use_limit > 0 and int(ability_uses_this_turn.get(ability_id, 0)) >= use_limit:
		return "Used"
	if String(ability.get("type", "")) == "buff" \
			and String(ability.get("buffType", "")) == "shield" \
			and shield >= int(ability.get("buffValue", 0)):
		return "Shielded"
	if String(ability.get("type", "")) == "buff" \
			and String(ability.get("buffType", "")) in ["atk", "def", "speed"]:
		var buff_type := String(ability.get("buffType", ""))
		var active: Dictionary = timed_buffs.get(buff_type, {})
		if int(active.get("value", 0)) > int(ability.get("buffValue", 0)):
			return "Stronger active"
		if int(active.get("value", 0)) == int(ability.get("buffValue", 0)) \
				and int(active.get("rounds", 0)) >= int(ability.get("buffDuration", 1)):
			return "Active"
	var debuff_type := String(ability.get("debuffType", ""))
	if debuff_type in ["atk", "def", "speed"]:
		var active: Dictionary = timed_debuffs.get(debuff_type, {})
		if int(active.get("value", 0)) > int(ability.get("debuffValue", 0)):
			return "Stronger active"
		if int(active.get("value", 0)) == int(ability.get("debuffValue", 0)) \
				and int(active.get("rounds", 0)) >= int(ability.get("debuffDuration", 1)):
			return "Active"
	if String(ability.get("type", "")) in ["counter", "parry"] \
			and pending_counter_damage >= int(ability.get("counterDamage", 0)):
		return "Armed"
	if String(ability.get("type", "")) == "heal" and player_hp >= player_max_hp:
		return "Full HP"
	return ""


func can_use_item() -> bool:
	return not is_over() and not item_used_this_turn


func can_use_combat_item(item: Dictionary) -> bool:
	if not can_use_item() or not ConsumableLogic.is_supported_combat_item(item):
		return false
	if ConsumableLogic.is_supported_attack(item):
		return true
	if ConsumableLogic.combat_restored_hp(item, player_hp, player_max_hp) > 0:
		return true
	if ConsumableLogic.restored_energy(item, energy, MAX_ENERGY) > 0:
		return true
	var buff_type := String(item.get("buffType", ""))
	var value := int(item.get("buffValue", 0))
	if buff_type == "shield":
		return shield < value
	if buff_type in ["atk", "def"]:
		var active: Dictionary = timed_buffs.get(buff_type, {})
		return int(active.get("value", 0)) < value \
			or (int(active.get("value", 0)) == value \
				and int(active.get("rounds", 0)) < int(item.get("buffDuration", 0)))
	return false


func can_use_prepared_meal(item: Dictionary) -> bool:
	return can_use_item() and ConsumableLogic.is_preparation_meal(item) \
		and int(item.get("heal", 0)) > 0 and player_hp < player_max_hp


## Honest enemy intent for the UI. Runtime damage varies by +/-15%, so preview the full
## reachable HP-loss range instead of showing a false exact number. Current Guard is included.
func enemy_damage_range() -> Vector2i:
	if full_parry_ready:
		return Vector2i.ZERO
	var low := CombatLogic.enemy_damage(effective_enemy_atk(), effective_def(), 0.0)
	var high := CombatLogic.enemy_damage(effective_enemy_atk(), effective_def(), 1.0)
	return Vector2i(maxi(0, low - shield), maxi(0, high - shield))


func effective_atk() -> int:
	return player_atk + int((timed_buffs.get("atk", {}) as Dictionary).get("value", 0))


func effective_def() -> int:
	return player_def + int((timed_buffs.get("def", {}) as Dictionary).get("value", 0))


func effective_speed() -> int:
	return player_speed + int((timed_buffs.get("speed", {}) as Dictionary).get("value", 0))


func effective_enemy_atk() -> int:
	return maxi(1, enemy_atk - int((timed_debuffs.get("atk", {}) as Dictionary).get("value", 0)))


func effective_enemy_def() -> int:
	return maxi(0, enemy_def - int((timed_debuffs.get("def", {}) as Dictionary).get("value", 0)))


func effective_enemy_speed() -> int:
	return maxi(1, enemy_speed - int((timed_debuffs.get("speed", {}) as Dictionary).get("value", 0)))


static func stat_label(stat: String) -> String:
	return "SPD" if stat == "speed" else stat.to_upper()


func timed_buff_summary() -> String:
	var parts: Array[String] = []
	for buff_type in ["atk", "def", "speed"]:
		var active: Dictionary = timed_buffs.get(buff_type, {})
		if int(active.get("rounds", 0)) > 0:
			parts.append("%s+%d/%dr" % [stat_label(buff_type),
				int(active.get("value", 0)), int(active.get("rounds", 0))])
	if pending_counter_damage > 0:
		parts.append("%s RET%d" % ["PARRY" if full_parry_ready else "COUNTER",
			pending_counter_damage])
	return " · ".join(parts)


func enemy_debuff_summary() -> String:
	var parts: Array[String] = []
	for debuff_type in ["atk", "def", "speed"]:
		var active: Dictionary = timed_debuffs.get(debuff_type, {})
		if int(active.get("rounds", 0)) > 0:
			parts.append("%s-%d/%dr" % [stat_label(debuff_type),
				int(active.get("value", 0)), int(active.get("rounds", 0))])
	return " · ".join(parts)


func begin_player_round() -> void:
	turns_left = player_turn_count(effective_speed(), effective_enemy_speed())
	bonus_turn = false
	_begin_player_turn()


func _begin_player_turn() -> void:
	energy = MAX_ENERGY
	item_used_this_turn = false
	ability_uses_this_turn.clear()
	for raw_id in ability_cooldowns.keys():
		var ability_id := String(raw_id)
		var remaining := maxi(0, int(ability_cooldowns[ability_id]) - 1)
		if remaining <= 0:
			ability_cooldowns.erase(ability_id)
		else:
			ability_cooldowns[ability_id] = remaining


## Fast enemies take the opening action once; surviving always hands control to a fresh
## player round. Later enemy responses are handled by end_player_turn().
func enemy_opening_turn() -> RoundResult:
	var r := RoundResult.new()
	_enemy_response(r)
	if not r.player_defeated:
		begin_player_round()
	return r


## Spend Energy and resolve only the player's action. The enemy never interrupts inside an
## Energy turn; the UI (or another caller) explicitly ends the full turn afterward.
func spend_and_resolve(chosen: String, answer: String, ability: Dictionary = {}) -> RoundResult:
	if not can_use_ability(ability):
		return RoundResult.new()
	energy -= action_cost(ability)
	var result := resolve(chosen, answer, ability, false)
	var ability_id := String(ability.get("id", ""))
	if result.action_resolved and not ability_id.is_empty() and result.action_id == ability_id:
		ability_uses_this_turn[ability_id] = int(ability_uses_this_turn.get(ability_id, 0)) + 1
		var cooldown := maxi(0, int(ability.get("cooldownTurns", 0)))
		if cooldown > 0:
			# Include the current turn in the internal countdown. This makes authored CD 1
			# skip exactly the next full player turn, including a Speed-granted bonus turn.
			ability_cooldowns[ability_id] = cooldown + 1
	return result


## Resolve one Basic Attack or authored starter action. The default enemy response preserves
## the original one-call simulation API; the live Energy loop passes false and ends the full
## turn explicitly. Unsupported future effects fail safely to Basic Attack until their distinct
## behavior exists, so authored data cannot create fake menu choices.
func resolve(chosen: String, answer: String, ability: Dictionary = {},
		enemy_responds: bool = true) -> RoundResult:
	var r := RoundResult.new()
	r.action_resolved = true
	r.answer = answer
	r.correct = _normalize(chosen) == _normalize(answer)
	r.action_id = String(ability.get("id", "basic_attack"))
	r.action_type = String(ability.get("type", "attack"))
	var buff_type := String(ability.get("buffType", ""))
	var buff_duration := int(ability.get("buffDuration", 1))
	if r.action_type not in ["attack", "block", "heal", "counter", "parry"] \
			and not (r.action_type == "buff" and (
				(buff_type in ["energy", "shield"] and buff_duration <= 1) \
				or (buff_type in ["atk", "def", "speed"] and buff_duration > 0))):
		r.action_id = "basic_attack"
		r.action_type = "attack"

	# Recall Flow updates BEFORE the swing, so a correct answer's own stack counts toward it.
	flow = flow + 1 if r.correct else 0
	r.flow_after = flow

	var base_power := CombatLogic.BASIC_ATTACK_POWER if r.action_id == "basic_attack" \
		else int(ability.get("power", CombatLogic.BASIC_ATTACK_POWER))
	var power := int(round(base_power * CombatLogic.flow_multiplier(flow)))
	if r.action_type == "attack":
		var enemy_hp_before := enemy_hp
		var hits := maxi(1, int(ability.get("hits", 1)))
		for _hit in hits:
			r.player_damage_dealt += CombatLogic.ability_damage(
				power, effective_atk(), effective_enemy_def(), r.correct, roll)
		enemy_hp = CombatLogic.apply_damage(enemy_hp, r.player_damage_dealt)
		# Report and drain only HP actually removed. The legacy Kana resolver rounded each
		# percentage heal but accidentally counted overkill as damage dealt.
		r.player_damage_dealt = enemy_hp_before - enemy_hp
		var lifesteal_pct := clampf(float(ability.get("lifestealPct", 0.0)), 0.0, 1.0)
		if lifesteal_pct > 0.0 and r.player_damage_dealt > 0:
			var healing := maxi(1, roundi(r.player_damage_dealt * lifesteal_pct))
			var player_hp_before := player_hp
			player_hp = mini(player_max_hp, player_hp + healing)
			r.player_healed = player_hp - player_hp_before
		var debuff_type := String(ability.get("debuffType", ""))
		var debuff_duration := int(ability.get("debuffDuration", 0))
		if debuff_type in ["atk", "def", "speed"] and debuff_duration > 0:
			var amount := int(ability.get("debuffValue", 0))
			amount = amount if r.correct else maxi(1, roundi(amount * 0.5))
			var old_enemy_speed := effective_enemy_speed()
			var active: Dictionary = timed_debuffs.get(debuff_type, {})
			timed_debuffs[debuff_type] = {
				"value": maxi(int(active.get("value", 0)), amount),
				"rounds": maxi(int(active.get("rounds", 0)), debuff_duration),
			}
			r.debuff_type = debuff_type
			r.debuff_value = int((timed_debuffs[debuff_type] as Dictionary)["value"])
			r.debuff_rounds = int((timed_debuffs[debuff_type] as Dictionary)["rounds"])
			if debuff_type == "speed":
				var extra_turns := player_turn_count(effective_speed(), effective_enemy_speed()) \
					- player_turn_count(effective_speed(), old_enemy_speed)
				turns_left = mini(2, turns_left + maxi(0, extra_turns))
	elif r.action_type == "block":
		r.shield_gained = power if r.correct else maxi(1, roundi(power * 0.5))
		shield = r.shield_gained
	elif r.action_type == "heal":
		var healing := power if r.correct else maxi(1, roundi(power * 0.5))
		var before := player_hp
		player_hp = mini(player_max_hp, player_hp + healing)
		r.player_healed = player_hp - before
	elif r.action_type in ["counter", "parry"]:
		# Reactive guard is a listed contract, like its return damage. Recall Flow changes
		# attacks, but must not make the Skills preview understate this defensive value.
		var guard_power := base_power if r.correct else maxi(1, roundi(base_power * 0.5))
		full_parry_ready = r.action_type == "parry" and r.correct
		if not full_parry_ready:
			shield = maxi(shield, guard_power)
			r.shield_gained = guard_power
		var return_damage := int(ability.get("counterDamage", 0))
		return_damage = return_damage if r.correct else maxi(1, roundi(return_damage * 0.5))
		pending_counter_damage = return_damage
		r.counter_damage_armed = pending_counter_damage
		r.parry_armed = full_parry_ready
	elif r.action_type == "buff":
		var amount := int(ability.get("buffValue", 0))
		amount = amount if r.correct else maxi(1, roundi(amount * 0.5))
		if buff_type == "energy":
			var energy_before := energy
			energy = mini(MAX_ENERGY, energy + amount)
			r.energy_restored = energy - energy_before
		elif buff_type == "shield":
			var shield_before := shield
			shield = maxi(shield, amount)
			r.shield_gained = shield - shield_before
		elif buff_type in ["atk", "def", "speed"]:
			var old_speed := effective_speed()
			var active: Dictionary = timed_buffs.get(buff_type, {})
			timed_buffs[buff_type] = {
				"value": maxi(int(active.get("value", 0)), amount),
				"rounds": maxi(int(active.get("rounds", 0)), buff_duration),
			}
			r.buff_type = buff_type
			r.buff_value = int((timed_buffs[buff_type] as Dictionary)["value"])
			r.buff_rounds = int((timed_buffs[buff_type] as Dictionary)["rounds"])
			if buff_type == "speed":
				var extra_turns := player_turn_count(effective_speed(), enemy_speed) \
					- player_turn_count(old_speed, enemy_speed)
				turns_left = mini(2, turns_left + maxi(0, extra_turns))
	r.enemy_defeated = CombatLogic.is_dead(enemy_hp)

	if enemy_responds:
		_enemy_response(r)
		if r.enemy_acted:
			_tick_timed_buffs()

	return r


## Healing items are a direct combat action, not a Japanese prompt. The caller owns
## inventory removal and passes the authored healing value only after validating stock.
func use_healing_item(item_id: String, healing: int, enemy_responds: bool = true) -> RoundResult:
	var r := RoundResult.new()
	if not can_use_item():
		return r
	r.action_id = item_id
	r.action_type = "item"
	var before := player_hp
	player_hp = mini(player_max_hp, player_hp + maxi(0, healing))
	r.player_healed = player_hp - before
	r.action_resolved = r.player_healed > 0
	item_used_this_turn = r.action_resolved
	r.flow_after = flow
	r.enemy_defeated = CombatLogic.is_dead(enemy_hp)
	if r.action_resolved and enemy_responds:
		_enemy_response(r)
		if r.enemy_acted:
			_tick_timed_buffs()
	return r


## Energy tonics share the one-item-per-turn limit with healing items. They refill only the
## current full turn's budget and never overflow, so using one at full Energy is rejected.
func use_energy_item(item_id: String, amount: int, enemy_responds: bool = true) -> RoundResult:
	var r := RoundResult.new()
	if not can_use_item() or energy >= MAX_ENERGY:
		return r
	r.action_id = item_id
	r.action_type = "item"
	var before := energy
	energy = mini(MAX_ENERGY, energy + maxi(0, amount))
	r.energy_restored = energy - before
	r.action_resolved = r.energy_restored > 0
	item_used_this_turn = r.action_resolved
	r.flow_after = flow
	r.enemy_defeated = CombatLogic.is_dead(enemy_hp)
	if r.action_resolved and enemy_responds:
		_enemy_response(r)
		if r.enemy_acted:
			_tick_timed_buffs()
	return r


## Resolve structured consumables through one path. Direct damage reports only HP actually
## removed; hybrid food succeeds when any effect helps and never overwrites a stronger buff.
func use_combat_item(item: Dictionary, enemy_responds: bool = true) -> RoundResult:
	var r := RoundResult.new()
	if not can_use_combat_item(item):
		return r
	r.action_id = String(item.get("id", "item"))
	r.action_type = "item"

	if ConsumableLogic.is_supported_attack(item):
		var enemy_hp_before := enemy_hp
		enemy_hp = CombatLogic.apply_damage(enemy_hp, int(item.get("attackDmg", 0)))
		r.player_damage_dealt = enemy_hp_before - enemy_hp

	var hp_before := player_hp
	player_hp = mini(player_max_hp, player_hp + maxi(0, int(item.get("heal", 0))))
	r.player_healed = player_hp - hp_before

	if ConsumableLogic.is_supported_energy(item):
		var energy_before := energy
		energy = mini(MAX_ENERGY, energy + int(item.get("buffValue", 0)))
		r.energy_restored = energy - energy_before

	var buff_type := String(item.get("buffType", ""))
	var value := maxi(0, int(item.get("buffValue", 0)))
	if buff_type == "shield":
		var shield_before := shield
		shield = maxi(shield, value)
		r.shield_gained = shield - shield_before
	elif buff_type in ["atk", "def"]:
		var duration := maxi(0, int(item.get("buffDuration", 0)))
		var active: Dictionary = timed_buffs.get(buff_type, {})
		var improves := int(active.get("value", 0)) < value \
			or (int(active.get("value", 0)) == value \
				and int(active.get("rounds", 0)) < duration)
		if improves:
			timed_buffs[buff_type] = {
				"value": maxi(int(active.get("value", 0)), value),
				"rounds": maxi(int(active.get("rounds", 0)), duration),
			}
			r.buff_type = buff_type
			r.buff_value = int((timed_buffs[buff_type] as Dictionary)["value"])
			r.buff_rounds = int((timed_buffs[buff_type] as Dictionary)["rounds"])

	r.action_resolved = r.player_damage_dealt > 0 or r.player_healed > 0 \
		or r.energy_restored > 0 \
		or r.shield_gained > 0 or not r.buff_type.is_empty()
	item_used_this_turn = r.action_resolved
	r.flow_after = flow
	r.enemy_defeated = CombatLogic.is_dead(enemy_hp)
	if r.action_resolved and enemy_responds:
		_enemy_response(r)
		if r.enemy_acted:
			_tick_timed_buffs()
	return r


## A prepared meal is intentionally narrower than a carried combat item: it uses
## only its authored heal, shares the once-per-turn item budget, and never becomes
## an instant-use Bag potion merely because it has a large heal value.
func use_prepared_meal(item: Dictionary, enemy_responds: bool = true) -> RoundResult:
	var r := RoundResult.new()
	if not can_use_prepared_meal(item):
		return r
	r.action_id = String(item.get("id", "meal"))
	r.action_type = "meal"
	var hp_before := player_hp
	player_hp = mini(player_max_hp, player_hp + maxi(0, int(item.get("heal", 0))))
	r.player_healed = player_hp - hp_before
	r.action_resolved = r.player_healed > 0
	item_used_this_turn = r.action_resolved
	r.flow_after = flow
	if r.action_resolved and enemy_responds:
		_enemy_response(r)
		if r.enemy_acted:
			_tick_timed_buffs()
	return r


## Finish one full player turn. A Speed bonus refreshes Energy without an enemy action;
## otherwise the enemy responds once and the next surviving round is prepared immediately.
func end_player_turn() -> RoundResult:
	var r := RoundResult.new()
	if is_over():
		return r
	turns_left = maxi(0, turns_left - 1)
	if turns_left > 0:
		bonus_turn = true
		r.bonus_turn_granted = true
		_begin_player_turn()
		return r
	bonus_turn = false
	_enemy_response(r)
	if r.enemy_acted:
		_tick_timed_buffs()
	if not r.player_defeated and not r.enemy_defeated:
		begin_player_round()
	return r


func _enemy_response(r: RoundResult) -> void:
	r.enemy_defeated = CombatLogic.is_dead(enemy_hp)
	if r.enemy_defeated:
		return
	r.enemy_acted = true
	var incoming := CombatLogic.enemy_damage(effective_enemy_atk(), effective_def(), roll)
	r.shield_absorbed = incoming if full_parry_ready else mini(shield, incoming)
	r.enemy_damage_dealt = incoming - r.shield_absorbed
	shield = 0
	full_parry_ready = false
	player_hp = CombatLogic.apply_damage(player_hp, r.enemy_damage_dealt)
	r.player_defeated = CombatLogic.is_dead(player_hp)
	if pending_counter_damage > 0 and not r.player_defeated:
		r.counter_damage_dealt = pending_counter_damage
		enemy_hp = CombatLogic.apply_damage(enemy_hp, r.counter_damage_dealt)
		r.enemy_defeated = CombatLogic.is_dead(enemy_hp)
	pending_counter_damage = 0


func _tick_timed_buffs() -> void:
	for raw_type in timed_buffs.keys():
		var buff_type := String(raw_type)
		var active: Dictionary = timed_buffs[buff_type]
		var remaining := maxi(0, int(active.get("rounds", 0)) - 1)
		if remaining <= 0:
			timed_buffs.erase(buff_type)
		else:
			active["rounds"] = remaining
			timed_buffs[buff_type] = active
	for raw_type in timed_debuffs.keys():
		var debuff_type := String(raw_type)
		var active: Dictionary = timed_debuffs[debuff_type]
		var remaining := maxi(0, int(active.get("rounds", 0)) - 1)
		if remaining <= 0:
			timed_debuffs.erase(debuff_type)
		else:
			active["rounds"] = remaining
			timed_debuffs[debuff_type] = active


## Build one round's challenge from a card plus a pool to draw wrong runes from.
##
## This INVERTS the usual recall prompt. The notebook and gates ask "what does み mean?"
## (recognition); combat shows the meaning and asks you to produce み (production), which
## is the harder direction and the one that actually sticks. It is also what makes the
## action menu Japanese: every button is a rune, so reading them is how you fight.
##
## Returns { "guard": String, "choices": Array[String], "answer": String } — `answer` is the
## Japanese the player must pick. Distractors are deduped against the answer so a round can
## never present the same rune twice.
static func build_challenge(card: Dictionary, pool: Array, rng: RandomNumberGenerator, count: int = 4) -> Dictionary:
	var answer := String(card.get("prompt", ""))
	# Show the meaning when the card has one, else its plain answer (kana use romaji).
	var meaning := String(card.get("meaning", ""))
	var guard := meaning if not meaning.is_empty() else String(card.get("answer", ""))

	var seen := {answer: true}
	var runes: Array[String] = []
	var shuffled := pool.duplicate()
	shuffled.shuffle()

	# Prefer distractors of the SAME card type. Offering さかな against "vowel u" is not a
	# test — the player rules it out on shape alone without knowing う. Same-type runes
	# force an actual recall. Mixed types are only a fallback when the pool is too thin.
	var card_type := String(card.get("type", ""))
	for pass_num in 2:
		var same_type_only := pass_num == 0
		for c in shuffled:
			if runes.size() >= count - 1:
				break
			if same_type_only and String(c.get("type", "")) != card_type:
				continue
			var p := String(c.get("prompt", ""))
			if p.is_empty() or seen.has(p):
				continue
			seen[p] = true
			runes.append(p)
		if runes.size() >= count - 1:
			break

	runes.append(answer)
	runes.shuffle()
	return {"guard": guard, "choices": runes, "answer": answer}


func is_over() -> bool:
	return CombatLogic.is_dead(enemy_hp) or CombatLogic.is_dead(player_hp)


func player_won() -> bool:
	return CombatLogic.is_dead(enemy_hp) and not CombatLogic.is_dead(player_hp)


static func _normalize(s: String) -> String:
	return s.strip_edges().to_lower()
