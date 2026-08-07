extends Node
## Runtime coordinator for station crafting. Eligibility stays pure in CraftingLogic;
## this node commits the bag transaction and crafting progression together.

const Rules = preload("res://src/systems/crafting_logic.gd")


func _ready() -> void:
	Bus.enemy_died.connect(_on_enemy_died)


## Recipes taught by killing something.
##
## `recipes.json` has carried `discoverySource: "boss:<id>"` entries since the port, and
## nothing ever called that prefix — only raid and expedition completions discovered
## anything. So the Flame Staff and the Oni Blade were fully authored, priced and placed
## behind bosses that exist, and killing those bosses taught nothing at all.
##
## This listens to every death rather than to a "this one is a boss" flag, because the recipe
## table is already the thing that decides whether a kill teaches something. An ordinary foe
## matches no source and costs one walk of the recipe list.
func _on_enemy_died(enemy_id: String) -> void:
	discover("boss:%s" % enemy_id)


## Reveal the single recipe a source teaches, once, and say so. Returns {} when the source
## teaches nothing or its recipe is already known, so callers can stay quiet about it.
##
## Saving is this function's job: `Rules.discover_from_source` only mutates the dictionary,
## which is why both existing callers follow it with `profile.save()`.
func discover(source: String) -> Dictionary:
	if Learning.profile == null:
		return {}
	var recipe := Rules.discover_from_source(
		Learning.profile.data, DB.recipes.values(), source)
	if recipe.is_empty():
		return {}
	Learning.profile.save()
	Bus.toast.emit("Recipe learned — %s" % String(recipe.get("name", source)))
	Bus.crafting_changed.emit(String(recipe.get("station", "")))
	return recipe


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
	Learning.profile.record_activity(LearningProfile.ACTIVITY_CRAFT_COMPLETE)
	Learning.profile.save()
	Bus.crafting_changed.emit(station)
	return {"ok": true, "xp": xp, "output": output.duplicate(true)}
