## Headless test runner: godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const GameData = preload("res://core/game_data.gd")
const Unit = preload("res://core/unit.gd")
const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")
const Campaign = preload("res://core/campaign.gd")
const MinigameView = preload("res://scenes/minigame/minigame_view.gd")

## The four heroes the older campaign tests were written for (a story campaign starts smaller).
const BAND4 := ["robin", "little_john", "will", "tuck"]

var failures := 0
var passed := 0
var db


func _init() -> void:
	db = GameData.new()
	for m in get_method_list():
		if m["name"].begins_with("test_"):
			call(m["name"])
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failures += 1
		printerr("FAIL: " + label)


## Plays a battle where heroes use their first usable ability on the weakest target.
func autoplay(b, max_turns := 400) -> void:
	var turns := 0
	while not b.is_over() and turns < max_turns:
		var u = b.next_turn()
		if u == null:
			break
		if u.side == "enemies":
			b.run_ai_turn()
		else:
			while not b.is_over() and u.ap > 0:
				var opts: Array = b.usable_abilities(u)
				opts = opts.filter(func(a): return a != "defend")
				if opts.is_empty():
					break
				var targets: Array = b.legal_targets(u, opts[0])
				targets.sort_custom(func(x, y): return x.hp < y.hp)
				b.perform(u, opts[0], targets[0])
			b.end_turn()
		turns += 1


## Travels like the map screen does: if bounty hunters jump the band on the way, fight them and walk on.
func go(c, to: String) -> void:
	for _i in 10:
		c.travel(to)
		if not c.ambush.is_empty():
			var run = c.start_ambush()
			autoplay_mission(run)
			c.finish_mission(run)
		if c.location == to or c.free_heroes().is_empty():
			return


func test_screens_load() -> void:
	# Screens aren't run headlessly, so at least make sure each one parses.
	for path in ["res://scenes/menu/main_menu.gd", "res://scenes/map/map_view.gd", "res://scenes/mission/mission_view.gd", "res://scenes/battle/battle_view.gd", "res://scenes/minigame/minigame_view.gd"]:
		check(load(path) != null, "%s loads" % path)


func test_data_references_are_valid() -> void:
	for set in [db.heroes, db.enemies]:
		for id in set:
			for a in set[id]["abilities"]:
				check(db.abilities.has(a), "%s references unknown ability %s" % [id, a])
	for e in db.encounters:
		for en in db.encounters[e]["enemies"]:
			check(db.enemies.has(en), "encounter %s references unknown enemy %s" % [e, en])
	for a in db.abilities:
		if db.abilities[a].has("summon"):
			check(db.enemies.has(db.abilities[a]["summon"]), "ability %s summons unknown enemy" % a)


func test_same_seed_replays_identically() -> void:
	var a = db.make_battle(["robin", "little_john", "will", "tuck"], "tax_wagon", 42)
	var b = db.make_battle(["robin", "little_john", "will", "tuck"], "tax_wagon", 42)
	autoplay(a)
	autoplay(b)
	check(a.battle_log == b.battle_log, "same seed should give identical battle logs")
	check(a.is_over(), "battle should finish")


func test_initiative_orders_by_speed() -> void:
	var b = db.make_battle(["robin", "little_john"], "forest_patrol", 1)
	b.next_turn()
	for i in range(b.turn_order.size() - 1):
		check(b.turn_order[i].effective_speed() >= b.turn_order[i + 1].effective_speed(), "turn order sorted by speed")


func test_melee_cannot_reach_back_row_while_front_stands() -> void:
	var b = db.make_battle(["will"], "tax_wagon", 3)
	var will = b.heroes()[0]
	var targets: Array = b.legal_targets(will, "strike")
	check(not targets.is_empty(), "will has melee targets")
	check(targets.all(func(t): return t.row == "front"), "melee only hits front row")
	var robin_b = db.make_battle(["robin"], "tax_wagon", 3)
	var shots: Array = robin_b.legal_targets(robin_b.heroes()[0], "bow_shot")
	check(shots.any(func(t): return t.row == "back"), "ranged can hit back row")


func test_back_row_cannot_use_melee_while_front_row_ally_stands() -> void:
	var b = db.make_battle(["robin", "little_john"], "tax_wagon", 3)
	var tuck = Unit.from_data("tuck", db.heroes["tuck"], "heroes")
	b.add_unit(tuck)
	check(b.legal_targets(tuck, "strike").is_empty(), "back-row tuck cannot melee past little john")


func test_back_row_gets_bow_shot() -> void:
	var b = db.make_battle(["robin", "little_john"], "tax_wagon", 3)
	var tuck = Unit.from_data("tuck", db.heroes["tuck"], "heroes")
	b.add_unit(tuck)
	check(tuck.available_abilities().has("bow_shot"), "back-row tuck can use a bow shot")
	check(b.legal_targets(tuck, "bow_shot").any(func(t): return t.row == "back"), "bow shot reaches the enemy back row")
	var john = b.heroes()[1]
	check(not john.available_abilities().has("bow_shot"), "front-row little john has no bow shot")
	john.row = "back"
	check(john.available_abilities().has("bow_shot"), "little john gets a bow shot after moving to the back row")
	check(tuck.available_abilities().count("bow_shot") == 1 and b.heroes()[0].available_abilities().count("bow_shot") == 1, "no duplicate bow shot")


func test_taunt_forces_targeting() -> void:
	var b = db.make_battle(["robin", "little_john"], "tax_wagon", 5)
	var john = b.heroes()[1]
	john.add_status("taunt", 2)
	var xbow = b.enemies()[3]
	check(b.legal_targets(xbow, "crossbow_bolt") == [john], "taunt forces single-target attacks onto little john")


func test_defeat_captures_downed_heroes_victory_revives() -> void:
	var lost = db.make_battle(["robin", "will"], "gisborne", 7)
	for h in lost.heroes():
		h.hp = 0
	lost._check_end()
	check(lost.result == "defeat", "all heroes down is a defeat")
	check(lost.captured.size() == 2, "downed heroes are captured on defeat, got %s" % [lost.captured])

	var won = db.make_battle(["robin", "will"], "tax_wagon", 7)
	won.heroes()[1].hp = 0
	for e in won.enemies():
		e.hp = 0
	won._check_end()
	check(won.result == "victory", "all enemies down is a victory")
	check(won.captured.is_empty() and won.heroes()[1].hp == 1, "downed heroes recover after a victory")


func test_enemies_are_knocked_out_and_gold_is_won() -> void:
	var b = db.make_battle(["robin", "little_john", "will", "tuck"], "tax_wagon", 11)
	autoplay(b)
	check(b.result in ["victory", "defeat", "retreated"], "battle resolved")
	check(not b.battle_log.any(func(l): return "killed" in l or "dies" in l), "nobody dies in a family adventure")


func test_netted_hero_loses_turn_until_freed() -> void:
	var b = db.make_battle(["robin", "little_john"], "gisborne", 2)
	var robin = b.heroes()[0]
	robin.add_status("netted", 2)
	check(not robin.begin_turn(), "netted hero skips their turn")
	robin.statuses.erase("netted")
	check(robin.begin_turn(), "freed hero can act")


func test_full_party_usually_beats_tax_wagon() -> void:
	var wins := 0
	for s in 50:
		var b = db.make_battle(["robin", "little_john", "will", "tuck"], "tax_wagon", 1000 + s)
		autoplay(b)
		if b.result == "victory":
			wins += 1
	print("tax_wagon win rate with simple autoplay: %d/50" % wins)
	check(wins >= 35, "full party should win most tax-wagon fights (got %d/50)" % wins)


# --- Missions ----------------------------------------------------------------

func party() -> Array:
	return ["robin", "little_john", "will", "tuck"].map(func(h): return db.make_hero(h))


## Plays a whole mission: walks into known traps, takes the first option, autoplays fights.
func autoplay_mission(run, use_scouts := false) -> void:
	if use_scouts:
		run.scout()
	var guard := 0
	while not run.is_over() and guard < 50:
		guard += 1
		var step: Dictionary = run.arrive()
		if step["type"] == "trap_choice":
			step = run.decide_trap(true)
		if step["type"] == "choice":
			# The second option where the band can afford it, else the first it can.
			var picks: Array = [1, 0] + range(2, step["options"].size())
			step = run.choose(picks.filter(func(i): return i < step["options"].size() and run.can_choose(i))[0])
		if step["type"] == "battle":
			var b = run.make_battle(step["enemies"])
			autoplay(b)
			run.battle_finished(b)
		if step["type"] == "archery":
			var round = run.make_archery()
			while not round.done():
				round.tap(0.4 * round.shots.size())
			run.archery_finished(round)
		run.advance()


func test_mission_data_references_are_valid() -> void:
	for l in db.locations:
		for e in db.locations[l]["enemy_pool"]:
			check(db.enemies.has(e), "location %s uses unknown enemy %s" % [l, e])
			check(MissionGen.ENEMY_COST.has(e), "enemy %s has no generator cost" % e)
		for m in db.locations[l]["missions"]:
			check(db.mission_templates.has(m), "location %s offers unknown mission %s" % [l, m])
	for t in db.traps:
		for e in db.traps[t].get("extra_enemies", []):
			check(db.enemies.has(e), "trap %s summons unknown enemy %s" % [t, e])


