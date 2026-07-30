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


func _initialize() -> void:
	await process_frame
	bus = root.get_node("Bus")
	inv = root.get_node("Inv")
	learning = root.get_node("Learning")
	db = root.get_node("DB")
	save_game = root.get_node("SaveGame")

	bus.dialogue_open.connect(func(_s, _l): bus.dialogue_closed.emit.call_deferred())

	giver = load("res://src/entities/quest_giver.tscn").instantiate()
	giver.quest_id = "stock_the_stall"
	root.add_child(giver)
	await process_frame

	save_game.clear()
	learning.reload()
	inv.reset()

	_drop_table_can_supply_the_goal()
	await _accept_then_gather_then_turn_in()
	await _reward_is_paid_only_once()

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
	await giver.interact(null)
	check_eq("no second payout", inv.coins, coins_before)
	check_eq("and the items are not re-consumed", inv.count("spore_cap"), giver.goal_qty())
	check_eq("stage stays done", giver.current_stage(), "done")


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
