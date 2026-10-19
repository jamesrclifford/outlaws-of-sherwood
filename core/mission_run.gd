## Plays one generated mission node by node. Battles are created here but fought by the caller
## (the UI, or a test's autoplay), which hands the finished battle back via battle_finished().
extends RefCounted

const MAX_ENEMIES := 6

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
var result := ""              # "", "success", "failed", "called_off"
var mission_log: Array = []
var _trap_decided := false
var _sprung := {}             # trap effects waiting for this node's battle
var _duel_loadouts := {}      # hero id -> [abilities, row, sprite] kept while a duel sets the weapons


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
	if node_index > 0:
		return found
	if is_bait() and rng.randf() < 0.6:
		mission["bait"]["revealed"] = true
		_log(db.baits[mission["bait"]["by"]]["scout_hint"])
	for n in mission["nodes"]:
		if n.has("trap") and not n["trap"]["revealed"] and rng.randf() < 0.75:
			n["trap"]["revealed"] = true
			found += 1
	_log("Scouts report %d trap%s ahead." % [found, "" if found == 1 else "s"])
	return found


## Called when the band reaches the current node. Returns what the player must do next:
##   {"type": "trap_choice"}  a known trap: call decide_trap(avoid)
##   {"type": "choice", "options": [...]}  call choose(i)
##   {"type": "battle", "enemies": [...]}  fight, then call battle_finished(battle)
##   {"type": "continue"}  nothing to resolve: call advance()
func arrive() -> Dictionary:
	var node := current_node()
	if not _trap_decided:
		_log(node["text"])
	if node.has("trap") and not node["trap"].get("done", false):
		if node["trap"]["revealed"] and not _trap_decided:
			return {"type": "trap_choice", "trap": db.traps[node["trap"]["id"]]}
		_spring_trap(node)
	if node["kind"] == "choice":
		return {"type": "choice", "options": node["options"]}
	return _battle_or_continue(node.get("enemies", []))


func decide_trap(avoid: bool) -> Dictionary:
	var node := current_node()
	_trap_decided = true
	if avoid:
		node["trap"]["done"] = true
		_log("The band avoids the %s." % db.traps[node["trap"]["id"]]["name"])
	return arrive()


func choose(option_index: int) -> Dictionary:
	var opt: Dictionary = current_node()["options"][option_index]
	if opt.has("log"):
		_log(opt["log"])
	gold += int(opt.get("gold", 0))
	reputation += int(opt.get("reputation", 0))
	if opt["result"] == "sneak":
		if rng.randf() < 0.7:
			_log("The band slips past unseen.")
			return {"type": "continue"}
		_log("A twig snaps. The sentry raises the alarm!")
		return _battle_or_continue(["man_at_arms"])
	return _battle_or_continue(opt.get("enemies", []))


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
			if recruited != "":
				_log("%s joins the band!" % db.heroes[recruited]["name"])
		else:
			_fail("The objective was not achieved.")


func _objective_met() -> bool:
	match mission["type"]:
		"robbery":
			return loot_taken
		"story":
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
