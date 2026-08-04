extends Node
## Saved fishing-site cooldowns and reward transactions. The minigame itself is
## pure; this coordinator is the only place that awards fish and Kitchen XP.

const QUALITY_BONUS := {"normal": 0, "silver": 1, "gold": 2}

var _sites: Dictionary = {}


func register_site(site_id: String, display_name: String, cooldown_seconds: int,
		seasons: Array) -> bool:
	if site_id.is_empty():
		return false
	var first_registration := not _sites.has(site_id)
	_sites[site_id] = {
		"name": display_name,
		"cooldown": maxi(0, cooldown_seconds),
		"seasons": seasons.duplicate(),
	}
	return first_registration


func daily_status(now_seconds: float = -1.0) -> Dictionary:
	var result := {
		"total": _sites.size(),
		"ready": 0,
		"cooling": 0,
		"quiet": 0,
		"min_remaining": 0,
		"renewed_names": [],
	}
	var nodes: Dictionary = Learning.profile.data.get("resourceNodes", {})
	for raw_id in _sites:
		var site_id := String(raw_id)
		var site: Dictionary = _sites[raw_id]
		var seasons: Array = site.get("seasons", [])
		if not seasons.is_empty() and Farm.season() not in seasons:
			result["quiet"] += 1
			continue
		var remaining := remaining_seconds(site_id, int(site.get("cooldown", 0)), now_seconds)
		if remaining > 0:
			result["cooling"] += 1
			var shortest := int(result["min_remaining"])
			result["min_remaining"] = remaining if shortest == 0 else mini(shortest, remaining)
		else:
			result["ready"] += 1
			if nodes.has(site_id):
				(result["renewed_names"] as Array).append(String(site.get("name", site_id)))
	return result


func remaining_seconds(site_id: String, cooldown_seconds: int,
		now_seconds: float = -1.0) -> int:
	var now := Time.get_unix_time_from_system() if now_seconds < 0.0 else now_seconds
	var nodes: Dictionary = Learning.profile.data.get("resourceNodes", {})
	var last := float(nodes.get(site_id, 0.0))
	return maxi(0, ceili(float(cooldown_seconds) - (now - last)))


func status(site_id: String, cooldown_seconds: int, max_reward: int,
		seasons: Array, now_seconds: float = -1.0) -> Dictionary:
	if not seasons.is_empty() and Farm.season() not in seasons:
		return {"ok": false, "reason": "The pond is quiet in %s." % Farm.season().capitalize()}
	var remaining := remaining_seconds(site_id, cooldown_seconds, now_seconds)
	if remaining > 0:
		return {"ok": false, "reason": "The fish are returning - ready in %s." % _duration(remaining),
			"remaining": remaining}
	if Inv.max_addable("river_fish") < max_reward:
		return {"ok": false, "reason": "Leave room for up to %d River Fish." % max_reward}
	return {"ok": true, "reason": "Ready.", "remaining": 0}


func complete(site_id: String, base_qty: int, quality: String, cooldown_seconds: int,
		difficulty: float, now_seconds: float = -1.0) -> Dictionary:
	var safe_quality := quality if QUALITY_BONUS.has(quality) else "normal"
	var qty := maxi(1, base_qty) + int(QUALITY_BONUS[safe_quality])
	if Inv.max_addable("river_fish") < qty:
		return {"ok": false, "reason": "The catch will not fit in your Bag."}
	if Inv.add("river_fish", qty) != 0:
		return {"ok": false, "reason": "The catch will not fit in your Bag."}
	var xp := maxi(5, int(round(difficulty * 10.0)) * 3)
	Crafting.award_xp("kitchen", xp)
	var now := Time.get_unix_time_from_system() if now_seconds < 0.0 else now_seconds
	if not Learning.profile.data.has("resourceNodes") \
			or Learning.profile.data["resourceNodes"] is not Dictionary:
		Learning.profile.data["resourceNodes"] = {}
	Learning.profile.data["resourceNodes"][site_id] = now
	Learning.profile.save()
	Bus.fishing_changed.emit(site_id)
	Bus.hud_refresh.emit()
	return {"ok": true, "qty": qty, "quality": safe_quality, "xp": xp,
		"cooldown": cooldown_seconds}


func reset_site(site_id: String, save: bool = false) -> void:
	var nodes: Dictionary = Learning.profile.data.get("resourceNodes", {})
	nodes.erase(site_id)
	Learning.profile.data["resourceNodes"] = nodes
	if save:
		Learning.profile.save()
	Bus.fishing_changed.emit(site_id)


func _duration(seconds: int) -> String:
	if seconds >= 60:
		return "%dm %02ds" % [seconds / 60, seconds % 60]
	return "%ds" % seconds
