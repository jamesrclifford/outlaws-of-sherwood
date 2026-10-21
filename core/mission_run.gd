## Plays one generated mission node by node. Battles are created here but fought by the caller
## (the UI, or a test's autoplay), which hands the finished battle back via battle_finished().
extends RefCounted

const Archery = preload("res://core/archery.gd")
const MAX_ENEMIES := 6
const SNEAK_BASE := 0.75       # chance for one or two heroes to creep past where nobody is on guard
const SNEAK_PER_HERO := 0.04   # each extra hero makes more noise
const SNEAK_MIN := 0.3
const RAID_GLORY := 8          # reputation for beating Sir Guy's raid
const TOUGH_HP := 0.02         # a legend's foes gain this much health per point of reputation it asks for
const TOUGH_ATK := 0.005       # and this much bite

var db
var mission: Dictionary
var heroes: Array             # persistent hero units; HP carries from node to node
var rng := RandomNumberGenerator.new()
var node_index := 0
var gold := 0
var reputation := 0
var prisoner_freed := false
var loot_taken := false
var recruited := ""           # a story mission's new companion, once won over
var captured: Array = []
var result := ""              # "", "success", "failed", "called_off", "outshot" (a legend's contest lost)
var mission_log: Array = []
var _trap_decided := false
var _sprung := {}             # trap effects waiting for this node's battle
var scouted := false          # scouting takes the band a day, paid when the mission ends
var _duel_loadouts := {}      # hero id -> [abilities, row, sprite] kept while a duel sets the weapons
var disguise := ""            # the disguise the band wore, if any
var surprise := false         # the next battle opens with the enemy caught flat-footed
var known_disguises = null    # disguise ids the band has learned from the legends; null means all
var purse := -1               # the band's gold at home, for choices that cost some; -1 means no limit
var spent := 0                # gold paid out of the band's purse by choices (kept even if the job fails)
var flags: Array = []         # story flags set by choices (Sir Richard's loan), kept by the campaign
var grip := {}                # set by the campaign: region name, Sheriff's control there and how much a win loosens it


func _init(game_data, mission_data: Dictionary, hero_units: Array) -> void:
	db = game_data
	mission = mission_data
	heroes = hero_units
	rng.seed = int(mission["seed"]) + 7


## Walks away from a job the scouts exposed as bait. No reward, no risk.
func call_off() -> void:
	if node_index == 0 and is_bait() and mission["bait"]["revealed"]:
		result = "called_off"
		_log("The band melts back into Sherwood. %s waits in vain." % db.baits[mission["bait"]["by"]]["name"])


func current_node() -> Dictionary:
	return mission["nodes"][node_index] if node_index < mission["nodes"].size() else {}


func is_over() -> bool:
	return result != ""


func _log(text: String) -> void:
	mission_log.append(text)


func is_bait() -> bool:
	return not mission.get("bait", {}).is_empty()


## Scouting ahead may uncover that the whole job is bait, and reveals each planted trap with a
## good chance. Only possible before setting out.
func scout() -> int:
	var found := 0
	if node_index > 0 or scouted:
		return found
	scouted = true
	if is_bait() and rng.randf() < 0.6:
		mission["bait"]["revealed"] = true
		_log(db.baits[mission["bait"]["by"]]["scout_hint"])
	for n in mission["nodes"]:
		if n.has("trap") and not n["trap"]["revealed"] and rng.randf() < 0.75:
			n["trap"]["revealed"] = true
			found += 1
	_log("Scouts report %d trap%s ahead." % [found, "" if found == 1 else "s"])
	return found


## The three disguises on offer for this job, each secretly fated to work ("slip": walk past a
## fight), half-work ("surprise": strike first) or fail ("blown": attacked at once). The mission's
## seed decides, so the same job always offers the same three with the same fates.
func disguise_options() -> Array:
	if not mission.has("disguises"):
		var pick := RandomNumberGenerator.new()
		pick.seed = int(mission["seed"]) + 31
		var ids: Array = known()
		var fates := ["slip", "surprise", "blown"]
		var options := []
		for i in 3:
			var id: String = ids.pop_at(pick.randi_range(0, ids.size() - 1))
			options.append({"id": id, "fate": fates.pop_at(pick.randi_range(0, fates.size() - 1))})
		mission["disguises"] = options
	return mission["disguises"]


## The disguises the band can choose from.
func known() -> Array:
	return db.disguises.keys() if known_disguises == null else known_disguises.duplicate()


func can_disguise() -> bool:
	return node_index == 0 and disguise == "" and not scouted and mission["type"] in ["robbery", "rescue"] \
		and (mission.has("disguises") or known().size() >= 3)


