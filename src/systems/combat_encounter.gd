class_name CombatEncounter
extends RefCounted
## One turn-based fight, as pure state + math. Node-free and headless-testable: the panel
## renders this and feeds it choices, but every rule lives here.
##
## The learning contract (COMBAT_DESIGN.md): recall is the input method, not a toll booth.
## Each round the enemy raises a guard word; your four moves are labelled in Japanese and
## picking the matching one IS the recall. A wrong pick still swings — CombatLogic halves
## the damage rather than cancelling the action — so a miss costs tempo, never agency.
##
## Damage, the wrong-answer penalty, and Recall Flow all come from the ported CombatLogic,
## so combat keeps the balance the TS build was actually playtested with.

## Result of resolving one player choice.
class RoundResult extends RefCounted:
	var correct: bool
	var player_damage_dealt: int
	var enemy_damage_dealt: int
	var flow_after: int
	var enemy_defeated: bool
	var player_defeated: bool
	var answer: String        ## the right Japanese, for revealing on a miss

var player_hp: int
var player_max_hp: int
var player_atk: int
var player_def: int

var enemy_id: String
var enemy_name: String
var enemy_hp: int
var enemy_max_hp: int
var enemy_atk: int
var enemy_def: int

## Consecutive correct recalls. Drives CombatLogic.flow_multiplier — accurate recall
## literally hits harder, and a miss resets it.
var flow: int = 0

## Deterministic variance for tests. -1 draws a fresh roll at runtime like the TS build.
var roll: float = -1.0


func _init(enemy_def_dict: Dictionary, hp: int, max_hp: int, atk: int = 6, def_stat: int = 2) -> void:
	enemy_id = String(enemy_def_dict.get("id", "enemy"))
	enemy_name = String(enemy_def_dict.get("name", enemy_id))
	enemy_max_hp = int(enemy_def_dict.get("maxHp", 30))
	enemy_hp = enemy_max_hp
	enemy_atk = int(enemy_def_dict.get("atk", 6))
	enemy_def = int(enemy_def_dict.get("def", 1))
	player_hp = hp
	player_max_hp = max_hp
	player_atk = atk
	player_def = def_stat


## Resolve one round: the player's swing, then the enemy's if it survived.
## `chosen` and `answer` are compared case/space-insensitively, matching LearningProgression.
func resolve(chosen: String, answer: String) -> RoundResult:
	var r := RoundResult.new()
	r.answer = answer
	r.correct = _normalize(chosen) == _normalize(answer)

	# Recall Flow updates BEFORE the swing, so a correct answer's own stack counts toward it.
	flow = flow + 1 if r.correct else 0
	r.flow_after = flow

	var power := int(round(CombatLogic.BASIC_ATTACK_POWER * CombatLogic.flow_multiplier(flow)))
	r.player_damage_dealt = CombatLogic.ability_damage(power, player_atk, enemy_def, r.correct, roll)
	enemy_hp = CombatLogic.apply_damage(enemy_hp, r.player_damage_dealt)
	r.enemy_defeated = CombatLogic.is_dead(enemy_hp)

	# A defeated enemy does not get a parting shot.
	if not r.enemy_defeated:
		r.enemy_damage_dealt = CombatLogic.enemy_damage(enemy_atk, player_def, roll)
		player_hp = CombatLogic.apply_damage(player_hp, r.enemy_damage_dealt)
		r.player_defeated = CombatLogic.is_dead(player_hp)

	return r


## Build one round's challenge from a card plus a pool to draw wrong runes from.
##
## This INVERTS the usual recall prompt. The notebook and gates ask "what does み mean?"
## (recognition); combat shows the meaning and asks you to produce み (production), which
## is the harder direction and the one that actually sticks. It is also what makes the
## action menu Japanese: every button is a rune, so reading them is how you fight.
##
## Returns { "guard": String, "choices": Array[String], "answer": String } — `answer` is the
## Japanese the player must pick. Distractors are deduped against the answer so a round can
## never present the same rune twice.
static func build_challenge(card: Dictionary, pool: Array, rng: RandomNumberGenerator, count: int = 4) -> Dictionary:
	var answer := String(card.get("prompt", ""))
	# Show the meaning when the card has one, else its plain answer (kana use romaji).
	var meaning := String(card.get("meaning", ""))
	var guard := meaning if not meaning.is_empty() else String(card.get("answer", ""))

	var seen := {answer: true}
	var runes: Array[String] = []
	var shuffled := pool.duplicate()
	shuffled.shuffle()

	# Prefer distractors of the SAME card type. Offering さかな against "vowel u" is not a
	# test — the player rules it out on shape alone without knowing う. Same-type runes
	# force an actual recall. Mixed types are only a fallback when the pool is too thin.
	var card_type := String(card.get("type", ""))
	for pass_num in 2:
		var same_type_only := pass_num == 0
		for c in shuffled:
			if runes.size() >= count - 1:
				break
			if same_type_only and String(c.get("type", "")) != card_type:
				continue
			var p := String(c.get("prompt", ""))
			if p.is_empty() or seen.has(p):
				continue
			seen[p] = true
			runes.append(p)
		if runes.size() >= count - 1:
			break

	runes.append(answer)
	runes.shuffle()
	return {"guard": guard, "choices": runes, "answer": answer}


func is_over() -> bool:
	return CombatLogic.is_dead(enemy_hp) or CombatLogic.is_dead(player_hp)


func player_won() -> bool:
	return CombatLogic.is_dead(enemy_hp) and not CombatLogic.is_dead(player_hp)


static func _normalize(s: String) -> String:
	return s.strip_edges().to_lower()
