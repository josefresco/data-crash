class_name Car
extends VehicleBody3D
## Drivable civilian car. Forward is +Z (VehicleBody3D convention).
## Ramming anything with `apply_damage` deals damage scaled by impact speed.

@export var max_engine_force := 1800.0
@export var max_brake := 25.0
@export var max_steer := 0.55
@export var steer_speed := 3.0
@export var ram_min_speed := 4.0
@export var ram_damage_per_mps := 9.0

var driver: Player = null

## Speed from before this physics step, so contacts see pre-impact speed.
var _last_speed := 0.0
var _driver_change_frame := -1

@onready var _cam_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var _exit_point: Marker3D = $ExitPoint


func _ready() -> void:
	add_to_group("vehicles")
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)
	_spring.add_excluded_object(get_rid())
	_cam_rig.top_level = true
	_cam_rig.global_position = global_position


func enter(player: Player) -> void:
	if driver:
		return
	driver = player
	_driver_change_frame = Engine.get_physics_frames()
	brake = 0.0
	player.set_driving(self)
	_camera.make_current()


func exit() -> void:
	if driver == null:
		return
	var player := driver
	driver = null
	_driver_change_frame = Engine.get_physics_frames()
	engine_force = 0.0
	brake = max_brake
	player.set_driving(null, _exit_point.global_position)


func _physics_process(delta: float) -> void:
	_update_camera(delta)
	var speed := linear_velocity.length()

	if driver == null:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, steer_speed * delta)
		_last_speed = speed
		return

	if Input.is_action_just_pressed("interact") and Engine.get_physics_frames() != _driver_change_frame:
		exit()
		_last_speed = speed
		return

	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_input := Input.get_axis("move_right", "move_left")
	steering = move_toward(steering, steer_input * max_steer, steer_speed * delta)

	var forward_speed := global_basis.z.dot(linear_velocity)
	if throttle < 0.0 and forward_speed > 1.0:
		# Pulling back while rolling forward brakes before reversing.
		engine_force = 0.0
		brake = max_brake
	else:
		engine_force = throttle * max_engine_force
		brake = 0.0
	if Input.is_action_pressed("jump"):
		brake = max_brake

	_last_speed = speed


func _update_camera(delta: float) -> void:
	var weight := 1.0 - exp(-6.0 * delta)
	_cam_rig.global_position = _cam_rig.global_position.lerp(global_position + Vector3.UP * 1.2, weight)
	var forward := global_basis.z
	var target_yaw := atan2(-forward.x, -forward.z)
	_cam_rig.rotation.y = lerp_angle(_cam_rig.rotation.y, target_yaw, weight)


func _on_body_entered(body: Node) -> void:
	if _last_speed < ram_min_speed or body == driver:
		return
	if body.has_method("apply_damage"):
		body.call(&"apply_damage", _last_speed * ram_damage_per_mps, global_position, &"impact")
