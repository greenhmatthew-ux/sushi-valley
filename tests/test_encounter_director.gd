extends SceneTree
## Single-active-encounter ownership and token filtering.
##
## The director is instantiated from a local preload so this test exercises the
## script itself without depending on global class-cache state or project autoload
## order. Bus remains the real autoload because its signals are the public seam.

const EncounterDirectorType = preload("res://src/autoload/encounter_director.gd")

var failures: int = 0
var director: EncounterDirectorType
var bus: Node
var requests: Array = []
var resolutions: Array = []
var starts: Array[String] = []
var ends: Array[bool] = []


func _initialize() -> void:
	await process_frame
	bus = root.get_node("Bus")
	director = EncounterDirectorType.new()
	director.name = "EncounterDirectorUnderTest"
	root.add_child(director)

	bus.combat_requested.connect(func(token: String, enemy_id: String) -> void:
		requests.append([token, enemy_id]))
	bus.combat_resolved.connect(func(token: String, victory: bool) -> void:
		resolutions.append([token, victory]))
	bus.combat_started.connect(func(enemy_id: String) -> void:
		starts.append(enemy_id))
	bus.combat_ended.connect(func(victory: bool) -> void:
		ends.append(victory))

	await _single_owner_contract()
	await _vanished_owner_contract()
	_runtime_owners_use_tokens()
	director.queue_free()
	await process_frame
	_finish()


func _single_owner_contract() -> void:
	var owner_a := Node.new()
	owner_a.name = "OwnerA"
	root.add_child(owner_a)
	var owner_b := Node.new()
	owner_b.name = "OwnerB"
	root.add_child(owner_b)

	check_eq("blank enemy ids are rejected", director.request("   ", owner_a), "")
	var token_a := director.request("mushroom", owner_a)
	var rejected := director.request("bat", owner_b)
	check_true("the first request receives an opaque token", not token_a.is_empty())
	check_eq("a simultaneous request is rejected", rejected, "")
	check_true("the accepted request owns the slot", director.is_busy())
	check_eq("the active token is queryable", director.active_token(), token_a)
	check_eq("dispatch is deferred until the requester can await", requests.size(), 0)

	await process_frame
	check_eq("only the accepted request is dispatched",
		requests, [[token_a, "mushroom"]])
	check_eq("legacy start remains a single lifecycle notification",
		starts, ["mushroom"])

	check_true("a wrong token cannot resolve the fight",
		not director.resolve("encounter-not-active", true))
	check_true("wrong-token resolution leaves the slot owned", director.is_busy())
	check_eq("wrong-token resolution emits no outcome", resolutions.size(), 0)

	director.call_deferred("resolve", token_a, true)
	var victory: bool = await director.wait_for_result(token_a)
	# The matching coroutine resumes during combat_resolved emission; yield once so
	# resolve() can finish its following legacy lifecycle notification too.
	await process_frame
	check_true("the matching waiter receives victory", victory)
	check_eq("the tokenized result identifies its owner",
		resolutions, [[token_a, true]])
	check_eq("legacy end remains a single lifecycle notification", ends, [true])
	check_true("matching resolution releases the slot", not director.is_busy())
	check_eq("the released director exposes no active token", director.active_token(), "")

	var token_b := director.request("bat", owner_b)
	check_true("a later encounter can start", not token_b.is_empty())
	check_true("tokens are not reused", token_b != token_a)
	await process_frame
	director.call_deferred("resolve", token_b, false)
	var second_victory: bool = await director.wait_for_result(token_b)
	await process_frame
	check_true("the next owner receives its own defeat", not second_victory)
	check_eq("the second result keeps its distinct token",
		resolutions, [[token_a, true], [token_b, false]])
	check_eq("lifecycle outcomes preserve request order", ends, [true, false])

	owner_a.queue_free()
	owner_b.queue_free()
	await process_frame


func _vanished_owner_contract() -> void:
	var owner := Node.new()
	owner.name = "VanishingOwner"
	root.add_child(owner)
	var request_count := requests.size()
	var start_count := starts.size()
	var token := director.request("kappa", owner)
	check_true("a live owner can reserve before dispatch", not token.is_empty())
	owner.free()
	await process_frame
	check_true("a vanished owner releases its reservation", not director.is_busy())
	check_eq("a vanished owner never opens combat", requests.size(), request_count)
	check_eq("a vanished owner emits no start notification", starts.size(), start_count)


func _runtime_owners_use_tokens() -> void:
	var enemy_source := FileAccess.get_file_as_string("res://src/entities/enemy.gd")
	var raid_source := FileAccess.get_file_as_string("res://src/entities/raid_teacher.gd")
	var panel_source := FileAccess.get_file_as_string("res://src/ui/combat_panel.gd")
	check_true("overworld enemies reserve an encounter token",
		enemy_source.contains("EncounterDirector.request(enemy_id, self)"))
	check_true("overworld enemies await only their matching token",
		enemy_source.contains("EncounterDirector.wait_for_result(token)")
		and not enemy_source.contains("await Bus.combat_ended"))
	check_true("Raid bosses use the same owned encounter path",
		raid_source.contains("EncounterDirector.request(encounter_id, self)")
		and raid_source.contains("EncounterDirector.wait_for_result(token)"))
	check_true("the combat panel accepts tokenized commands",
		panel_source.contains("Bus.combat_requested.connect(_on_combat_requested)"))
	check_true("the combat panel resolves the matching token",
		panel_source.contains("EncounterDirector.resolve(token, victory)")
		and not panel_source.contains("Bus.combat_ended.emit(victory)"))


func _finish() -> void:
	print("")
	print("PASS - encounter tokens enforce one active owner." if failures == 0 \
		else "FAIL - %d encounter-director check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
