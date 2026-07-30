extends SceneTree
## Inventory slice: the pure InventoryLogic bag + coin rules.
##
##   godot --headless --path . --script res://tests/test_inventory.gd
##
## Instantiates InventoryLogic directly (no autoload, no SceneTree nodes) and
## asserts against the TS Inventory.ts behavior it was ported from: stacking,
## safe removal, stack cap + leftover, the coin purse, capacity/encumbrance, and
## a save round-trip through to_dict()/load_dict().

var failures: int = 0


func _initialize() -> void:
	_stacking()
	_removal()
	_stack_cap_and_leftover()
	_coins()
	_capacity()
	_equipment_swaps()
	_full_stack_cannot_delete_displaced_gear()
	_round_trip()
	_finish()


func _stacking() -> void:
	var inv := InventoryLogic.new()
	check_eq("fresh bag counts zero", inv.count("rice_ball"), 0)
	check_eq("first add reports no leftover", inv.add("rice_ball", 3), 0)
	check_eq("count after first add", inv.count("rice_ball"), 3)
	check_eq("second add of same id stacks", inv.add("rice_ball", 2), 0)
	check_eq("stack merged, not duplicated", inv.count("rice_ball"), 5)
	check_eq("distinct ids are separate stacks", inv.add("wild_herb", 4), 0)
	check_eq("wild_herb count", inv.count("wild_herb"), 4)
	check_eq("two stacks in the bag", inv.entries().size(), 2)
	check_true("has() true when enough held", inv.has("rice_ball", 5))
	check_true("has() false when short", not inv.has("rice_ball", 6))
	check_eq("add with default qty adds one", inv.add("wild_herb"), 0)
	check_eq("default-qty add landed", inv.count("wild_herb"), 5)


func _removal() -> void:
	var inv := InventoryLogic.new()
	inv.add("rice_ball", 5)
	check_eq("remove decrements and returns removed", inv.remove("rice_ball", 2), 2)
	check_eq("count after partial remove", inv.count("rice_ball"), 3)

	# Removing more than held is safe: clears the stack, reports only what was there.
	check_eq("over-remove returns only what was held", inv.remove("rice_ball", 99), 3)
	check_eq("over-removed stack is now empty", inv.count("rice_ball"), 0)
	check_eq("emptied stack is dropped from the bag", inv.entries().size(), 0)

	# Removing from an absent stack is a harmless no-op.
	check_eq("remove from absent id removes nothing", inv.remove("ghost_item", 1), 0)
	check_eq("non-positive remove is a no-op", inv.remove("rice_ball", 0), 0)


func _stack_cap_and_leftover() -> void:
	var inv := InventoryLogic.new()
	check_eq("room in a fresh stack is MAX_STACK", inv.max_addable("rice_ball"), InventoryLogic.MAX_STACK)
	check_eq("filling to the cap leaves no leftover",
		inv.add("rice_ball", InventoryLogic.MAX_STACK), 0)
	check_eq("stack sits exactly at the cap", inv.count("rice_ball"), InventoryLogic.MAX_STACK)
	check_eq("no room left at the cap", inv.max_addable("rice_ball"), 0)
	check_eq("adding past the cap returns the leftover", inv.add("rice_ball", 5), 5)
	check_eq("stack never exceeds the cap", inv.count("rice_ball"), InventoryLogic.MAX_STACK)

	# Partial fit: 90 held, add 15 -> 9 fit, 6 leftover.
	var inv2 := InventoryLogic.new()
	inv2.add("wild_herb", 90)
	check_eq("partial fit returns the surplus only", inv2.add("wild_herb", 15), 6)
	check_eq("partial fit topped the stack to the cap", inv2.count("wild_herb"), InventoryLogic.MAX_STACK)


func _coins() -> void:
	var inv := InventoryLogic.new()
	check_eq("coins start at zero", inv.coins, 0)
	inv.add_coins(50)
	check_eq("coins added", inv.coins, 50)
	check_true("spend within balance succeeds", inv.spend_coins(30))
	check_eq("coins deducted after spend", inv.coins, 20)
	check_true("spend beyond balance fails", not inv.spend_coins(100))
	check_eq("failed spend leaves balance untouched", inv.coins, 20)
	inv.add_coins(-999)
	check_eq("coins never go negative", inv.coins, 0)
	inv.set_coins(7)
	check_eq("set_coins overwrites the balance", inv.coins, 7)


