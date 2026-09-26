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
## 0 = no limit. The bulldozer tops out slow.
@export var max_speed := 0.0
## Neighborhood trust needed before the owner hands over the keys.
@export var required_trust := 0.0
## Optional imported model (Kenney Car Kit, faces +Z like this body). When
## set, the scene's placeholder meshes are hidden and this is shown instead.
@export_file("*.glb") var model_path := ""
@export var model_scale := 1.45
@export var model_offset := Vector3.ZERO
## Meters to drop the center of mass below the scene's (keeps cars on their
## wheels in hard turns). The heavy, wide bulldozer doesn't need it.
@export var lower_center_of_mass := 0.55
## Resize the collider and move the wheels to match the model (parked cars
## pick random Kenney models of different sizes).
@export var fit_to_model := false
## Looping engine sound cue (see Sfx) while someone is driving.
@export var engine_cue := &"engine_loop"
@export_group("Turbo")
## [Shift] while driving: engine force x turbo_force for up to turbo_seconds,
## then it recharges over turbo_recharge seconds.
@export var turbo_force := 2.4
@export var turbo_seconds := 3.0
@export var turbo_recharge := 9.0

## Seconds of boost left (0..turbo_seconds).
var turbo_left := 3.0
var boosting := false

var driver: Player = null

## Speed from before this physics step, so contacts see pre-impact speed.
var _last_speed := 0.0
var _driver_change_frame := -1
var _engine: AudioStreamPlayer3D
var _tipped_time := 0.0
var _flame_left := 0.0

@onready var _cam_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var _exit_point: Marker3D = $ExitPoint


func _ready() -> void:
	add_to_group("vehicles")
	turbo_left = turbo_seconds
	# People and animals don't stop a car (the bumper shoves them instead).
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_VEHICLES | Game.LAYER_DEBRIS | Game.LAYER_DESTRUCTIBLE
	# Low center of mass and little body roll: cars stay on their wheels.
	if center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_AUTO:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = Vector3(0.0, 0.3, 0.0)
	center_of_mass.y -= lower_center_of_mass
	for wheel: VehicleWheel3D in find_children("*", "VehicleWheel3D", false, false):
		wheel.wheel_roll_influence = 0.02
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)
	_spring.add_excluded_object(get_rid())
	_cam_rig.top_level = true
	_cam_rig.global_position = global_position
	if not model_path.is_empty():
		_use_model()
	var box := (get_node("CollisionShape3D") as CollisionShape3D)
	var size := (box.shape as BoxShape3D).size
	Bumper.attach(self, size + Vector3(0.6, 0.6, 1.0), box.position)
	_dress_materials()
	Models.set_gi_mode(self, GeometryInstance3D.GI_MODE_DYNAMIC)


func _use_model() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
	var model := Models.model(model_path, model_scale)
	model.position = model_offset
	add_child(model)
	if fit_to_model:
		_fit_to(Models.model_bounds(model))


## Sizes the chassis box and places the wheels for a model's bounds
## (local AABB, origin at the ground under the model's center).
func _fit_to(bounds: AABB) -> void:
	var collider := get_node("CollisionShape3D") as CollisionShape3D
	var shape := (collider.shape as BoxShape3D).duplicate() as BoxShape3D
	shape.size = Vector3(bounds.size.x * 0.95, shape.size.y, bounds.size.z * 0.92)
	collider.shape = shape
	collider.position.z = bounds.get_center().z
	var half_track := bounds.size.x * 0.5 - 0.2
	var axle := bounds.size.z * 0.31
	for wheel: VehicleWheel3D in find_children("*", "VehicleWheel3D", false, false):
		wheel.position.x = signf(wheel.position.x) * half_track
		wheel.position.z = bounds.get_center().z + signf(wheel.position.z) * axle


## Upgrades the scene's flat materials: glossy paint on the body, glass on the
## cabin, grain on everything else.
func _dress_materials() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.get_surface_override_material(0) as StandardMaterial3D
		if material == null:
			continue
		match String(mesh.name):
			"Chassis", "Body", "ArmL", "ArmR":
				Models.surface(material, &"paint")
			"Cabin":
				Models.surface(material, &"window")
			"Blade":
				Models.surface(material, &"metal")
			_:
				Models.surface(material, &"rough")


func can_enter() -> bool:
	return driver == null and (Game.district == null or Game.district.trust >= required_trust)


func enter(player: Player) -> bool:
	if not can_enter():
		return false
	driver = player
	_driver_change_frame = Engine.get_physics_frames()
	brake = 0.0
	player.set_driving(self)
	_camera.make_current()
	if _engine == null:
		_engine = Sfx.loop(self, engine_cue, -4.0)
	elif not _engine.playing:
		_engine.play()
	Game.tip("driving", "Driving: W/S throttle and reverse, A/D steer, Space brakes, E gets out. Ram guards, dogs, and fences at speed: damage scales with how fast you hit.")
	return true