## Puts on the chosen disguise and tells how it went. Returns its fate.
func wear_disguise(option_index: int) -> String:
	var opt: Dictionary = disguise_options()[option_index]
	var d: Dictionary = db.disguises[opt["id"]]
	disguise = opt["id"]
	_log(d["wear"])
	var place: String = mission["location_name"]
	match opt["fate"]:
		"slip":
			for i in range(1, mission["nodes"].size()):
				var n: Dictionary = mission["nodes"][i]
				if not n.get("enemies", []).is_empty() or n["kind"] == "choice":
					n["slipped"] = d["slip"].format({"place": place})
					break
		"surprise":
			surprise = true
			_log(d["surprise"].format({"place": place}))
		"blown":
			_log(d["blown"].format({"place": place}))
			var pool: Array = db.locations[mission["location"]]["enemy_pool"]
			var foes := []
			for _i in 2 + int(mission["threat"]) / 40:
				foes.append(pool[rng.randi_range(0, pool.size() - 1)])
			mission["nodes"].insert(0, {"kind": "combat", "text": "Spotted! The guards attack before the band is ready.", "enemies": foes})
	return opt["fate"]


## Called when the band reaches the current node. Returns what the player must do next:
##   {"type": "trap_choice"}  a known trap: call decide_trap(avoid)
##   {"type": "choice", "options": [...]}  call choose(i)
##   {"type": "battle", "enemies": [...]}  fight, then call battle_finished(battle)
##   {"type": "archery"}  shoot a round from make_archery(), then call archery_finished(round)
##   {"type": "continue"}  nothing to resolve: call advance()
func arrive() -> Dictionary:
	var node := current_node()
	if not _trap_decided:
		_log(node["text"])
	if node.has("trap") and not node["trap"].get("done", false):
		if node["trap"]["revealed"] and not _trap_decided:
			return {"type": "trap_choice", "trap": db.traps[node["trap"]["id"]]}
		_spring_trap(node)
	if node.has("slipped"):
		_log(node["slipped"])
		_apply_objective(node)
		return {"type": "continue"}
	if node["kind"] == "choice":
		return {"type": "choice", "options": node["options"]}
	if node["kind"] == "archery":
		return {"type": "archery"}
	return _battle_or_continue(node.get("enemies", []))


func decide_trap(avoid: bool) -> Dictionary:
	var node := current_node()
	_trap_decided = true
	if avoid:
		node["trap"]["done"] = true
		_log("The band avoids the %s." % db.traps[node["trap"]["id"]]["name"])
	return arrive()


## Whether the band can afford an option (some story choices are paid from the band's purse).
func can_choose(option_index: int) -> bool:
	return _cost(current_node()["options"][option_index]) == 0 or purse < 0 or purse - spent >= _cost(current_node()["options"][option_index])


## What an option costs: nothing if its flag is already set (the loan was made on an earlier try).
func _cost(opt: Dictionary) -> int:
	return 0 if flags.has(opt.get("flag", "")) else int(opt.get("pay", 0))


func choose(option_index: int) -> Dictionary:
	var opt: Dictionary = current_node()["options"][option_index]
	if not can_choose(option_index):
		_log("The band hasn't got %d gold to spare." % int(opt["pay"]))
		return {"type": "choice", "options": current_node()["options"]}
	spent += _cost(opt)
	if opt.has("flag") and not flags.has(opt["flag"]):
		flags.append(opt["flag"])
	if opt.has("log"):
		_log(opt["log"])
	gold += int(opt.get("gold", 0))
	reputation += int(opt.get("reputation", 0))
	if opt["result"] == "sneak":
		if rng.randf() < sneak_chance():
			_log("The band slips past unseen.")
			return {"type": "continue"}
		# Caught creeping: the guards the band hoped to avoid, and one more who heard the alarm.
		_log("A twig snaps. The sentry raises the alarm!")
		var fight: Array = current_node()["options"].filter(func(o): return o["result"] == "fight")
		var guards: Array = fight[0].get("enemies", []).duplicate() if not fight.is_empty() else ["man_at_arms"]
		return _battle_or_continue(guards + ["man_at_arms"])
	return _battle_or_continue(opt.get("enemies", []))


## Sneaking works about half the time: less often where the Sheriff's men are alert (high threat)
## and when more of the band are trying to creep past together.
func sneak_chance() -> float:
	var extra := maxi(0, active_heroes().size() - 2)
	return clampf(SNEAK_BASE - int(mission["threat"]) / 250.0 - SNEAK_PER_HERO * extra, SNEAK_MIN, SNEAK_BASE)


