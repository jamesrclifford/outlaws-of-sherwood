## Title screen: the band around the fire under the Major Oak. Start or continue the campaign,
## or practise a single mission or battle.
extends Control

const GameData = preload("res://core/game_data.gd")
const Campaign = preload("res://core/campaign.gd")
const MapView = preload("res://scenes/map/map_view.gd")
const MissionView = preload("res://scenes/mission/mission_view.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")
const Style = preload("res://scenes/ui/style.gd")


func _ready() -> void:
	theme = Style.theme()
	# 180x320 art at 2x; the game's name is painted into it.
	var art := TextureRect.new()
	art.texture = preload("res://assets/ui/title.png")
	art.size = Vector2(360, 640)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(art)
	for i in 4:
		var hero := TextureRect.new()
		hero.texture = BattleView.sprite_by_id(["robin", "little_john", "will", "tuck"][i])
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_SCALE
		hero.size = Vector2(64, 64)
		hero.position = Vector2([20, 76, 220, 276][i], 506 if i in [0, 3] else 516)
		hero.flip_h = i >= 2
		add_child(hero)
	var box := VBoxContainer.new()
	box.position = Vector2(60, 132)
	box.size = Vector2(240, 360)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	if Campaign.has_save():
		_button(box, "Continue campaign", func():
			var db = GameData.new()
			_open_map(db, Campaign.load_saved(db)))
	_button(box, "New campaign", func(): _open_map(null, null))
	var practice := Label.new()
	practice.text = "- Practice -"
	practice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	practice.add_theme_color_override("font_color", Color("e0c890"))
	box.add_child(practice)
	for entry in [["Robbery (low threat)", "robbery", 20], ["Robbery (high threat)", "robbery", 80],
			["Rescue (low threat)", "rescue", 20], ["Rescue (high threat)", "rescue", 80]]:
		_button(box, entry[0], _start_mission.bind(entry[1], entry[2]))
	_button(box, "Quick battle", func(): get_tree().change_scene_to_file("res://scenes/battle/battle_scene.tscn"))


func _button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
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
