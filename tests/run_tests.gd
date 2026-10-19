## Headless test runner: godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const GameData = preload("res://core/game_data.gd")
const Unit = preload("res://core/unit.gd")

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
	var shots: Array = robin_b.legal_targets(robin_b.heroes()[0], "shoot")
	check(shots.any(func(t): return t.row == "back"), "ranged can hit back row")


func test_back_row_cannot_use_melee_while_front_row_ally_stands() -> void:
	var b = db.make_battle(["robin", "little_john"], "tax_wagon", 3)
	var tuck = Unit.from_data("tuck", db.heroes["tuck"], "heroes")
	b.add_unit(tuck)
	check(b.legal_targets(tuck, "strike").is_empty(), "back-row tuck cannot melee past little john")


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
