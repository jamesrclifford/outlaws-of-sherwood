## A timing meter for close-in moves: a marker swings along a bar and each tap is judged by how
## near the middle it lands. Little John's sweep is one big swing; Will's flourish is three quick
## cuts. Each tap's quality runs from 0 (a wild swing) to 1 (dead centre).
## Like archery, the caller says when each tap happens, so a seed and its timing always replay.
extends RefCounted

const SWEET := 0.4            # how far from the middle a tap still counts for something

var rng := RandomNumberGenerator.new()
var taps := 1
var speed := 1.0
var qualities: Array = []
var _phase := 0.0


func _init(seed_value: int, tap_count := 1, swing_speed := 1.0) -> void:
	rng.seed = seed_value
	taps = tap_count
	speed = swing_speed
	_phase = rng.randf_range(0, TAU)


## The marker's place on the bar, 0 (left end) to 1 (right end), t seconds into this tap's swing.
func pos(t: float) -> float:
	return 0.5 + 0.5 * sin(t * 2.6 * speed + _phase)


func tap(t: float) -> float:
	if done():
		return 0.0
	var q := quality_at(pos(t))
	qualities.append(q)
	_phase = rng.randf_range(0, TAU)
	return q


func done() -> bool:
	return qualities.size() >= taps


static func quality_at(p: float) -> float:
	return clampf(1.0 - absf(p - 0.5) / SWEET, 0.0, 1.0)
