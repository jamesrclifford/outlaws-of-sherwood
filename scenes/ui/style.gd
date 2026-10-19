## Shared look for the screens: wooden buttons, dark panels and parchment plaques,
## all 9-slice frames drawn by tools/make_scenery.py.
extends RefCounted

const UI := "res://assets/ui/%s.png"
const TEXT := Color("f0e6cc")


static func frame(name: String, margin := 4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(UI % name)
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(margin)
	return sb


## A theme for a whole screen; children pick it up automatically.
static func theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", frame("button"))
	t.set_stylebox("hover", "Button", frame("button_hover"))
	t.set_stylebox("pressed", "Button", frame("button_pressed"))
	t.set_stylebox("disabled", "Button", frame("button_disabled"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("fff4d8"))
	t.set_color("font_pressed_color", "Button", Color("d8c8a0"))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color("8a7a60"))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_stylebox("panel", "Panel", frame("panel"))
	return t


## A dark wooden panel covering the given rectangle.
static func panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A button with no frame, for things that are already pictures (units, places on the map).
static func flat(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
