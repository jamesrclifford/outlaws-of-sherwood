## Plays a short campaign through the real map UI: travel to jobs, play them via the mission screen.
## godot --headless --path . -s tests/map_smoke.gd   (pass a PNG path after -- to save map screenshots)
extends SceneTree

const MapView = preload("res://scenes/map/map_view.gd")
const MissionView = preload("res://scenes/mission/mission_view.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")


func _press(box: Container, prefix: String) -> bool:
	for b in box.get_children():
		if not b.is_queued_for_deletion() and b.text.begins_with(prefix):
			b.pressed.emit()
			return true
	return false


func _init() -> void:
	var shot: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var view := MapView.new()
	root.add_child(view)
	await process_frame
	if shot != "":
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_start.png"))
	var jobs := 0
	var frames := 0
	while jobs < 2 and frames < 30000:
		frames += 1
		await process_frame
		if view.busy:
			continue
		var mv = view.get_children().filter(func(c): return c is MissionView and not c.is_queued_for_deletion())
		if mv.is_empty():
			var c = view.campaign
			if c.missions.has(c.location):
				_press(view.buttons, "Start the job")
				jobs += 1
			elif not c.missions.is_empty():
				view._select(c.missions.keys()[0])
				_press(view.buttons, "Travel here")
			else:
				view._select("camp")
				if not _press(view.buttons, "Travel here"):
					_press(view.buttons, "Rest")
			continue
		var m = mv[0]
		var bvs = m.get_children().filter(func(c): return c is BattleView and not c.is_queued_for_deletion())
		if not bvs.is_empty():
			var bv = bvs[0]
			if bv.battle == null:
				continue
			if bv.battle.is_over():
				bv.finished.emit(bv.battle)
				continue
			var cur = bv.battle.current()
			if cur != null and cur.side == "heroes" and cur.ap > 0:
				var opts: Array = bv.battle.usable_abilities(cur).filter(func(a): return bv.db.abilities[a]["target"] == "enemy")
				if opts.is_empty():
					bv._end_hero_turn()
				else:
					bv._on_ability_pressed(opts[0])
					bv._on_unit_pressed(bv.battle.legal_targets(cur, opts[0])[0])
			continue
		var btns: Array = m.buttons.get_children().filter(func(b): return not b.is_queued_for_deletion())
		if not btns.is_empty():
			btns[btns.size() - 1].pressed.emit()
	# Let the last mission finish and return to the map.
	while frames < 40000:
		frames += 1
		await process_frame
		var mvs = view.get_children().filter(func(c): return c is MissionView and not c.is_queued_for_deletion())
		if mvs.is_empty():
			break
		var m = mvs[0]
		var bvs = m.get_children().filter(func(c): return c is BattleView and not c.is_queued_for_deletion())
		if bvs.is_empty():
			var btns: Array = m.buttons.get_children().filter(func(b): return not b.is_queued_for_deletion())
			if not btns.is_empty():
				btns[btns.size() - 1].pressed.emit()
			continue
		var bv = bvs[0]
		if bv.battle == null:
			continue
		if bv.battle.is_over():
			bv.finished.emit(bv.battle)
			continue
		var cur = bv.battle.current()
		if cur != null and cur.side == "heroes" and cur.ap > 0:
			var opts: Array = bv.battle.usable_abilities(cur).filter(func(a): return bv.db.abilities[a]["target"] == "enemy")
			if opts.is_empty():
				bv._end_hero_turn()
			else:
				bv._on_ability_pressed(opts[0])
				bv._on_unit_pressed(bv.battle.legal_targets(cur, opts[0])[0])
	var c = view.campaign
	print("Map smoke: %d jobs started, day %d, gold %d, at %s, captured %s" % [jobs, c.day, c.gold, c.location, c.captured.keys()])
	print("News: %s" % [c.news.slice(max(0, c.news.size() - 4))])
	if jobs < 2:
		printerr("SCRIPT ERROR: map UI did not get through two jobs")
	if shot != "":
		view._select(c.location)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_later.png"))
	quit()
