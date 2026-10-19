## Prototype menu: start or continue the campaign, or practise a single mission or battle.
extends Control

const GameData = preload("res://core/game_data.gd")
const Campaign = preload("res://core/campaign.gd")
const MapView = preload("res://scenes/map/map_view.gd")
const MissionView = preload("res://scenes/mission/mission_view.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1d2b1f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(40, 90)
	box.size = Vector2(280, 400)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Outlaws of Sherwood\n(prototype)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	if Campaign.has_save():
		_button(box, "Continue campaign", func():
			var db = GameData.new()
			_open_map(db, Campaign.load_saved(db)))
	_button(box, "New campaign", func(): _open_map(null, null))
	var practice := Label.new()
	practice.text = "Practice"
	practice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(practice)
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


func _open_map(db, campaign) -> void:
	var view := MapView.new()
	if campaign != null:
		view.start(db, campaign)
	_switch_to(view)


func _switch_to(view: Control) -> void:
	var tree := get_tree()
	tree.root.add_child(view)
	tree.current_scene = view
	queue_free()


func _start_mission(type: String, threat: int) -> void:
	var view := MissionView.new()
	view.mission_type = type
	view.threat = threat
	_switch_to(view)
