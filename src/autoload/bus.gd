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
## Fired after the six-slot active ability loadout changes.
signal ability_loadout_changed()
## Fired after a saved stat allocation changes so the player and all summaries resync.
signal player_build_changed()

# --- crafting ---
signal crafting_open(station: String)
signal crafting_changed(station: String)

# --- settings ---
## Camera zoom preference changed. The live player camera listens and retunes itself,
## so no scene needs to hold a reference back to the Settings autoload.
signal zoom_changed(zoom: float)
## English visibility changed — either pinned in settings or peeked with the hold key.
## Bilingual surfaces (dialogue, signs) listen and re-render in place.
signal language_changed(english_visible: bool)
## Music/pronunciation volume preference changed. The Audio autoload listens and retunes
## live players, so panels never poke the audio players directly.
signal audio_settings_changed(music: float, voice: float)
## UI scale preference changed (UI_UX_GUIDE section 15's 80-160%). Every UI layer
## listens and re-fits itself; the world is deliberately untouched, so pixel art
## keeps its integer camera zoom.
signal ui_scale_changed(scale: float)
## Last-used input family changed. Visible prompts redraw from the real InputMap so
## controller players never get keyboard-only instructions after touching the pad.
signal input_method_changed(method: String)

# --- shop ---
## A vendor was interacted with — the ShopPanel opens on this, keyed by shop_id (a
## key into DB.shops). Kept a Bus signal so vendors never hold a UI reference.
signal shop_open(shop_id: String)
## A purchase went through: the item and the coins it cost. For quests / SFX later.
signal item_purchased(item_id: String, price: int)

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

# --- quests ---
## A quest was accepted; the HUD starts tracking it as the current objective.
signal quest_accepted(quest_id: String)
## A quest was turned in and paid out.
signal quest_completed(quest_id: String)
## The player chose which Quest, Raid, or Expedition should lead the objective HUD.
signal activity_tracking_changed(activity_key: String)

# --- farm / day ------------------------------------------------------------
signal farm_plot_open(plot_id: String)
signal sleep_requested()
signal farm_changed()

# --- fishing --------------------------------------------------------------
signal fishing_open(site_id: String, display_name: String, base_qty: int,
	cooldown_seconds: int, difficulty: float)
signal fishing_changed(site_id: String)
