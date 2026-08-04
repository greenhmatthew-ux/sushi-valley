class_name InventoryLogic
extends RefCounted
## Pure bag + coin logic. Port of the bag/coin half of `src/game/systems/Inventory.ts`
## in the archived Vite/Phaser build (github.com/greenhmatthew-ux/Kana).
##
## Node-free and DB-free on purpose, so it stays headless-testable and the real
## stacking / capacity rules can be asserted against the TS behavior. The Inv
## autoload wraps this, resolves item defs through DB, and emits Bus signals; the
## Equipment slot mutation now lives here too, while item-definition validation and
## gear stat math remain in Inv and PlayerStats respectively.
##
## The bag is `{item_id: qty}`, equipment is `{slot: item_id}`, and coins is a plain int,
## matching the three legacy profile fields inside one Godot inventory save section.

## Ported verbatim from Inventory.ts. A single stack never exceeds MAX_STACK; a
## surplus add returns the leftover so the caller can drop or discard it. Total
## units across the whole bag are compared against BASE_CAPACITY for the
## "encumbered" warning — capacity does NOT block adds, it only flags the bag.
const MAX_STACK := 99          # MAX_STACK_SIZE in Inventory.ts
const BASE_CAPACITY := 300     # BASE_CAPACITY in Inventory.ts
const EQUIPMENT_SLOTS: Array[String] = [
	"weapon", "offhand", "head", "body", "shoulders", "cape",
	"belt", "hands", "legs", "feet", "ring", "amulet",
]

var bag: Dictionary = {}       # item_id -> qty (>0); empty stacks are deleted
var coins: int = 0
var equipment: Dictionary = {} # slot -> item_id; equipped items are not also in the bag
var favorites: Dictionary = {} # item_id -> true; absence means not favorited
var prepared_meal: String = "" # one meal reserved outside the bag for combat


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


## Validate and apply a recipe as one bag mutation. Inputs are aggregated first, then
## output capacity is checked against the post-consumption bag; failure changes nothing.
func can_craft_transaction(inputs: Array, output_id: String, output_qty: int,
		amount: int = 1) -> bool:
	if output_id.is_empty() or output_qty <= 0 or amount <= 0:
		return false
	var required := {}
	for input in inputs:
		var item_id := String(input.get("item", ""))
		var qty := int(input.get("qty", 0)) * amount
		if item_id.is_empty() or qty <= 0:
			return false
		required[item_id] = int(required.get(item_id, 0)) + qty
	for item_id in required:
		if count(item_id) < int(required[item_id]):
			return false
	var output_after_inputs := count(output_id) - int(required.get(output_id, 0))
	return output_after_inputs + output_qty * amount <= MAX_STACK


func craft_transaction(inputs: Array, output_id: String, output_qty: int,
		amount: int = 1) -> bool:
	if not can_craft_transaction(inputs, output_id, output_qty, amount):
		return false
	var next_bag := bag.duplicate(true)
	for input in inputs:
		var item_id := String(input.get("item", ""))
		var left := int(next_bag.get(item_id, 0)) - int(input.get("qty", 0)) * amount
		if left <= 0:
			next_bag.erase(item_id)
		else:
			next_bag[item_id] = left
	next_bag[output_id] = int(next_bag.get(output_id, 0)) + output_qty * amount
	bag = next_bag
	return true


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


# --- favorites ---------------------------------------------------------------
# A player preference, not gameplay state — deliberately independent of whether
# the item is currently held. Favoriting a spare, using the last one, then
# picking up a fresh one should not silently lose the mark.

func is_favorite(id: String) -> bool:
	return bool(favorites.get(id, false))


## Returns the new state, so a caller does not need a second is_favorite() call
## to know what just happened.
func toggle_favorite(id: String) -> bool:
	var next := not is_favorite(id)
	if next:
		favorites[id] = true
	else:
		favorites.erase(id)
	return next


# --- prepared meal ---------------------------------------------------------

func prepared_meal_id() -> String:
	return prepared_meal


## Move one held meal into the preparation slot. Replacing a meal is atomic: the
## previous meal must fit back into the post-removal bag or nothing changes.
## Item-definition validation stays in Inv, alongside gear validation.
func prepare_meal(item_id: String) -> bool:
	if item_id.is_empty() or item_id == prepared_meal or not has(item_id):
		return false
	var next_bag := bag.duplicate(true)
	_remove_from(next_bag, item_id, 1)
	if not prepared_meal.is_empty() and not _add_to(next_bag, prepared_meal, 1):
		return false
	bag = next_bag
	prepared_meal = item_id
	return true


