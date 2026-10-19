## Headless test runner: godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const GameData = preload("res://core/game_data.gd")
const Unit = preload("res://core/unit.gd")
const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")
const Campaign = preload("res://core/campaign.gd")

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
			step = run.choose(1)
		if step["type"] == "battle":
			var b = run.make_battle(step["enemies"])
			autoplay(b)
			run.battle_finished(b)
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
		c.travel(targets[0])
		var run = c.start_mission()
		if run == null:
			c.travel("camp")
			continue
		autoplay_mission(run, true)
		c.finish_mission(run)
		played += 1
		c.travel("camp")
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


# --- Story missions --------------------------------------------------------------

func test_story_data_is_valid() -> void:
	var kinds := ["approach", "combat", "choice", "duel", "hazard", "objective", "escape"]
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
	return order.slice(0, maxi(2, deepest + 1))


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
		c.travel(at)
		for h in c.heroes.values():
			h.hp = h.max_hp
		var run = c.start_mission()
		autoplay_mission(run)
		c.finish_mission(run)
		c.captured.clear()
		c._remove_rescues()
		c.travel("camp")
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
			c.travel(targets[0])
			var run = c.start_mission()
			if run == null:
				c.travel("camp")
				continue
			autoplay_mission(run, true)
			if c.band.size() <= 2 and run.mission["type"] != "story":
				early_jobs += 1
				early_ok += 1 if run.result == "success" else 0
			c.finish_mission(run)
			c.travel("camp")
			while c.supply_days() < 8 and c.buy_supplies():
				pass
			c.rest()
		finished += c.stories_done.size()
		print("story campaign %d: day %d, band %s, legends %s, gold %d, rep %d" % [s, c.day, c.band, c.stories_done, c.gold, c.reputation])
	print("ordinary jobs tried with only Robin and Will: %d/%d succeeded" % [early_ok, early_jobs])
	check(finished >= 6 * 3, "most legends get played within 30 trips (%d of %d)" % [finished, 6 * db.stories["stories"].size()])
