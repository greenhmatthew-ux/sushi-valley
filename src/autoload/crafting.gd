extends Node
## Runtime coordinator for station crafting. Eligibility stays pure in CraftingLogic;
## this node commits the bag transaction and crafting progression together.

const Rules = preload("res://src/systems/crafting_logic.gd")


func recipes_for_station(station: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for recipe in DB.recipes.values():
		if String(recipe.get("station", "")) == station \
				and Rules.is_known(recipe, Learning.profile.data):
			out.append(recipe)
	out.sort_custom(func(a, b):
		var la := int(a.get("levelReq", 1))
		var lb := int(b.get("levelReq", 1))
		return la < lb or (la == lb and String(a.get("name", "")) < String(b.get("name", ""))))
	return out


func station_level(station: String) -> int:
	return Rules.station_level(Learning.profile.data, station)


## Life-skill actions such as fishing feed the same station progression as the
## recipes they supply. Returns the new station level.
func award_xp(station: String, amount: int) -> int:
	if station not in Rules.STATIONS or amount <= 0:
		return station_level(station)
	var state := Rules.ensure_state(Learning.profile.data)
	state["xp"][station] = int(state["xp"].get(station, 0)) + amount
	Learning.profile.save()
	Bus.crafting_changed.emit(station)
	return Rules.station_level(Learning.profile.data, station)


func recipe_status(recipe: Dictionary, station: String) -> Dictionary:
	var output: Dictionary = recipe.get("output", {})
	var output_id := String(output.get("item", ""))
	var unique_owned := bool(DB.item(output_id).get("unique", false)) and Inv.has(output_id)
	return Rules.status(recipe, station, Learning.profile.data, Inv.logic, unique_owned)


func craft(recipe_id: String, station: String) -> Dictionary:
	var recipe: Dictionary = DB.recipe(recipe_id)
	var check := recipe_status(recipe, station)
	if not bool(check.get("ok", false)):
		return check
	var output: Dictionary = recipe.get("output", {})
	if not Inv.craft_transaction(recipe.get("inputs", []), String(output.get("item", "")),
			int(output.get("qty", 0))):
		return {"ok": false, "reason": "Materials changed; try again."}
	var state := Rules.ensure_state(Learning.profile.data)
	var xp := Rules.earned_xp(recipe)
	state["xp"][station] = int(state["xp"].get(station, 0)) + xp
	state["counts"][recipe_id] = int(state["counts"].get(recipe_id, 0)) + 1
	Learning.profile.save()
	Bus.crafting_changed.emit(station)
	return {"ok": true, "xp": xp, "output": output.duplicate(true)}
