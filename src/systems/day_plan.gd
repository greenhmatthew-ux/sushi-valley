class_name DayPlan
extends RefCounted
## Concise, read-only priorities for the returning-player and sleep surfaces.
## Life-skill autoloads remain authoritative; this model only turns their
## snapshots into copy with a strict line budget.

const MAX_TODAY_LINES := 3


static func today(farm: Dictionary, gathering: Dictionary,
		fishing: Dictionary) -> Array:
	var lines: Array = []
	var ready_crops := int(farm.get("ready", 0))
	var needs_water := int(farm.get("needs_water", 0))
	var weather_watered := int(farm.get("weather_watered", 0))
	if ready_crops > 0:
		lines.append(_line("farm", "Farm: %s ready to harvest" %
			_counted(ready_crops, "crop")))
	elif needs_water > 0:
		lines.append(_line("farm", "Farm: water %s before sleeping" %
			_counted(needs_water, "crop")))
	elif weather_watered > 0:
		lines.append(_line("farm", "Farm: weather is watering %s" %
			_counted(weather_watered, "crop")))

	var renewed_nodes := int(gathering.get("renewed", 0))
	if renewed_nodes > 0:
		lines.append(_line("gathering", "Gathering: %s renewed" %
			_counted(renewed_nodes, "resource node")))

	var renewed_sites: Array = fishing.get("renewed_names", [])
	if not renewed_sites.is_empty():
		var place := String(renewed_sites[0])
		var extra := int(renewed_sites.size()) - 1
		lines.append(_line("fishing", "Fishing: %s is ready again%s" % [
			place, " (+%d more)" % extra if extra > 0 else ""]))

	return lines.slice(0, MAX_TODAY_LINES)


static func sleep_notes(farm: Dictionary, gathering: Dictionary,
		fishing: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var ready_now := int(farm.get("ready_now", 0))
	var ready_tomorrow := int(farm.get("ready_tomorrow", 0))
	var advancing := int(farm.get("advancing", 0))
	var paused := int(farm.get("paused", 0))
	if ready_now > 0:
		notes.append("%s stay ready for harvest" % _counted(ready_now, "mature crop"))
	if ready_tomorrow > 0:
		notes.append("%s become ready" % _counted(ready_tomorrow, "crop"))
	var still_growing := maxi(0, advancing - ready_tomorrow)
	if still_growing > 0:
		notes.append("%s advance" % _counted(still_growing, "watered crop"))
	if paused > 0:
		notes.append("%s pause dry" % _counted(paused, "crop"))

	var returning := int(gathering.get("returning", 0))
	var waiting := int(gathering.get("waiting", 0))
	if returning > 0:
		notes.append("%s return" % _counted(returning, "resource node"))
	if waiting > 0:
		notes.append("%s need more time" % _counted(waiting, "rare node"))
	if int(fishing.get("cooling", 0)) > 0:
		notes.append("fishing cooldowns still use real time")
	return notes


static func morning_notes(farm: Dictionary, gathering: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var ready := int(farm.get("ready_tomorrow", 0))
	var renewed := int(gathering.get("returning", 0))
	if ready > 0:
		notes.append("%s ready" % _counted(ready, "crop"))
	if renewed > 0:
		notes.append("%s renewed" % _counted(renewed, "resource node"))
	return notes


static func _line(kind: String, text: String) -> Dictionary:
	return {"kind": kind, "text": text}


static func _counted(count: int, noun: String) -> String:
	return "%d %s%s" % [count, noun, "" if count == 1 else "s"]