func test_generator_is_deterministic_and_valid() -> void:
	var gen = MissionGen.new(db)
	for s in 200:
		var type: String = ["robbery", "rescue"][s % 2]
		var m: Dictionary = gen.generate(type, s % 100, s)
		check(JSON.stringify(m) == JSON.stringify(gen.generate(type, s % 100, s)), "same seed gives the same mission")
		check(db.locations[m["location"]]["missions"].has(type), "location offers this mission type")
		check(m["nodes"].size() == db.mission_templates[type]["nodes"].size(), "node count follows the template")
		check(m["nodes"][0]["kind"] == "approach" and not m["nodes"][0].has("trap"), "missions start with a safe approach")
		var has_objective: bool = m["nodes"].any(func(n): return n["kind"] == "objective")
		check(has_objective, "every mission has an objective")
		for n in m["nodes"]:
			check(n.get("enemies", []).size() <= 5, "no more than five enemies per node")


func test_some_robberies_are_bait_more_at_high_threat() -> void:
	var gen = MissionGen.new(db)
	var low := 0
	var high := 0
	for s in 200:
		low += 1 if not gen.generate("robbery", 0, s)["bait"].is_empty() else 0
		high += 1 if not gen.generate("robbery", 90, s)["bait"].is_empty() else 0
	check(low > 0 and high > low, "bait robberies exist and are more common at high threat (%d vs %d of 200)" % [low, high])
	for s in 100:
		var m: Dictionary = gen.generate("rescue", 90, s)
		check(m["bait"].is_empty(), "rescues are never bait")


func test_only_bait_missions_have_traps() -> void:
	var gen = MissionGen.new(db)
	for s in 200:
		var m: Dictionary = gen.generate(["robbery", "rescue"][s % 2], 80, s, "", "little_john")
		var traps: Array = m["nodes"].filter(func(n): return n.has("trap"))
		if m["bait"].is_empty():
			check(traps.is_empty(), "an honest job has no planted traps")
		else:
			var by: String = m["bait"]["by"]
			check(traps.all(func(n): return db.traps[n["trap"]["id"]]["owner"] == by), "traps in a bait job belong to whoever set it")
			var goal: Dictionary = m["nodes"].filter(func(n): return n["kind"] == "objective")[0]
			check(goal.get("ambush", false) and not goal.get("loot", false), "the bait's prize is an ambush with no loot")
			if by == "guy":
				check(goal["enemies"].has("guy"), "Gisborne springs his own trap")


func _bait_mission(by: String) -> Dictionary:
	var gen = MissionGen.new(db)
	for s in 1000:
		var m: Dictionary = gen.generate("robbery", 90, s)
		if not m["bait"].is_empty() and m["bait"]["by"] == by:
			return m
	return {}


func test_scouts_can_expose_bait_and_call_it_off() -> void:
	var exposed := 0
	for s in 40:
		var m := _bait_mission("sheriff")
		m["seed"] = s
		var run = MissionRun.new(db, m, party())
		run.scout()
		if m["bait"]["revealed"]:
			exposed += 1
			run.call_off()
			check(run.result == "called_off" and run.gold == 0 and run.captured.is_empty(), "calling off a bait job is safe")
	check(exposed > 10 and exposed < 40, "scouts expose some but not all bait (%d/40)" % exposed)


func test_surviving_bait_pays_no_loot() -> void:
	for s in 20:
		var m := _bait_mission("guy")
		m["seed"] = s
		var run = MissionRun.new(db, m, party())
		autoplay_mission(run)
		check(run.is_over(), "bait mission finishes")
		if run.result == "success":
			check(not run.loot_taken, "there was never any loot in the bait wagon")


func test_gisborne_net_targets_the_hunted_hero() -> void:
	var gen = MissionGen.new(db)
	var m: Dictionary = gen.generate("rescue", 50, 5, "", "little_john")
	for n in m["nodes"]:
		n.erase("trap")
	m["nodes"][1]["trap"] = {"id": "net", "revealed": false, "target": "little_john"}
	var run = MissionRun.new(db, m, party())
	run.arrive()
	run.advance()
	run.arrive()
	var john = run.heroes[1]
	check(john.has_status("netted"), "the hunted hero gets caught in the net")


func test_revealed_trap_can_be_avoided() -> void:
	var gen = MissionGen.new(db)
	var m: Dictionary = gen.generate("robbery", 50, 9)
	for n in m["nodes"]:
		n.erase("trap")
	m["nodes"][1]["trap"] = {"id": "snare", "revealed": true, "target": ""}
	var run = MissionRun.new(db, m, party())
	run.arrive()
	run.advance()
	var step: Dictionary = run.arrive()
	check(step["type"] == "trap_choice", "a known trap asks the player what to do")
	run.decide_trap(true)
	check(run.heroes.all(func(h): return h.hp == h.max_hp), "avoiding the snare means nobody is hurt")


func test_missions_finish_and_failures_capture_not_kill() -> void:
	var gen = MissionGen.new(db)
	var wins := 0
	for s in 40:
		var run = MissionRun.new(db, gen.generate(["robbery", "rescue"][s % 2], 40, 500 + s), party())
		autoplay_mission(run, true)
		check(run.is_over(), "mission %d finishes" % s)
		if run.result == "success":
			wins += 1
			check(run.gold > 0 or run.is_bait(), "a successful honest mission pays out")
		else:
			check(run.gold == 0, "a failed mission pays nothing")
	print("mission success rate at threat 40 with simple autoplay: %d/40" % wins)
	check(wins >= 20, "a full party should succeed at most threat-40 missions (got %d/40)" % wins)


# --- Campaign / strategic map ------------------------------------------------

func test_map_data_is_consistent() -> void:
	for n in db.map["nodes"]:
		var nd: Dictionary = db.map["nodes"][n]
		check(db.map["regions"].has(nd["region"]), "%s is in a known region" % n)
		if nd.has("location"):
			check(db.locations.has(nd["location"]), "%s maps to a known mission location" % n)
		for l in nd["links"]:
			check(db.map["nodes"].has(l) and db.map["nodes"][l]["links"].has(n), "road %s-%s goes both ways" % [n, l])
	check(db.map["nodes"].has(Campaign.DUNGEON), "the dungeon is on the map")


func test_travel_takes_a_day_per_road_and_follows_shortest_route() -> void:
	var c = Campaign.new(db, 1, BAND4)
	var path: Array = c.route("nottingham")
	check(path == ["blidworth", "hanged_mans_crossing", "nottingham"], "shortest road from camp to Nottingham, got %s" % [path])
	c.travel("nottingham")
	check(c.day == 4 and c.location == "nottingham", "three roads take three days")


func test_resting_at_camp_heals() -> void:
	var c = Campaign.new(db, 2, BAND4)
	c.heroes["robin"].hp = 5
	c.rest()
	check(c.heroes["robin"].hp == c.heroes["robin"].max_hp, "a day at camp heals fully")
	c.travel("edwinstowe")
	var before: int = c.day
	c.rest()
	check(c.day == before, "you can only rest at camp")


func test_villains_plot_and_set_bait() -> void:
	var c = Campaign.new(db, 3, BAND4)
	for _i in 40:
		c.rest()
	var baits: Array = c.missions.values().filter(func(m): return not m["bait"].is_empty())
	check(c.news.any(func(n): return "Gisborne is hunting" in n), "Guy picks someone to hunt")
	check(c.news.any(func(n): return "Too rich" in n), "the Sheriff dangles a wagon")
	check(c.hunted_hero != "" and c.hunted_hero != "robin", "Guy hunts one of Robin's companions")
	check(c.control.values().all(func(v): return v >= 0 and v <= 100), "control stays within 0-100")
	check(c.missions.values().all(func(m): return m.get("expires", 0) >= c.day or m.has("rescue_heroes") or m["type"] == "story"), "old jobs expire")


func test_archery_rules() -> void:
	const Archery = preload("res://core/archery.gd")
	check(Archery.score_at(Vector2.ZERO) == 10 and Archery.score_at(Vector2(0.55, 0)) == 5 and Archery.score_at(Vector2(0, 1.2)) == 0, "rings score 10 in the gold down to 0 off the target")
	var a = Archery.new(5, 3, 0.7, "The champion")
	var b = Archery.new(5, 3, 0.7, "The champion")
	for i in 3:
		check(a.wind == b.wind and a.aim_at(0.8) == b.aim_at(0.8), "the same seed sways and blows the same way")
		check(a.aim_at(0.3).y == 0.0, "the first tap fixes the sight left and right")
		check(a.tap(0.3) == -1 and b.tap(0.3) == -1, "the first tap doesn't loose the arrow")
		var x: float = a.locked_x
		var expect: int = Archery.score_at(Vector2(x + a.wind * Archery.WIND_PUSH, a.aim_at(1.1).y))
		check(a.tap(1.1) == expect and b.tap(1.1) == expect, "the second tap looses it, and the wind carries it sideways")
	check(a.done() and a.total() == b.total() and a.rival_total() == b.rival_total(), "a round is three arrows each and replays exactly")
	check(a.won() == (a.total() >= a.rival_total()), "the higher score wins, ties to Robin")
	var weak := 0
	var strong := 0
	for s in 200:
		weak += Archery.new(s, 3, 0.3, "x").rival_total()
		strong += Archery.new(s, 3, 0.9, "x").rival_total()
	check(strong > weak, "a skilled rival outshoots a poor one (%d vs %d)" % [strong, weak])
	# Good timing hits the gold: fix the sight just into the wind, then loose it as it crosses the middle.
	for s in 20:
		var c = Archery.new(s, 1)
		var best_x := 0.0
		var best := 99.0
		for k in 300:
			var off := absf(c.landing(k * 0.01).x)
			if off < best:
				best = off
				best_x = k * 0.01
		c.tap(best_x)
		var best_y := 0.0
		best = 99.0
		for k in 300:
			if absf(c.aim_at(k * 0.01).y) < best:
				best = absf(c.aim_at(k * 0.01).y)
				best_y = k * 0.01
		check(c.tap(best_y) >= 9, "well-timed taps hit the gold (seed %d)" % s)


