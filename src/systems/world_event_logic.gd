class_name WorldEventLogic
extends RefCounted
## Pure deterministic daily world events.
##
## Matthew's direction for content: "mostly just content, with staged content being gates to
## new areas, unlocking raids and expeditions in an area, and random events." This is the
## random-events half — the cheapest return-value system the valley can have, because it
## makes the SAME area worth re-entering tomorrow without needing a new map.
##
## Deterministic on the saved day, exactly like WeatherLogic: reloading a day can never
## reroll it, so an event cannot be save-scummed and a fixed day always reads the same in a
## test. It shares WeatherLogic's hash with a different salt so the two never move together —
## rain and Rich Seams landing on the same days forever would read as one system, not two.
##
## Note: `data/game/worldEvents.json` is NOT this. Despite the name it holds map-authoring
## constraints (clearance rules, path tile frames) and nothing reads it. Events live in
## `events.json`.
##
## No nodes, no autoloads, no scene tree — src/systems/ stays headless-testable.

## Different salt from WeatherLogic.day_random, so events and weather do not correlate.
const SALT := 7789

## The event when no data is loaded at all. Named so a missing file degrades to "nothing
## special happened" rather than to a crash or a silently doubled yield.
const NONE := {
	"id": "quiet_day",
	"displayName": "A Quiet Day",
	"description": "Nothing out of the ordinary.",
	"weight": 1,
	"resourceKinds": [],
	"gatherBonus": 0,
}


## Deterministic 0..1 for a day. Same shape as WeatherLogic.day_random with our own salt.
static func day_random(day: int) -> float:
	var mixed: int = maxi(1, day) * 12345 + SALT
	mixed = (mixed ^ (mixed >> 16)) & 0xffffffff
	mixed = int(float(mixed) * 1103515245.0 + 12345.0) & 0xffffffff
	return float(mixed) / 4294967295.0


## Today's event, chosen by weight so "A Quiet Day" stays the common case. An event that
## fires most days is not an event; it is a balance change with a banner.
static func event_for_day(day: int, events: Array) -> Dictionary:
	if events.is_empty():
		return NONE
	var total := 0
	for entry in events:
		total += maxi(1, int((entry as Dictionary).get("weight", 1)))
	if total <= 0:
		return NONE
	var roll := int(day_random(day) * float(total))
	roll = clampi(roll, 0, total - 1)
	var running := 0
	for entry in events:
		running += maxi(1, int((entry as Dictionary).get("weight", 1)))
		if roll < running:
			return entry as Dictionary
	return events[events.size() - 1] as Dictionary


## Extra quantity this event grants when harvesting `resource_kind`.
##
## Stacks with the weather bonus rather than replacing it: they are different reasons for a
## good day, and a player who works out both is being rewarded for paying attention.
static func gather_bonus(event: Dictionary, resource_kind: String) -> int:
	if event.is_empty() or resource_kind.is_empty():
		return 0
	var kinds: Array = event.get("resourceKinds", [])
	if not kinds.has(resource_kind):
		return 0
	return maxi(0, int(event.get("gatherBonus", 0)))


## True when the event is worth telling the player about on arrival.
static func is_notable(event: Dictionary) -> bool:
	return not event.is_empty() and int(event.get("gatherBonus", 0)) > 0
