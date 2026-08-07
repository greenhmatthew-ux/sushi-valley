extends SceneTree
## The real quest loop, end to end: accept -> gather -> turn in -> paid.
##
##   godot --headless --path . --script res://tests/test_quest_giver.gd
##
## Drives the live QuestGiver against an authored quest from data/game/quests.json, with a
## fake dialogue responder standing in for DialogueBox. The pure stage/template helpers are
## covered by test_quest.gd; this pins the wiring the player actually experiences:
##
##   - progress is read from the BAG, so drops count automatically
##   - turn-in CONSUMES the goal items (otherwise one stack completes every fetch quest)
##   - the reward is paid exactly once, no matter how many times you talk afterwards
##
## Also checks LootLogic against the authored drop table, because the quest is only
## completable if the mushroom actually yields spore caps.

var failures: int = 0
var giver: Node
var bus: Node
var inv: Node
var learning: Node
var db: Node
var save_game: Node
var opened_shop := ""


func _initialize() -> void:
	await process_frame
	bus = root.get_node("Bus")
	inv = root.get_node("Inv")
	learning = root.get_node("Learning")
	db = root.get_node("DB")
	save_game = root.get_node("SaveGame")

	bus.dialogue_open.connect(func(_s, _l): bus.dialogue_closed.emit.call_deferred())
	bus.shop_open.connect(func(id: String): opened_shop = id)

	giver = load("res://src/entities/quest_giver.tscn").instantiate()
	giver.quest_id = "stock_the_stall"
	giver.shop_id = "mako_stall"
	root.add_child(giver)
	await process_frame

	save_game.clear()
	learning.reload()
	inv.reset()

	_drop_table_can_supply_the_goal()
	_mako_stocks_each_starter_weapon_style()
	_mako_stocks_every_authored_crop_seed()
	_village_mako_is_linked_to_the_stall()
	await _accept_then_gather_then_turn_in()
	await _reward_is_paid_only_once()
	await _woods_quiet_steps_pays_once()
	await _tool_commission_preserves_the_field_kit()
	await _valley_morning_counts_real_daily_actions()

	save_game.clear()
	_finish()


## The quest asks for spore caps; the mushroom's authored table must actually produce them,
## or the objective is unreachable no matter how the dialogue behaves.
func _drop_table_can_supply_the_goal() -> void:
	var table: Array = db.enemy("mushroom").get("drops", [])
	var guaranteed := LootLogic.roll(table, [0.99, 0.99, 0.99])   # only chance 1.0 passes
	check_true("mushroom always drops the quest item", guaranteed.has("spore_cap"))
	var everything := LootLogic.roll(table, [0.0, 0.0, 0.0])      # every chance passes
	check_true("lucky kill can drop extras too", everything.size() > 1)
	var nothing := LootLogic.roll([{"item": "x", "chance": 0.0}], [0.0])
	check_eq("chance 0 never drops", nothing.size(), 0)

	var racoon_table: Array = db.enemy("racoon").get("drops", [])
	var racoon_guaranteed := LootLogic.roll(
		racoon_table, [0.99, 0.99, 0.99, 0.99])
	check_true("racoon always drops a raccoon tail",
		racoon_guaranteed.has("raccoon_tail"))


## The permanent talent choices each require a weapon family. Mako's first unlocked shop
## must offer one honest starter for every family, rather than presenting dead build choices.
func _mako_stocks_each_starter_weapon_style() -> void:
	var styles := {}
	for entry in db.shops.get("mako_stall", {}).get("stock", []):
		var item: Dictionary = db.item(String(entry.get("item", "")))
		if String(item.get("slot", "")) == "weapon":
			styles[String(item.get("weaponType", ""))] = true
	check_eq("Mako stocks blade, heavy, ranged, and kana starters",
		styles.size(), 4)
	for style in ["blade", "heavy", "ranged", "kana"]:
		check_true("Mako stocks a %s starter" % style, styles.has(style))


## Once Stock the Stall is complete, farming must remain a repeatable economy
## rather than ending when the one-time starter cache is empty. The archived
## Valley store priced staple stock at 2x item value; keep that balance contract.
func _mako_stocks_every_authored_crop_seed() -> void:
	var seed_prices := {}
	for entry in db.shops.get("mako_stall", {}).get("stock", []):
		var item_id := String(entry.get("item", ""))
		if String(db.item(item_id).get("kind", "")) == "seed":
			seed_prices[item_id] = int(entry.get("price", 0))
	check_eq("Mako stocks one seed for every crop", seed_prices.size(), db.crops.size())
	for crop in db.crops.values():
		var seed_id := String((crop as Dictionary).get("seedItem", ""))
		check_true("Mako stocks %s" % seed_id, seed_prices.has(seed_id))
		check_eq("%s keeps the archived 2x-value markup" % seed_id,
			int(seed_prices.get(seed_id, 0)), int(db.item(seed_id).get("value", 0)) * 2)


