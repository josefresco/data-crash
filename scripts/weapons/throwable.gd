class_name Throwable
extends RigidBody3D
## Thrown object. On first contact (or after `max_flight`): a molotov leaves a
## FireZone, a rocket explodes, a rock deals light damage and lures nearby
## hostiles. Grenades bounce and explode when their `fuse` runs out.

@export var kind := &"rock"
@export var damage := 5.0
## Grenades ignore contact and go off after this long.
@export var fuse := 2.2
@export var max_flight := 4.0
## Hostiles within this distance of a rock's landing spot go to investigate.
@export var lure_radius := 10.0

var _done := false
var _trail: GPUParticles3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4 | 16 | 32  # world, vehicles, destructibles, units
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	if kind == &"rocket":
		gravity_scale = 0.0
	elif kind == &"grenade":
		var bouncy := PhysicsMaterial.new()
		bouncy.bounce = 0.35
		bouncy.friction = 0.8
		physics_material_override = bouncy

	var shape := SphereShape3D.new()
	shape.radius = 0.12
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

	var mat := StandardMaterial3D.new()
	var mesh := MeshInstance3D.new()
	if kind == &"grenade":
		var shell := SphereMesh.new()
		shell.radius = 0.1
		shell.height = 0.22
		mesh.mesh = shell
		mat.albedo_color = Color(0.25, 0.3, 0.2)
	elif kind == &"rocket":
		var body := CylinderMesh.new()
		body.top_radius = 0.07
		body.bottom_radius = 0.07
		body.height = 0.7
		mesh.mesh = body
		mesh.rotation.x = PI * 0.5  # along the flight axis
		mat.albedo_color = Color(0.35, 0.38, 0.3)
	elif kind == &"molotov":
		var bottle := CylinderMesh.new()
		bottle.top_radius = 0.05
		bottle.bottom_radius = 0.09
		bottle.height = 0.3
		mesh.mesh = bottle
		mat.albedo_color = Color(0.3, 0.55, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		mat.emission_energy_multiplier = 0.6
	else:
		var stone := SphereMesh.new()
		stone.radius = 0.12
		stone.height = 0.22
		mesh.mesh = stone
		mat.albedo_color = Color(0.45, 0.43, 0.4)
	mesh.material_override = mat
	add_child(mesh)

	if kind == &"rocket":
		_trail = Vfx.smoke_column(self, Vector3.ZERO, 0.4, false)
		(_trail.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, 0.3, 0.0)
		(_trail.process_material as ParticleProcessMaterial).initial_velocity_max = 0.5
	var lifetime := fuse if kind == &"grenade" else max_flight
	get_tree().create_timer(lifetime).timeout.connect(_impact.bind(null))


func _physics_process(_delta: float) -> void:
	if kind != &"rocket" or _done:
		return
	if linear_velocity.length_squared() > 1.0:
		look_at(global_position + linear_velocity, Vector3.UP if absf(linear_velocity.normalized().y) < 0.99 else Vector3.RIGHT)


func _on_body_entered(body: Node) -> void:
	if kind == &"grenade":
		return  # bounces; the fuse decides
	# Deferred: contact callbacks run while the physics space is locked.
	_impact.call_deferred(body)


func _impact(body: Variant) -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	var point := global_position
	if _trail:  # let the trail drift and fade instead of vanishing with the rocket
		_trail.emitting = false
		_trail.reparent(get_parent())
		get_tree().create_timer(_trail.lifetime + 0.5).timeout.connect(_trail.queue_free)
	match kind:
		&"grenade", &"rocket":
			var blast := Explosive.new()
			blast.damage = damage
			blast.radius = 5.0 if kind == &"grenade" else 4.0
			get_parent().add_child(blast)
			blast.global_position = point
			blast.detonate()
		&"molotov":
			var fire := FireZone.new()
			get_parent().add_child(fire)
			fire.global_position = _ground_below(point)
		_:
			var victim := body as Node
			if is_instance_valid(victim) and victim is Enemy:
				(victim as Enemy).apply_damage(damage, point, &"impact")
			for node in get_tree().get_nodes_in_group("hostiles"):
				var enemy := node as Enemy
				if enemy.global_position.distance_to(point) <= lure_radius:
					enemy.investigate(point)
	queue_free()


func _ground_below(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 5.0, 1 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else point
