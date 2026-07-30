extends SceneTree
## The bag survives a reload — and a v1 save still loads.
##
##   godot --headless --path . --script res://tests/test_inventory_persistence.gd
##
## WHY. The save document persisted learning state and the player's position but NEVER the
## bag or the coin purse. Quitting deleted every item and coin you had. That became worse once
## quests landed: quest progress is measured from what you are carrying, while the
## accepted-quest flag lives in the learning section — so a reload could leave a quest
## accepted with its gathered items gone, and no way to tell why.
##
## Schema went 1 -> 2. A v1 document has no "inventory" key and must still load, as an empty
## bag — which is precisely the state it described.

var failures: int = 0
var inv: Node
var learning: Node
var save_game: Node


func _initialize() -> void:
	await process_frame
	inv = root.get_node("Inv")
	learning = root.get_node("Learning")
	save_game = root.get_node("SaveGame")

	save_game.clear()
	inv.reset()

	_round_trips_items_and_coins()
	_autosaves_without_an_explicit_quit()
	_v1_save_still_loads()
	_learning_save_does_not_clobber_the_bag()

	save_game.clear()
	inv.reset()
	_finish()


func _round_trips_items_and_coins() -> void:
	inv.reset()
	inv.add("spore_cap", 3)
	inv.add("rice_ball", 2)
	inv.add_coins(137)

	var snapshot: Dictionary = save_game.build_snapshot({}, Vector2(10, 20), "left", inv.to_dict())
	check_eq("snapshot records the new schema version", int(snapshot["version"]), 2)
	check_true("snapshot carries an inventory section", snapshot.has("inventory"))

	# Wipe the live bag, then restore from the snapshot the way world.gd does.
	inv.reset()
	check_eq("bag is empty after reset", inv.count("spore_cap"), 0)
	var restored: Dictionary = save_game.apply_snapshot(snapshot)
	inv.load_dict(restored["inventory"])

	check_eq("items survive the round trip", inv.count("spore_cap"), 3)
	check_eq("second stack survives too", inv.count("rice_ball"), 2)
	check_eq("coins survive the round trip", inv.coins, 137)


## The bag must persist on change, not only on a clean quit — a crash should not cost an hour.
func _autosaves_without_an_explicit_quit() -> void:
	save_game.clear()
	inv.reset()
	inv.add("kappa_scale", 2)
	inv.add_coins(40)
	# No save_snapshot() call at all: only the autosave on inventory_changed has run.
	check_true("a save file exists without an explicit save", save_game.has_save())

	var doc: Dictionary = save_game.load_snapshot()
	var bag: Dictionary = doc.get("inventory", {})
	check_true("the autosaved document has an inventory section", not bag.is_empty())
	inv.reset()
	inv.load_dict(bag)
	check_eq("autosaved items come back", inv.count("kappa_scale"), 2)
	check_eq("autosaved coins come back", inv.coins, 40)


## A pre-inventory save has no "inventory" key; it must load as an empty bag, not crash.
func _v1_save_still_loads() -> void:
	var v1 := {
		"version": 1,
		"learning": {"flags": {"quest_stock_the_stall_started": true}},
		"world": {"player": {"x": 5.0, "y": 6.0, "facing": "up"}},
	}
	var restored: Dictionary = save_game.apply_snapshot(v1)
	check_true("a v1 document still unpacks", restored.has("inventory"))
	check_true("its inventory reads as empty", (restored["inventory"] as Dictionary).is_empty())
	check_eq("its player placement is preserved", restored["position"], Vector2(5.0, 6.0))
	check_true("its learning flags are preserved",
		(restored["learning"] as Dictionary).get("flags", {}).has("quest_stock_the_stall_started"))


## Learning saves fire constantly (every review). They must not wipe the bag.
func _learning_save_does_not_clobber_the_bag() -> void:
	save_game.clear()
	inv.reset()
	inv.add("spore_cap", 3)          # autosaves the bag
	save_game.save_profile({"stats": {"xp": 250}})   # a mid-session learning write

	var doc: Dictionary = save_game.load_snapshot()
	var bag: Dictionary = doc.get("inventory", {})
	inv.reset()
	inv.load_dict(bag)
	check_eq("the bag survives a learning-only save", inv.count("spore_cap"), 3)
	check_eq("and the learning section was written", int(doc["learning"]["stats"]["xp"]), 250)


func _finish() -> void:
	print("")
	print(("PASS — the bag persists, autosaves, and old saves still load."
		if failures == 0 else "FAIL — %d persistence check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + label + ("" if ok else "  (got %s, want %s)" % [got, want]))
	if not ok:
		failures += 1
