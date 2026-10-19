## Turn-based battle rules: initiative, actions, enemy AI, outcome.
## Deterministic for a given seed so fights can be replayed and balanced headlessly.
extends RefCounted

const Unit = preload("res://core/unit.gd")

signal event(text: String)
## For the battle screen's animations: who used what on whom, and what each target took.
signal acted(unit, ability_id: String, targets: Array)
signal damaged(unit, amount: int, is_crit: bool)
signal healed(unit, amount: int)
signal status_added(unit, status: String)

var abilities: Dictionary
var enemy_defs: Dictionary
var units: Array = []
var rng := RandomNumberGenerator.new()
var round_number := 0
var turn_order: Array = []
var turn_index := -1
var result := ""          # "", "victory", "defeat", "retreated"
var captured: Array = []  # hero ids captured when the band loses or retreats
var gold_escaped := 0
var gold_won := 0
var battle_log: Array = []
var friendly := false     # a sporting bout from a story: losers yield instead of being captured


func _init(ability_db: Dictionary, enemy_db: Dictionary, seed_value: int) -> void:
	abilities = ability_db
	enemy_defs = enemy_db
	rng.seed = seed_value


func add_unit(u) -> void:
	units.append(u)


func heroes() -> Array:
	return units.filter(func(u): return u.side == "heroes")


func enemies() -> Array:
	return units.filter(func(u): return u.side == "enemies")


func active(side: String) -> Array:
	return units.filter(func(u): return u.side == side and u.is_active())


func current():
	if turn_index < 0 or turn_index >= turn_order.size():
		return null
	return turn_order[turn_index]


func is_over() -> bool:
	return result != ""


func _emit(text: String) -> void:
	battle_log.append(text)
	event.emit(text)


# --- Turn flow ---------------------------------------------------------------

## Advances to the next unit able to act. Returns that unit, or null if the battle ended.
func next_turn():
	while not is_over():
		turn_index += 1
		if turn_index >= turn_order.size():
			_start_round()
		var u = current()
		if u == null or not u.is_active():
			continue
		if u.begin_turn():
			return u
		_emit("%s cannot act." % u.name)
		u.end_turn()
	return null


