class_name SecurityGuard
extends Enemy
## Private Security: rifle hitscan, accuracy drops with distance.

const SHOT_MASK := 1 | 2 | 16 | 32  # world, player, destructibles, units

@export var shot_damage := 6.0
@export var close_accuracy := 0.8
@export var far_accuracy := 0.3


func _init() -> void:
	max_health = 60.0
	move_speed = 3.8
	sight_range = 25.0
	attack_range = 16.0
	attack_interval = 0.7
	bounty = 25
	body_color = Color(0.16, 0.17, 0.22)


func _decorate(visual_root: Node3D) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.06)
	_add_box(visual_root, Vector3(0.5, 0.18, 0.5), Vector3(0, body_height - 0.05, 0), dark)  # helmet
	_add_box(visual_root, Vector3(0.1, 0.1, 0.8), Vector3(0.3, body_height * 0.6, -0.35), dark)  # rifle


func _attack(victim: Node3D) -> void:
	var from := global_position + Vector3.UP * body_height * 0.75
	var aim := _aim_point_of(victim)
	var accuracy := lerpf(close_accuracy, far_accuracy, clampf(_distance_to(victim) / sight_range, 0.0, 1.0))
	if randf() > accuracy:
		aim += Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 0.9), randf_range(-1.5, 1.5))

	var direction := (aim - from).normalized()
	var to := from + direction * (sight_range + 5.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, SHOT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = hit["position"]
		var struck := hit["collider"] as Node
		if struck and struck.has_method("apply_damage") and not _is_friend(struck):
			struck.call(&"apply_damage", shot_damage, from, &"bullet")
	Fx.tracer(get_parent(), from, to, Color(1.0, 0.85, 0.5))


func _add_box(parent: Node3D, box_size: Vector3, at: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = box_size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
