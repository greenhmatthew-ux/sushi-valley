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

	check("items", db.items.size(), 172)
	check("enemies", db.enemies.size(), 76)
	check("abilities", db.abilities.size(), 68)
	check("recipes", db.recipes.size(), 84)
	check("quests", db.quests.size(), 24)
	check("crops", db.crops.size(), 4)
	check("expeditions", db.expeditions.size(), 1)
	check("raids", db.raids.size(), 1)
	check("regions", db.regions.size(), 12)
	check("lessons", db.lessons.size(), 138)
	check("learning_content", db.learning_content.size(), 17)
	var tool_quest: Dictionary = db.quest("tools_of_the_trail")
	check("tool quest objectives", tool_quest.get("objectives", []).size(), 3)
	check_true("tool commission rewards the Trailblazer Charm",
		tool_quest.get("reward", {}).get("items", []).any(
			func(entry): return entry.get("id", "") == "trailblazer_charm"))
	check_true("Trailblazer Charm is a unique amulet",
		db.item("trailblazer_charm").get("slot", "") == "amulet"
		and bool(db.item("trailblazer_charm").get("unique", false)))
	var morning_quest: Dictionary = db.quest("valley_morning")
	check("Valley Morning objectives", morning_quest.get("objectives", []).size(), 3)
	check_true("Valley Morning uses the three authored daily activity counters",
		morning_quest.get("objectives", []).map(
			func(row): return String(row.get("activity", ""))) \
			== [LearningProfile.ACTIVITY_FARM_HARVEST,
				LearningProfile.ACTIVITY_RESOURCE_GATHER,
				LearningProfile.ACTIVITY_FISH_CATCH])
	check_true("Valley Morning links to one real follow-up quest",
		String(morning_quest.get("followUpQuest", "")) == "ready_for_the_road"
		and not db.quest("ready_for_the_road").is_empty())
	var road_quest: Dictionary = db.quest("ready_for_the_road")
	check("Ready for the Road objectives", road_quest.get("objectives", []).size(), 3)
	check_true("the follow-up joins learning, crafting, and combat",
		road_quest.get("objectives", []).map(
			func(row): return String(row.get("activity", ""))) \
			== [LearningProfile.ACTIVITY_REVIEW_CORRECT,
				LearningProfile.ACTIVITY_CRAFT_COMPLETE,
				LearningProfile.ACTIVITY_ENEMY_DEFEAT])

	# Keyed-object tables keep their authored shape rather than being indexed.
	check_true("shops has mako_stall", db.shops.has("mako_stall"))
	check_true("world_events has events", db.world_events.has("events"))

	# Region status is player-facing truth: only scenes that can actually be
	# entered in this build may advertise themselves as playable.
	var playable_regions: Array[String] = []
	var planned_regions: Array[String] = []
	for raw_id: Variant in db.regions:
		var region_id := String(raw_id)
		var status := String(db.regions[raw_id].get("status", ""))
		if status == "playable":
			playable_regions.append(region_id)
		elif status == "planned":
			planned_regions.append(region_id)
	playable_regions.sort()
	planned_regions.sort()
	# Checked against the scene files rather than a fixed list of names: a region
	# added later cannot advertise itself as playable without one, and this does not
	# have to be edited every time the world grows.
	var region_scenes := {
		"valley_crossroads": "res://src/scenes/world.tscn",
		"whispering_woods": "res://src/scenes/wilds.tscn",
		"mountain_pass": "res://src/scenes/mountain_pass.tscn",
	}
	var unbuilt: Array[String] = []
	for region_id in playable_regions:
		var scene_path := String(region_scenes.get(region_id, ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			unbuilt.append(region_id)
	check_true("every playable region has a scene to enter (%s)" % str(unbuilt),
		unbuilt.is_empty())
	var advertised: Array[String] = []
	for region_id in planned_regions:
		if region_scenes.has(region_id):
			advertised.append(region_id)
	check_true("a region with a scene is not still called planned (%s)" % str(advertised),
		advertised.is_empty())
	check("regions accounted for as playable or planned",
		playable_regions.size() + planned_regions.size(), db.regions.size())

	# 62 hand-authored cards + 1330 deck rows across 11 packs, with zero id
	# collisions (verified against the source JSON). An exact number here catches
	# a pack that silently failed to load OR one that started shadowing ids.
	check("cards", db.cards.size(), 1392)
	check_true("card_order matches cards", db.card_order.size() == db.cards.size())
	check("pronunciation clips", db.pronunciation_clips.size(), 366)
	check("pronunciation card mappings", db.pronunciation_cards.size(), 459)
	check_str("pronunciation provider",
		db.pronunciation_source.get("provider", ""), "Kanji alive")

	# Spot-check real content, not just counts — a loader that returns empty
	# dictionaries would pass size checks on an empty table otherwise.
	check_str("item wooden_katana", db.item("wooden_katana").get("name", ""), "Wooden Katana")
	check_str("item bamboo_tonic", db.item("bamboo_tonic").get("name", ""),
		"Bamboo Breeze Tonic")
	var missing_item_icons: Array[String] = []
	for item_id in db.item_order:
		var item: Dictionary = db.items[item_id]
		if not bool(item.get("icon", false)):
			continue
		var icon_id := String(item.get("iconAlias", item_id))
		if not ResourceLoader.exists("res://assets/icons/items/%s.png" % icon_id):
			missing_item_icons.append(item_id)
	check_true("all icon-enabled items resolve real art (%s)" % [str(missing_item_icons)],
		missing_item_icons.is_empty())
	check_str("enemy mushroom", db.enemy("mushroom").get("name", ""), "Spore Mushroom")
	check_str("ability strike", db.ability("strike").get("name", ""), "Strike")
	var woods_quest: Dictionary = db.quest("woods_quiet_steps")
	check_true("Whispering Woods quest exists", not woods_quest.is_empty())
	check_str("Woods quest goal",
		woods_quest.get("goal", {}).get("item", ""), "raccoon_tail")
	check("Woods quest coin reward",
		int(woods_quest.get("reward", {}).get("coins", 0)), 25)
	check_str("card kana-a prompt", db.card("kana-a").get("prompt", ""), "あ")
	var pronunciation: Dictionary = db.pronunciation_for_card(
		"core-2k6k-optimized-japanese-vocabulary-with-sound-part-01-2")
	check_true("pronunciation lookup resolves a known card", not pronunciation.is_empty())
	check_true("pronunciation lookup has a shipped OGG",
		String(pronunciation.get("path", "")).ends_with(".ogg"))
	# Kana used to be silent because Kanji alive is a word-level source with no
	# coverage for a bare あ. It now speaks, using a recording of the same character
	# from an imported kana deck — but the word-level source still must not be the
	# one claiming that coverage.
	var kana_audio: Dictionary = db.pronunciation_for_card("kana-a")
	check_true("kana is no longer silent", not kana_audio.is_empty())
	check_true("kana is not voiced by the word-level licensed source",
		not db.pronunciation_cards.has("kana-a"))
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
