extends SceneTree
## Slice 0 smoke test: prove every content table loads out of res://data.
##
## Run: godot --headless --path D:\SushiValleyGodot --script res://tests/smoke_db.gd
##
## DB is instantiated by hand rather than read off the autoload. That is
## deliberate: it proves the loader has no hidden autoload coupling and lets the
## test assert exact load-time state, independent of the boot sequence.

var failures: int = 0


func _initialize() -> void:
	var db: Node = load("res://src/autoload/db.gd").new()
	db.load_all()   # not add_child(): _ready() is deferred and would run too late

	check("items", db.items.size(), 167)
	check("enemies", db.enemies.size(), 76)
	check("abilities", db.abilities.size(), 68)
	check("recipes", db.recipes.size(), 78)
	check("quests", db.quests.size(), 18)
	check("crops", db.crops.size(), 4)
	check("expeditions", db.expeditions.size(), 1)
	check("raids", db.raids.size(), 1)
	check("regions", db.regions.size(), 12)
	check("lessons", db.lessons.size(), 138)
	check("learning_content", db.learning_content.size(), 17)

	# Keyed-object tables keep their authored shape rather than being indexed.
	check_true("shops has mako_stall", db.shops.has("mako_stall"))
	check_true("world_events has events", db.world_events.has("events"))

	# 62 hand-authored cards + 1330 deck rows across 11 packs, with zero id
	# collisions (verified against the source JSON). An exact number here catches
	# a pack that silently failed to load OR one that started shadowing ids.
	check("cards", db.cards.size(), 1392)
	check_true("card_order matches cards", db.card_order.size() == db.cards.size())

	# Spot-check real content, not just counts — a loader that returns empty
	# dictionaries would pass size checks on an empty table otherwise.
	check_str("item wooden_katana", db.item("wooden_katana").get("name", ""), "Wooden Katana")
	check_str("enemy mushroom", db.enemy("mushroom").get("name", ""), "Spore Mushroom")
	check_str("ability strike", db.ability("strike").get("name", ""), "Strike")
	check_str("card kana-a prompt", db.card("kana-a").get("prompt", ""), "あ")
	check_true("lesson kana-vowels exists", db.lessons.has("kana-vowels"))
	check_true("lesson kana-vowels has cards",
		(db.lesson("kana-vowels").get("cardIds", []) as Array).size() > 0)

	# Authored order is preserved (the Compendium depends on it).
	check_true("first enemy in table order is mushroom",
		db.enemy_order.size() > 0 and db.enemy_order[0] == "mushroom")

	# Source-pack attribution survived the flattening.
	var sourced: Dictionary = db.card("hiragana-a") if db.cards.has("hiragana-a") else {}
	if sourced.is_empty():
		# Find any card that came from a deck rather than cards.json.
		for id in db.card_order:
			if db.cards[id].has("source"):
				sourced = db.cards[id]
				break
	check_true("some card carries deck attribution", sourced.has("source"))

	db.free()

	print("")
	if failures == 0:
		print("PASS — all content tables loaded.")
	else:
		print("FAIL — %d check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check(label: String, got: int, want: int) -> void:
	check_true("%s = %d (want %d)" % [label, got, want], got == want)


func check_str(label: String, got: String, want: String) -> void:
	check_true("%s = '%s'" % [label, got], got == want and not got.is_empty())


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
