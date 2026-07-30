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
	_village_mako_is_linked_to_the_stall()
	await _accept_then_gather_then_turn_in()
	await _reward_is_paid_only_once()
	await _woods_quiet_steps_pays_once()

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


func _village_mako_is_linked_to_the_stall() -> void:
	var village: Node = load("res://src/scenes/world.tscn").instantiate()
	var mako: Node = village.find_child("QuestGiver", true, false)
	check_true("the playable village contains Mako", mako != null)
	check_eq("village Mako unlocks the starter stall", mako.get("shop_id"), "mako_stall")
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


func _finish() -> void:
	print("")
	print(("PASS — quests accept, track from the bag, consume, and pay once."
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
