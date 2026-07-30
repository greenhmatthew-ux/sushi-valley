extends SceneTree
## Simulate the real encounter to see whether combat is winnable at all.
func _initialize() -> void:
	await process_frame
	var db := root.get_node("DB")
	print("player: MAX_HP=12  atk=6  def=2   (CombatEncounter defaults)")
	print("")
	for eid in ["slime", "mushroom", "kappa", "lantern"]:
		var e: Dictionary = db.enemy(eid)
		var wins := 0
		var rounds_total := 0
		const TRIALS := 400
		for t in TRIALS:
			var enc := CombatEncounter.new(e, 12, 12, 6, 2)
			var rounds := 0
			while not enc.is_over() and rounds < 60:
				# assume a PERFECT player: every recall correct
				enc.resolve("x", "x")
				rounds += 1
			if enc.player_won():
				wins += 1
				rounds_total += rounds
		var wr := 100.0 * wins / TRIALS
		var avg := (float(rounds_total) / maxi(1, wins))
		print("  %-9s hp=%-3d atk=%-2d def=%-2d  ->  win rate %5.1f%%  avg rounds %.1f" % [
			eid, int(e.get("maxHp",0)), int(e.get("atk",0)), int(e.get("def",0)), wr, avg])
	quit()