func test_timing_meter() -> void:
	const Timing = preload("res://core/timing.gd")
	check(Timing.quality_at(0.5) == 1.0 and Timing.quality_at(0.1) == 0.0 and Timing.quality_at(0.7) > 0.4, "a tap is judged by how near the middle it lands")
	var m = Timing.new(3, 3, 1.6)
	var n = Timing.new(3, 3, 1.6)
	for t in [0.2, 0.5, 0.9]:
		check(m.tap(t) == n.tap(t), "the same seed and timing judge the same")
	check(m.done() and m.qualities.size() == 3, "a flourish is three taps")


func test_minigames_reward_good_play() -> void:
	var dealt := {}
	for q in [0.0, 0.5, 1.0]:
		var b = db.make_battle(["robin"], "forest_patrol", 41)
		var hits := []
		b.damaged.connect(func(u, amount, crit): hits.append([amount, crit]))
		var robin = b.next_turn()
		while robin != null and robin.id != "robin":
			b.run_ai_turn()
			robin = b.next_turn()
		robin.ap = 2
		var target = b.legal_targets(robin, "split_arrow")[0]
		target.hp = 999
		hits.clear()
		b.perform(robin, "split_arrow", target, [q])
		dealt[q] = hits[0]
	check(dealt[0.0][0] < dealt[0.5][0] and dealt[0.5][0] < dealt[1.0][0], "a better aimed shot hits harder (%s)" % [dealt])
	check(dealt[1.0][1] and not dealt[0.5][1], "a perfect shot is a sure critical, a middling one isn't")
	# Will's flourish judges each of its three cuts on its own.
	var b2 = db.make_battle(["will"], "forest_patrol", 41)
	var cuts := []
	b2.damaged.connect(func(u, amount, crit): cuts.append(crit))
	var will = b2.next_turn()
	while will != null and will.id != "will":
		b2.run_ai_turn()
		will = b2.next_turn()
	will.ap = 2
	var foe = b2.legal_targets(will, "flourish")[0]
	foe.hp = 999
	cuts.clear()
	b2.perform(will, "flourish", foe, [1.0, 0.2, 1.0])
	check(cuts == [true, false, true], "each flourish cut is judged on its own tap (%s)" % [cuts])
	for id in ["split_arrow", "pinning_shot", "staff_sweep", "flourish"]:
		check(db.abilities[id].get("minigame", "") in ["aim", "swing", "rhythm"], "%s has a mini-game" % id)
	check(not db.abilities["bow_shot"].has("minigame"), "a plain bow shot just shoots")


func test_contests_appear_and_pay_out() -> void:
	var c = Campaign.new(db, 3, BAND4)
	var seen := 0
	for _d in 60:
		c.rest()
		var held: Array = c.missions.values().filter(func(m): return m["type"] == "contest")
		check(held.size() <= 1, "never more than one contest at a time")
		seen += held.size()
	check(seen > 0, "contests turn up now and then")
	var gen = MissionGen.new(db)
	for won in [true, false]:
		c.missions.clear()
		c.location = "nottingham"
		c.missions["nottingham"] = gen.contest("market_arrow", "Nottingham", 12)
		c.missions["nottingham"]["expires"] = c.day + 3
		var save: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
		check(Campaign.from_dict(db, save).missions["nottingham"] == c.missions["nottingham"], "a waiting contest saves and loads unchanged")
		var gold_before: int = c.gold
		var run = c.start_mission()
		check(run.arrive()["type"] == "continue", "the band arrives at the contest")
		run.advance()
		check(run.arrive()["type"] == "archery", "then Robin shoots")
		var round = run.make_archery()
		while not round.done():
			round.tap(0.0)
		if won:
			round.rival_scores = [0, 0, 0]
		else:
			round.rival_scores = [10, 10, 10]
			round.scores = [0, 0, 0]
		run.archery_finished(round)
		run.advance()
		c.finish_mission(run)
		check(run.result == "success", "a contest is never a failed mission")
		if won:
			check(c.gold == gold_before + 60, "winning the Golden Arrow pays its purse (%d)" % (c.gold - gold_before))
		else:
			check(c.gold == gold_before, "losing pays nothing")


func test_scouting_costs_a_day() -> void:
	var days := []
	var food := []
	for scouted in [false, true]:
		var c = Campaign.new(db, 8, BAND4)
		c.missions.clear()
		c.missions[c.location] = MissionGen.new(db).generate("robbery", 30, 77, "", "")
		for h in c.free_heroes():
			h.hp = h.max_hp / 2
		var hp_before: Array = c.free_heroes().map(func(h): return h.hp)
		var run = c.start_mission()
		if scouted:
			run.scout()
			run.scout()   # asking twice costs nothing more
		run.result = "success"
		c.finish_mission(run)
		days.append(c.day)
		food.append(c.supplies)
		if scouted:
			check(c.free_heroes().map(func(h): return h.hp) == hp_before, "the scouting day is no rest: nobody heals")
	check(days[1] == days[0] + 1, "scouting costs the band a day (%s)" % [days])
	check(food[1] < food[0], "and a day's food (%s)" % [food])


func _fake_run(c, result: String, captured_ids: Array):
	var run = c.start_mission()
	run.result = result
	run.captured = captured_ids
	run.gold = 50 if result == "success" else 0
	return run


func test_capture_creates_rescue_and_rescue_frees() -> void:
	var c = Campaign.new(db, 4, BAND4)
	var target: String = c.missions.keys()[0]
	c.travel(target)
	c.finish_mission(_fake_run(c, "failed", ["will", "tuck"]))
	check(c.captured.has("will") and c.captured.has("tuck"), "heroes left behind are captured")
	check(c.missions[target].get("rescue_heroes", []) == ["will", "tuck"], "one rescue job for both prisoners")
	check(c.free_heroes().size() == 2, "only two heroes left to send")
	c.finish_mission(_fake_run(c, "success", []))
	check(c.captured.is_empty(), "rescue frees everyone held there")


func test_prisoners_moved_to_dungeon_after_deadline() -> void:
	var c = Campaign.new(db, 5, BAND4)
	var target: String = c.missions.keys()[0]
	if target == Campaign.DUNGEON:
		target = c.missions.keys()[1]
	c.travel(target)
	c.finish_mission(_fake_run(c, "failed", ["little_john"]))
	c.travel("camp")
	for _i in Campaign.RESCUE_DEADLINE:
		c.rest()
	check(c.captured["little_john"]["node"] == Campaign.DUNGEON, "unrescued prisoner ends up in Nottingham's dungeon")
	check(c.missions[Campaign.DUNGEON].get("rescue_heroes", []).has("little_john"), "the rescue job moves with them")
	check(not c.missions.has(target) or not c.missions[target].has("rescue_heroes"), "the old rescue job is gone")


func test_whole_band_captured_is_not_game_over() -> void:
	var c = Campaign.new(db, 6, BAND4)
	c.travel(c.missions.keys()[0])
	c.finish_mission(_fake_run(c, "failed", ["robin", "little_john", "will", "tuck"]))
	check(c.captured.is_empty() and c.location == "camp", "friends break the band out; the campaign goes on")


func test_save_and_load_round_trip() -> void:
	var c = Campaign.new(db, 7, BAND4)
	for _i in 5:
		c.rest()
	c.heroes["will"].hp = 9
	var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(JSON.stringify(copy.to_dict()) == JSON.stringify(c.to_dict()), "saved campaign loads back identically")
	c.rest()
	copy.rest()
	check(JSON.stringify(copy.to_dict()) == JSON.stringify(c.to_dict()), "and carries on identically")


func test_long_campaign_with_autoplay_stays_sane() -> void:
	var c = Campaign.new(db, 8, BAND4)
	var played := 0
	for _i in 30:
		if c.missions.is_empty():
			c.rest()
			continue
		var targets: Array = c.missions.keys()
		go(c, targets[0])
		var run = c.start_mission()
		if run == null:
			go(c, "camp")
			continue
		autoplay_mission(run, true)
		c.finish_mission(run)
		played += 1
		go(c, "camp")
		while c.supply_days() < 8 and c.buy_supplies():
			pass
		c.rest()
	print("30-turn campaign: day %d, %d missions, %d gold, %d supplies, infamy %d, control %s" % [c.day, played, c.gold, c.supplies, c.infamy, c.control])
	check(played > 10, "the band finds plenty to do")
	check(c.gold >= 0 and c.day > 30, "campaign advanced sensibly")


