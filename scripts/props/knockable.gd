class_name Knockable
extends RigidBody3D
## A small street prop (bins, benches, mailboxes, signs, lawn clutter). It
## stands solid to people (world layer) until a vehicle's bumper, a blast, or
## a shove reaches it; then it lets go, tumbles away as debris that cars push
## aside, and shrinks out after LIFETIME. Build the visuals as children, then
## call `finish()`: the meshes merge into one, and the collider is sized from
## them. It is a frozen RigidBody, so the navmesh ignores it (units slide
## around it). Group `knockables`.

## Its own layer bit next to the world bit: vehicle bumpers look for it.
const LAYER := 128
const LIFETIME := 9.0
## Slower than this, a vehicle just nudges up against it.
const MIN_SPEED := 1.5

var knocked := false

var _fade_left := -1.0


func _init() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1 | LAYER  # Game.LAYER_WORLD (builders run as @tool: no autoload)
	collision_mask = 0
	mass = 25.0
	add_to_group("knockables")


## Call once the visuals are in: drops any static colliders the builder
## added, merges the meshes, and fits a box collider around them.
func finish(view_distance := 90.0) -> void:
	for child in get_children():
		if child is StaticBody3D:
			remove_child(child)
			child.free()
	Models.merge_static(self)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		mesh.visibility_range_end = view_distance
		var chain := Transform3D()
		var node: Node = mesh
		while node != self:
			chain = (node as Node3D).transform * chain
			node = node.get_parent()
		var box := chain * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(bounds.size.x, 0.2), maxf(bounds.size.y, 0.2), maxf(bounds.size.z, 0.2))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	add_child(collider)
	mass = clampf(shape.size.x * shape.size.y * shape.size.z * 60.0, 4.0, 60.0)


## Sends it flying with `push` (a velocity change, m/s). Safe to call from a
## physics callback: the body is released on the next idle frame.
func knock(push: Vector3) -> void:
	if knocked:
		return
	knocked = true
	_release.call_deferred(push)


func _release(push: Vector3) -> void:
	collision_layer = 8  # Game.LAYER_DEBRIS
	collision_mask = 1 | 16  # world, destructibles
	freeze = false
	Models.set_gi_mode(self, GeometryInstance3D.GI_MODE_DYNAMIC)
	apply_central_impulse(push * mass)
	apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * mass * 0.6)
	Sfx.play(&"hit_metal", global_position, -6.0, randf_range(0.8, 1.2))
	_fade_left = LIFETIME


## Blasts and rams knock it over; bullets just ping off.
func apply_damage(amount: float, from: Vector3, kind: StringName = &"generic") -> void:
	if amount < 15.0 or kind == &"bullet" or kind == &"water" or kind == &"fire":
		return
	var away := global_position - from
	away.y = 0.0
	knock(away.normalized() * clampf(amount * 0.08, 3.0, 9.0) + Vector3.UP * 3.0)


func apply_knockback(impulse: Vector3) -> void:
	knock(impulse)


func _process(delta: float) -> void:
	if _fade_left < 0.0:
		return
	_fade_left -= delta
	if _fade_left < 1.0:
		# Shrink the visuals, not the body (physics bodies don't take scaling).
		for child in get_children():
			if child is GeometryInstance3D or child is Label3D:
				(child as Node3D).scale = Vector3.ONE * maxf(_fade_left, 0.05)
	if _fade_left <= 0.0:
		queue_free()