func _village_mako_is_linked_to_the_stall() -> void:
	var village: Node = load("res://src/scenes/world.tscn").instantiate()
	var mako: Node = village.find_child("QuestGiverMako", true, false)
	check_true("the playable village contains Mako", mako != null)
	check_eq("village Mako unlocks the starter stall", mako.get("shop_id"), "mako_stall")
	# She ran on the export defaults for a long time, which is why an audit of explicit
	# `quest_id =` assignments reported her quest as reachable by nobody. State it outright.
	check_eq("village Mako offers her authored quest", mako.get("quest_id"), "stock_the_stall")
	check_eq("village Mako is named in the scene", mako.get("speaker"), "Mako")
	var stall: Node = village.find_child("MakoStall", true, false)
	check_true("Mako has a stall to stock", stall != null)
	check_true("the stall stands within a tile of her pitch",
		stall != null and (stall.get("position") as Vector2).distance_to(
			mako.get("position") as Vector2) <= 32.0)
	village.free()


func _accept_then_gather_then_turn_in() -> void:
	check_eq("starts unaccepted", giver.current_stage(), "intro")

	await giver.interact(null)
	check_true("talking accepts the quest", giver.is_accepted())
	check_eq("with nothing gathered it is active", giver.current_stage(), "active")
	check_eq("progress starts at zero", giver.progress(), 0)

	# Gather one short of the goal.
	inv.add("spore_cap", giver.goal_qty() - 1)
	check_eq("partial progress is reported", giver.progress(), giver.goal_qty() - 1)
	check_eq("and it is still active", giver.current_stage(), "active")

	# The last one flips it to ready.
	inv.add("spore_cap", 1)
	check_eq("goal met -> turnin", giver.current_stage(), "turnin")

	var coins_before: int = inv.coins
	await giver.interact(null)

	check_true("turn-in marks it complete", giver.is_complete())
	check_eq("goal items are consumed", inv.count("spore_cap"), 0)
	check_true("coins were paid", inv.coins > coins_before)
	# The authored reward includes items, not just coins.
	var reward: Dictionary = db.quest("stock_the_stall").get("reward", {})
	for entry in reward.get("items", []):
		var id := String(entry.get("id", ""))
		check_true("reward item %s was granted" % id, inv.count(id) >= int(entry.get("qty", 1)))


## Talking again after completion must not pay a second time — the flag, not the bag, decides.
func _reward_is_paid_only_once() -> void:
	var coins_before: int = inv.coins
	inv.add("spore_cap", giver.goal_qty())   # even holding the items again
	opened_shop = ""
	await giver.interact(null)
	check_eq("completed Mako opens her stocked stall", opened_shop, "mako_stall")
	check_eq("no second payout", inv.coins, coins_before)
	check_eq("and the items are not re-consumed", inv.count("spore_cap"), giver.goal_qty())
	check_eq("stage stays done", giver.current_stage(), "done")


## The Whispering Woods route ends in one small, complete fetch loop: the local
## racoon supplies the item, Trail Ranger consumes one, and the authored reward
## is granted exactly once.
func _woods_quiet_steps_pays_once() -> void:
	var ranger: Node = load("res://src/entities/quest_giver.tscn").instantiate()
	ranger.quest_id = "woods_quiet_steps"
	root.add_child(ranger)
	await process_frame

	check_eq("Woods quest starts unaccepted", ranger.current_stage(), "intro")
	await ranger.interact(null)
	check_true("Trail Ranger accepts the Woods quest", ranger.is_accepted())
	check_eq("Woods quest starts at zero progress", ranger.progress(), 0)

	inv.add("raccoon_tail", 1)
	check_eq("one raccoon tail completes the objective",
		ranger.current_stage(), "turnin")

	var coins_before: int = inv.coins
	var sandals_before: int = inv.count("straw_sandals")
	await ranger.interact(null)
	check_true("Woods quest is marked complete", ranger.is_complete())
	check_eq("turn-in consumes exactly one raccoon tail",
		inv.count("raccoon_tail"), 0)
	check_eq("Woods quest pays exactly 25 coins",
		inv.coins, coins_before + 25)
	check_eq("Woods quest grants exactly one pair of straw sandals",
		inv.count("straw_sandals"), sandals_before + 1)

	var paid_coins: int = inv.coins
	var paid_sandals: int = inv.count("straw_sandals")
	inv.add("raccoon_tail", 1)
	await ranger.interact(null)
	check_eq("completed Woods quest pays no second coins", inv.coins, paid_coins)
	check_eq("completed Woods quest grants no second sandals",
		inv.count("straw_sandals"), paid_sandals)
	check_eq("completed Woods quest does not consume another tail",
		inv.count("raccoon_tail"), 1)
	ranger.queue_free()