# --- Spending gold -------------------------------------------------------------

func test_item_data_is_valid() -> void:
	var classes := {}
	for h in db.heroes:
		classes[db.heroes[h]["class"]] = true
	for i in db.items:
		var it: Dictionary = db.items[i]
		check(it["slot"] in ["weapon", "armor", "trinket"], "%s has a known slot" % i)
		check(it["classes"].all(func(c): return classes.has(c)), "%s is for real classes" % i)
		check(it["bonus"].keys().all(func(k): return k in Campaign.STAT_KEYS), "%s only boosts known stats" % i)
	for h in db.heroes:
		check(db.items.values().any(func(it): return it["slot"] == "weapon" and it["classes"].has(db.heroes[h]["class"])), "%s can buy a weapon" % h)


func test_giving_to_the_poor() -> void:
	var c = Campaign.new(db, 20, BAND4)
	c.gold = 200
	check(not c.give_to_poor(50), "nobody to give to at camp")
	c.travel("edwinstowe")
	var before: int = c.control["sherwood"]
	check(c.give_to_poor(50), "can give in a village")
	check(c.gold == 150 and c.reputation == 5, "50 gold buys 5 reputation")
	check(c.control["sherwood"] == before - 2, "and loosens the Sheriff's grip")
	check(not c.give_to_poor(500), "can't give gold you don't have")


func test_supplies_run_down_and_hunger_hurts() -> void:
	var c = Campaign.new(db, 21, BAND4)
	var start: int = c.supplies
	c.rest()
	check(c.supplies == start - 4, "four heroes eat four supplies a day")
	c.supplies = 0
	var robin = c.heroes["robin"]
	c.rest()
	check(robin.hp < robin.max_hp, "a hungry band gets weaker instead of healing")
	check(robin.hp >= 1, "hunger never knocks anyone out")
	c.gold = 15
	check(c.buy_supplies() and c.supplies == 10 and c.gold == 0, "buy a bundle of supplies at camp")


func test_buying_gear_boosts_stats_and_respects_class() -> void:
	var c = Campaign.new(db, 22, BAND4)
	c.gold = 500
	var robin = c.heroes["robin"]
	var atk: int = robin.atk
	check(not c.buy_item("robin", "ironshod_staff"), "Robin can't buy Little John's staff")
	check(c.buy_item("robin", "yew_longbow") and robin.atk == atk + 2, "a longbow adds 2 attack")
	check(c.buy_item("robin", "hunters_recurve") and robin.atk == atk + 3, "a better bow replaces the old one")
	robin.hp = robin.max_hp - 5
	check(c.buy_item("robin", "mail_shirt") and robin.max_hp == 38 and robin.hp == 33, "armor raises max HP but keeps the wound")
	check(not c.buy_item("robin", "mail_shirt"), "can't buy what you're already wearing")
	c.travel("edwinstowe")
	check(not c.buy_item("will", "lucky_charm"), "the armory is at camp")
	var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(copy.heroes["robin"].atk == robin.atk and copy.heroes["robin"].max_hp == robin.max_hp, "gear survives save and load")


func test_merry_men_fill_gaps() -> void:
	var c = Campaign.new(db, 23, Campaign.FULL_BAND)
	c.gold = 500
	check(not c.hire_merry_man(), "nobody joins a band with no reputation")
	c.reputation = 10
	check(c.hire_merry_man(), "hire a Merry Man at camp")
	var mm_id: String = c.merry_men.keys()[0]
	check(c.party().size() == Campaign.PARTY_SIZE and not c.party().has(c.heroes[mm_id]), "with everyone free, the named heroes go")
	c.captured["will"] = {"node": "locksley", "since": c.day}
	check(c.party().has(c.heroes[mm_id]), "a Merry Man steps in when Will is captured")
	check(c.buy_item(mm_id, "outlaw_spear"), "Merry Men can be equipped too")
	var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(copy.hero_name(mm_id) == c.hero_name(mm_id) and copy.heroes[mm_id].atk == c.heroes[mm_id].atk, "Merry Men survive save and load")
	for _i in 5:
		c.hire_merry_man()
	check(c.merry_men.size() == int(db.economy["merry_men"]["max"]), "the camp only feeds so many")


func test_informant_reveals_bait() -> void:
	var c = Campaign.new(db, 24, BAND4)
	c.gold = 500
	c.missions.clear()
	var gen = MissionGen.new(db)
	var m: Dictionary = gen.generate("robbery", 50, 3, "locksley")
	gen.make_bait(m, "guy", "")
	m["expires"] = 99
	c.missions["edwinstowe"] = m
	c.travel("edwinstowe")
	var cost: int = c.informant_cost()
	check(c.pay_informant() and c.gold == 500 - cost, "pay the informant")
	check(m["bait"]["revealed"], "the informant exposes Guy's bait")
	check(not c.pay_informant(), "no need to pay twice")


func test_bribing_the_jailer_frees_prisoners() -> void:
	var c = Campaign.new(db, 25, BAND4)
	c.gold = 1000
	c.travel("locksley")
	c.missions.erase("locksley")
	c.captured["will"] = {"node": "locksley", "since": c.day}
	c._post_rescue("will", "locksley")
	var cost: int = c.jailer_cost()
	check(cost == 70, "one prisoner in a village costs 70")
	check(c.bribe_jailer() and c.captured.is_empty() and not c.missions.has("locksley"), "the bribe frees Will and clears the rescue job")
	c.travel("nottingham")
	c.captured["tuck"] = {"node": "nottingham", "since": c.day}
	check(c.jailer_cost() == 140, "the dungeon jailer wants twice as much")


func test_every_unit_has_a_sprite() -> void:
	for id in db.heroes:
		check(ResourceLoader.exists("res://assets/sprites/%s.png" % id), "%s has a sprite" % id)
	for id in db.enemies:
		var art: String = db.enemies[id].get("sprite", id)
		check(ResourceLoader.exists("res://assets/sprites/%s.png" % art), "%s has a sprite" % id)


func test_every_battle_place_has_a_backdrop() -> void:
	for id in db.locations:
		check(ResourceLoader.exists("res://assets/backdrops/%s.png" % id), "%s has a backdrop" % id)
	for id in db.encounters:
		check(db.locations.has(db.encounters[id].get("location", "")), "encounter %s names a real location" % id)
	check(ResourceLoader.exists("res://assets/map/map.png"), "the strategic map is painted")


func test_every_item_and_path_step_has_art() -> void:
	for id in db.items:
		check(ResourceLoader.exists("res://assets/items/%s.png" % id), "%s has an icon" % id)
	for kind in ["approach", "combat", "choice", "hazard", "objective", "escape"]:
		check(ResourceLoader.exists("res://assets/ui/node_%s.png" % kind), "path step %s has a medallion" % kind)
	for id in db.abilities:
		var fx: String = db.abilities[id].get("fx", "")
		check(fx in ["", "dash"] or ResourceLoader.exists("res://assets/fx/%s.png" % fx), "%s's effect has art" % id)


func test_battle_reports_hits_for_animation() -> void:
	var b = db.make_battle(["robin"], "forest_patrol", 5)
	var seen := []
	b.acted.connect(func(u, a, _t): seen.append(a))
	b.damaged.connect(func(_u, amount, _c): seen.append(amount))
	var robin = b.next_turn()
	while robin != null and robin.side != "heroes":
		b.run_ai_turn()
		robin = b.next_turn()
	seen.clear()
	b.perform(robin, "bow_shot", b.legal_targets(robin, "bow_shot")[0])
	check(seen.size() == 2 and seen[0] == "bow_shot" and seen[1] is int, "a bow shot reports the action, then the damage")


## Alan's songs must do something you can see: the ballad heals and inspires everyone, the lullaby
## usually puts its target to sleep, and both report the change for the battle screen.
func test_alan_songs_heal_inspire_and_stun() -> void:
	var stuns := 0
	for s in 40:
		var b = db.make_battle(["alan", "robin", "little_john"], "forest_patrol", 300 + s)
		var added := []
		b.status_added.connect(func(u, st): added.append([u, st]))
		var alan = b.next_turn()
		while alan != null and alan.id != "alan":
			if alan.side == "heroes":
				b.end_turn()
			else:
				b.run_ai_turn()
			alan = b.next_turn()
		if alan == null:
			continue
		if s == 0:
			var john = b.units.filter(func(u): return u.id == "little_john")[0]
			john.hp = 10
			added.clear()
			b.perform(alan, "rousing_ballad", alan)
			check(john.hp >= 10 + 5, "Rousing Ballad heals a hurt friend by at least 5 (%d)" % john.hp)
			var heroes: Array = b.units.filter(func(u): return u.side == "heroes" and u.is_active())
			check(heroes.all(func(u): return u.has_status("inspired")), "Rousing Ballad inspires the whole band")
			check(added.size() == heroes.size(), "each inspired hero is reported to the battle screen")
		else:
			var target = b.legal_targets(alan, "lullaby")[0]
			b.perform(alan, "lullaby", target)
			stuns += 1 if target.has_status("stunned") else 0
	check(stuns >= 20, "Lullaby puts its target to sleep most of the time (%d of 39)" % stuns)


