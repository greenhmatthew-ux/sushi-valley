extends RefCounted
## Attack effects for the combat panel.
##
## Every one of the 68 abilities used to resolve identically on screen: a number moved and a
## sentence changed. A committed sword blow, a five-hit flurry and a thrown kunai were the
## same event visually, which is most of why combat did not read as a fight even after the
## hit flash and the wind-up were added.
##
## The effect is chosen from the ability's OWN data -- its `style`, `type` and `hits` -- not
## from a per-ability lookup. There are 68 abilities and a table listing them would be wrong
## the day a 69th is added; a blade ability with 3 hits gets the heavy cross by construction.
##
## Art is Ninja Adventure's FX/Attack set (CC0), seven sheets of uniform 32x32 frames.
## Defensive abilities deliberately get NO slash: a block that threw a sword arc across the
## screen would read as an attack. They are carried by the existing shield/flash feedback.

const FRAME := 32
const FPS := 22.0
## Drawn over the portrait at 2x so a 32px effect covers a 48px portrait and reads clearly.
const SCALE := 2.0

const SHEETS := {
	"cut": preload("res://assets/fx/fx_cut.png"),
	"cutdouble": preload("res://assets/fx/fx_cutdouble.png"),
	"cutx": preload("res://assets/fx/fx_cutx.png"),
	"claw": preload("res://assets/fx/fx_claw.png"),
	"clawdouble": preload("res://assets/fx/fx_clawdouble.png"),
	"circularslash": preload("res://assets/fx/fx_circularslash.png"),
	"slashcurved": preload("res://assets/fx/fx_slashcurved.png"),
}

## Per-effect tint, so two abilities sharing a sheet still read as different techniques.
const TINTS := {
	"kana": Color(0.72, 0.80, 1.0),      # rune work reads cold
	"counter": Color(1.0, 0.88, 0.55),   # returned damage reads gold
	"enemy": Color(1.0, 0.80, 0.80),     # the foe's own strike reads hostile
	"impact": Color(1.0, 0.86, 0.62),    # a heavy weapon driven into the ground reads earthy
}


## Which sheet an ability should throw, or "" when it should throw none.
##
## `ability` is a row from abilities.json; an empty dictionary means the plain weapon attack
## every player has before they pick anything, which is a single cut.
static func effect_for(ability: Dictionary) -> String:
	var kind := String(ability.get("type", "attack"))
	# Blocks, parries, buffs and heals are not strikes and must not draw one.
	if kind in ["block", "parry", "buff", "heal"]:
		return ""
	if kind == "counter":
		return "clawdouble"
	var hits := int(ability.get("hits", 1))
	match String(ability.get("style", "blade")):
		"ranged":
			return "cutx"
		"kana":
			return "circularslash"
		"focus", "guard":
			# Reached only by an ATTACK, since blocks/parries/buffs/heals returned above. The
			# guardian's heavy-weapon slams (Ironquake, Titan Slam) live here: a ground strike,
			# so it throws the ring rather than a sword arc. The test caught these resolving
			# with no visual at all, which is the exact thing this file exists to stop.
			return "circularslash"
		_:
			# blade, and anything new that does not name a style: a heavier arc for a flurry.
			if hits >= 3:
				return "slashcurved"
			return "cutdouble" if hits == 2 else "cut"


static func tint_for(ability: Dictionary) -> Color:
	if String(ability.get("type", "")) == "counter":
		return TINTS["counter"]
	if String(ability.get("style", "")) == "kana":
		return TINTS["kana"]
	if String(ability.get("style", "")) in ["guard", "focus"]:
		return TINTS["impact"]
	return Color.WHITE


## Play `effect` centred on `target`, parented to `layer`.
##
## `layer` is the panel's existing hit overlay — it already ignores mouse input and is already
## excluded from the container layout, so an effect cannot reflow the round mid-swing the way
## a laid-out child would.
static func play(layer: Control, target: Control, effect: String, tint: Color) -> void:
	if layer == null or target == null or effect.is_empty():
		return
	var sheet: Texture2D = SHEETS.get(effect)
	if sheet == null:
		return
	var frames := int(sheet.get_width() / FRAME)
	if frames <= 0:
		return

	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, FRAME, FRAME)
	# Stops the next frame bleeding in along the seam once the sprite is scaled up.
	atlas.filter_clip = true

	var sprite := TextureRect.new()
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = tint
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.size = Vector2(FRAME, FRAME) * SCALE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(sprite)

	# Centre on the target's middle, in the layer's own space.
	var centre := target.global_position + target.size * 0.5
	sprite.global_position = centre - sprite.size * 0.5

	var tween := sprite.create_tween()
	tween.tween_method(
		func(f: float) -> void:
			var index: int = clampi(int(f), 0, frames - 1)
			atlas.region = Rect2(index * FRAME, 0, FRAME, FRAME),
		0.0, float(frames), float(frames) / FPS)
	tween.tween_callback(sprite.queue_free)