## Kaji's commission is the first objective-list quest. All three permanent
## tools must be present at once, but inspection never consumes them.
func _tool_commission_preserves_the_field_kit() -> void:
	var kaji: Node = load("res://src/entities/quest_giver.tscn").instantiate()
	kaji.quest_id = "tools_of_the_trail"
	root.add_child(kaji)
	await process_frame

	check_eq("Kaji's tool commission starts unaccepted", kaji.current_stage(), "intro")
	await kaji.interact(null)
	check_true("talking to Kaji accepts the checklist", kaji.is_accepted())
	check_eq("the checklist begins with the Copper Pick", kaji.goal_item(), "copper_pick")
	check_eq("Kaji exposes three live objective rows", kaji.objectives().size(), 3)

	inv.add("copper_pick", 1)
	check_eq("finishing the pick advances to the Trail Hatchet",
		kaji.goal_item(), "trail_hatchet")
	inv.add("trail_hatchet", 1)
	check_eq("finishing the hatchet advances to the Herb Sickle",
		kaji.goal_item(), "herb_sickle")
	inv.add("herb_sickle", 1)
	check_eq("the complete field kit is ready for inspection",
		kaji.current_stage(), "turnin")

	var coins_before: int = inv.coins
	var charm_before: int = inv.count("trailblazer_charm")
	await kaji.interact(null)
	# Kaji now heads a chain, so `is_complete()` reports on whatever he offers *next*.
	# The finished quest is asserted by its own flag, the same way Aiko's chain is below.
	check_true("Kaji marks the tool commission complete",
		learning.profile.get_flag(QuestJournal.done_flag("tools_of_the_trail")))
	for tool_id in ["copper_pick", "trail_hatchet", "herb_sickle"]:
		check_eq("inspection preserves %s" % tool_id, inv.count(tool_id), 1)
	check_eq("the commission pays its exact coin reward", inv.coins, coins_before + 75)
	check_eq("the commission grants its unique Trailblazer Charm",
		inv.count("trailblazer_charm"), charm_before + 1)
	var charm: Dictionary = db.item("trailblazer_charm")
	check_true("the signature reward is useful immediately",
		charm.get("slot", "") == "amulet"
		and int(charm.get("stats", {}).get("spd", 0)) == 1)

	# The field kit is the apprenticeship; the smithing commissions follow from it. Both
	# were authored long ago and unreachable until this chain pointed at them.
	check_eq("the same Kaji now leads with his smithing commission",
		kaji.active_quest_id(), "smiths_first_order")
	check_eq("the commission waits for a new acceptance", kaji.current_stage(), "intro")

	var paid_coins: int = inv.coins
	await kaji.interact(null)
	check_eq("accepting the commission cannot repay the field kit", inv.coins, paid_coins)
	check_eq("the completed checklist pays no second charm",
		inv.count("trailblazer_charm"), charm_before + 1)
	check_true("Kaji accepts A Smith's First Order", kaji.is_accepted())
	check_eq("the commission asks for the refined ingot, not raw ore",
		kaji.goal_item(), "iron_ingot")

	# Iron ore was unobtainable more than once before this slice, so this step could be
	# accepted and never finished. Renewable seams now back it — see test_smithing_chain.
	inv.add("iron_ingot", 1)
	check_eq("a smelted ingot readies the commission", kaji.current_stage(), "turnin")
	await kaji.interact(null)
	check_true("Kaji marks the smithing commission complete",
		learning.profile.get_flag(QuestJournal.done_flag("smiths_first_order")))
	check_eq("turn-in consumes the delivered ingot", inv.count("iron_ingot"), 0)
	check_eq("the line continues to the alloy test",
		kaji.active_quest_id(), "kaji_copper_testing")
	kaji.queue_free()