func test_staff_sweep_hits_hard_and_can_knock_down() -> void:
	var sweep_hits := []
	var strike_hits := []
	var stuns := 0
	for s in 30:
		var b = db.make_battle(["little_john", "robin"], "forest_patrol", 500 + s)
		var john = b.next_turn()
		while john != null and john.id != "little_john":
			if john.side == "heroes":
				b.end_turn()
			else:
				b.run_ai_turn()
			john = b.next_turn()
		if john == null:
			continue
		var targets: Array = b.legal_targets(john, "staff_sweep")
		var before := targets.map(func(t): return t.hp)
		if s % 2 == 0:
			b.perform(john, "staff_sweep", targets[0])
			for i in targets.size():
				sweep_hits.append(before[i] - targets[i].hp)
				stuns += 1 if targets[i].has_status("stunned") else 0
		else:
			b.perform(john, "strike", targets[0])
			strike_hits.append(before[0] - targets[0].hp)
	var avg := func(a: Array) -> float: return float(a.reduce(func(x, y): return x + y, 0)) / maxi(1, a.size())
	check(avg.call(sweep_hits) >= 0.8 * avg.call(strike_hits), "Staff Sweep hits each foe nearly as hard as a strike (%.1f vs %.1f)" % [avg.call(sweep_hits), avg.call(strike_hits)])
	check(stuns >= 2, "Staff Sweep sometimes knocks foes off their feet (%d)" % stuns)

# --- Story missions --------------------------------------------------------------

func test_bridge_duel_is_staffs_only() -> void:
	var robin = db.make_hero("robin")
	var before: Array = robin.available_abilities()
	var run = MissionRun.new(db, MissionGen.new(db).story("little_john_bridge", 25, 1), [robin, db.make_hero("will")])
	run.arrive()
	run.advance()
	run.arrive()
	run.choose(0)
	run.advance()
	var step: Dictionary = run.arrive()
	check(step["type"] == "battle", "the bridge bout begins")
	var b = run.make_battle(step["enemies"])
	check(robin.sprite == "robin_staff" and ResourceLoader.exists("res://assets/sprites/robin_staff.png"), "Robin carries a staff on the bridge")
	check(robin.row == "front" and robin.available_abilities() == ["strike", "staff_sweep", "defend"], "Robin brings only his staff to the bridge (%s)" % [robin.available_abilities()])
	b.swap_row(robin)
	check(not robin.available_abilities().has("bow_shot"), "no bow on the bridge, even from the back row")
	b.result = "victory"
	run.battle_finished(b)
	check(robin.available_abilities() == before, "Robin has his bow back after the bout")
	check(robin.sprite == "robin", "and looks like himself again")


func test_story_data_is_valid() -> void:
	var kinds := ["approach", "combat", "choice", "duel", "hazard", "objective", "escape", "archery"]
	for h in db.stories["start_band"]:
		check(db.heroes.has(h), "start band hero %s exists" % h)
	for id in db.stories["stories"]:
		var st: Dictionary = db.stories["stories"][id]
		check(db.map["nodes"].has(st["node"]), "story %s is placed on a real map node" % id)
		check(ResourceLoader.exists("res://assets/backdrops/%s.png" % st["backdrop"]), "story %s has a backdrop" % id)
		check(st["recruit"] == "" or db.heroes.has(st["recruit"]), "story %s recruits a real hero" % id)
		for h in st["requires"].get("band", []):
			check(db.heroes.has(h), "story %s requires a real hero" % id)
		for n in st["nodes"]:
			check(kinds.has(n["kind"]), "story %s uses known node kinds" % id)
			for e in n.get("enemies", []):
				check(db.enemies.has(e), "story %s uses known enemy %s" % [id, e])
			for opt in n.get("options", []):
				check(opt["result"] in ["next", "sneak", "fight"], "story %s choice results are known" % id)
			if n.get("friendly", false):
				check(n.has("win") and n.has("lose") and n.has("party"), "story %s duel says who fights and how it ends" % id)
		check(st["recruit"] == "" or st["nodes"].any(func(n): return n.get("recruit", false)), "story %s has a node where the companion joins" % id)
		for s in st["requires"].get("stories", []):
			check(db.stories["stories"].has(s) and s != id, "story %s follows a real earlier story %s" % [id, s])
		for n in st["nodes"]:
			for h in n.get("party", []):
				check(db.heroes.has(h), "story %s names a real hero %s to fight" % [id, h])
			for t in [n.get("text", ""), n.get("win", ""), n.get("lose", "")] + n.get("options", []).map(func(o): return o.get("log", "")):
				for word in ["kill", "dead", "die", "blood", "murder", "hanged"]:
					check(not (" %s " % t.to_lower()).contains(" %s" % word), "story %s keeps the family tone (no '%s')" % [id, word])


func test_there_are_forty_tales() -> void:
	var tales: Array = db.stories["stories"].keys().filter(func(id): return db.stories["stories"][id]["recruit"] == "" and id != "silver_arrow")
	check(tales.size() >= 40, "at least 40 tales from the legends (%d)" % tales.size())
	# Every tale can eventually be reached: requirements only point at stories that can be posted.
	var reachable := {}
	for _pass in 50:
		for id in db.stories["stories"]:
			if db.stories["stories"][id]["requires"].get("stories", []).all(func(s): return reachable.has(s)):
				reachable[id] = true
	check(reachable.size() == db.stories["stories"].size(), "no tale waits on a story that can never happen")
	var used := {}
	for id in tales:
		used[db.stories["stories"][id]["node"]] = true
	check(used.size() >= 7, "tales are spread across the map (%d places)" % used.size())


## Tales wait their turn: only a couple are posted at once, so the map still has ordinary jobs.
func test_tales_are_capped_and_chained() -> void:
	var c = Campaign.new(db, 44)
	c.reputation = 100
	c.stories_done = []
	for id in db.stories["stories"]:
		if db.stories["stories"][id]["recruit"] != "":
			c.stories_done.append(id)
	for h in Campaign.FULL_BAND:
		if not c.band.has(h):
			c._join(h)
	c.missions.clear()
	c._post_stories()
	var posted: Array = c.missions.values().filter(func(m): return m["type"] == "story")
	check(posted.size() == Campaign.MAX_TALES, "only %d tales on the map at once (%d)" % [Campaign.MAX_TALES, posted.size()])
	check(not c.story_ready("cellarer"), "a tale that follows another waits for it")
	c.stories_done.append_array(["poor_knight", "knight_pays_abbot"])
	check(c.story_ready("cellarer"), "the next tale in a chain opens once the earlier ones are done")
	# A companion's origin story bumps a waiting tale off its spot.
	c = Campaign.new(db, 45, ["robin", "will", "little_john"])
	c.reputation = 20
	c.missions.clear()
	c.missions["blidworth"] = MissionGen.new(db).story("much_miller", 10, 1)
	c.missions["blidworth"]["expires"] = 0
	c._post_stories()
	check(c.missions["blidworth"]["story"] == "tuck_ford", "Tuck's ford takes the place of a waiting tale")


## The band a player would have when a tale first appears: who it names, plus who its chain needed.
func band_for_story(id: String) -> Array:
	var st: Dictionary = db.stories["stories"][id]
	var need: Array = st["requires"].get("band", []).duplicate()
	for s in st["requires"].get("stories", []):
		need.append_array(band_for_story(s))
	var order := ["robin", "will", "little_john", "tuck", "alan"]
	var deepest := -1
	for h in need:
		deepest = maxi(deepest, order.find(h))
	return order.slice(0, maxi(1, deepest + 1))


## Each tale should be winnable most of the time by the band you'd have when it first appears.
func test_every_tale_is_winnable_by_its_band() -> void:
	var weak: Array = []
	for id in db.stories["stories"]:
		var wins := 0
		var tries := 12
		for s in tries:
			var c = Campaign.new(db, 500 + s, band_for_story(id))
			c.missions.clear()
			var at: String = db.stories["stories"][id]["node"]
			c.missions[at] = MissionGen.new(db).story(id, 10, 900 + s)
			c.missions[at]["expires"] = 0
			c.location = at
			var run = c.start_mission()
			autoplay_mission(run)
			wins += 1 if run.result == "success" else 0
		if wins < tries / 2:
			weak.append("%s %d/%d" % [id, wins, tries])
		print("tale %s with %s: %d/%d" % [id, band_for_story(id), wins, tries])
	check(weak.is_empty(), "every tale is won at least half the time by its band (%s)" % [weak])


