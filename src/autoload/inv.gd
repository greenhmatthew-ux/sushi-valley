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

const ConsumableRules = preload("res://src/systems/consumable_logic.gd")

var logic := InventoryLogic.new()

## Guards the autosave while load_dict is repopulating the bag from disk — otherwise
## restoring a save would immediately write it straight back out again.
var _restoring := false


func _ready() -> void:
	# The bag is the only subsystem whose loss is pure player time (gathered quest items,
	# earned coins), so it persists on every change rather than only at quit.
	Bus.inventory_changed.connect(_autosave)


func _autosave() -> void:
	if not _restoring:
		SaveGame.save_inventory(to_dict())


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


## Consume one supported healing item and return actual HP restored. Zero means the
## item was unsupported, absent, or would be wasted at full health; nothing is removed.
func use_healing_item(item_id: String, current_hp: int, max_hp: int) -> int:
	var item: Dictionary = DB.item(item_id)
	var restored := ConsumableRules.restored_hp(item, current_hp, max_hp)
	if restored <= 0 or remove(item_id, 1) != 1:
		return 0
	return restored


# --- equipment -------------------------------------------------------------

func equipped_id(slot: String) -> String:
	return logic.equipped_id(slot)


func equipment() -> Dictionary:
	return logic.equipment_dict()


func equipped_def(slot: String) -> Dictionary:
	var item_id := equipped_id(slot)
	return {} if item_id.is_empty() else DB.item(item_id)


func equipped_defs() -> Array[Dictionary]:
	var defs: Array[Dictionary] = []
	for slot in InventoryLogic.EQUIPMENT_SLOTS:
		var item_id := logic.equipped_id(slot)
		if item_id.is_empty():
			continue
		var item: Dictionary = DB.item(item_id)
		if not item.is_empty():
			defs.append(item)
	return defs


## Equip one held gear item after validating its authored slot and level floor.
## InventoryLogic performs the actual swap atomically, including two-hand conflicts.
func equip(item_id: String) -> bool:
	var item: Dictionary = DB.item(item_id)
	if item.get("kind", "") != "gear":
		return false
	var slot := String(item.get("slot", ""))
	if slot.is_empty() or not has(item_id):
		return false
	if _player_level() < int(item.get("requiredLevel", 1)):
		return false
	var weapon_handedness := String(equipped_def("weapon").get("handedness", ""))
	if not logic.equip(item_id, slot, String(item.get("handedness", "")),
			weapon_handedness):
		return false
	Bus.inventory_changed.emit()
	return true


func unequip(slot: String) -> bool:
	if not logic.unequip(slot):
		return false
	Bus.inventory_changed.emit()
	return true


func _player_level() -> int:
	var xp := 0
	if Learning.profile != null:
		xp = int(Learning.profile.data.get("stats", {}).get("xp", 0))
	return PlayerStats.level_from_xp(xp)


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
	_restoring = true
	logic.load_dict(data)
	Bus.coins_changed.emit(logic.coins)
	Bus.inventory_changed.emit()
	_restoring = false


func reset() -> void:
	logic.clear()
	Bus.coins_changed.emit(0)
	Bus.inventory_changed.emit()