func _start_round() -> void:
	round_number += 1
	turn_index = 0
	turn_order = units.filter(func(u): return u.is_active())
	# Shuffle first so speed ties break by seeded RNG, then stable-sort by speed.
	for i in range(turn_order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = turn_order[i]
		turn_order[i] = turn_order[j]
		turn_order[j] = tmp
	turn_order.sort_custom(func(a, b): return a.effective_speed() > b.effective_speed())


func end_turn() -> void:
	var u = current()
	if u != null:
		u.end_turn()
	_check_end()


## Upcoming units this round after the current one, for the initiative timeline.
func upcoming() -> Array:
	var out := []
	for i in range(max(turn_index, 0), turn_order.size()):
		if turn_order[i].is_active():
			out.append(turn_order[i])
	return out


# --- Targeting ---------------------------------------------------------------

func usable_abilities(u) -> Array:
	return u.available_abilities().filter(func(a): return abilities[a]["ap"] <= u.ap and not legal_targets(u, a).is_empty())


func legal_targets(u, ability_id: String) -> Array:
	var ab: Dictionary = abilities[ability_id]
	var foe_side := "enemies" if u.side == "heroes" else "heroes"
	match ab["target"]:
		"self":
			return [u]
		"ally":
			return active(u.side)
		"all_allies":
			return [u]
		"enemy", "all_enemies":
			if ab.get("range", "any") == "melee" and u.row == "back" and _has_front(u.side):
				return []
			var foes := active(foe_side).filter(func(f): return not f.has_status("hidden"))
			if ab.get("range", "any") == "melee" and _has_front(foe_side):
				foes = foes.filter(func(f): return f.row == "front")
			var taunters := foes.filter(func(f): return f.has_status("taunt"))
			if not taunters.is_empty() and ab["target"] == "enemy":
				return taunters
			return foes
	return []


func _has_front(side: String) -> bool:
	return active(side).any(func(x): return x.row == "front")


# --- Actions -----------------------------------------------------------------

## Performs an ability. Returns true if it was legal and happened.
func perform(u, ability_id: String, target) -> bool:
	if is_over() or u != current() or not u.available_abilities().has(ability_id):
		return false
	var ab: Dictionary = abilities[ability_id]
	if ab["ap"] > u.ap or not legal_targets(u, ability_id).has(target):
		return false
	u.ap -= ab["ap"]
	u.statuses.erase("hidden")

	var targets: Array = [target]
	if ab["target"] == "all_enemies":
		targets = legal_targets(u, ability_id)
	elif ab["target"] == "all_allies":
		targets = active(u.side)

	_emit("%s uses %s." % [u.name, ab["name"]])
	acted.emit(u, ability_id, targets)
	for t in targets:
		if ab.has("power"):
			for _i in int(ab.get("hits", 1)):
				if t.is_active():
					_deal_damage(u, t, ab)
		if ab.has("heal"):
			var amount_healed: int = t.heal(int(round(u.atk * float(ab["heal"]))))
			_emit("%s recovers %d HP." % [t.name, amount_healed])
			healed.emit(t, amount_healed)
		for eff in ab.get("effects", []):
			if t.is_active() and rng.randf() < float(eff.get("chance", 1.0)):
				t.add_status(eff["status"], int(eff["turns"]))
				_emit("%s is %s." % [t.name, eff["status"]])
				status_added.emit(t, eff["status"])
	if ab.has("summon"):
		_summon(u, ab["summon"])
	_check_end()
	return true


func _deal_damage(attacker, target, ab: Dictionary) -> void:
	var dmg: float = attacker.atk * float(ab["power"])
	for tag in ab.get("bonus_vs_tag", {}):
		if target.tags.has(tag):
			dmg *= float(ab["bonus_vs_tag"][tag])
	if attacker.has_status("inspired"):
		dmg *= 1.25
	var is_crit: bool = rng.randf() < attacker.crit + float(ab.get("bonus_crit", 0.0))
	if is_crit:
		dmg *= 1.5
	dmg -= target.def * 0.5
	if target.has_status("defending"):
		dmg *= 0.5
	dmg *= rng.randf_range(0.9, 1.1)
	var amount: int = max(1, int(round(dmg)))
	target.hp = max(0, target.hp - amount)
	_emit("%s takes %d%s." % [target.name, amount, " (critical!)" if is_crit else ""])
	damaged.emit(target, amount, is_crit)
	if target.is_down():
		_on_down(target)


func _on_down(target) -> void:
	if target.side == "heroes":
		_emit("%s is down!" % target.name)
		return
	# Family-friendly: enemies are knocked out, never killed.
	_emit("%s is knocked out." % target.name)
	gold_won += target.carries_gold
	if target.tags.has("leader"):
		for e in active("enemies"):
			if not e.tags.has("boss") and rng.randf() < 0.5:
				e.fled = true
				_emit("%s loses heart and flees!" % e.name)
				gold_escaped += e.carries_gold


func _summon(u, enemy_id: String) -> void:
	if active(u.side).size() >= 6:
		return
	var s = Unit.from_data(enemy_id, enemy_defs[enemy_id], u.side)
	add_unit(s)
	_emit("%s arrives!" % s.name)


## Swap rows (costs 1 AP). Pinned or netted units cannot move.
func swap_row(u) -> bool:
	if u != current() or u.ap < 1 or u.has_status("pinned"):
		return false
	u.ap -= 1
	u.row = "back" if u.row == "front" else "front"
	_emit("%s moves to the %s row." % [u.name, u.row])
	return true


## Any hero may attempt a retreat (uses all AP). Downed heroes left behind are captured.
func retreat(u) -> bool:
	if u != current() or u.side != "heroes" or u.ap < 1:
		return false
	u.ap = 0
	if rng.randf() < 0.6:
		_emit("The band slips away into the trees.")
		_finish("retreated")
		return true
	_emit("The retreat is cut off!")
	return false


func free_ally(u, target) -> bool:
	if u != current() or u.ap < 1 or not target.has_status("netted"):
		return false
	u.ap -= 1
	target.statuses.erase("netted")
	_emit("%s cuts %s free." % [u.name, target.name])
	return true


# --- Enemy AI ----------------------------------------------------------------

## Plays the current enemy's whole turn.
func run_ai_turn() -> void:
	var u = current()
	while not is_over() and u.ap > 0:
		var options := usable_abilities(u)
		if options.is_empty():
			break
		var ability_id: String = options[rng.randi_range(0, options.size() - 1)]
		# Prefer damaging abilities; defensive ones only sometimes.
		if abilities[ability_id]["target"] == "self" and options.size() > 1 and rng.randf() < 0.7:
			options.erase(ability_id)
			ability_id = options[rng.randi_range(0, options.size() - 1)]
		var targets := legal_targets(u, ability_id)
		targets.sort_custom(func(a, b): return a.hp < b.hp)
		var pick = targets[0] if rng.randf() < 0.6 else targets[rng.randi_range(0, targets.size() - 1)]
		perform(u, ability_id, pick)
	end_turn()


# --- Outcome -----------------------------------------------------------------

func _check_end() -> void:
	if is_over():
		return
	if active("enemies").is_empty():
		_finish("victory")
	elif active("heroes").is_empty():
		_finish("defeat")


func _finish(how: String) -> void:
	result = how
	for h in heroes():
		if h.is_down():
			if how == "victory":
				h.hp = 1
				_emit("%s is helped back to their feet." % h.name)
			elif friendly:
				h.hp = 1
				_emit("%s yields the bout." % h.name)
			else:
				captured.append(h.id)
				_emit("%s is captured by the Sheriff's men!" % h.name)
	for e in enemies():
		if e.is_active():
			gold_escaped += e.carries_gold
	_emit({"victory": "Victory!", "defeat": "The band is defeated.", "retreated": "Retreated."}[how])