func test_campaign_starts_small_and_john_joins_on_the_bridge() -> void:
	var c = Campaign.new(db, 40)
	check(c.band == db.stories["start_band"], "a new campaign starts with only the start band")
	check(c.missions.get("sherwood_edge", {}).get("story", "") == "little_john_bridge", "Little John's bridge is waiting on day one")
	check(c.missions.get("locksley", {}).get("story", "") == "will_meets_robin", "so is the stranger in scarlet, and Will isn't in the band yet")
	check(not c.missions.values().any(func(m): return m.get("story", "") == "tuck_ford"), "Tuck's story waits until John has joined")
	c.travel("sherwood_edge")
	var run = c.start_mission()
	var step: Dictionary = {}
	while step.get("type", "") != "battle":
		step = run.arrive()
		if step["type"] == "choice":
			step = run.choose(0)
		if step["type"] == "continue":
			run.advance()
	var b = run.make_battle(step["enemies"])
	var heroes_in_duel: Array = b.units.filter(func(u): return u.side == "heroes")
	check(b.friendly and heroes_in_duel.size() == 1 and heroes_in_duel[0].id == "robin", "Robin faces the stranger alone, in a friendly bout")
	# Lose on purpose: Robin still wins a friend.
	for u in heroes_in_duel:
		u.hp = 0
	b._check_end()
	check(b.result == "defeat" and b.captured.is_empty(), "losing a bout captures nobody")
	run.battle_finished(b)
	check(not run.is_over() and c.heroes["robin"].hp >= 1, "the story goes on after a lost bout")
	run.advance()
	while not run.is_over():
		run.arrive()
		run.advance()
	check(run.result == "success" and run.recruited == "little_john", "the bridge story succeeds and John is won over")
	c.finish_mission(run)
	check(c.band.has("little_john") and c.heroes.has("little_john"), "Little John joins the band")
	check(c.stories_done.has("little_john_bridge") and c.missions.get("sherwood_edge", {}).get("type", "") != "story", "the bridge story is done for good")
	check(c.missions.get("blidworth", {}).get("story", "") == "tuck_ford", "Tuck's ford appears once John has joined")
	var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(copy.band == c.band and copy.stories_done == c.stories_done, "the band and finished stories survive save and load")


func test_every_legend_can_be_played_through() -> void:
	var c = Campaign.new(db, 41)
	c.reputation = 60
	c.infamy = 60
	c.gold = 500
	var guard := 0
	while c.stories_done.size() < db.stories["stories"].size() and guard < 300:
		guard += 1
		var at := ""
		for n in c.missions:
			if c.missions[n]["type"] == "story":
				at = n
		if at == "":
			c.rest()
			continue
		go(c, at)
		for h in c.heroes.values():
			h.hp = h.max_hp
		var run = c.start_mission()
		autoplay_mission(run)
		c.finish_mission(run)
		c.captured.clear()
		c._remove_rescues()
		go(c, "camp")
	check(c.stories_done.size() == db.stories["stories"].size(), "all legends finished (%s)" % [c.stories_done])
	for h in Campaign.FULL_BAND:
		check(c.band.has(h), "%s has joined by the end of the legends" % h)


func test_old_saves_keep_the_whole_band() -> void:
	var c = Campaign.new(db, 42, BAND4)
	var data: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	data.erase("band")
	data.erase("stories_done")
	var copy = Campaign.from_dict(db, data)
	check(copy.band == BAND4, "a save from before stories keeps Robin, John, Will and Tuck")
	check(not copy.missions.values().any(func(m): return m.get("recruit", "") in BAND4), "nobody already in the band is offered a recruiting story")


## A story campaign from day one, legends first: the small starting band must survive until friends join.
func test_story_campaign_with_autoplay() -> void:
	var finished := 0
	var early_ok := 0
	var early_jobs := 0
	for s in 6:
		var c = Campaign.new(db, 100 + s)
		for _i in 30:
			if c.missions.is_empty():
				c.rest()
				continue
			var targets: Array = c.missions.keys()
			targets.sort_custom(func(a, b): return c.missions[a]["type"] == "story" and c.missions[b]["type"] != "story")
			go(c, targets[0])
			var run = c.start_mission()
			if run == null:
				go(c, "camp")
				continue
			autoplay_mission(run, true)
			if c.band.size() <= 2 and run.mission["type"] != "story":
				early_jobs += 1
				early_ok += 1 if run.result == "success" else 0
			c.finish_mission(run)
			go(c, "camp")
			while c.supply_days() < 8 and c.buy_supplies():
				pass
			c.rest()
		finished += c.stories_done.size()
		print("story campaign %d: day %d, band %s, legends %s, gold %d, rep %d" % [s, c.day, c.band, c.stories_done, c.gold, c.reputation])
	print("ordinary jobs tried with only Robin and Will: %d/%d succeeded" % [early_ok, early_jobs])
	check(finished >= 6 * 3, "most legends get played within 30 trips (%d of %d)" % [finished, 6 * db.stories["stories"].size()])


# --- The Sheriff hits back -----------------------------------------------------

func test_wanted_posters_go_up_with_infamy() -> void:
	var c = Campaign.new(db, 60, BAND4)
	check(c.wanted_level() == 0 and c.bounty() == 0, "nobody is wanted at first")
	c.infamy = 30
	c._update_wanted()
	check(c.wanted_level() == 1 and c.poster_news == 1, "infamy 30 puts up the first posters")
	check(c.news.back().contains("Wanted posters"), "the news says so")
	c.infamy = 80
	c._update_wanted()
	check(c.wanted_level() == 3 and c.bounty() > 100, "infamy 80 is the biggest bounty (%d)" % c.bounty())
	var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(copy.posted_wanted == 3 and copy.poster_news == 3, "posters survive a save")
	c.poster_news = 0
	c.infamy = 76
	c.rest()
	check(c.infamy == 74 and c.wanted_level() == 2, "lying low at camp cools the band's infamy (%d)" % c.infamy)
	check(c.posted_wanted == 2 and c.poster_news == 0, "the posters fade without a new one being shown")


func test_robberies_raise_the_bounty() -> void:
	var c = Campaign.new(db, 61, BAND4)
	var run = MissionRun.new(db, MissionGen.new(db).generate("robbery", 10, 5, "great_north_road"), c.party())
	run.mission["bait"] = {}
	run.result = "success"
	run.loot_taken = true
	c.infamy = 22
	c.location = "great_north_road"
	c.finish_mission(run)
	check(c.wanted_level() == 1 and c.poster_news == 1, "the robbery that tips infamy past 25 puts up posters")


func test_bounty_hunters_ambush_on_the_road() -> void:
	var ambushes := 0
	var fights := 0
	for s in 40:
		var c = Campaign.new(db, 300 + s, BAND4)
		c.infamy = 80
		c.posted_wanted = 3
		var visited: Array = c.travel("nottingham")
		if c.ambush.is_empty():
			check(c.location == "nottingham", "without an ambush the band arrives")
			continue
		ambushes += 1
		check(c.location == visited.back() and c.location != "camp", "an ambush stops the band on the road")
		var job_before = c.missions.get(c.location, {}).duplicate(true)
		var run = c.start_ambush()
		check(run.mission["type"] == "ambush" and run.mission["nodes"][0]["enemies"].has("bounty_hunter"), "bounty hunters are waiting")
		var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
		check(not copy.ambush.is_empty(), "a waiting ambush survives a save")
		autoplay_mission(run)
		c.finish_mission(run)
		fights += 1 if run.result == "success" else 0
		check(c.ambush.is_empty(), "the ambush is over once fought")
		check(JSON.stringify(c.missions.get(c.location, {})) == JSON.stringify(job_before) or run.result != "success", "the job at that place is still there")
	check(ambushes >= 10, "a wanted band is often waylaid on a long walk (%d of 40)" % ambushes)
	check(fights >= ambushes / 2, "the full band usually sees the hunters off (%d of %d)" % [fights, ambushes])
	var calm = Campaign.new(db, 300, BAND4)
	calm.travel("nottingham")
	check(calm.ambush.is_empty(), "nobody hunts a band that isn't wanted")


func test_running_from_hunters_is_getting_away() -> void:
	var c = Campaign.new(db, 70, BAND4)
	c.infamy = 60
	c.posted_wanted = c.wanted_level()
	c.location = "great_north_road"
	c.ambush = MissionGen.new(db).ambush(["bounty_hunter"], "the road", "great_north_road", 100, 3)
	var run = c.start_ambush()
	var step: Dictionary = run.arrive()
	var b = run.make_battle(step["enemies"])
	b.result = "retreated"
	run.battle_finished(b)
	run.advance()
	check(run.result == "success", "slipping away from bounty hunters still counts")
	c.finish_mission(run)
	check(c.news.any(func(n): return n.contains("slip")), "the news says the band gave them the slip")


func test_sheriff_story_builds_to_the_castle() -> void:
	var c = Campaign.new(db, 80, Campaign.FULL_BAND)
	c.reputation = 40
	c.missions.clear()
	c._post_stories()
	check(not c.missions.has("edwinstowe") or c.missions["edwinstowe"].get("story", "") != "wanted_posters", "no posters story before the band is wanted")
	c.infamy = 30
	c.missions.clear()
	c._post_stories()
	check(c.missions.get("edwinstowe", {}).get("story", "") == "wanted_posters", "the posters story comes once the band is wanted")
	check(not c.story_ready("hunters_hunted") and not c.story_ready("storm_castle"), "the rest of the story waits its turn")
	c.stories_done.append("wanted_posters")
	check(not c.story_ready("hunters_hunted"), "Black Hob comes after the band only at a higher bounty")
	c.infamy = 45
	check(c.story_ready("hunters_hunted"), "then Black Hob's camp appears")
	c.stories_done.append_array(["hunters_hunted", "silver_arrow"])
	check(c.story_ready("storm_castle"), "with Hob's secret and the silver arrow, the castle can be stormed")
	# An ordinary tale never pushes out the Sheriff's story, but the story does take a tale's place.
	c.missions.clear()
	c.missions["nottingham"] = MissionGen.new(db).story("butcher", 10, 1)
	c.missions["nottingham"]["expires"] = 0
	c._post_stories()
	check(c.missions["nottingham"]["story"] == "storm_castle", "the finale takes the place of a waiting tale")


