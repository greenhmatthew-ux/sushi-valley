extends SceneTree
## Daily random world events: deterministic, weighted, and actually felt in the world.
##
##   godot --headless --path . --script res://tests/test_world_events.gd
##
## Matthew's content direction: "mostly just content, with staged content being gates to new
## areas, unlocking raids and expeditions in an area, and random events." This is the
## random-events half — the cheapest return-value system the valley can have, because it
## makes the same area worth re-entering tomorrow without needing a new map.
##
## The properties that matter: an event cannot be save-scummed (same day, same event), it
## must not correlate with the weather (or the two read as one system), "nothing special"
## must stay the common case, and the bonus must reach the player's bag.

const Events = preload("res://src/systems/world_event_logic.gd")
const Weather = preload("res://src/systems/weather_logic.gd")

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var db: Node = root.get_node("DB")
	var events: Array = db.events

	check_true("events data loads (%d authored)" % events.size(), events.size() >= 3)

	# --- deterministic: a reloaded day cannot reroll into a better one ---
	var stable := true
	for day in range(1, 40):
		var a: Dictionary = Events.event_for_day(day, events)
		var b: Dictionary = Events.event_for_day(day, events)
		if String(a.get("id", "")) != String(b.get("id", "")):
			stable = false
	check_true("the same day always yields the same event", stable)

	# --- weighted: "nothing special" is the common case ---
	var seen: Dictionary = {}
	var quiet := 0
	var sample := 400
	for day in range(1, sample + 1):
		var e: Dictionary = Events.event_for_day(day, events)
		var id := String(e.get("id", ""))
		seen[id] = int(seen.get(id, 0)) + 1
		if not Events.is_notable(e):
			quiet += 1
	check_true("every authored event can actually occur (%d of %d seen)"
		% [seen.size(), events.size()],
		seen.size() == events.size())
	var quiet_share := float(quiet) / float(sample)
	check_true("an ordinary day is the common case (%.0f%% quiet)" % (quiet_share * 100.0),
		quiet_share > 0.35 and quiet_share < 0.85)

	# --- independent of weather: two systems, not one wearing two hats ---
	var agree := 0
	for day in range(1, 201):
		var wet: bool = Weather.is_raining(Weather.current_weather(day, "spring"))
		var notable: bool = Events.is_notable(Events.event_for_day(day, events))
		if wet == notable:
			agree += 1
	var correlation := absf(float(agree) / 200.0 - 0.5)
	check_true("events do not track the weather (agreement %.0f%%, want ~50%%)"
		% (float(agree) / 2.0),
		correlation < 0.2)

	# --- the bonus is targeted, not blanket ---
	var rich: Dictionary = {}
	for e in events:
		if String((e as Dictionary).get("id", "")) == "rich_seams":
			rich = e
	check_true("rich_seams is authored", not rich.is_empty())
	if not rich.is_empty():
		check_true("Rich Seams helps ore", Events.gather_bonus(rich, "ore") == 1)
		check_true("Rich Seams does not help herbs", Events.gather_bonus(rich, "herb") == 0)
		check_true("an unknown kind is never bonused",
			Events.gather_bonus(rich, "fish") == 0)

	# --- missing data degrades to nothing special, never to a crash or a free bonus ---
	var none: Dictionary = Events.event_for_day(5, [])
	check_true("no data degrades to a quiet day", not Events.is_notable(none))
	check_true("no data grants no bonus", Events.gather_bonus(none, "ore") == 0)

	# --- it reaches the bag: Gathering reports the event bonus it applied ---
	var gathering: Node = root.get_node("Gathering")
	var farm: Node = root.get_node("Farm")
	var found_day := -1
	for day in range(1, 60):
		if Events.gather_bonus(Events.event_for_day(day, events), "ore") > 0:
			found_day = day
			break
	check_true("some day in the first 60 boosts ore (%d)" % found_day, found_day > 0)
	if found_day > 0:
		# Farm.day() reads farm.logic.day; setting a "day" property on the autoload itself
		# creates a new one that nothing consults, which is how the first version of this
		# check passed a day change to nobody and read a zero bonus back.
		farm.logic.day = found_day
		var status: Dictionary = gathering.status(
			"test_event_seam", "copper_ore", 1, 1, "forge", 1, "ore")
		check_true("Gathering reports the event bonus it applied (%s)" % str(status),
			int(status.get("event_bonus", 0)) > 0)
	_finish()


func check_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _finish() -> void:
	if failures == 0:
		print("PASS — daily events are deterministic, weighted, and felt.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
