class_name SurveillanceDrone
extends Drone
## Fark Suckerbush's surveillance drone: circles the player high up. While any
## of them has line of sight, the player is "tracked" and Fark hits harder
## from farther away.

var sees_player := false


func _init() -> void:
	max_health = 30.0
	body_color = Color(0.2, 0.22, 0.28)
	orbit_radius = 8.0
	orbit_height = 6.0
	orbit_speed = 0.6


func orbit_center() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.is_visible_in_tree():
		return player.global_position
	return super()


func _drone_tick() -> void:
	sees_player = false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.is_visible_in_tree():
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, player.global_position + Vector3.UP,
		LOS_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	sees_player = hit.is_empty() or hit["collider"] == player


func _decorate(visual_root: Node3D) -> void:
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1.0, 0.1, 0.1)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.1, 0.05)
	eye.emission_energy_multiplier = 3.0
	Models.ball(visual_root, 0.14, Vector3(0.0, 0.1, -0.3), eye)