func exit() -> void:
	if driver == null:
		return
	var player := driver
	driver = null
	_driver_change_frame = Engine.get_physics_frames()
	engine_force = 0.0
	brake = max_brake
	if _engine:
		_engine.stop()
	player.set_driving(null, _exit_point.global_position)


func _physics_process(delta: float) -> void:
	_update_camera(delta)
	_stay_upright(delta)
	var speed := linear_velocity.length()
	if _engine and _engine.playing:
		_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.8 + minf(speed / 14.0, 1.6) + absf(engine_force) / max_engine_force * 0.2, 1.0 - exp(-5.0 * delta))

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
	var top := max_speed * (1.4 if Input.is_action_pressed("sprint") and turbo_left > 0.0 else 1.0)
	if max_speed > 0.0 and absf(forward_speed) > top and signf(throttle) == signf(forward_speed):
		engine_force = 0.0
	if Input.is_action_pressed("jump"):
		brake = max_brake

	# Turbo: limited boost on [Shift], with flames out the back.
	var wants_boost := Input.is_action_pressed("sprint") and throttle > 0.0 and turbo_left > 0.0
	if wants_boost and not boosting:
		Sfx.play(&"rocket", global_position, -6.0, 1.4)
		Game.tip("turbo", "Turbo! Hold Shift while driving for a short boost. The bar under your health shows what's left; it recharges on its own.")
	boosting = wants_boost
	if boosting:
		turbo_left = maxf(turbo_left - delta, 0.0)
		engine_force = max_engine_force * turbo_force
		_flame_left -= delta
		if _flame_left <= 0.0:
			_flame_left = 0.06
			Vfx.fire_puff(get_parent(), global_transform * Vector3(0.0, 0.6, -2.4), 0.35, -global_basis.z)
	else:
		turbo_left = minf(turbo_left + delta * turbo_seconds / turbo_recharge, turbo_seconds)

	_last_speed = speed


## Anti-roll torque while tilted, and a reset onto the wheels if the car
## ends up on its side or roof for a moment.
func _stay_upright(delta: float) -> void:
	var up := global_basis.y
	var tilt := up.angle_to(Vector3.UP)
	if tilt > 0.35:
		apply_torque(up.cross(Vector3.UP).normalized() * mass * 6.0 * tilt)
	if tilt > 1.1 and linear_velocity.length() < 4.0:
		_tipped_time += delta
		if _tipped_time > 1.2:
			_tipped_time = 0.0
			var forward := global_basis.z
			forward.y = 0.0
			if forward.length_squared() < 0.01:
				forward = Vector3.FORWARD
			global_transform = Transform3D(Basis.looking_at(-forward.normalized(), Vector3.UP), global_position + Vector3.UP * 1.2)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_tipped_time = 0.0


## Boost left, 0..1 (HUD).
func turbo_ratio() -> float:
	return turbo_left / maxf(turbo_seconds, 0.01)


## The bumper touched someone: hostiles get rammed, everyone gets shoved aside.
func _bump(unit: Enemy) -> void:
	var speed := linear_velocity.length()
	if speed < 1.5:
		return
	var away := unit.global_position - global_position
	away.y = 0.0
	var along := linear_velocity.normalized()
	var push := (along * 0.6 + away.normalized() * 0.8).normalized() * minf(speed * 0.9, 14.0) + Vector3.UP * minf(speed * 0.3, 4.0)
	unit.apply_knockback(push)
	var hostile := unit.faction == Enemy.Faction.HOSTILE and not unit.is_in_group("protesters") and not unit.is_in_group("strays")
	if hostile and speed >= ram_min_speed:
		Sfx.play(&"car_crash", global_position, minf(-8.0 + speed, 4.0))
		unit.apply_damage(speed * ram_damage_per_mps, global_position, &"impact")
	elif speed > 8.0 and unit.is_in_group("residents"):
		Sfx.play(&"hit_soft", unit.global_position, 0.0)
		unit.call(&"speak", ["Hey! Watch it!", "Slow down!", "Road hog!"].pick_random())


func _update_camera(delta: float) -> void:
	var weight := 1.0 - exp(-6.0 * delta)
	_cam_rig.global_position = _cam_rig.global_position.lerp(global_position + Vector3.UP * 1.2, weight)
	var forward := global_basis.z
	var target_yaw := atan2(-forward.x, -forward.z)
	_cam_rig.rotation.y = lerp_angle(_cam_rig.rotation.y, target_yaw, weight)


func _on_body_entered(body: Node) -> void:
	if _last_speed < ram_min_speed or body == driver:
		return
	Sfx.play(&"car_crash", global_position, minf(-8.0 + _last_speed, 4.0))
	if body.has_method("apply_damage"):
		body.call(&"apply_damage", _last_speed * ram_damage_per_mps, global_position, &"impact")