func test_storming_the_castle_frees_sherwood() -> void:
	var wins := 0
	for s in 8:
		var c = Campaign.new(db, 90 + s, Campaign.FULL_BAND)
		c.infamy = 80
		c.posted_wanted = 3
		# A hired man is in the dungeon; the whole named band storms the castle.
		c.reputation = 20
		c.gold = 100
		c.hire_merry_man()
		c.captured["merry_man_1"] = {"node": "nottingham", "since": c.day}
		c.missions.clear()
		c.missions["nottingham"] = MissionGen.new(db).story("storm_castle", 60, 7 + s)
		c.missions["nottingham"]["expires"] = 0
		c.location = "nottingham"
		check(not c.finale_won(), "the Sheriff still holds the castle")
		var run = c.start_mission()
		check(run.mission["location"] == "castle_courtyard", "the finale is fought in the castle courtyard")
		autoplay_mission(run)
		c.finish_mission(run)
		if run.result != "success":
			continue
		wins += 1
		check(c.finale_won(), "the Sheriff is driven out")
		check(c.infamy == 0 and c.wanted_level() == 0, "the posters come down for good")
		check(c.control.values().all(func(v): return v <= 40), "the Sheriff's grip is broken everywhere (%s)" % [c.control])
		check(c.captured.is_empty(), "every cell is opened")
	check(wins >= 4, "the whole band usually wins the finale (%d of 8)" % wins)


func test_every_enemy_has_a_sprite_and_hunters_net() -> void:
	check(db.enemies["bounty_hunter"]["abilities"].has("throw_net"), "bounty hunters carry nets")
	check(ResourceLoader.exists("res://assets/sprites/bounty_hunter.png"), "bounty hunters have a picture")
	check(ResourceLoader.exists("res://assets/backdrops/castle_courtyard.png"), "the castle courtyard is painted")


# --- Disguises -------------------------------------------------------------------

func test_disguises_offer_one_of_each_fate() -> void:
	for s in 30:
		var m: Dictionary = MissionGen.new(db).generate(["robbery", "rescue"][s % 2], 30, s, "great_north_road")
		var run = MissionRun.new(db, m, [db.make_hero("robin"), db.make_hero("little_john")])
		check(run.can_disguise(), "a %s can be done in disguise" % m["type"])
		var opts: Array = run.disguise_options()
		check(opts.size() == 3, "three disguises are offered")
		var fates: Array = opts.map(func(o): return o["fate"])
		fates.sort()
		check(fates == ["blown", "slip", "surprise"], "one works, one half-works, one fails (%s)" % [fates])
		check(opts.map(func(o): return o["id"]).all(func(id): return db.disguises.has(id)), "they are real disguises")
		var again = MissionRun.new(db, MissionGen.new(db).generate(m["type"], 30, s, "great_north_road"), [])
		check(JSON.stringify(again.disguise_options()) == JSON.stringify(opts), "the same job always offers the same disguises")
	for id in db.disguises:
		for k in ["name", "legend", "wear", "slip", "surprise", "blown"]:
			check(db.disguises[id].has(k), "disguise %s says %s" % [id, k])
		check(db.stories["stories"].has(db.disguises[id]["legend"]), "disguise %s comes from a real legend" % id)
	var story = MissionRun.new(db, MissionGen.new(db).story("wanted_posters", 10, 1), [])
	check(not story.can_disguise(), "legends are played as told, without disguises")


func _run_with_fate(fate: String, type := "rescue"):
	for s in 50:
		var run = MissionRun.new(db, MissionGen.new(db).generate(type, 30, s, "great_north_road"), BAND4.map(func(h): return db.make_hero(h)))
		var opts: Array = run.disguise_options()
		for i in 3:
			if opts[i]["fate"] == fate:
				run.wear_disguise(i)
				return run
	return null


func test_a_good_disguise_slips_past_a_fight() -> void:
	var run = _run_with_fate("slip")
	var fights_before: int = run.mission["nodes"].filter(func(n): return not n.get("enemies", []).is_empty() and not n.has("slipped")).size()
	var battles := 0
	var guard := 0
	while not run.is_over() and guard < 20:
		guard += 1
		var step: Dictionary = run.arrive()
		if step["type"] == "battle":
			battles += 1
			var b = run.make_battle(step["enemies"])
			autoplay(b)
			run.battle_finished(b)
		run.advance()
	check(run.mission_log.any(func(l): return l.contains(db.disguises[run.disguise]["slip"].left(20))), "the log tells how the band slipped past")
	check(battles <= fights_before, "one fight fewer than without the disguise (%d of %d)" % [battles, fights_before])
	check(run.result == "success" and run.prisoner_freed, "and the prisoner is still freed")


func test_a_half_good_disguise_strikes_first() -> void:
	var run = _run_with_fate("surprise")
	check(run.surprise, "the band will strike first")
	var step: Dictionary = run.arrive()
	while step["type"] != "battle":
		run.advance()
		step = run.arrive()
	var b = run.make_battle(step["enemies"])
	check(b.units.filter(func(u): return u.side == "enemies").all(func(u): return u.has_status("stunned")), "every foe starts the fight stunned")
	check(not run.surprise, "only the first fight is a surprise")


func test_a_bad_disguise_brings_an_attack_at_once() -> void:
	var run = _run_with_fate("blown", "robbery")
	var first: Dictionary = run.current_node()
	check(first["kind"] == "combat" and not first["enemies"].is_empty(), "the band is attacked straight away")
	check(run.arrive()["type"] == "battle", "the fight starts before the approach")
	check(run.mission_log.any(func(l): return l == db.disguises[run.disguise]["blown"].format({"place": run.mission["location_name"]})), "the log tells how the disguise was seen through")


## On a phone one tap sends a touch and a click. It must fix the aim, not also loose the arrow.
func test_one_tap_on_a_phone_counts_once() -> void:
	var game = MinigameView.new()
	game.start_contest(preload("res://core/archery.gd").new(3, 3, 0.5, "Rival"), "Robin", "robin", "Test")
	root.add_child(game)
	game.t = 0.5
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	game._gui_input(touch)
	game._gui_input(click)
	check(game.round.locked_x != null and game.round.shots.is_empty(), "a tap fixes the aim without shooting")
	game._gui_input(click)
	check(game.round.shots.is_empty(), "a second tap straight after is ignored")
	game.t = 0.5
	game._gui_input(click)
	check(game.round.shots.size() == 1, "the next real tap looses the arrow")
	game.free()


func test_disguises_are_learned_from_the_legends() -> void:
	var c = Campaign.new(db, 75, BAND4)
	check(c.known_disguises().is_empty(), "a new band knows no disguises")
	c.missions.clear()
	c.missions["great_north_road"] = MissionGen.new(db).generate("robbery", 20, 9, "great_north_road")
	c.location = "great_north_road"
	var run = c.start_mission()
	check(not run.can_disguise(), "no disguises until three are learned")
	for tale in ["potter", "beggar"]:
		c.stories_done.append(tale)
	check(c.known_disguises() == ["potter", "beggar"], "playing the Potter and the Beggar teaches those two disguises")
	check(not c.start_mission().can_disguise(), "two are not enough to choose from")
	# Finishing a third legend's mission teaches its disguise and says so.
	c.missions["sherwood_edge"] = MissionGen.new(db).story("butcher", 10, 2)
	c.missions["sherwood_edge"]["expires"] = 0
	c.location = "sherwood_edge"
	var tale_run = c.start_mission()
	tale_run.result = "success"
	c.finish_mission(tale_run)
	check(c.known_disguises().has("butcher"), "the Butcher teaches the butcher's disguise")
	check(c.news.any(func(n): return n.contains("Butcher")), "the news says a disguise was learned")
	c.location = "great_north_road"
	run = c.start_mission()
	check(run.can_disguise(), "with three learned, the band can go in disguise")
	var offered: Array = run.disguise_options().map(func(o): return o["id"])
	offered.sort()
	check(offered == ["beggar", "butcher", "potter"], "only learned disguises are offered (%s)" % [offered])


## A simulated archer who reads the wind from the screen's arrows and taps with a timing error.
func _sim_round(skill: float, seed_value: int, tap_error: float) -> bool:
	var r = preload("res://core/archery.gd").new(seed_value, 3, skill, "Rival")
	var hand := RandomNumberGenerator.new()
	hand.seed = seed_value * 7 + 1
	var rate: float = r.SWING_RATE * r.speed
	while not r.done():
		# The screen shows up to three wind arrows; the archer aims into the wind by that much.
		var shown: float = ceil(absf(r.wind) * 3) / 3.0 * signf(r.wind) if absf(r.wind) >= 0.05 else 0.0
		var guess: float = shown - 0.17 * signf(shown)
		for target in [-guess * r.WIND_PUSH, 0.0]:
			var t: float = fposmod(asin(clampf(target / r.SWAY, -1, 1)) - r._phase, TAU) / rate
			r.tap(maxf(0.0, t + hand.randfn(0.0, tap_error)))
	return r.won()


