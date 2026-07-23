extends Node
## Global signal bus. Replaces the old EventBus.ts pub/sub module.
##
## Systems emit here rather than holding references to each other, which is what
## kept the TS systems layer testable in isolation. Keep signal names stable —
## they are the seams between gameplay, UI, and persistence.

# --- UI feedback ---
signal toast(text: String)
signal hud_refresh()

# --- dialogue / interaction ---
signal dialogue_open(speaker: String, lines: Array[String])
signal dialogue_closed()

# --- the learning loop ---
## Request a recall session. `focus_lesson` empty means "whatever is due".
signal learn_open(focus_lesson: String, session_size: int, allow_practice: bool)
## Result of a recall session: how many cards were attempted, and whether the
## player bailed out. LessonGate keys its retry loop off `attempted`/`cancelled`.
signal learn_closed(attempted: int, correct: int, cancelled: bool)
signal card_reviewed(card_id: String, grade: String, correct: bool)

# --- progression ---
signal xp_gained(amount: int)
signal level_up(level: int)
signal flag_set(flag: String, value: bool)

# --- inventory ---
signal item_added(item_id: String, qty: int)
signal item_removed(item_id: String, qty: int)
signal coins_changed(coins: int)
## Fired after any inventory mutation so panels can refresh without polling.
signal inventory_changed()

# --- combat ---
signal combat_started(enemy_id: String)
signal combat_ended(victory: bool)
## Per-hit resolution: a single strike landed on an enemy.
signal enemy_damaged(enemy_id: String, amount: int, remaining_hp: int)
signal enemy_died(enemy_id: String)
## The player swung; `facing` is the attack direction ("down"/"up"/"left"/"right").
signal player_attacked(facing: String)

# --- player vitals ---
signal player_hp_changed(hp: int, max_hp: int)
signal player_died()

# --- persistence ---
signal game_saved()
signal game_loaded()

# --- world / NPCs ---
signal npc_talked(npc_id: String)
