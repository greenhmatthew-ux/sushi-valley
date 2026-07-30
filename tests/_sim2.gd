extends SceneTree
## Tune the curve: win rate per enemy at each level, perfect play.
func _initialize() -> void:
	await process_frame
	var db := root.get_node("DB")
	print("lvl  hp/atk/def   slime  mushroom   kappa  lantern")
	for lv in [1, 2, 3, 4, 5, 7, 10]:
		var hp := PlayerStats.max_hp(lv)
		var a := PlayerStats.atk(lv)
		var d := PlayerStats.def(lv)
		var row := "%3d  %2d/%2d/%2d  " % [lv, hp, a, d]
		for eid in ["slime","mushroom","kappa","lantern"]:
			var e: Dictionary = db.enemy(eid)
			var wins := 0
			const TRIALS := 300
			for t in TRIALS:
				var enc := CombatEncounter.new(e, hp, hp, a, d)
				var r := 0
				while not enc.is_over() and r < 80:
					enc.resolve("x", "x")
					r += 1
				if enc.player_won(): wins += 1
			row += "%6.0f%%" % (100.0 * wins / TRIALS)
		print(row)
	quit()
