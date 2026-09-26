class_name SecurityGuard
extends Enemy
## Private Security: rifle hitscan, accuracy drops with distance.

const SHOT_MASK := 1 | 2 | 16 | 32  # world, player, destructibles, units

@export var shot_damage := 8.0
@export var close_accuracy := 0.8
@export var far_accuracy := 0.3


func _init() -> void:
	outfit = "guard"
	max_health = 60.0
	move_speed = 3.8
	sight_range = 25.0
	attack_range = 16.0
	attack_interval = 0.7
	bounty = 20
	body_color = Color(0.16, 0.17, 0.22)


func _decorate(_visual_root: Node3D) -> void:
	var dark := _solid(Color(0.06, 0.06, 0.07))
	var top := _head_top()
	Models.hat(_anchor(&"head"), &"cap", Color(0.08, 0.08, 0.09), top, body_height / 1.8)
	_add_box(_anchor(&"chest"), Vector3(0.48, 0.42, 0.36), Vector3(0.0, -0.06, 0.0), dark)  # vest
	_add_box(_anchor(&"hand_r"), Vector3(0.08, 0.1, 0.75), Vector3(0.0, -0.04, -0.28), dark)  # rifle


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
	Vfx.muzzle(get_parent(), from + direction * 0.5)
	Sfx.play(&"guard_gun", from, -6.0)
	if not hit.is_empty():
		to = hit["position"]
		var struck := hit["collider"] as Node
		if not struck is Enemy and not struck is Player:
			Vfx.impact(get_parent(), to, hit["normal"])
		if struck and struck.has_method("apply_damage") and not _is_friend(struck):
			struck.call(&"apply_damage", shot_damage, from, &"bullet")
	Fx.tracer(get_parent(), from, to, Color(1.0, 0.85, 0.5))

