## Prototype menu: pick a mission type and threat level, or a quick battle.
extends Control

const MissionView = preload("res://scenes/mission/mission_view.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1d2b1f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(40, 140)
	box.size = Vector2(280, 400)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Outlaws of Sherwood\n(prototype)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	for entry in [["Robbery (low threat)", "robbery", 20], ["Robbery (high threat)", "robbery", 80],
			["Rescue (low threat)", "rescue", 20], ["Rescue (high threat)", "rescue", 80]]:
		_button(box, entry[0], _start_mission.bind(entry[1], entry[2]))
	_button(box, "Quick battle", func(): get_tree().change_scene_to_file("res://scenes/battle/battle_scene.tscn"))


func _button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	box.add_child(b)


func _start_mission(type: String, threat: int) -> void:
	var view := MissionView.new()
	view.mission_type = type
	view.threat = threat
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	var tree := get_tree()
	tree.root.add_child(view)
	tree.current_scene = view
	queue_free()
