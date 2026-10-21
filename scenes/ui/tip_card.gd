## A parchment card with one tutorial tip over the screen. "Got it" closes it; "No more tips" also
## turns the tutorial off. Nothing behind it can be tapped while it is open.
extends Control

const Tips = preload("res://core/tips.gd")
const Style = preload("res://scenes/ui/style.gd")

const INK := Color("3a2614")

signal closed

## Shared by every screen; tests point it at a scratch file.
static var store = null


static func tips():
	if store == null:
		store = Tips.new()
	return store


## Shows the tip once over parent, if it has not been seen. Returns the card (wait on its closed
## signal), or null when there is nothing to show.
static func show_once(parent: Control, id: String):
	var tip: Dictionary = tips().take(id)
	if tip.is_empty():
		return null
	var card = load("res://scenes/ui/tip_card.gd").new()
	card._tip = tip
	parent.add_child(card)
	return card


var _tip: Dictionary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.theme()
	var h := Style.screen_height(self)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var body := Label.new()
	body.text = _tip["text"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", INK)
	body.add_theme_constant_override("shadow_offset_x", 0)
	body.add_theme_constant_override("shadow_offset_y", 0)
	body.size = Vector2(276, 0)
	add_child(body)
	var text_h: float = body.get_line_count() * Style.LINE + 4
	var tall: float = 40 + text_h + 64
	var top: float = (h - tall) / 2
	var edge := ColorRect.new()
	edge.color = Color("6a4a2c")
	edge.position = Vector2(26, top)
	edge.size = Vector2(308, tall)
	add_child(edge)
	var paper := ColorRect.new()
	paper.color = Color("e8d8a8")
	paper.position = Vector2(30, top + 4)
	paper.size = Vector2(300, tall - 8)
	add_child(paper)
	var title := Label.new()
	title.text = _tip["title"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("8a1f1f"))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.position = Vector2(30, top + 12)
	title.size = Vector2(300, Style.lines(1))
	add_child(title)
	move_child(body, -1)
	body.position = Vector2(42, top + 40)
	body.size = Vector2(276, text_h)
	var got := Button.new()
	got.text = "Got it"
	got.position = Vector2(42, top + tall - 52)
	got.size = Vector2(130, 40)
	got.pressed.connect(_close)
	add_child(got)
	var off := Button.new()
	off.text = "No more tips"
	off.position = Vector2(188, top + tall - 52)
	off.size = Vector2(130, 40)
	off.pressed.connect(func():
		tips().turn_off()
		_close())
	add_child(off)


func _close() -> void:
	closed.emit()
	queue_free()
