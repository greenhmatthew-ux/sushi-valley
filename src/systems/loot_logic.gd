class_name LootLogic
extends RefCounted
## Rolling an enemy's drop table. Pure and node-free so the odds are testable without
## spawning anything.
##
## Enemies carry authored drop tables in data/game/enemies.json shaped
## `[{ "item": "spore_cap", "chance": 1 }, ...]`, where chance is an independent probability
## in 0..1 — not a weighted pick. A mushroom rolls its cap (1.0, always), its straw hat
## (0.3), and its rice ball (0.4) separately, so one kill can yield several items or just
## the guaranteed one.
##
## This existed only as data before: enemies awarded coins and silently ignored their tables,
## which is why every item-collection quest in quests.json was uncompletable.

## Roll a drop table into a list of item ids.
##
## `rolls` optionally supplies deterministic samples in 0..1 (one per table entry) for tests;
## leave it empty to draw fresh randomness. Entries missing an item id are skipped rather
## than producing an empty pickup.
static func roll(table: Array, rolls: Array = []) -> Array[String]:
	var out: Array[String] = []
	for i in table.size():
		var entry = table[i]
		if not (entry is Dictionary):
			continue
		var id := String(entry.get("item", ""))
		if id.is_empty():
			continue
		var chance := float(entry.get("chance", 0.0))
		var sample: float = float(rolls[i]) if i < rolls.size() else randf()
		# `<` so chance 0 never drops and chance 1 always does, whatever randf() returns.
		if sample < chance:
			out.append(id)
	return out


## Human-readable summary of a drop list for a toast: "2x Rice Ball, Spore Cap".
## `namer` maps an item id to its display name; ids repeat in the list, so they are counted.
static func describe(drops: Array, namer: Callable) -> String:
	if drops.is_empty():
		return ""
	var counts := {}
	var order: Array[String] = []
	for id in drops:
		var key := String(id)
		if not counts.has(key):
			counts[key] = 0
			order.append(key)
		counts[key] = int(counts[key]) + 1

	var parts: Array[String] = []
	for id in order:
		var name := String(namer.call(id)) if namer.is_valid() else id
		var n := int(counts[id])
		parts.append(name if n == 1 else "%dx %s" % [n, name])
	return ", ".join(parts)
