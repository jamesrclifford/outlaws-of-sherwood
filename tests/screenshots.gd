## Saves screenshots of the title screen, a mission briefing, a legend's briefing and duel, and a battle mid-attack.
## xvfb-run godot --path . --rendering-driver opengl3 -s tests/screenshots.gd -- out_dir
extends SceneTree

const MinigameView = preload("res://scenes/minigame/minigame_view.gd")
const Archery = preload("res://core/archery.gd")
const MapView = preload("res://scenes/map/map_view.gd")
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

	var map := MapView.new()
	root.add_child(map)
	await _snap(dir, "map")
	map._show_armory("robin")
	await _snap(dir, "armory")
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
	while battle.battle.current().side != "heroes" or battle.animating:
		await process_frame
	var hero = battle.battle.current()
	battle._on_ability_pressed(battle.db.heroes[hero.id]["abilities"][2] if battle.db.heroes.has(hero.id) else "strike")
	await _snap(dir, "battle_hint")
	await _clear()

	# Skill games: a contest after one arrow, an arrow move in battle, and Little John's sweep.
	var contest := MinigameView.new()
	contest.start_contest(Archery.new(4, 3, 0.7, "The Sheriff's archer"), "Robin", "robin", "The Sheriff's archer shoots against you")
	root.add_child(contest)
	await process_frame
	contest.t = 0.35
	contest.tap()
	contest.t = 0.6
	contest.tap()
	contest._paused = 0.0
	contest._flash = ""
	contest.t = 0.2
	contest.tap()
	contest.t = 0.3
	await _snap(dir, "contest")
	await _clear()
	var shot_db = GameData.new()
	for kind in ["aim", "swing", "rhythm"]:
		var move: String = {"aim": "split_arrow", "swing": "staff_sweep", "rhythm": "flourish"}[kind]
		var who: String = {"aim": "robin", "swing": "little_john", "rhythm": "will"}[kind]
		var game := MinigameView.new()
		game.start_move(7, kind, shot_db.abilities[move], who.capitalize(), who)
		root.add_child(game)
		await process_frame
		game.t = 0.4
		if kind == "rhythm":
			game.tap()
			game._paused = 0.0
			game._flash = ""
		await _snap(dir, "move_" + kind)
		await _clear()
	quit()
