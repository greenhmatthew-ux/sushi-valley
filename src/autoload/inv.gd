extends Node
## The player's bag + coin purse, global for the whole game. Thin wrapper around
## the pure InventoryLogic (which holds the real stacking / capacity math), whose
## only jobs are to own the one shared instance and announce every mutation on the
## Bus so panels, the HUD, and persistence stay in sync without polling.
##
## Mirrors the Learning autoload's shape: heavy logic in a headless-testable
## RefCounted, this Node just glue. Systems call `Inv.add(...)`, `Inv.remove(...)`,
## `Inv.coins`, etc.; nobody references this node's internals.
##
## Persistence: the save slice can call `to_dict()` on save and `load_dict()` on
## load. This autoload deliberately does NOT touch SaveGame itself, to keep the
## save schema owned by that slice.

var logic := InventoryLogic.new()


# --- items -----------------------------------------------------------------

## Add items; returns the leftover that didn't fit (stack cap hit). Emits
## `item_added` with the amount that actually landed, then `inventory_changed`.
func add(id: String, qty: int = 1) -> int:
	var leftover := logic.add(id, qty)
	var added := qty - leftover
	if added > 0:
		Bus.item_added.emit(id, added)
		Bus.inventory_changed.emit()
	return leftover


## Remove items; returns how many were actually removed. Emits `item_removed`
## with that amount, then `inventory_changed`.
func remove(id: String, qty: int = 1) -> int:
	var removed := logic.remove(id, qty)
	if removed > 0:
		Bus.item_removed.emit(id, removed)
		Bus.inventory_changed.emit()
	return removed


func count(id: String) -> int:
	return logic.count(id)


func has(id: String, qty: int = 1) -> bool:
	return logic.has(id, qty)


## `[{ "id", "qty" }, ...]` — see InventoryLogic.entries.
func entries() -> Array:
	return logic.entries()


func encumbrance() -> Dictionary:
	return logic.encumbrance()


# --- coins ------------------------------------------------------------------

var coins: int:
	get:
		return logic.coins


func add_coins(n: int) -> void:
	logic.add_coins(n)
	Bus.coins_changed.emit(logic.coins)
	Bus.inventory_changed.emit()


## Spend if affordable; returns false and emits nothing if the balance is short.
func spend_coins(n: int) -> bool:
	if not logic.spend_coins(n):
		return false
	Bus.coins_changed.emit(logic.coins)
	Bus.inventory_changed.emit()
	return true


# --- persistence (wired by the save slice) ---------------------------------

func to_dict() -> Dictionary:
	return logic.to_dict()


## Replace the whole bag + coins from a save, then announce so UI rebuilds.
func load_dict(data: Dictionary) -> void:
	logic.load_dict(data)
	Bus.coins_changed.emit(logic.coins)
	Bus.inventory_changed.emit()


func reset() -> void:
	logic.clear()
	Bus.coins_changed.emit(0)
	Bus.inventory_changed.emit()
