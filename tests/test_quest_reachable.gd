extends SceneTree
## Guard: every quest a player can actually be offered has an obtainable goal.
##
##   godot --headless --path . --script res://tests/test_quest_reachable.gd
##
## `quests.json` holds 24 quests and the world places seven givers. Most of the rest are
## authored against regions that do not exist yet, which is fine — content ahead of the map
## is a plan, not a bug. The bug is a quest the player CAN accept whose goal item drops from
## nothing that has been placed, because that is indistinguishable from a broken game: the
## Journal names a thing to fetch, and no amount of playing produces it.
##
## `scale_spectrum` was exactly that. It asked for three green dragon scales "from Lesser
## Dragons or Tyrant Lizards" — two enemies with full stat lines that appear in no scene. It
## only became completable when a Cliff Drake was placed on the Mountain Pass, and its text
## still named the wrong quarry until then.
##
## Two things this deliberately does NOT do. It does not check quest prose, because a
## direction can be wrong in ways no assertion catches. And it does not demand that dormant
## quests be reachable — only that reachable ones be finishable.
##
## Reachability follows the game's own rule, which is why the scenes are instantiated rather
## than parsed: `quest_id` has a DEFAULT on quest_giver.gd, so Mako offers Stock the Stall
## while setting only `shop_id`. Grepping .tscn for `quest_id =` misses her entirely — the
## same scene-defaults trap that once hid four village NPCs sharing one face.

const REGION_SCENES: Array[String] = [
	"res://src/scenes/world.tscn",
	"res://src/scenes/wilds.tscn",
	"res://src/scenes/mountain_pass.tscn",
	"res://src/scenes/expedition_forest.tscn",
	"res://src/scenes/expedition_pass.tscn",
	"res://src/scenes/interior_house.tscn",
	"res://src/scenes/interior_lake_house.tscn",
]

var failures: int = 0
var db: Node
## item id -> a human-readable reason it is obtainable, for the failure message.
var sources: Dictionary = {}
## quest ids a placed giver will offer, following follow-up chains.
var offered: Dictionary = {}
## shop ids a node in a real scene actually opens.
var open_shops: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	db = root.get_node("DB")

	for path in REGION_SCENES:
		await _scan(path)

	_add_shop_stock()
	_add_craft_outputs()

	check_true("the world places quest givers (%d chains reachable)" % offered.size(),
		not offered.is_empty())
	check_true("something in the world drops loot (%d item sources)" % sources.size(),
		sources.size() > 10)

	_goals_are_obtainable()
	_default_quest_is_real()
	_finish()


## Instantiate rather than parse: exported defaults only resolve on a real node.
func _scan(path: String) -> void:
	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	await process_frame

	for node in scene.find_children("*", "", true, false):
		# --- who offers what -------------------------------------------------
		var quest_id: Variant = node.get("quest_id")
		if quest_id != null and not String(quest_id).is_empty() and node.has_method("interact"):
			_walk_chain(String(quest_id))

		# --- what the world can give you -------------------------------------
		var enemy_id: Variant = node.get("enemy_id")
		if enemy_id != null and node.has_method("take_damage"):
			for drop in db.enemy(String(enemy_id)).get("drops", []):
				_add_source(String(drop.get("item", "")),
					"dropped by %s" % String(enemy_id))

		var shop_id: Variant = node.get("shop_id")
		if shop_id != null and not String(shop_id).is_empty():
			open_shops[String(shop_id)] = true

		if node.get("resource_kind") != null:
			_add_source(String(node.get("item_id")), "gathered at %s" % node.name)
		elif node.get("pickup_id") != null:
			_add_source(String(node.get("item_id")), "picked up at %s" % node.name)

	scene.queue_free()
	await process_frame


## A giver hands out its whole chain over time, so every link is reachable.
func _walk_chain(start_id: String) -> void:
	var id := start_id
	var guard := 0
	while not id.is_empty() and not offered.has(id) and guard < 32:
		var quest: Dictionary = db.quest(id)
		if quest.is_empty():
			return
		offered[id] = true
		id = String(quest.get("followUpQuest", ""))
		guard += 1


func _add_source(item_id: String, why: String) -> void:
	if item_id.is_empty() or sources.has(item_id):
		return
	sources[item_id] = why


## Only counters a player can actually stand at.
##
## Counting every shop in `shops.json` was this test's own version of the bug it exists to
## catch: `northern_reach_trader` stocks frost cores for a region with no scene, so a quest
## demanding one looked satisfiable and was not. A shop nobody can walk up to sells nothing.
func _add_shop_stock() -> void:
	for shop_id in open_shops:
		var shop: Dictionary = db.shops.get(shop_id, {})
		for season in shop.get("seasonalStock", {}):
			for entry in shop["seasonalStock"][season]:
				_add_source(String(entry.get("item", "")), "sold at %s" % shop_id)
		for entry in shop.get("stock", []):
			_add_source(String(entry.get("item", "")), "sold at %s" % shop_id)


## A craftable item counts as obtainable. This does NOT recurse into the recipe's own inputs:
## the crafting tree has its own coverage, and a quest asking for something craftable is a
## different (and much louder) failure than one asking for something nothing produces.
func _add_craft_outputs() -> void:
	for recipe_id in db.recipes:
		var recipe: Dictionary = db.recipes[recipe_id]
		_add_source(String(recipe.get("output", {}).get("item", "")),
			"crafted via %s" % recipe_id)


func _goals_are_obtainable() -> void:
	var stranded: Array[String] = []
	var checked := 0
	for quest_id in offered:
		var quest: Dictionary = db.quest(String(quest_id))
		for item_id in _required_items(quest):
			checked += 1
			if not sources.has(item_id):
				stranded.append("%s needs %s" % [quest_id, item_id])
	check_true("every offered quest asks for something the world produces (%d items checked)"
		% checked, checked > 0)
	check_true("no offered quest strands the player (%s)"
		% ("all obtainable" if stranded.is_empty()
			else ", ".join(PackedStringArray(stranded))),
		stranded.is_empty())


## Both quest shapes: a single `goal`, or a list of `objectives`. Activity objectives
## ("harvest a crop") carry no item and are the player's own doing, so they are skipped.
func _required_items(quest: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var goal: Dictionary = quest.get("goal", {})
	if not goal.is_empty() and not String(goal.get("item", "")).is_empty():
		out.append(String(goal["item"]))
	for objective in quest.get("objectives", []):
		var item_id := String((objective as Dictionary).get("item", ""))
		if not item_id.is_empty():
			out.append(item_id)
	return out


## The export default is live content: any giver that does not set `quest_id` silently offers
## it, so a typo here would hand out a quest that does not exist and read as a mute NPC.
func _default_quest_is_real() -> void:
	var giver: Node = load("res://src/entities/quest_giver.tscn").instantiate()
	var default_id := String(giver.get("quest_id"))
	check_true("quest_giver's default quest_id is authored (%s)" % default_id,
		not db.quest(default_id).is_empty())
	check_true("and a placed giver actually relies on that default",
		offered.has(default_id))
	giver.queue_free()


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func _finish() -> void:
	print("")
	print(("PASS — every offered quest can be finished with what the world contains."
		if failures == 0 else "FAIL — %d quest reachability check(s) failed." % failures))
	quit(1 if failures > 0 else 0)
