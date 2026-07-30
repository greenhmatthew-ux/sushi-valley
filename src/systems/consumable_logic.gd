class_name ConsumableLogic
extends RefCounted
## Honest first-pass consumable rules. Pure healing items work now; hybrid food, buffs,
## energy items, and attack scrolls remain unavailable until all authored effects resolve.

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
