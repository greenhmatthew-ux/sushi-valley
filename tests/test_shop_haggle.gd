extends SceneTree
## Ordering in Japanese at a shop: knowledge buys a discount, never access.
##
##   godot --headless --path . --script res://tests/test_shop_haggle.gd
##
## The load-bearing rule is UI_UX_GUIDE principle 7 — "Japanese mastery adds understanding,
## efficiency, optional routes, relationships, and rewards; it never removes basic
## accessibility or the main route." A player who knows no Japanese, or answers wrong, must
## still be able to buy the item at list price. If recall ever blocks a purchase this is a
## gate, not a reward, and the whole design intent is inverted.
##
## Drives the real ShopPanel with a fake recall responder standing in for RecallPanel.

var failures: int = 0
var shop: Node
var bus: Node
var inv: Node
var learning: Node
var db: Node
var save_game: Node

## What the fake recall responder should do next.
var answer_mode := "correct"   # correct | wrong | cancel | nothing


func _initialize() -> void:
	await process_frame
	bus = root.get_node("Bus")
	inv = root.get_node("Inv")
	learning = root.get_node("Learning")
	db = root.get_node("DB")
	save_game = root.get_node("SaveGame")

	bus.learn_open.connect(_fake_recall)

	var ui: Node = load("res://src/ui/ui_layer.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	shop = ui.get_node("ShopPanel")

	save_game.clear()
	learning.reload()
	inv.reset()

	await _correct_answer_discounts()
	await _wrong_answer_pays_full_but_still_buys()
	await _cancelled_recall_still_buys()
	await _beginner_with_nothing_learned_can_still_buy()

	save_game.clear()
	_finish()


func _price_of(item_id: String) -> int:
	for entry in db.shops.get("forest_trader", {}).get("stock", []):
		if String(entry.get("item", "")) == item_id:
			return int(entry.get("price", 0))
	return 0


func _correct_answer_discounts() -> void:
	learning.profile.unlock_lesson("greetings")
	answer_mode = "correct"
	var price: int = _price_of("rice_ball")
	inv.reset()
	inv.add_coins(price * 2)
	var before: int = inv.coins

	await shop._on_buy("rice_ball", price)

	var spent: int = before - inv.coins
	check_eq("correct recall gets the item", inv.count("rice_ball"), 1)
	check_true("correct recall costs less than list price", spent < price)
	var expected: int = maxi(1, int(round(price * (1.0 - shop.HAGGLE_DISCOUNT))))
	check_eq("discount matches HAGGLE_DISCOUNT", spent, expected)


func _wrong_answer_pays_full_but_still_buys() -> void:
	answer_mode = "wrong"
	var price: int = _price_of("rice_ball")
	inv.reset()
	inv.add_coins(price * 2)
	var before: int = inv.coins

	await shop._on_buy("rice_ball", price)

	check_eq("a wrong answer still buys the item", inv.count("rice_ball"), 1)
	check_eq("and pays full list price", before - inv.coins, price)


func _cancelled_recall_still_buys() -> void:
	answer_mode = "cancel"
	var price: int = _price_of("rice_ball")
	inv.reset()
	inv.add_coins(price * 2)
	var before: int = inv.coins

	await shop._on_buy("rice_ball", price)

	check_eq("backing out of the prompt still buys", inv.count("rice_ball"), 1)
	check_eq("at full price, with no penalty", before - inv.coins, price)


## The most important case: someone who has learned nothing at all. They must not be shown a
## prompt they cannot answer, and must not be blocked from shopping.
func _beginner_with_nothing_learned_can_still_buy() -> void:
	save_game.clear()
	learning.reload()          # fresh profile: nothing unlocked
	answer_mode = "nothing"
	var price: int = _price_of("rice_ball")
	inv.reset()
	inv.add_coins(price * 2)
	var before: int = inv.coins

	await shop._on_buy("rice_ball", price)

	check_eq("a beginner can still buy", inv.count("rice_ball"), 1)
	check_eq("at full price", before - inv.coins, price)


# --- fake RecallPanel -------------------------------------------------------

func _fake_recall(lesson: String, size: int, practice: bool) -> void:
	match answer_mode:
		"cancel":
			bus.learn_closed.emit.call_deferred(0, 0, true)
		"nothing":
			bus.learn_closed.emit.call_deferred(0, 0, false)
		"wrong":
			var p: Dictionary = learning.build_prompt({}, practice, lesson)
			if not p.is_empty():
				learning.answer(p["card"], "__definitely_wrong__")
			bus.learn_closed.emit.call_deferred(1, 0, false)
		_:
			var pc: Dictionary = learning.build_prompt({}, practice, lesson)
			if not pc.is_empty():
				learning.answer(pc["card"], String(pc["answer"]))
			bus.learn_closed.emit.call_deferred(1, 1, false)


func _finish() -> void:
	print("")
	print(("PASS — Japanese buys a discount, never access."
		if failures == 0 else "FAIL — %d shop check(s) failed." % failures))
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
