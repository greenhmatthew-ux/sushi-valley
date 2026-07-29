extends SceneTree
## Readable signs: the world itself introducing vocabulary.
##
##   godot --headless --path . --script res://tests/test_sign_post.gd
##
## The load-bearing rule here is unlock-ONCE. A sign is re-readable with no quiz and no
## fail state, so if reading it kept touching the card the player could farm a signpost for
## free progress and wreck their own review spacing. This pins that re-reads are inert.
##
## Autoloads are fetched via root.get_node() because this entry script is parsed before
## they register (same reason as smoke_autoloads.gd).

var failures: int = 0
var sign_post: Node
var bus: Node
var learning: Node
var save_game: Node


func _initialize() -> void:
	await process_frame
	bus = root.get_node("Bus")
	learning = root.get_node("Learning")
	save_game = root.get_node("SaveGame")

	# Stand in for DialogueBox: close immediately so `await Bus.dialogue_closed` returns.
	bus.dialogue_open.connect(func(_speaker, _lines): bus.dialogue_closed.emit.call_deferred())

	sign_post = load("res://src/entities/sign_post.tscn").instantiate()
	sign_post.sign_id = "test_sign"
	sign_post.japanese = "きた　の　とりい"
	sign_post.english = "North torii gate"
	sign_post.teaches_card = "kana-ki"
	root.add_child(sign_post)
	await process_frame

	save_game.clear()
	learning.reload()

	await _first_read_unlocks()
	await _reread_does_not_regrade()
	await _sign_without_a_card_still_reads()

	save_game.clear()
	_finish()


func _first_read_unlocks() -> void:
	check_true("card starts locked", not _card().get("unlocked", false))
	await sign_post.interact(null)
	check_true("reading the sign unlocks its card", _card().get("unlocked", false))


## Re-reading must not touch the schedule at all — no review, no interval change.
func _reread_does_not_regrade() -> void:
	var before := _card().duplicate(true)
	await sign_post.interact(null)
	await sign_post.interact(null)
	var after := _card()
	check_eq("re-read leaves dueAt untouched", after.get("dueAt"), before.get("dueAt"))
	check_eq("re-read leaves interval untouched", after.get("intervalDays"), before.get("intervalDays"))
	check_eq("re-read adds no correct count", after.get("correctCount"), before.get("correctCount"))
	check_eq("re-read adds no incorrect count", after.get("incorrectCount"), before.get("incorrectCount"))


## A decorative sign with no card attached should still be readable, not error.
func _sign_without_a_card_still_reads() -> void:
	var plain: Node = load("res://src/entities/sign_post.tscn").instantiate()
	plain.japanese = "むら"
	plain.english = "village"
	plain.teaches_card = ""
	root.add_child(plain)
	await process_frame
	await plain.interact(null)
	check_true("a card-less sign reads without error", true)
	plain.queue_free()


func _card() -> Dictionary:
	return learning.profile.card("kana-ki")


func _finish() -> void:
	print("")
	print(("PASS — signs teach a word once and never re-grade it."
		if failures == 0 else "FAIL — %d sign check(s) failed." % failures))
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
