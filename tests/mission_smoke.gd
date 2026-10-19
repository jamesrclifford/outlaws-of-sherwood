## Clicks through whole missions in the real UI, fighting battles with a simple autoplayer.
## godot --headless --path . -s tests/mission_smoke.gd   (pass a PNG path after -- to save a screenshot mid-mission)
extends SceneTree

const MissionView = preload("res://scenes/mission/mission_view.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")


func _init() -> void:
	var shot: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for type in ["robbery", "rescue"]:
		var view := MissionView.new()
		view.mission_type = type
		view.threat = 80
		root.add_child(view)
		var steps := 0
		while steps < 20000:
			steps += 1
			await process_frame
			await process_frame
			if steps == 1 and shot != "":
				root.get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_%s.png" % type))
			var battle_view = view.get_children().filter(func(c): return c is BattleView)
			if not battle_view.is_empty():
				var bv = battle_view[0]
				if bv.battle == null:
					continue
				if bv.battle.is_over():
					bv.finished.emit(bv.battle)
				else:
					var cur = bv.battle.current()
					if cur != null and cur.side == "heroes" and cur.ap > 0:
						var opts: Array = bv.battle.usable_abilities(cur).filter(func(a): return bv.db.abilities[a]["target"] == "enemy")
						if opts.is_empty():
							bv._end_hero_turn()
						else:
							bv._on_ability_pressed(opts[0])
							bv._on_unit_pressed(bv.battle.legal_targets(cur, opts[0])[0])
				continue
			var btns: Array = view.buttons.get_children().filter(func(b): return not b.is_queued_for_deletion())
			if view.run.is_over():
				break
			if not btns.is_empty():
				btns[btns.size() - 1].pressed.emit()
		print("%s mission: %s after %d steps. %s" % [type, view.run.result, steps, view.run.mission_log.back()])
		if view.run.result == "":
			printerr("SCRIPT ERROR: mission UI did not finish")
		view.queue_free()
	quit()
