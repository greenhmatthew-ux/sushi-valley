class_name InventoryLogic
extends RefCounted
## Pure bag + coin logic. Port of the bag/coin half of `src/game/systems/Inventory.ts`
## in the archived Vite/Phaser build (github.com/greenhmatthew-ux/Kana).
##
## Node-free and DB-free on purpose, so it stays headless-testable and the real
## stacking / capacity rules can be asserted against the TS behavior. The Inv
## autoload wraps this, resolves item defs through DB, and emits Bus signals; the
## equip / gear-bonus half of the TS system belongs to the combat slice, not here.
##
## The bag is `{item_id: qty}` and coins is a plain int — the exact shape the TS
## build persisted under `profile.data.inventory` / `profile.data.coins`, so a save
## round-trips through `to_dict()` / `load_dict()` without translation.

## Ported verbatim from Inventory.ts. A single stack never exceeds MAX_STACK; a
## surplus add returns the leftover so the caller can drop or discard it. Total
## units across the whole bag are compared against BASE_CAPACITY for the
## "encumbered" warning — capacity does NOT block adds, it only flags the bag.
const MAX_STACK := 99          # MAX_STACK_SIZE in Inventory.ts
const BASE_CAPACITY := 300     # BASE_CAPACITY in Inventory.ts

var bag: Dictionary = {}       # item_id -> qty (>0); empty stacks are deleted
var coins: int = 0


# --- items -----------------------------------------------------------------

## How many of `id` are held.
func count(id: String) -> int:
	return int(bag.get(id, 0))


func has(id: String, qty: int = 1) -> bool:
	return count(id) >= qty


## Room left in this item's stack before it hits MAX_STACK.
func max_addable(id: String) -> int:
	return maxi(0, MAX_STACK - count(id))


## Add up to a full stack; returns the leftover that did NOT fit (0 normally).
## Mirrors Inventory.addItem: clamp to the stack cap, keep the surplus for the
## caller. Non-positive quantities are a no-op that "leftover" the whole request.
func add(id: String, qty: int = 1) -> int:
	if id.is_empty() or qty <= 0:
		return maxi(0, qty)
	var current := count(id)
	var can_add := mini(qty, maxi(0, MAX_STACK - current))
	if can_add > 0:
		bag[id] = current + can_add
	return qty - can_add


## Remove up to `qty`; returns how many were actually removed (never more than
## held, so removing more than you own is safe and clears the stack). Mirrors
## Inventory.removeItem, which decrements and deletes the key at zero.
func remove(id: String, qty: int = 1) -> int:
	if qty <= 0:
		return 0
	var current := count(id)
	var removed := mini(qty, current)
	if removed <= 0:
		return 0
	var left := current - removed
	if left <= 0:
		bag.erase(id)
	else:
		bag[id] = left
	return removed


## Bag contents as `[{ "id": String, "qty": int }, ...]` in insertion order.
## Display concerns (resolving names, sorting) live with the UI, which has DB.
func entries() -> Array:
	var out: Array = []
	for id in bag:
		out.append({"id": id, "qty": int(bag[id])})
	return out


## Sum of every stack — the number compared against capacity.
func total_units() -> int:
	var units := 0
	for id in bag:
		units += int(bag[id])
	return units


## Encumbrance snapshot. Port of Inventory.encumbrance: a percentage of capacity,
## flagged `encumbered` once the bag exceeds BASE_CAPACITY. Advisory only.
func encumbrance() -> Dictionary:
	var units := total_units()
	var percent := mini(100, roundi(float(units) / float(BASE_CAPACITY) * 100.0))
	return {
		"units": units,
		"cap": BASE_CAPACITY,
		"percent": percent,
		"encumbered": units > BASE_CAPACITY,
	}


# --- coins ------------------------------------------------------------------

## Add coins (or subtract with a negative n, as Inventory.addCoins allowed).
func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)


## Spend if affordable; returns false and changes nothing if the balance is short.
func spend_coins(n: int) -> bool:
	if n <= 0:
		return true
	if coins < n:
		return false
	coins -= n
	return true


func set_coins(n: int) -> void:
	coins = maxi(0, n)


# --- persistence hooks (the save slice wires these to SaveGame) --------------

## Serialize to the exact TS save shape: `{ "inventory": {...}, "coins": int }`.
func to_dict() -> Dictionary:
	return {"inventory": bag.duplicate(true), "coins": coins}


## Load from a save dict, tolerating a missing/partial payload. Quantities are
## coerced to positive ints and empty stacks dropped, so a hand-edited save can't
## seed a negative or zero stack.
func load_dict(data: Dictionary) -> void:
	bag.clear()
	var raw: Dictionary = data.get("inventory", {})
	for id in raw:
		var qty := int(raw[id])
		if qty > 0:
			bag[String(id)] = qty
	coins = maxi(0, int(data.get("coins", 0)))


## Drop everything — used by a "new game" reset.
func clear() -> void:
	bag.clear()
	coins = 0
