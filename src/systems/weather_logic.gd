class_name WeatherLogic
extends RefCounted
## Pure deterministic weather rules ported from the archived WeatherSystem.ts.
## The saved calendar is the seed, so reloading a day can never reroll conditions.

const WEATHER_BY_SEASON := {
	"spring": ["clear", "cloudy", "rain", "rain"],
	"summer": ["clear", "clear", "storm", "cloudy"],
	"autumn": ["clear", "cloudy", "rain", "rain"],
	"winter": ["clear", "cloudy", "snow", "snow"],
}
const DISPLAY_NAMES := {
	"clear": "Clear",
	"cloudy": "Cloudy",
	"rain": "Rain",
	"storm": "Storm",
	"snow": "Snow",
}


## Match JavaScript's number multiplication followed by `>>> 0`. Converting the
## multiply to float deliberately preserves JS double rounding before the mask.
static func day_random(day: int) -> float:
	var mixed: int = maxi(1, day) * 12345 + 54321
	mixed = (mixed ^ (mixed >> 16)) & 0xffffffff
	mixed = int(float(mixed) * 1103515245.0 + 12345.0) & 0xffffffff
	return float(mixed) / 4294967295.0


static func current_weather(day: int, season: String) -> String:
	var safe_season := season if WEATHER_BY_SEASON.has(season) else "spring"
	var pool: Array = WEATHER_BY_SEASON[safe_season]
	var index := mini(floori(day_random(day) * pool.size()), pool.size() - 1)
	return String(pool[index])


static func is_raining(weather: String) -> bool:
	return weather == "rain" or weather == "storm"


static func is_snowing(weather: String) -> bool:
	return weather == "snow"


static func is_precipitation(weather: String) -> bool:
	return is_raining(weather) or is_snowing(weather)


static func display_name(weather: String) -> String:
	return String(DISPLAY_NAMES.get(weather, "Clear"))


static func hud_text(weather: String) -> String:
	match weather:
		"rain":
			return "Rain - crops watered"
		"storm":
			return "Storm - rough fishing"
		"snow":
			return "Snow - crops watered"
		"cloudy":
			return "Cloudy"
		_:
			return "Clear"
