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
const Campaign = preload("res://core/campaign.gd")
const TipCard = preload("res://scenes/ui/tip_card.gd")
const Tips = preload("res://core/tips.gd")


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
	# Tutorial tips stay out of the way except in their own shots.
	TipCard.store = Tips.new("user://shot_tips.cfg")
	TipCard.store.reset()
	TipCard.store.enabled = false
	root.add_child(load("res://scenes/menu/main_menu.tscn").instantiate())
	await _snap(dir, "menu")
	await _clear()

	var map := MapView.new()
	root.add_child(map)
	await _snap(dir, "map")
	TipCard.store.enabled = true
	map._next_tip()
	await _snap(dir, "tip_map")
	for ch in map.get_children():
		if ch is TipCard:
			ch._close()
	await process_frame
	await _snap(dir, "tip_legends")
	for ch in map.get_children():
		if ch is TipCard:
			ch._close()
	TipCard.store.enabled = false
	map.campaign.stories_done = ["will_meets_robin", "little_john_bridge", "potter", "tinker", "beggar"]
	map._show_legends()
	await _snap(dir, "legends")
	for ch in map.get_children():
		if ch is Control and ch.mouse_filter == Control.MOUSE_FILTER_STOP and ch.get_child_count() > 0 and ch.get_child(0) is ColorRect:
			ch.queue_free()
	map.busy = false
	map.campaign.stories_done = []
	map._show_armory("robin")
	await _snap(dir, "armory")
	await _clear()

	var mission := MissionView.new()
	mission.mission_type = "robbery"
	mission.threat = 40
	root.add_child(mission)
	await _snap(dir, "mission")
	mission.buttons.get_child(1).pressed.emit()   # Go in disguise
	await _snap(dir, "disguise_pick")
	mission.buttons.get_child(0).pressed.emit()
	await _snap(dir, "disguise_worn")
	await _clear()

	var db = GameData.new()
	# Maid Marian: on an ordinary job, at her own legend, and as the page in the greenwood.
	var job: Dictionary = MissionGen.new(db).generate("robbery", 40, 11, "great_north_road")
	MissionGen.new(db).add_marian(job, "distraction")
	var with_marian := MissionView.new()
	with_marian.play(db, MissionRun.new(db, job, [db.make_hero("robin"), db.make_hero("will"), db.make_hero("little_john"), db.make_hero("tuck"), db.make_hero("alan")]))
	root.add_child(with_marian)
	await _snap(dir, "marian_job")
	await _clear()
	var fair := MissionView.new()
	fair.play(db, MissionRun.new(db, MissionGen.new(db).story("marian_alms", 30, 2), [db.make_hero("robin"), db.make_hero("will"), db.make_hero("little_john")]))
	root.add_child(fair)
	await _snap(dir, "marian_legend")
	await _clear()
	var page_run = MissionRun.new(db, MissionGen.new(db).story("marian_page", 20, 3), [db.make_hero("robin"), db.make_hero("will")])
	page_run.node_index = 2
	var duel := BattleView.new()
	duel.run_battle(db, page_run.make_battle(["rival_marian"]), "The page", page_run.backdrop())
	root.add_child(duel)
	await _snap(dir, "marian_duel")
	await _clear()

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
	battle._on_ability_pressed(battle.battle.usable_abilities(hero).filter(func(a): return battle.db.abilities[a]["target"] == "enemy")[0])
	await _snap(dir, "battle_aim")
	battle.selected_ability = ""
	# Tuck in the back row has five abilities: three rows, clear of the commands.
	for i in 3000:
		if not battle.animating and battle.battle.current() != null and battle.battle.current().id == "tuck" and battle.actions_box.get_child_count() > 0:
			break
		if not battle.animating and battle.battle.current() != null and battle.battle.current().side == "heroes":
			battle._end_hero_turn()
		await process_frame
	await _snap(dir, "battle_tuck")
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
		TipCard.store.enabled = kind == "aim"
		root.add_child(game)
		if kind == "aim":
			await _snap(dir, "tip_aim")
			for ch in game.get_children():
				if ch is TipCard:
					ch._close()
			TipCard.store.enabled = false
		await process_frame
		game.t = 0.4
		if kind == "rhythm":
			game.tap()
			game._paused = 0.0
			game._flash = ""
		await _snap(dir, "move_" + kind)
		await _clear()

	# The Sheriff hits back: a wanted poster, a bounty hunters' ambush, the castle and the victory.
	var cdb = GameData.new()
	var camp = Campaign.new(cdb, 12, Campaign.FULL_BAND)
	camp.infamy = 55
	camp._update_wanted()
	var wanted_map := MapView.new()
	wanted_map.start(cdb, camp)
	root.add_child(wanted_map)
	await _snap(dir, "wanted_poster")
	wanted_map.get_child(wanted_map.get_child_count() - 1).queue_free()
	wanted_map.busy = false
	camp.location = "great_north_road"
	camp.ambush = MissionGen.new(cdb).ambush(cdb.economy["wanted"]["hunters"][2], "Great North Road", "great_north_road", camp.bounty(), 5)
	wanted_map._select("great_north_road")
	await _snap(dir, "wanted_map")
	wanted_map._play(camp.start_ambush())
	await _snap(dir, "ambush")
	await _clear()
	var finale_run = MissionRun.new(cdb, MissionGen.new(cdb).story("storm_castle", 60, 3), camp.party())
	finale_run.node_index = 4
	var castle := BattleView.new()
	castle.run_battle(cdb, finale_run.make_battle(finale_run.current_node()["enemies"]), finale_run.current_node()["text"], "castle_courtyard")
	root.add_child(castle)
	for i in 10:
		await process_frame
	await _snap(dir, "castle")
	await _clear()
	var won_map := MapView.new()
	won_map.start(cdb, camp)
	root.add_child(won_map)
	await process_frame
	won_map._show_finale()
	await _snap(dir, "finale")
	await _clear()
	# After the wedding Marian lives at Major Oak Camp.
	var home = Campaign.new(cdb, 5, Campaign.FULL_BAND)
	home.flags.append("marian_wed")
	var home_map := MapView.new()
	home_map.start(cdb, home)
	root.add_child(home_map)
	home.rest()
	home_map._after_day()
	await _snap(dir, "marian_home")
	# The camp: a few things built, a visitor waiting, an evening, and the build list.
	home.gold = 300
	for id in ["lookout", "larder", "butts", "hall", "hall", "hall", "hunting", "herbs", "paths"]:
		home.upgrades.append(id)
	home.visitor = "pedlar"
	home.visitor_until = home.day + 3
	home_map._select("camp")
	home_map._show_camp()
	await _snap(dir, "camp")
	var cv = home_map.get_child(home_map.get_child_count() - 1)
	cv._show_visitor()
	await _snap(dir, "camp_visitor")
	home.upgrades = ["lookout", "larder"]
	cv._show_build("")
	await _snap(dir, "camp_build")
	home.evening = "rain"
	cv._rest()
	await _snap(dir, "camp_evening")
	await _clear()
	quit()
