class_name CraftingLogic
extends RefCounted
## Pure crafting progression and recipe eligibility. The legacy quadratic level curve
## is retained, but each station has its own XP so Japanese/combat XP cannot buy crafting.

const STATIONS := ["forge", "workshop", "kitchen"]
const MAX_LEVEL := 60


static func ensure_state(profile_data: Dictionary) -> Dictionary:
	if not profile_data.has("crafting") or profile_data["crafting"] is not Dictionary:
		profile_data["crafting"] = {}
	var state: Dictionary = profile_data["crafting"]
	if not state.has("xp") or state["xp"] is not Dictionary:
		state["xp"] = {"forge": 0, "workshop": 0, "kitchen": 0}
	for station in STATIONS:
		if not state["xp"].has(station):
			state["xp"][station] = 0
	if not state.has("discovered") or state["discovered"] is not Array:
		state["discovered"] = []
	if not state.has("counts") or state["counts"] is not Dictionary:
		state["counts"] = {}
	return state


static func xp_for_level(level: int) -> int:
	var n := maxi(1, level) - 1
	return 30 * n * n


static func level_from_xp(xp: int) -> int:
	var level := 1
	while level < MAX_LEVEL and xp >= xp_for_level(level + 1):
		level += 1
	return level


static func station_level(profile_data: Dictionary, station: String) -> int:
	var state := ensure_state(profile_data)
	return level_from_xp(int(state["xp"].get(station, 0)))


static func is_known(recipe: Dictionary, profile_data: Dictionary) -> bool:
	if String(recipe.get("discovery", "starter")) == "starter":
		return true
	return String(recipe.get("id", "")) in ensure_state(profile_data)["discovered"]


## Resolve a data-authored source ("raid:sushi_prep", "boss:forest_wraith",
## "chest:...") to one newly learned recipe, or {} when every match is already
## known. Port of discoverRecipeFromSource in CraftingSystem.ts. Mutates
## profile_data only; the caller owns saving and announcing the discovery.
static func discover_from_source(profile_data: Dictionary, recipes: Array, source: String) -> Dictionary:
	for recipe in recipes:
		if String(recipe.get("discoverySource", "")) == source \
				and not is_known(recipe, profile_data):
			ensure_state(profile_data)["discovered"].append(String(recipe.get("id", "")))
			return recipe
	return {}


static func status(recipe: Dictionary, station: String, profile_data: Dictionary,
		inventory: InventoryLogic) -> Dictionary:
	if recipe.is_empty() or String(recipe.get("station", "")) != station:
		return {"ok": false, "reason": "Wrong station."}
	if not is_known(recipe, profile_data):
		return {"ok": false, "reason": "Recipe not discovered."}
	var level := station_level(profile_data, station)
	var required := int(recipe.get("levelReq", 1))
	if level < required:
		return {"ok": false, "reason": "Requires %s Lv %d." % [station.capitalize(), required]}
	var output: Dictionary = recipe.get("output", {})
	if not inventory.can_craft_transaction(recipe.get("inputs", []),
			String(output.get("item", "")), int(output.get("qty", 0))):
		for input in recipe.get("inputs", []):
			var item_id := String(input.get("item", ""))
			var need := int(input.get("qty", 0))
			if inventory.count(item_id) < need:
				return {"ok": false, "reason": "Need %d %s." % [need, item_id.replace("_", " ")]}
		return {"ok": false, "reason": "Output stack is full."}
	return {"ok": true, "reason": "Ready."}


static func earned_xp(recipe: Dictionary) -> int:
	return int(recipe.get("xp", maxi(5, int(recipe.get("levelReq", 1)) * 4)))
