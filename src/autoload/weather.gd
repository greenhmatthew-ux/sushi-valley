extends Node
## Calendar-backed weather facade. No weather field is saved: Farm's persisted
## day and season deterministically produce the same conditions after every load.

const Rules = preload("res://src/systems/weather_logic.gd")


func current() -> String:
	return Rules.current_weather(Farm.day(), Farm.season())


func tomorrow() -> String:
	var next: Dictionary = Farm.next_clock()
	return Rules.current_weather(int(next.get("day", Farm.day() + 1)),
		String(next.get("season", Farm.season())))


func for_calendar(day: int, season: String) -> String:
	return Rules.current_weather(day, season)


func is_raining(weather: String = "") -> bool:
	return Rules.is_raining(current() if weather.is_empty() else weather)


func is_snowing(weather: String = "") -> bool:
	return Rules.is_snowing(current() if weather.is_empty() else weather)


func is_precipitation(weather: String = "") -> bool:
	return Rules.is_precipitation(current() if weather.is_empty() else weather)


func display_name(weather: String = "") -> String:
	return Rules.display_name(current() if weather.is_empty() else weather)


func hud_text(weather: String = "") -> String:
	return Rules.hud_text(current() if weather.is_empty() else weather)