## Return the prepared meal to the bag without loss. A full matching stack leaves
## the slot untouched so the player can use or replace it later.
func unprepare_meal() -> bool:
	if prepared_meal.is_empty():
		return false
	var next_bag := bag.duplicate(true)
	if not _add_to(next_bag, prepared_meal, 1):
		return false
	bag = next_bag
	prepared_meal = ""
	return true


## Clear and return the prepared id after combat has successfully resolved it.
func consume_prepared_meal(expected_id: String = "") -> String:
	if prepared_meal.is_empty() or (not expected_id.is_empty() and expected_id != prepared_meal):
		return ""
	var consumed := prepared_meal
	prepared_meal = ""
	return consumed


# --- persistence hooks (the save slice wires these to SaveGame) --------------

## Serialize the bag, coin purse, and equipped slot map. Old saves omit equipment;
## load_dict treats that as an empty loadout.
func to_dict() -> Dictionary:
	return {
		"inventory": bag.duplicate(true),
		"coins": coins,
		"equipment": equipment.duplicate(true),
		"favorites": favorites.keys(),
		"preparedMeal": prepared_meal,
	}


## Load from a save dict, tolerating a missing/partial payload. Quantities are
## coerced to positive ints and empty stacks dropped, so a hand-edited save can't
## seed a negative or zero stack.
func load_dict(data: Dictionary) -> void:
	bag.clear()
	equipment.clear()
	favorites.clear()
	prepared_meal = ""
	var raw: Dictionary = data.get("inventory", {})
	for id in raw:
		var qty := int(raw[id])
		if qty > 0:
			bag[String(id)] = qty
	var raw_equipment: Dictionary = data.get("equipment", {})
	for raw_slot in raw_equipment:
		var slot := String(raw_slot)
		var item_id := String(raw_equipment[raw_slot])
		if EQUIPMENT_SLOTS.has(slot) and not item_id.is_empty():
			equipment[slot] = item_id
	coins = maxi(0, int(data.get("coins", 0)))
	# Absent on any save written before this slice; that reads as no favorites,
	# not an error.
	for id in data.get("favorites", []):
		if not String(id).is_empty():
			favorites[String(id)] = true
	prepared_meal = String(data.get("preparedMeal", ""))


## Drop everything — used by a "new game" reset.
func clear() -> void:
	bag.clear()
	equipment.clear()
	favorites.clear()
	prepared_meal = ""
	coins = 0


# --- equipment -------------------------------------------------------------

## The equipped item id in one slot, or an empty string. Item definitions and level
## requirements stay outside this DB-free class; the Inv autoload validates those first.
func equipped_id(slot: String) -> String:
	return String(equipment.get(slot, ""))


func equipment_dict() -> Dictionary:
	return equipment.duplicate(true)


## Move one held item into its slot as an atomic transaction. Displaced gear returns
## to the bag. Two-handed weapon/offhand conflicts match the archived Kana rules.
func equip(item_id: String, slot: String, handedness: String = "",
		equipped_weapon_handedness: String = "") -> bool:
	if item_id.is_empty() or not EQUIPMENT_SLOTS.has(slot) or not has(item_id):
		return false

	var next_bag: Dictionary = bag.duplicate(true)
	var next_equipment: Dictionary = equipment.duplicate(true)
	_remove_from(next_bag, item_id, 1)

	var displaced_slots: Array[String] = []
	if slot == "weapon" and handedness == "2h" and next_equipment.has("offhand"):
		displaced_slots.append("offhand")
	if slot == "offhand" and equipped_weapon_handedness == "2h" \
			and next_equipment.has("weapon"):
		displaced_slots.append("weapon")
	if next_equipment.has(slot) and not displaced_slots.has(slot):
		displaced_slots.append(slot)

	for displaced_slot in displaced_slots:
		var displaced_id := String(next_equipment.get(displaced_slot, ""))
		next_equipment.erase(displaced_slot)
		if not displaced_id.is_empty() and not _add_to(next_bag, displaced_id, 1):
			return false

	next_equipment[slot] = item_id
	bag = next_bag
	equipment = next_equipment
	return true


## Return one equipped item to the bag. Fails without changing state if its stack is full.
func unequip(slot: String) -> bool:
	var item_id := equipped_id(slot)
	if item_id.is_empty():
		return false
	var next_bag: Dictionary = bag.duplicate(true)
	if not _add_to(next_bag, item_id, 1):
		return false
	bag = next_bag
	equipment.erase(slot)
	return true


func _add_to(target: Dictionary, id: String, qty: int) -> bool:
	var current := int(target.get(id, 0))
	if current + qty > MAX_STACK:
		return false
	target[id] = current + qty
	return true


func _remove_from(target: Dictionary, id: String, qty: int) -> void:
	var left := int(target.get(id, 0)) - qty
	if left <= 0:
		target.erase(id)
	else:
		target[id] = left