func _battle_or_continue(enemy_ids: Array) -> Dictionary:
	var node := current_node()
	if enemy_ids.is_empty():
		_apply_objective(node)
		return {"type": "continue"}
	var all_enemies: Array = enemy_ids + _sprung.get("extra_enemies", [])
	return {"type": "battle", "enemies": all_enemies.slice(0, MAX_ENEMIES)}


func make_battle(enemy_ids: Array):
	var node := current_node()
	if node.has("abilities"):
		_arm_for_duel(node["abilities"], node.get("sprites", {}))
	var b = db.make_custom_battle(fighters(), enemy_ids, rng.randi())
	b.friendly = node.get("friendly", false)
	# Legends that ask for a big reputation are told of bigger, tougher foes.
	var tough: int = int(mission.get("toughness", 0))
	if tough > 0:
		for u in b.units:
			if u.side == "enemies":
				u.max_hp = int(round(u.max_hp * (1.0 + tough * TOUGH_HP)))
				u.hp = u.max_hp
				u.atk = int(round(u.atk * (1.0 + tough * TOUGH_ATK)))
	if surprise:
		surprise = false
		_log("Surprise attack! The enemy is caught flat-footed.")
		for u in b.units:
			if u.side == "enemies":
				u.add_status("stunned", 1)
	return b


## A duel can set the weapons (quarterstaves on the bridge): the fighters stand in the front row
## with only those abilities, and maybe a matching look, until the bout ends.
func _arm_for_duel(ability_ids: Array, sprites: Dictionary) -> void:
	for h in fighters():
		_duel_loadouts[h.id] = [h.abilities, h.row, h.sprite]
		h.abilities = ability_ids.duplicate()
		h.sprite = sprites.get(h.id, h.sprite)
		h.row = "front"
		h.fixed_abilities = true


func _disarm_after_duel() -> void:
	for h in heroes:
		if _duel_loadouts.has(h.id):
			h.abilities = _duel_loadouts[h.id][0]
			h.row = _duel_loadouts[h.id][1]
			h.sprite = _duel_loadouts[h.id][2]
			h.fixed_abilities = false
	_duel_loadouts.clear()


## The scenery for where the band is now: a legend's node may move the scene (the Potter's fight
## is deep in Sherwood, though the tale is told at Nottingham market).
func backdrop() -> String:
	if node_index < mission["nodes"].size():
		return current_node().get("backdrop", mission["location"])
	return mission["location"]


## The archery round at the current node, against its rival.
func make_archery():
	var node := current_node()
	return Archery.new(rng.randi(), int(node.get("arrows", 3)), float(node.get("skill", 0.5)), node.get("rival", "The champion"))


## Who shoots in a contest: Robin if he's here, otherwise the first of the band.
func archer():
	for h in active_heroes():
		if h.id == "robin":
			return h
	return active_heroes()[0] if not active_heroes().is_empty() else null


## Win or lose, a contest goes on; winning takes the node's prize.
func archery_finished(round) -> void:
	var node := current_node()
	var who: String = archer().name if archer() else "The band"
	_log("%s scores %d. %s scores %d." % [who, round.total(), round.rival_name, round.rival_total()])
	if round.won():
		_log(node.get("win", "The crowd roars!"))
		var prize: Dictionary = node.get("prize", {})
		gold += int(prize.get("gold", 0))
		reputation += int(prize.get("reputation", 0))
	else:
		_log(node.get("lose", "So close!"))
		reputation += 1
		if mission["type"] == "story":
			# A legend lost at the butts is not over: the band will hear of another match.
			result = "outshot"
			_log("This legend is not finished. Another match will come round before long.")


func active_heroes() -> Array:
	return heroes.filter(func(h): return not captured.has(h.id))


## Who fights at the current node: a story duel names its fighters, otherwise the whole band.
func fighters() -> Array:
	var named: Array = current_node().get("party", [])
	var picked := active_heroes().filter(func(h): return named.has(h.id))
	return picked if not picked.is_empty() else active_heroes()