func test_contests_are_winnable() -> void:
	for row in [[0.45, 0.06, 0.85], [0.6, 0.06, 0.75], [0.8, 0.06, 0.55], [0.85, 0.06, 0.5], [0.45, 0.09, 0.7], [0.8, 0.09, 0.3]]:
		var wins := 0
		for s in 400:
			wins += 1 if _sim_round(row[0], 5000 + s, row[1]) else 0
		print("contest vs skill %.2f, taps within %dms: won %d/400" % [row[0], row[1] * 1000, wins])
		check(wins >= int(400 * row[2]), "an archer tapping within %dms beats a skill %.2f rival often (%d/400)" % [row[1] * 1000, row[0], wins])
	var sharp := 0
	for s in 400:
		sharp += 1 if _sim_round(0.85, 9000 + s, 0.0) else 0
	check(sharp >= 360, "perfect timing nearly always wins, even the hardest match (%d/400)" % sharp)


func test_sneaking_past_is_a_gamble() -> void:
	var tried := 0
	var slipped := 0
	var bigger_fights := 0
	for s in 2000:
		var m: Dictionary = MissionGen.new(db).generate("robbery", 40, s, "great_north_road")
		for i in m["nodes"].size():
			if m["nodes"][i]["kind"] != "choice":
				continue
			var run = MissionRun.new(db, m, BAND4.map(func(h): return db.make_hero(h)))
			run.node_index = i
			run.arrive()
			var step: Dictionary = run.choose(0)
			tried += 1
			if step["type"] == "continue":
				slipped += 1
			elif step["enemies"].size() > m["nodes"][i]["options"][1]["enemies"].size():
				bigger_fights += 1
	var rate := float(slipped) / tried
	check(rate > 0.35 and rate < 0.65, "sneaking past works about half the time for the band (%d/%d)" % [slipped, tried])
	check(bigger_fights == tried - slipped, "getting caught brings the guards and one more (%d of %d)" % [bigger_fights, tried - slipped])
	var m2: Dictionary = MissionGen.new(db).generate("robbery", 0, 1, "great_north_road")
	var pair = MissionRun.new(db, m2, [db.make_hero("robin"), db.make_hero("will")])
	var crowd = MissionRun.new(db, m2, BAND4.map(func(h): return db.make_hero(h)) + [db.make_hero("alan")])
	check(pair.sneak_chance() > crowd.sneak_chance(), "two can sneak more quietly than five")
	m2["threat"] = 90
	check(pair.sneak_chance() < 0.75, "alert guards are harder to sneak past")


func test_lending_to_the_knight_costs_gold_and_is_repaid() -> void:
	var c = Campaign.new(db, 77, BAND4)
	c.missions.clear()
	c.missions["great_north_road"] = MissionGen.new(db).story("poor_knight", 10, 3)
	c.missions["great_north_road"]["expires"] = 0
	c.location = "great_north_road"
	c.gold = 50
	var run = c.start_mission()
	run.arrive()
	run.advance()
	check(run.arrive()["type"] == "choice", "Sir Richard asks for help")
	check(not run.can_choose(0) and not run.can_choose(1) and run.can_choose(2), "with 50 gold the band can only wish him luck")
	check(run.choose(0)["type"] == "choice", "trying to lend money the band hasn't got does nothing")
	c.gold = 100
	run = c.start_mission()
	run.arrive()
	run.advance()
	run.arrive()
	run.choose(0)
	check(run.spent == 60, "lending costs 60 gold")
	run.result = "failed"
	c.finish_mission(run)
	check(c.gold == 40 and c.flags.has("knight_loan"), "the gold is gone even if the spies win, and the loan is remembered")
	c.missions["great_north_road"] = MissionGen.new(db).story("poor_knight", 10, 3)
	c.missions["great_north_road"]["expires"] = 0
	run = c.start_mission()
	run.arrive()
	run.advance()
	run.arrive()
	check(run.can_choose(0), "trying the tale again doesn't charge the loan twice")
	# Wishing him luck ends the knight's story.
	var mean = Campaign.new(db, 78, BAND4)
	mean.stories_done.append("poor_knight")
	mean.reputation = 30
	check(not mean.story_ready("knight_pays_abbot"), "no loan, no visit to the Abbot")
	mean.flags.append("knight_loan")
	check(mean.story_ready("knight_pays_abbot"), "with the loan made, Sir Richard's story goes on")
	var knight_returns: Dictionary = db.stories["stories"]["knight_returns"]
	check(int(knight_returns["rewards"]["gold"]) > 80, "Sir Richard pays back more than the band lent (%d)" % int(knight_returns["rewards"]["gold"]))
	var old: Dictionary = JSON.parse_string(JSON.stringify(mean.to_dict()))
	old.erase("flags")
	check(Campaign.from_dict(db, old).flags.has("knight_loan"), "older saves that played the tale keep the knight's story going")


# --- Gisborne's raid ---------------------------------------------------------------

func test_guy_raids_when_his_plot_is_full() -> void:
	var c = Campaign.new(db, 3, BAND4)
	c.plots["guy"] = 99
	c.rest()
	check(not c.ambush.is_empty() and c.ambush.get("raid", "") == "guy", "at 100 Sir Guy rides out to raid the band")
	check(c.ambush["nodes"][0]["enemies"].has("guy"), "and he comes himself")
	check(c.plots["guy"] < 20, "his plot starts again")
	var copy = Campaign.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(copy.ambush.get("raid", "") == "guy", "a waiting raid survives a save")
	# On the road it stops the band where it catches them.
	var t = Campaign.new(db, 4, BAND4)
	t.plots["guy"] = 99
	var visited: Array = t.travel("nottingham")
	check(visited.size() == 1 and not t.ambush.is_empty(), "the raid catches the band on the road")


func test_guy_raid_is_hard_and_takes_one_hero() -> void:
	var wins := 0
	var one_taken := 0
	var losses := 0
	for s in 40:
		var c = Campaign.new(db, 600 + s, BAND4)
		c.hunted_hero = "tuck"
		c.ambush = MissionGen.new(db).guy_raid("the road", "great_north_road", 900 + s)
		c.ambush["hunted"] = "tuck"
		c.location = "great_north_road"
		var rep_before: int = c.reputation
		var run = c.start_ambush()
		autoplay_mission(run)
		c.finish_mission(run)
		if run.result == "success":
			wins += 1
			check(c.reputation >= rep_before + MissionRun.RAID_GLORY, "beating Guy wins glory")
			check(c.captured.is_empty(), "and nobody is taken")
		else:
			losses += 1
			one_taken += 1 if c.captured.keys() == ["tuck"] else 0
			check(c.captured.get("tuck", {}).get("node", "") == "nottingham", "Guy takes his prisoner to Nottingham")
			check(c.missions.get("nottingham", {}).get("rescue_heroes", []) == ["tuck"], "a rescue is posted there")
			check(c.free_heroes().size() == 3 and c.free_heroes().all(func(h): return h.hp >= 1), "the rest of the band gets away")
	print("Guy's raid against four heroes: won %d/40" % wins)
	check(wins <= 20, "Guy's raid is a very hard fight (%d/40 won)" % wins)
	check(wins >= 2, "but it can be won (%d/40)" % wins)
	check(one_taken == losses, "losing always costs exactly the hero Guy is hunting (%d/%d)" % [one_taken, losses])
	# Running away counts as losing.
	var c2 = Campaign.new(db, 7, BAND4)
	c2.ambush = MissionGen.new(db).guy_raid("the road", "great_north_road", 1)
	c2.location = "great_north_road"
	var run2 = c2.start_ambush()
	var step: Dictionary = run2.arrive()
	var b = run2.make_battle(step["enemies"])
	b.result = "retreated"
	run2.battle_finished(b)
	check(run2.result == "failed" and run2.captured.size() == 1, "running from Guy still costs one hero")


func test_guy_may_raid_before_his_plot_is_full() -> void:
	var c = Campaign.new(db, 3, BAND4)
	c.plots["guy"] = 40
	check(c.raid_chance() == 0.0, "no raid while his plot is under half")
	c.plots["guy"] = 70
	var mid: float = c.raid_chance()
	c.plots["guy"] = 95
	var late: float = c.raid_chance()
	check(mid > 0.0 and late > mid * 3, "the chance grows quickly near the top (%.2f then %.2f)" % [mid, late])
	c.plots["guy"] = 100
	check(c.raid_chance() == 1.0, "at 100 he always comes")
	var early := 0
	for s in 200:
		var r = Campaign.new(db, 1000 + s, BAND4)
		r.plots["guy"] = 50
		for _d in 15:
			var before: int = r.plots["guy"]
			r.rest()
			if not r.ambush.is_empty():
				early += 1 if before + 5 < 100 else 0
				break
	check(early > 40 and early < 190, "Guy often strikes before the meter fills, but not always (%d/200)" % early)
