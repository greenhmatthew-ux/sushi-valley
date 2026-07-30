class_name ConsumableLogic
extends RefCounted
## Honest consumable rules. Exploration supports the explicit instant-heal family; combat
## additionally supports direct damage, Energy, Shield, and authored timed ATK/DEF meals.

## Explicit, reviewable MVP families. Meals/broths/feasts are deliberately absent: they
## belong to the later preparation-buff loop, not the legacy pile of larger instant heals.
const INSTANT_HEAL_IDS := [
	# Snacks: modest sustain; using one in combat spends the action and invites a counter.
	"rice_ball", "matcha_latte", "honey", "fortune_cookie", "yakitori",
	"cucumber_roll", "herb_tea", "kitsune_dango",
	# Emergency recovery: scarce potion/poultice/scroll identity.
	"foragers_poultice", "life_potion", "trail_elixir", "storm_tonic",
	"elder_draught", "sovereign_elixir", "scroll_heal",
]


static func is_supported_healing(item: Dictionary) -> bool:
	return String(item.get("id", "")) in INSTANT_HEAL_IDS \
		and String(item.get("kind", "")) == "consumable" \
		and int(item.get("heal", 0)) > 0 \
		and String(item.get("buffType", "")).is_empty()


static func restored_hp(item: Dictionary, current_hp: int, max_hp: int) -> int:
	if not is_supported_healing(item) or current_hp >= max_hp:
		return 0
	return mini(int(item.get("heal", 0)), maxi(0, max_hp - current_hp))


static func is_supported_energy(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "consumable" \
		and String(item.get("buffType", "")) == "energy" \
		and int(item.get("buffValue", 0)) > 0 \
		and int(item.get("heal", 0)) <= 0


static func restored_energy(item: Dictionary, current_energy: int, max_energy: int) -> int:
	if not is_supported_energy(item) or current_energy >= max_energy:
		return 0
	return mini(int(item.get("buffValue", 0)), maxi(0, max_energy - current_energy))


static func is_supported_shield(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "consumable" \
		and String(item.get("buffType", "")) == "shield" \
		and int(item.get("buffValue", 0)) > 0


static func is_supported_attack(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "consumable" \
		and int(item.get("attackDmg", 0)) > 0


static func is_supported_timed_buff(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "consumable" \
		and String(item.get("buffType", "")) in ["atk", "def"] \
		and int(item.get("buffValue", 0)) > 0 \
		and int(item.get("buffDuration", 0)) > 0


static func combat_restored_hp(item: Dictionary, current_hp: int, max_hp: int) -> int:
	if not is_supported_combat_item(item) or current_hp >= max_hp:
		return 0
	return mini(maxi(0, int(item.get("heal", 0))), maxi(0, max_hp - current_hp))


static func effect_summary(item: Dictionary) -> String:
	var effects: Array[String] = []
	var attack_damage := int(item.get("attackDmg", 0))
	if attack_damage > 0:
		effects.append("Deals %d damage" % attack_damage)
	var healing := int(item.get("heal", 0))
	if healing > 0:
		effects.append("Restores %d HP" % healing)
	var buff_type := String(item.get("buffType", ""))
	var value := int(item.get("buffValue", 0))
	if buff_type == "energy":
		effects.append("Restores %d Energy" % value)
	elif buff_type == "shield":
		effects.append("Grants up to %d Shield" % value)
	elif buff_type in ["atk", "def"]:
		effects.append("+%d %s for %d rounds" % [
			value, buff_type.to_upper(), int(item.get("buffDuration", 0))])
	return " · ".join(effects)


static func is_supported_combat_item(item: Dictionary) -> bool:
	return is_supported_attack(item) or is_supported_healing(item) or is_supported_energy(item) \
		or is_supported_shield(item) or is_supported_timed_buff(item)
