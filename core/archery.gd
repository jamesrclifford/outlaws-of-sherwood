## An archery round. Each arrow is aimed in two taps: the sight sways left and right until the archer
## taps to fix it, then up and down until a second tap looses the arrow. The wind carries each arrow
## sideways, so a good archer fixes the sight a little into the wind.
## Positions are in target units: the centre is (0, 0) and the outer ring has radius 1.
## The caller (the screen, or a test) says when each tap happens; nothing else is left to chance,
## so the same seed and the same timing always score the same.
extends RefCounted

const SWAY := 0.9             # how far the sight swings from the centre
const WIND_PUSH := 0.35       # how far a full-strength wind carries an arrow
## Tuned with a simulated player whose taps land within about 60ms (tests/run_tests.gd): they beat
## a village champion almost always, the best rivals about two times in three.
const SWING_RATE := 1.8       # radians per second at speed 1
const RIVAL_SPREAD := 6.0     # how far a rival's arrows stray, falling as their skill rises
const RIVAL_MIN_SPREAD := 1.2 # even the best rival is not perfect

var rng := RandomNumberGenerator.new()
var arrows := 3               # arrows each archer shoots
var speed := 1.0              # how fast the sight swings; better rivals mean a faster sight
var wind := 0.0               # this arrow's wind, -1 (blowing left) to 1 (blowing right)
var locked_x = null           # the sight's fixed left-right position, once the first tap is in
var shots: Array = []         # where each arrow landed
var scores: Array = []
var rival_name := ""          # empty when there is no rival (a single shot in battle)
var rival_scores: Array = []
var _phase := 0.0


## rival_skill 0..1: how well the rival shoots, and how hard the round is.
func _init(seed_value: int, arrow_count := 3, rival_skill := 0.0, rival := "") -> void:
	rng.seed = seed_value
	arrows = arrow_count
	speed = 1.0 + rival_skill * 0.3
	rival_name = rival
	if rival != "":
		for i in arrows:
			var miss: float = absf(rng.randfn(0.0, (1.0 - rival_skill) * RIVAL_SPREAD + RIVAL_MIN_SPREAD))
			rival_scores.append(clampi(10 - int(miss), 0, 10))
	_next_arrow()


func _next_arrow() -> void:
	wind = snappedf(rng.randf_range(-1.0, 1.0), 0.1)
	locked_x = null
	_phase = rng.randf_range(0, TAU)


## Where the sight is t seconds after this tap's swing began.
func aim_at(t: float) -> Vector2:
	var swing: float = sin(t * SWING_RATE * speed + _phase) * SWAY
	return Vector2(swing, 0) if locked_x == null else Vector2(locked_x, swing)


## Where an arrow loosed at time t would land, once the sight's left-right position is fixed.
func landing(t: float) -> Vector2:
	return aim_at(t) + Vector2(wind * WIND_PUSH, 0)


## A tap at time t: the first fixes left-right and returns -1, the second looses the arrow and
## returns its score.
func tap(t: float) -> int:
	if done():
		return 0
	if locked_x == null:
		locked_x = aim_at(t).x
		_phase = rng.randf_range(0, TAU)
		return -1
	var at := landing(t)
	shots.append(at)
	var s := score_at(at)
	scores.append(s)
	if not done():
		_next_arrow()
	return s


func done() -> bool:
	return shots.size() >= arrows


## Ten rings: 10 in the gold at the middle, 1 on the outer edge, 0 for a miss.
static func score_at(p: Vector2) -> int:
	return clampi(10 - int(p.length() * 10.0), 0, 10)


func total() -> int:
	return scores.reduce(func(a, b): return a + b, 0)


func rival_total() -> int:
	return rival_scores.reduce(func(a, b): return a + b, 0)


## The rival's score after as many arrows as the archer has shot, for a running tally.
func rival_so_far() -> int:
	return rival_scores.slice(0, shots.size()).reduce(func(a, b): return a + b, 0)


## Ties go to the home crowd's favourite.
func won() -> bool:
	return total() >= rival_total()
