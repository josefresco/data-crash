class_name SentryTurret
extends SecurityGuard
## Crapya's automated roof sentry: a guard's rifle on a fixed mount. Dies when
## her control room goes down.


func _init() -> void:
	max_health = 120.0
	move_speed = 0.0
	sight_range = 35.0
	attack_range = 32.0
	attack_interval = 0.5
	shot_damage = 6.0
	close_accuracy = 0.7
	far_accuracy = 0.35
	bounty = 40
	body_color = Color(0.3, 0.32, 0.36)
	body_height = 1.2


func _ready() -> void:
	super()
	add_to_group("crapya_defenses")


func shut_down() -> void:
	if is_alive():
		apply_damage(9999.0, global_position, &"emp")


func _build_visual() -> Node3D:
	var rig := Node3D.new()
	Models.cylinder(rig, 0.45, 0.5, Vector3(0.0, 0.25, 0.0), _material, 10)
	Models.box(rig, Vector3(0.6, 0.45, 0.7), Vector3(0.0, 0.75, 0.0), _material)
	Models.box(rig, Vector3(0.12, 0.12, 0.9), Vector3(0.0, 0.8, -0.7), Models.mat(Color(0.1, 0.1, 0.1)))
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1.0, 0.2, 0.1)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.2, 0.1)
	Models.box(rig, Vector3(0.3, 0.08, 0.04), Vector3(0.0, 0.9, -0.36), eye)
	return rig


func _decorate(_visual_root: Node3D) -> void:
	pass  # no helmet or rifle on a turret
