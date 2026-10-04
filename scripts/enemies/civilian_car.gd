class_name CivilianCar
extends FelsaCar
## A neighbor out on an errand: an ordinary car that loops the blocks (`route`,
## lane points; the level builds them), keeps to the right, comes to a full
## stop at the stop signs (`stops`: route indices), and now and then pulls
## over at `park_spot` for a while before driving on. It hunts nobody and
## nobody hunts it (group `civilian_cars`); its bumper only nudges people.
## Wrecking one costs trust. When the defense starts, `go_home()` sends it to
## its parking spot for good, so the roads are clear for the fight.

const MODELS: Array[String] = ["sedan", "suv", "hatchback-sports", "van", "suv-luxury", "sedan-sports"]
## A full stop at a stop sign, in seconds.
const STOP_SECONDS := 1.3
## A waypoint counts as reached inside this (tighter than the van's 4 m, so
## the turns stay in the lane).
const REACH := 2.6

@export var route: Array[Vector3] = []
## Route indices that are stop lines.
@export var stops: Array[int] = []
## A curbside spot along the route (Vector3.INF: never parks), and the route
## index it comes after.
@export var park_spot := Vector3.INF
@export var park_after := 0
## Laps between errands, and how long one takes.
@export var laps_per_errand := 2
@export var errand_seconds := Vector2(14.0, 30.0)

## Parked at the curb (on an errand, or home for good).
var parked := false

var _leg := 0
var _halt_left := 0.0
var _laps := 0
var _parking := false
var _retired := false


func _init() -> void:
	super()
	faction = Faction.ALLY
	obeys_traffic = true
	thermal_runaway = false
	bullet_factor = 1.0
	motor_cue = &"engine_loop"
	max_health = 140.0
	top_speed = 9.0
	traffic_speed = 8.0
	acceleration = 4.5
	wobble = 0.0
	bounty = 0
	ram_damage_per_mps = 0.0
	body_size = Vector3(1.9, 1.5, 4.0)
	body_color = [Color(0.7, 0.15, 0.15), Color(0.2, 0.3, 0.6), Color(0.85, 0.85, 0.8), Color(0.25, 0.45, 0.3)].pick_random()
	model_path = "res://assets/kenney/cars/%s.glb" % MODELS.pick_random()
	model_scale = 1.45
	explosion_damage = 30.0


func _faction_group() -> String:
	return "civilian_cars"


func _candidates() -> Array[Node3D]:
	return []


func _pick_target() -> Node3D:
	return null


## It steers by its route, never by the navmesh (the base ally idle follows
## the player, and pathing after a player up on a roof is an engine error).
func _idle() -> void:
	pass


## Heads for the parking spot and stays there (the defense is starting).
func go_home() -> void:
	_retired = true
	if park_spot == Vector3.INF:
		parked = true


func _drive(delta: float) -> void:
	if parked or _halt_left > 0.0:
		_halt_left -= delta
		speed = move_toward(speed, 0.0, acceleration * 3.0 * delta)
		if parked and not _retired and _halt_left <= 0.0:
			parked = false  # errand done: pull out
		return
	super(delta)


func _goal_point() -> Vector3:
	if route.is_empty():
		return global_position
	if _parking:
		if _near(park_spot):
			_parking = false
			parked = true
			_halt_left = randf_range(errand_seconds.x, errand_seconds.y)
		return park_spot
	if _near(route[_leg]):
		if _leg in stops:
			_halt_left = STOP_SECONDS
		var passed := _leg
		_leg = (_leg + 1) % route.size()
		if _leg == 0:
			_laps += 1
		if park_spot != Vector3.INF and passed == park_after and (_retired or _laps >= laps_per_errand):
			_laps = 0
			_parking = true
			return park_spot
	return route[_leg]


func _near(point: Vector3) -> bool:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() < REACH


func _on_death() -> void:
	super()
	if Game.district:
		Game.district.trust -= 0.02
		Game.notify("A neighbor's car was wrecked. Trust falls.", 3.0)
