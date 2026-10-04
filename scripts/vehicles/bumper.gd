class_name Bumper
extends Area3D
## Sensor box around a vehicle that notices people and animals (the enemies
## layer). Vehicles don't collide with them physically, so a crowd can't wedge
## a car; instead the owner shoves (and maybe rams) whoever the bumper touches.
## The owner implements `_bump(unit: Enemy)`.

## Seconds before the same unit can be bumped again.
const COOLDOWN := 0.6

var _recent := {}


static func attach(host: Node3D, box_size: Vector3, center: Vector3) -> Bumper:
	var bumper := Bumper.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 32 | Knockable.LAYER  # every NPC, and knock-over props
	bumper.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = box_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	bumper.add_child(collider)
	host.add_child(bumper)
	return bumper


func _physics_process(delta: float) -> void:
	for id: int in _recent.keys():
		_recent[id] -= delta
		if _recent[id] <= 0.0:
			_recent.erase(id)
	for body in get_overlapping_bodies():
		if body is Knockable:
			_knock(body as Knockable)
			continue
		var unit := body as Enemy
		if unit == null or unit == get_parent() or not unit.is_alive() or _recent.has(unit.get_instance_id()):
			continue
		_recent[unit.get_instance_id()] = COOLDOWN
		get_parent().call(&"_bump", unit)


## A bin, a bench, a mailbox: at any real speed the vehicle sends it flying
## instead of stopping dead against it.
func _knock(prop: Knockable) -> void:
	if prop.knocked:
		return
	var host := get_parent() as Node3D
	var motion: Vector3 = (host as RigidBody3D).linear_velocity if host is RigidBody3D else (host as CharacterBody3D).velocity
	motion.y = 0.0
	var pace := motion.length()
	if pace < Knockable.MIN_SPEED:
		return
	var away := prop.global_position - host.global_position
	away.y = 0.0
	var push := (motion / pace * 0.7 + away.normalized() * 0.5).normalized()
	prop.knock(push * minf(pace * 0.9 + 2.0, 14.0) + Vector3.UP * minf(1.5 + pace * 0.15, 4.0))
