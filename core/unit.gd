## A single combatant (hero or enemy) inside a battle. Pure data + rules, no UI.
extends RefCounted

const AP_PER_TURN := 2
const BACK_ROW_ABILITY := "bow_shot"

var id: String
var sprite: String        # art to draw; rivals in story duels borrow a hero's look
var name: String
var short: String         # a one-word name for the battle screen; empty to derive it
var cls: String           # hero class, e.g. "Archer"; enemies have none
var side: String          # "heroes" or "enemies"
var max_hp: int
var hp: int
var atk: int
var def: int
var spd: int
var crit: float
var row: String           # "front" or "back"
var tags: Array = []
var abilities: Array = []
var carries_gold: int = 0
var ap: int = 0
var statuses := {}        # status id -> turns remaining
var fled := false
var fixed_abilities := false  # a story duel set the weapons: no bow from the back row


## One word for tight spots on screen: the data's "short", else the first word of the name.
func short_name() -> String:
	return short if short != "" else name.trim_prefix("The ").split(" ")[0]


static func from_data(unit_id: String, data: Dictionary, unit_side: String):
	var u = load("res://core/unit.gd").new()
	u.id = unit_id
	u.sprite = data.get("sprite", unit_id)
	u.name = data.get("name", unit_id)
	u.short = data.get("short", "")
	u.cls = data.get("class", "")
	u.side = unit_side
	u.max_hp = int(data["hp"])
	u.hp = u.max_hp
	u.atk = int(data["atk"])
	u.def = int(data["def"])
	u.spd = int(data["spd"])
	u.crit = float(data.get("crit", 0.0))
	u.row = data.get("row", "front")
	u.tags = data.get("tags", [])
	u.abilities = data.get("abilities", [])
	u.carries_gold = int(data.get("carries_gold", 0))
	return u


## Abilities usable right now. Anyone standing in the back row can loose a bow shot,
## except those tagged no_bow (Friar Tuck sends his dogs instead).
func available_abilities() -> Array:
	var out := abilities.duplicate()
	if row == "back" and not fixed_abilities and not out.has(BACK_ROW_ABILITY) and not tags.has("no_bow"):
		out.append(BACK_ROW_ABILITY)
	return out


func is_active() -> bool:
	return hp > 0 and not fled


func is_down() -> bool:
	return hp <= 0


func has_status(status: String) -> bool:
	return statuses.has(status)


func add_status(status: String, turns: int) -> void:
	statuses[status] = max(turns, int(statuses.get(status, 0)))


## Called at the start of this unit's turn. Returns false if the turn is skipped.
func begin_turn() -> bool:
	ap = AP_PER_TURN
	statuses.erase("defending")
	if has_status("stunned") or has_status("netted"):
		ap = 0
		return false
	return true


## Called at the end of this unit's turn: tick down timed statuses.
func end_turn() -> void:
	for s in statuses.keys():
		statuses[s] -= 1
		if statuses[s] <= 0 and s != "defending":
			statuses.erase(s)


func effective_speed() -> int:
	return spd - (3 if has_status("pinned") else 0)


func heal(amount: int) -> int:
	var before := hp
	hp = min(max_hp, hp + amount)
	return hp - before
