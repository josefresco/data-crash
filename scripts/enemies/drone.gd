class_name Drone
extends Enemy
## Hovering boss drone: orbits `orbit_center()` at a fixed height, ignores
## gravity and the navmesh. Shootable (shotguns counter them, per WEAPONS.md).
## Subclasses do their job in _drone_tick().

@export var orbit_radius := 3.5
@export var orbit_height := 3.5
@export var orbit_speed := 1.2

## The boss this drone serves. The drone dies with it.
var owner_unit: Enemy

var _angle := randf() * TAU
var _tick_left := 0.0


func _init() -> void:
	max_health = 40.0
	bounty = 15
	body_radius = 0.35
	body_height = 0.5
	body_color = Color(0.85, 0.87, 0.9)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if owner_unit != null and (not is_instance_valid(owner_unit) or not owner_unit.is_alive()):
		_die()
		return
	_angle += orbit_speed * delta
	var center := orbit_center()
	var goal := center + Vector3(cos(_angle) * orbit_radius, orbit_height, sin(_angle) * orbit_radius)
	global_position = global_position.lerp(goal, 1.0 - exp(-3.0 * delta))
	_visual.rotation.y += delta * 3.0
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 0.2
		_drone_tick()


## Override: point to orbit around.
func orbit_center() -> Vector3:
	return owner_unit.global_position if is_instance_valid(owner_unit) else global_position


## Override: runs 5 times a second.
func _drone_tick() -> void:
	pass


func _build_visual() -> Node3D:
	var rig := Node3D.new()
	Models.box(rig, Vector3(0.6, 0.15, 0.6), Vector3(0.0, 0.25, 0.0), _material)
	for corner in [Vector3(0.45, 0.3, 0.45), Vector3(-0.45, 0.3, 0.45), Vector3(0.45, 0.3, -0.45), Vector3(-0.45, 0.3, -0.45)]:
		Models.cylinder(rig, 0.2, 0.03, corner, Models.mat(Color(0.2, 0.2, 0.22)), 8)
	return rig


func _play_death() -> void:
	Explosive.spawn_flash(get_parent(), global_position, 1.0, Color(0.6, 0.9, 1.0))
	queue_free()
