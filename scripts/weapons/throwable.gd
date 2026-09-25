class_name Throwable
extends RigidBody3D
## Thrown object. On first contact (or after `max_flight`), a molotov leaves a
## FireZone on the ground; a rock deals light damage and lures nearby hostiles.

@export var kind := &"rock"
@export var damage := 5.0
@export var max_flight := 4.0
## Hostiles within this distance of a rock's landing spot go to investigate.
@export var lure_radius := 10.0

var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4 | 16 | 32  # world, vehicles, destructibles, units
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	body_entered.connect(_on_body_entered)

	var shape := SphereShape3D.new()
	shape.radius = 0.12
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

	var mat := StandardMaterial3D.new()
	var mesh := MeshInstance3D.new()
	if kind == &"molotov":
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

	get_tree().create_timer(max_flight).timeout.connect(_impact.bind(null))


func _on_body_entered(body: Node) -> void:
	_impact(body)


func _impact(body: Variant) -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	var point := global_position
	match kind:
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