func _capacity() -> void:
	var inv := InventoryLogic.new()
	inv.add("rice_ball", 40)
	inv.add("wild_herb", 60)
	check_eq("total units sums every stack", inv.encumbrance()["units"], 100)
	check_eq("capacity is BASE_CAPACITY", inv.encumbrance()["cap"], InventoryLogic.BASE_CAPACITY)
	check_true("under-capacity bag is not encumbered", not inv.encumbrance()["encumbered"])

	# Push total units past BASE_CAPACITY (300): 4 stacks of 99 = 396.
	var inv2 := InventoryLogic.new()
	inv2.add("a", 99); inv2.add("b", 99); inv2.add("c", 99); inv2.add("d", 99)
	check_eq("units across many stacks", inv2.encumbrance()["units"], 396)
	check_true("over-capacity bag is encumbered", inv2.encumbrance()["encumbered"])
	check_eq("encumbrance percent is clamped to 100", inv2.encumbrance()["percent"], 100)


func _equipment_swaps() -> void:
	var inv := InventoryLogic.new()
	inv.add("wooden_katana")
	check_true("held weapon equips", inv.equip("wooden_katana", "weapon", "1h"))
	check_eq("equipped weapon leaves the bag", inv.count("wooden_katana"), 0)
	check_eq("weapon slot records its item", inv.equipped_id("weapon"), "wooden_katana")

	inv.add("wooden_buckler")
	check_true("offhand equips beside a one-hand weapon",
		inv.equip("wooden_buckler", "offhand", "", "1h"))
	inv.add("bamboo_spear")
	check_true("two-hand weapon equips", inv.equip("bamboo_spear", "weapon", "2h"))
	check_eq("two-hand weapon clears offhand", inv.equipped_id("offhand"), "")
	check_eq("cleared offhand returns to bag", inv.count("wooden_buckler"), 1)
	check_eq("replaced weapon returns to bag", inv.count("wooden_katana"), 1)

	check_true("offhand can replace a two-hand weapon",
		inv.equip("wooden_buckler", "offhand", "", "2h"))
	check_eq("equipping offhand clears two-hand weapon", inv.equipped_id("weapon"), "")
	check_eq("cleared two-hand weapon returns to bag", inv.count("bamboo_spear"), 1)
	check_true("unequip returns the offhand", inv.unequip("offhand"))
	check_eq("unequipped item returns to bag", inv.count("wooden_buckler"), 1)


func _full_stack_cannot_delete_displaced_gear() -> void:
	var inv := InventoryLogic.new()
	inv.add("straw_hat")
	inv.equip("straw_hat", "head")
	inv.add("straw_hat", InventoryLogic.MAX_STACK)
	inv.add("samurai_helmet")
	check_true("swap fails when displaced gear has no bag room",
		not inv.equip("samurai_helmet", "head"))
	check_eq("failed swap keeps old gear equipped", inv.equipped_id("head"), "straw_hat")
	check_eq("failed swap keeps new gear in bag", inv.count("samurai_helmet"), 1)


func _round_trip() -> void:
	var inv := InventoryLogic.new()
	inv.add("rice_ball", 5)
	inv.add("wild_herb", 3)
	inv.add_coins(42)
	inv.add("straw_hat")
	inv.equip("straw_hat", "head")
	var saved := inv.to_dict()
	check_true("save dict carries the coins", saved["coins"] == 42)
	check_true("save dict carries the bag", saved["inventory"]["rice_ball"] == 5)

	var loaded := InventoryLogic.new()
	loaded.load_dict(saved)
	check_eq("loaded bag restores counts", loaded.count("rice_ball"), 5)
	check_eq("loaded bag restores second stack", loaded.count("wild_herb"), 3)
	check_eq("loaded coins restored", loaded.coins, 42)
	check_eq("loaded equipment restored", loaded.equipped_id("head"), "straw_hat")

	# A hand-edited save with junk quantities is sanitized on load.
	var dirty := InventoryLogic.new()
	dirty.load_dict({"inventory": {"rice_ball": 0, "wild_herb": -3, "honey": 2}, "coins": -5})
	check_eq("zero-qty entry is dropped on load", dirty.count("rice_ball"), 0)
	check_eq("negative-qty entry is dropped on load", dirty.count("wild_herb"), 0)
	check_eq("valid entry survives load", dirty.count("honey"), 2)
	check_eq("negative coins clamp to zero on load", dirty.coins, 0)


# --- harness ---------------------------------------------------------------

func _finish() -> void:
	print("")
	print(("PASS — inventory bag, coins, capacity, and save round-trip hold."
		if failures == 0 else "FAIL — %d inventory check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
