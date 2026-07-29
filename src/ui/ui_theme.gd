class_name UiTheme
extends RefCounted
## The one source of truth for UI colour, spacing, and type — the "shared tokens" the
## UI_UX_GUIDE calls Next/Essential.
##
## Values are the guide's token table verbatim (section 16), written as hex so they can be
## diffed against the doc without decoding floats. Before this existed, seven panels each
## declared their own COL_* constants — 60 in total — and they had already drifted: the modal
## dim was 60% instead of 66%, and the danger red was #D97366 rather than #FF9B9B. One
## definition means a palette change lands everywhere at once.
##
## Also holds the small builders (panel/button/label) every panel was hand-rolling, so chrome
## stays consistent by default instead of by discipline.

# --- surfaces -------------------------------------------------------------
const SURFACE_BACKDROP := Color("05080c", 0.66)   ## modal dim
const SURFACE_BASE := Color("141b24")             ## panels
const SURFACE_RAISED := Color("1b2530")           ## cards / rows
const SURFACE_DEEP := Color("0e151d")             ## inset areas

# --- borders --------------------------------------------------------------
const BORDER_SUBTLE := Color("2a3744")
const BORDER_STRONG := Color("3c5168")

# --- text -----------------------------------------------------------------
const TEXT_PRIMARY := Color("eef1f5")
const TEXT_MUTED := Color("9fb0c3")

# --- accents and state ----------------------------------------------------
const ACCENT_GOLD := Color("ffd27d")              ## focus / headings
const STATE_SUCCESS := Color("9be7a3")
const STATE_INFO := Color("9fd6ff")
const STATE_DANGER := Color("ff9b9b")
const LEARNING_VIOLET := Color("c27ba0")          ## learning identity

# Derived fills, written out rather than computed: `const` cannot hold a call like
# `STATE_SUCCESS.darkened(0.45)`. These are the answer-feedback and disabled tones — the
# state colours are text-weight, too light to sit behind white button labels.
const FILL_CORRECT := Color("2e7d4f")             ## correct-answer button
const FILL_WRONG := Color("9e3b3b")               ## wrong-answer button
const TEXT_DISABLED := Color("6b7885")            ## unavailable / locked rows

# --- spacing: the guide's 8px unit ---------------------------------------
const UNIT := 8
const PAD_PANEL := UNIT * 2      # 16
const GAP_ROW := UNIT            # 8

# --- type scale (minimums at the 800x600 logical size) -------------------
const FONT_TITLE := 22
const FONT_SECTION := 16
const FONT_BODY := 14
const FONT_META := 12
## Japanese needs to be bigger than body text to stay legible at 16px-art scale.
const FONT_JAPANESE := 30

# --- motion (seconds) -----------------------------------------------------
const MOTION_PRESS := 0.07
const MOTION_FOCUS := 0.08
const MOTION_PANEL := 0.14
const MOTION_TOAST := 0.18


## A panel frame: integer-aligned, 2px inner border, restrained radius.
static func panel_style(border: Color = ACCENT_GOLD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE_BASE
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = border
	return s


## An inset card/row inside a panel.
static func card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE_RAISED
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = BORDER_SUBTLE
	return s


static func button_style(bg: Color = SURFACE_RAISED, border: Color = BORDER_STRONG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = UNIT + 2
	s.content_margin_right = UNIT + 2
	s.content_margin_top = UNIT
	s.content_margin_bottom = UNIT
	return s


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT_PRIMARY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Full-screen dim behind a modal.
static func backdrop() -> ColorRect:
	var d := ColorRect.new()
	d.color = SURFACE_BACKDROP
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	return d


## Outline so focus is readable without relying on colour alone (guide: "Focus uses
## outline/cursor shape as well as color").
static func focus_style() -> StyleBoxFlat:
	var s := button_style(SURFACE_RAISED.lightened(0.06), ACCENT_GOLD)
	s.set_border_width_all(3)
	return s