## The first typed activity quest proves the actual farm, resource, and fishing
## coordinators advance persisted rows only after acceptance. Nothing is faked by
## adding goal items directly to the Bag.
func _valley_morning_counts_real_daily_actions() -> void:
	var aiko: Node = load("res://src/entities/quest_giver.tscn").instantiate()
	aiko.quest_id = "valley_morning"
	root.add_child(aiko)
	await process_frame

	# Old lifetime activity must be excluded by the acceptance baseline.
	for activity_id in LearningProfile.ACTIVITY_IDS:
		learning.profile.record_activity(String(activity_id), 2)
	learning.profile.save()
	await aiko.interact(null)
	check_true("Aiko accepts the daily activity quest", aiko.is_accepted())
	check_eq("all pre-acceptance activity is excluded",
		aiko.objectives().map(func(row): return row["progress"]), [0, 0, 0])

	var farm: Node = root.get_node("Farm")
	var gathering: Node = root.get_node("Gathering")
	var fishing: Node = root.get_node("Fishing")
	farm.reset(false)
	gathering.reset(false)
	fishing.reset_site("quest_test_pond", false)
	inv.add("herb_seed", 1)
	check_true("the quest crop plants through the real farm transaction",
		bool(farm.plant("quest_test_plot", "herb").get("ok", false)))
	farm.advance_day()
	check_true("the real harvest advances the first activity row",
		bool(farm.harvest("quest_test_plot").get("ok", false)))
	check_eq("harvest advances to the resource objective",
		aiko.goal_label(), "Gather a resource node")

	var gathered: Dictionary = gathering.gather(
		"quest_test_patch", "wild_herb", 1, 1, "kitchen", 1, "herb")
	check_true("the real renewable node advances the second row",
		bool(gathered.get("ok", false)))
	check_eq("gathering advances to the fishing objective",
		aiko.goal_label(), "Land a fish")

	var caught: Dictionary = fishing.complete(
		"quest_test_pond", 2, "normal", 120, 0.1, 1000.0)
	check_true("the real fishing reward advances the final row",
		bool(caught.get("ok", false)))
	check_eq("all three daily actions ready Aiko's turn-in",
		aiko.current_stage(), "turnin")

	var coins_before: int = inv.coins
	var seeds_before: int = inv.count("herb_seed")
	var fish_before: int = inv.count("river_fish")
	await aiko.interact(null)
	check_true("Aiko marks the morning quest complete",
		learning.profile.get_flag(QuestJournal.done_flag("valley_morning")))
	check_eq("the activity quest pays its exact 60 coins", inv.coins, coins_before + 60)
	check_eq("the activity quest grants two repeatable seeds",
		inv.count("herb_seed"), seeds_before + 2)
	check_eq("turn-in never consumes evidence from an activity objective",
		inv.count("river_fish"), fish_before)
	var paid_coins: int = inv.coins
	check_eq("the same Aiko now leads with the authored follow-up",
		aiko.active_quest_id(), "ready_for_the_road")
	check_eq("the follow-up waits for a new acceptance", aiko.current_stage(), "intro")
	await aiko.interact(null)
	check_eq("accepting the follow-up cannot repay Valley Morning", inv.coins, paid_coins)
	check_true("Aiko accepts Ready for the Road", aiko.is_accepted())
	check_eq("pre-acceptance study, craft, and combat history is excluded",
		aiko.objectives().map(func(row): return row["progress"]), [0, 0, 0])

	learning.profile.unlock_lesson("kana-vowels")
	for card_id in ["kana-a", "kana-i", "kana-u"]:
		var card: Dictionary = learning.profile.card(card_id)
		check_true("a real correct review advances preparation: %s" % card_id,
			learning.progression.answer(card, String(card.get("answer", ""))))
	check_eq("three correct reviews advance to the craft proof",
		aiko.goal_label(), "Craft any recipe")

	inv.add("rice", 2)
	var crafted: Dictionary = root.get_node("Crafting").craft(
		"craft_rice_ball", "kitchen")
	check_true("a real recipe transaction advances the craft proof",
		bool(crafted.get("ok", false)))
	check_eq("crafting advances to the combat proof",
		aiko.goal_label(), "Defeat an enemy")

	bus.enemy_died.emit("mushroom")
	check_eq("a real victory readies the chained quest",
		aiko.current_stage(), "turnin")
	var road_coins_before: int = inv.coins
	var charm_before: int = inv.count("omamori_charm")
	var rice_balls_before: int = inv.count("rice_ball")
	await aiko.interact(null)
	check_true("Aiko completes the full two-quest chain", aiko.is_complete())
	check_eq("Ready for the Road pays exactly 90 coins",
		inv.coins, road_coins_before + 90)
	check_eq("the preparation reward grants one protective omamori",
		inv.count("omamori_charm"), charm_before + 1)
	check_eq("turn-in never consumes the crafted proof",
		inv.count("rice_ball"), rice_balls_before)
	var chain_paid_coins: int = inv.coins
	await aiko.interact(null)
	check_eq("the completed chain cannot pay either reward twice",
		inv.coins, chain_paid_coins)

	farm.reset(false)
	gathering.reset(false)
	fishing.reset_site("quest_test_pond", false)
	aiko.queue_free()


func _finish() -> void:
	print("")
	print(("PASS — quests track items and actions, then pay exactly once."
		if failures == 0 else "FAIL — %d quest check(s) failed." % failures))
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
