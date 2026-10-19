## Saves screenshots of the title screen, a mission briefing, a legend's briefing and duel, and a battle mid-attack.
## xvfb-run godot --path . --rendering-driver opengl3 -s tests/screenshots.gd -- out_dir
extends SceneTree

const MissionView = preload("res://scenes/mission/mission_view.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")
const GameData = preload("res://core/game_data.gd")
const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")


func _snap(dir: String, tag: String) -> void:
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, tag])


func _clear() -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame


func _init() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	root.add_child(load("res://scenes/menu/main_menu.tscn").instantiate())
	await _snap(dir, "menu")
	await _clear()

	var mission := MissionView.new()
	mission.mission_type = "robbery"
	mission.threat = 40
	root.add_child(mission)
	await _snap(dir, "mission")
	await _clear()

	var db = GameData.new()
	var story := MissionView.new()
	var run = MissionRun.new(db, MissionGen.new(db).story("little_john_bridge", 25, 1), [db.make_hero("robin"), db.make_hero("will")])
	story.play(db, run)
	root.add_child(story)
	await _snap(dir, "story")
	# Walk to the duel on the bridge.
	for i in 2:
		story.buttons.get_child(story.buttons.get_child_count() - 1).pressed.emit()
		await process_frame
		await process_frame
	await _snap(dir, "story_choice")
	# A long log must stop above the choice buttons rather than run under them.
	var keep: Array = run.mission_log.duplicate()
	for i in 12:
		run.mission_log.append("Line %d of a long story, long enough to wrap onto a second line of the briefing panel." % i)
	story._refresh()
	await _snap(dir, "story_long_log")
	run.mission_log = keep
	story._refresh()
	story.buttons.get_child(0).pressed.emit()
	await process_frame
	await process_frame
	story.buttons.get_child(0).pressed.emit()   # Onward, to the bridge
	for i in 30:
		await process_frame
	await _snap(dir, "duel")
	await _clear()

	var battle := BattleView.new()
	root.add_child(battle)
	for i in 10:
		await process_frame
	# Wait for a hero's turn, then attack and capture the moment the blow lands.
	while battle.battle.current().side != "heroes" or battle.animating:
		await process_frame
	var cur = battle.battle.current()
	var ability: String = battle.battle.usable_abilities(cur).filter(func(a): return battle.db.abilities[a]["target"] == "enemy")[0]
	battle._on_ability_pressed(ability)
	battle._on_unit_pressed(battle.battle.legal_targets(cur, ability)[0])
	await create_timer(0.2).timeout
	await _snap(dir, "battle_hit")
	quit()