func battle_finished(battle) -> void:
	_sprung.clear()
	_disarm_after_duel()
	if mission.has("raid"):
		_raid_finished(battle)
		return
	var node := current_node()
	if battle.friendly:
		# A sporting bout: win or lose, the story goes on.
		_log(node["win"] if battle.result == "victory" else node["lose"])
		# Nobody limps out of a friendly bout: fighters get back up to at least half strength.
		for h in fighters():
			h.hp = maxi(h.hp, h.max_hp / 2)
		return
	if battle.result == "victory":
		gold += battle.gold_won
		_apply_objective(current_node())
		return
	for h in battle.captured:
		captured.append(h)
	if battle.result == "retreated" and node.get("is_escape", false) and _objective_met():
		_log("The band shakes off the pursuit, but leaves friends behind.")
		return
	if battle.result == "retreated" and is_bait() and (node.get("ambush", false) or node.get("is_escape", false)):
		# Slipping out of a trap is the goal of a bait mission: skip straight home.
		_log("The band slips out of the trap and runs for the greenwood.")
		node_index = mission["nodes"].size() - 1
		return
	_fail("The mission has failed." if battle.result == "defeat" else "The band falls back to Sherwood.")


## Beating Sir Guy's raid wins glory; losing or running away, he takes one hero (the one he is
## hunting if they're here, otherwise anyone) and the rest get away.
func _raid_finished(battle) -> void:
	if battle.result == "victory":
		gold += battle.gold_won
		reputation += RAID_GLORY
		_log("Sir Guy is beaten! He limps back to his horse, swearing revenge.")
		return
	var pool := active_heroes()
	var taken = null
	for h in pool:
		if h.id == mission.get("hunted", ""):
			taken = h
	if taken == null and not pool.is_empty():
		taken = pool[rng.randi_range(0, pool.size() - 1)]
	for h in pool:
		h.hp = maxi(h.hp, 1)
	captured = [taken.id] if taken else []
	if taken:
		_log("Sir Guy throws %s over his saddle and gallops for Nottingham!" % taken.name)
	_fail("The rest of the band escapes into the greenwood.")


func advance() -> void:
	if is_over():
		return
	node_index += 1
	_trap_decided = false
	_sprung.clear()
	if node_index >= mission["nodes"].size():
		if is_bait():
			result = "success"
			reputation += 5
			_log("The band escaped %s's trap with %d gold!" % [db.baits[mission["bait"]["by"]]["name"], gold])
		elif _objective_met():
			gold += int(mission["rewards"]["gold"])
			reputation += int(mission["rewards"]["reputation"])
			result = "success"
			_log("Success! The band returns with %d gold." % gold)
			if mission["type"] == "rescue":
				_log(_rescue_impact())
			if recruited != "":
				_log("%s joins the band!" % db.heroes[recruited]["name"])
		else:
			_fail("The objective was not achieved.")


## What freeing the prisoner did, spelled out for the player.
func _rescue_impact() -> String:
	var who: String = "The villager is home safe"
	if mission.has("rescue_heroes"):
		var names: Array = mission["rescue_heroes"].map(func(h): return db.heroes[h]["name"])
		who = "%s is back with the band" % " and ".join(names)
	var text := "%s! The tale spreads: +%d reputation" % [who, reputation]
	if grip.is_empty():
		return text + "."
	var before: int = int(grip["control"])
	var after: int = maxi(0, before - int(grip["drop"]))
	return text + ", and the Sheriff's grip on %s loosens from %d%% to %d%%." % [grip["region"], before, after]


func _objective_met() -> bool:
	match mission["type"]:
		"robbery":
			return loot_taken
		"story", "contest", "ambush":
			return true
	return prisoner_freed


func _apply_objective(node: Dictionary) -> void:
	if node.get("loot", false):
		loot_taken = true
		_log("The loot is taken!")
	if node.get("ambush", false):
		_log("The band fights its way out of the ambush!")
	if node.get("prisoner", false):
		prisoner_freed = true
		_log("The prisoner is free!")
	if node.get("recruit", false):
		recruited = mission["recruit"]


func _fail(text: String) -> void:
	result = "failed"
	gold = 0
	_log(text)
	if not captured.is_empty():
		var names: Array = heroes.filter(func(h): return captured.has(h.id)).map(func(h): return h.name)
		_log("Captured: %s. A rescue mission will be needed." % ", ".join(names))


func _spring_trap(node: Dictionary) -> void:
	node["trap"]["done"] = true
	var trap: Dictionary = db.traps[node["trap"]["id"]]
	var victim = _pick_victim(node["trap"]["target"])
	_log(trap["desc"].format({"hero": victim.name if victim else "someone"}))
	match trap["effect"]:
		"netted":
			if victim:
				victim.add_status("netted", 2)
		"snare":
			if victim:
				victim.hp = max(1, victim.hp - int(trap["damage"]))
				victim.add_status("pinned", 2)
		"ambush":
			_sprung["extra_enemies"] = trap["extra_enemies"]


func _pick_victim(target_id: String):
	var pool := active_heroes()
	for h in pool:
		if h.id == target_id:
			return h
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null
