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
## Top speed in m/s (x1.4 on turbo); 0 = no limit. The bulldozer tops out slow.
@export var max_speed := 18.0
## Neighborhood trust needed before the owner hands over the keys.
@export var required_trust := 0.0
## Non-empty: locked until unlock() (a deed hands over the keys); shown as
## the prompt, e.g. "pick up all the litter".
@export var locked_hint := ""
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
@export_group("Damage")
## Crashes, gunfire, and blasts wear a car down: smoke under 40%, fire
## under 15%, then it explodes into a burnt wreck (the driver is thrown out).
@export var max_health := 500.0
## Self-damage per m/s of impact speed above `crash_damage_from`.
@export var crash_damage := 6.0
@export var crash_damage_from := 7.0
@export_group("Stability")
## Arcade handling: the fastest the car may pitch or roll (rad/s) and how fast
## those rates die out. Yaw stays free, so spinouts still happen.
@export var max_tip_rate := 1.1
@export var tip_damping := 4.0
## Upward speed cap (m/s): crashes shove cars sideways instead of launching them.
@export var max_rise_speed := 2.0
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
var health := 500.0
var wrecked := false
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _burn_left := -1.0
## Water on a burning car (hoses): enough puts the fire out.
var _doused := 0.0
var _headlight: SpotLight3D
## The imported model's bounds (zero size without a model).
var _model_bounds := AABB()
var _tail_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
## Skid marks: last mark position per wheel (for spacing), shared pool.
var _last_skid := {}
var _skid_puff_left := 0.0
## Seconds since someone last drove this car (INF: never driven).
var _since_driven := INF
static var _skid_material: StandardMaterial3D
const MAX_SKID_MARKS := 260
var _flame_left := 0.0

@onready var _cam_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var _exit_point: Marker3D = $ExitPoint


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("extinguishable")
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
	health = max_health
	_build_lights(size, box.position)
	if _model_bounds.size != Vector3.ZERO:
		_build_details(_model_bounds)
	_dress_materials()
	Models.set_gi_mode(self, GeometryInstance3D.GI_MODE_DYNAMIC)


func _use_model() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
	var model := Models.model(model_path, model_scale)
	model.position = model_offset
	add_child(model)
	_model_bounds = Models.model_bounds(model)
	if fit_to_model:
		_fit_to(_model_bounds)


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
	return not wrecked and driver == null and locked_hint.is_empty() \
		and (Game.district == null or Game.district.trust >= required_trust)


## Hands over the keys (clears `locked_hint`).
func unlock() -> void:
	locked_hint = ""


## Why [E] doesn't work right now.
func lock_text() -> String:
	if wrecked:
		return "Wrecked"
	if not locked_hint.is_empty():
		return "Locked: %s" % locked_hint
	return "Locked: the foreman wants more neighborhood trust (%d%% / %d%%)" % [
		roundi(Game.district.trust * 100.0), roundi(required_trust * 100.0)]


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
	_since_driven = 0.0 if driver else _since_driven + delta
	_burn(delta)
	if wrecked:
		engine_force = 0.0
		_last_speed = speed
		return
	_update_lights()
	if driver:
		_skid(delta, speed)

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

	# Top speed last, so the turbo can't push past it (x1.4 while boosting).
	var top := max_speed * (1.4 if boosting else 1.0)
	if max_speed > 0.0 and absf(forward_speed) > top and signf(engine_force) == signf(forward_speed):
		engine_force = 0.0

	_last_speed = speed


## Clamps and damps pitch/roll spin and caps upward speed (car-on-car
## crashes at speed used to flip and launch cars). Runs on the physics state:
## writing `angular_velocity` from `_physics_process` wiped out the yaw the
## steered wheels produce, so cars couldn't turn.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var basis := state.transform.basis
	var local := basis.inverse() * state.angular_velocity
	var keep := exp(-tip_damping * state.step)
	local.x = clampf(local.x, -max_tip_rate, max_tip_rate) * keep
	local.z = clampf(local.z, -max_tip_rate, max_tip_rate) * keep
	state.angular_velocity = basis * local
	if state.linear_velocity.y > max_rise_speed:
		state.linear_velocity.y = max_rise_speed


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


## True while driven and for a few seconds after the driver bails out.
func rams_units() -> bool:
	return driver != null or _since_driven < 4.0


## Damage from anything (bullets, blasts, fire, rams, crashes).
func apply_damage(amount: float, _from: Vector3, _kind: StringName = &"generic") -> void:
	if wrecked or amount <= 0.0:
		return
	health -= amount
	var ratio := health / max_health
	if ratio < 0.4 and _smoke == null:
		_smoke = Vfx.smoke_column(self, _hood(), 0.7)
		_smoke.emitting = true
		if driver:
			Game.tip("car_smoke", "Your car is smoking: it can't take much more. Get out before it catches fire and blows.")
	if ratio < 0.15 and _burn_left < 0.0:
		_burn_left = 4.0
		_fire = Vfx.fire_patch(self, _hood(), 0.6)
		_fire.emitting = true
		Sfx.play(&"explosion", global_position, -10.0, 1.6)
		if driver:
			Game.notify("Your car's on fire! Get out!", 3.0)


func is_burning() -> bool:
	return _burn_left >= 0.0 and not wrecked


## Hose water (seconds of fire put out). A couple of seconds of spray puts a
## burning car out and leaves it smoking at 20% health.
func douse(amount: float) -> void:
	if not is_burning():
		return
	_doused += amount
	if _doused < 2.0:
		return
	_doused = 0.0
	_burn_left = -1.0
	health = maxf(health, max_health * 0.2)
	if _fire:
		_fire.emitting = false
		_fire = null
	Sfx.play(&"hiss_loop", global_position, -6.0)
	Game.notify("Fire's out. That car's still smoking, though.", 2.5)


func _hood() -> Vector3:
	var box := get_node("CollisionShape3D") as CollisionShape3D
	var size := (box.shape as BoxShape3D).size
	return box.position + Vector3(0.0, size.y * 0.5, size.z * 0.3)


## Burning cars explode after a few seconds and stay as burnt-out wrecks.
func _burn(delta: float) -> void:
	if _burn_left < 0.0 or wrecked:
		return
	_burn_left -= delta
	if _burn_left > 0.0:
		return
	wrecked = true
	if driver:
		var victim := driver
		exit()
		victim.apply_damage(35.0, global_position, &"explosive")
		victim.apply_knockback((victim.global_position - global_position).normalized() * 8.0 + Vector3.UP * 4.0)
	var blast := Explosive.new()
	blast.radius = 5.5
	blast.damage = 60.0
	get_parent().add_child(blast)
	blast.global_position = global_position + Vector3.UP * 0.8
	blast.detonate.call_deferred()
	apply_central_impulse(Vector3.UP * mass * 1.5)
	# Char everything and douse the lights.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var burnt := StandardMaterial3D.new()
		burnt.albedo_color = Color(0.08, 0.07, 0.07)
		burnt.roughness = 1.0
		(mesh as MeshInstance3D).material_override = burnt
	if _headlight:
		_headlight.visible = false
	if _fire:
		_fire.amount_ratio = 0.4
	Game.count("cars_wrecked")


## Lenses on every car (unique materials so brake lights can flare) and a
## real headlight beam on the car being driven.
## Small parts the low-poly models lack: license plates (the rear one
## lettered), side mirrors, an antenna, an exhaust tip, rear mud flaps, and
## door handles. Merged into one mesh per material, and hidden past 70 m.
static var _plate_mat: StandardMaterial3D
static var _trim_mat: StandardMaterial3D
static var _chrome_mat: StandardMaterial3D
const PLATE_LETTERS := "ABCDEFGHJKLMNPRSTUVWXYZ"


func _build_details(bounds: AABB) -> void:
	if _plate_mat == null:
		_plate_mat = Models.mat(Color(0.93, 0.93, 0.9), &"paint")
		_trim_mat = Models.mat(Color(0.06, 0.06, 0.07), &"rough")
		_chrome_mat = Models.mat(Color(0.78, 0.79, 0.8), &"metal")
	var root := Node3D.new()
	root.name = "Details"
	add_child(root)
	var front := bounds.end.z
	var back := bounds.position.z
	var half := bounds.size.x * 0.5
	var bumper := bounds.position.y + bounds.size.y * 0.24
	# Plates.
	Models.box(root, Vector3(0.5, 0.14, 0.02), Vector3(0.0, bumper, front + 0.012), _plate_mat)
	Models.box(root, Vector3(0.5, 0.14, 0.02), Vector3(0.0, bumper + 0.08, back - 0.012), _plate_mat)
	# Side mirrors at the base of the windshield.
	var mirror_y := bounds.position.y + bounds.size.y * 0.62
	var mirror_z := bounds.get_center().z + bounds.size.z * 0.14
	for side: float in [-1.0, 1.0]:
		Models.box(root, Vector3(0.1, 0.05, 0.05), Vector3(side * (half + 0.04), mirror_y - 0.02, mirror_z), _trim_mat)
		Models.box(root, Vector3(0.05, 0.12, 0.16), Vector3(side * (half + 0.11), mirror_y, mirror_z - 0.02), _trim_mat)
		# Door handles, front and back doors.
		for dz: float in [0.1, -0.35]:
			Models.box(root, Vector3(0.02, 0.03, 0.16), Vector3(side * (half + 0.005), bounds.position.y + bounds.size.y * 0.5, bounds.get_center().z + dz * bounds.size.z * 0.5), _chrome_mat)
		# Mud flaps behind the rear wheels.
		Models.box(root, Vector3(0.18, 0.16, 0.015), Vector3(side * (half - 0.3), bounds.position.y + 0.14,
			bounds.get_center().z - 0.31 * bounds.size.z - 0.4), _trim_mat)
	# Antenna on the back of the roof, exhaust tip under the rear bumper.
	var antenna := Models.cylinder(root, 0.008, 0.6, Vector3(-half * 0.5, bounds.end.y + 0.28, back + bounds.size.z * 0.3), _trim_mat, 4)
	antenna.rotation.x = 0.25
	var pipe := Models.cylinder(root, 0.045, 0.22, Vector3(half * 0.55, bounds.position.y + 0.22, back + 0.05), _chrome_mat, 8)
	pipe.rotation.x = PI * 0.5
	Models.merge_static(root)
	for node in root.get_children():
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visibility_range_end = 70.0
	var plate := Label3D.new()
	plate.text = "%d%s%s%s %d%d%d" % [randi() % 9 + 1, PLATE_LETTERS[randi() % PLATE_LETTERS.length()],
		PLATE_LETTERS[randi() % PLATE_LETTERS.length()], PLATE_LETTERS[randi() % PLATE_LETTERS.length()],
		randi() % 10, randi() % 10, randi() % 10]
	plate.modulate = Color(0.1, 0.15, 0.4)
	plate.outline_size = 0
	plate.position = Vector3(0.0, bumper + 0.08, back - 0.025)
	plate.rotation.y = PI
	plate.visibility_range_end = 25.0
	root.add_child(plate)
	Models.fit_label(plate, Vector2(0.46, 0.11), 0.9)


func _build_lights(size: Vector3, center: Vector3) -> void:
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(1.0, 0.97, 0.85)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.95, 0.8)
	_head_mat.emission_energy_multiplier = 0.4
	_tail_mat = StandardMaterial3D.new()
	_tail_mat.albedo_color = Color(0.6, 0.05, 0.05)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.1, 0.05)
	_tail_mat.emission_energy_multiplier = 0.5
	var y := center.y + size.y * 0.1
	for side in [-1.0, 1.0]:
		var x: float = side * maxf(size.x * 0.5 - 0.35, 0.3)
		Models.box(self, Vector3(0.32, 0.14, 0.05), Vector3(x, y, center.z + size.z * 0.5 + 0.02), _head_mat)
		Models.box(self, Vector3(0.3, 0.12, 0.05), Vector3(x, y, center.z - size.z * 0.5 - 0.02), _tail_mat)
	_headlight = SpotLight3D.new()
	_headlight.position = Vector3(0.0, y, center.z + size.z * 0.5 + 0.1)
	_headlight.rotation = Vector3(deg_to_rad(-8.0), PI, 0.0)  # SpotLight shines -Z; cars face +Z
	_headlight.light_color = Color(1.0, 0.95, 0.82)
	_headlight.light_energy = 4.0
	_headlight.spot_range = 24.0
	_headlight.spot_angle = 32.0
	_headlight.light_volumetric_fog_energy = 2.5
	_headlight.shadow_enabled = false
	_headlight.visible = false
	add_child(_headlight)


func _update_lights() -> void:
	if _headlight == null:
		return
	var driven := driver != null
	_headlight.visible = driven
	_head_mat.emission_energy_multiplier = 3.0 if driven else 0.4
	var braking := brake > 0.0 or (driven and global_basis.z.dot(linear_velocity) < -0.5)
	_tail_mat.emission_energy_multiplier = 4.0 if braking else (1.2 if driven else 0.5)


## Skid marks where the tires lose grip, and tire smoke on hard slides.
func _skid(delta: float, speed: float) -> void:
	_skid_puff_left -= delta
	if speed < 4.0:
		return
	for wheel: VehicleWheel3D in find_children("*", "VehicleWheel3D", false, false):
		if not wheel.is_in_contact() or wheel.get_skidinfo() > 0.55:
			continue
		var contact := wheel.get_contact_point()
		var id := wheel.get_instance_id()
		if _last_skid.has(id) and (_last_skid[id] as Vector3).distance_to(contact) < 0.35:
			continue
		_last_skid[id] = contact
		_drop_skid(contact)
		if _skid_puff_left <= 0.0:
			_skid_puff_left = 0.12
			Vfx.dust(get_parent(), contact + Vector3.UP * 0.2, 0.8)


func _drop_skid(at: Vector3) -> void:
	if _skid_material == null:
		_skid_material = StandardMaterial3D.new()
		_skid_material.albedo_color = Color(0.05, 0.05, 0.05, 0.55)
		_skid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_skid_material.roughness = 1.0
	var mark := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.26, 0.5)
	mark.mesh = plane
	mark.material_override = _skid_material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_skid_holder().add_child(mark)
	var along := linear_velocity
	along.y = 0.0
	mark.global_position = at + Vector3.UP * 0.025
	if along.length_squared() > 0.01:
		mark.global_basis = Basis.looking_at(along.normalized(), Vector3.UP)
	var holder := mark.get_parent()
	while holder.get_child_count() > MAX_SKID_MARKS:
		var oldest := holder.get_child(0)
		holder.remove_child(oldest)
		oldest.queue_free()


## Skid marks live under one node in the level (the oldest are removed first).
func _skid_holder() -> Node3D:
	var holder := get_parent().get_node_or_null("SkidMarks") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "SkidMarks"
		get_parent().add_child(holder)
	return holder


## Skid marks on the ground right now (tests).
func skid_mark_count() -> int:
	var holder := get_parent().get_node_or_null("SkidMarks")
	return holder.get_child_count() if holder else 0


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
	var push := (along * 0.6 + away.normalized() * 0.8).normalized() * minf(speed * 0.9, 14.0) + Vector3.UP * minf(speed * 0.12, 1.5)
	unit.apply_knockback(push)
	var hostile := unit.faction == Enemy.Faction.HOSTILE and not unit.is_in_group("protesters") and not unit.is_in_group("strays")
	if hostile and speed >= ram_min_speed and rams_units():
		Sfx.play(&"car_crash", global_position, minf(-8.0 + speed, 4.0))
		unit.apply_damage(speed * ram_damage_per_mps, global_position, &"impact")
		if not unit.is_alive():
			# Ran them over: a thump through the suspension (bodies don't collide).
			apply_central_impulse(Vector3.UP * mass * 0.25)
			Game.shake(global_position, 0.25)
	if unit.is_alive() and speed >= 3.0:
		unit.knock_down(1.2 if speed >= ram_min_speed else 0.7)
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
	if body == driver:
		return
	# Hard crashes into the world or other cars wear this car down too.
	if _last_speed > crash_damage_from and (body is StaticBody3D or body is VehicleBody3D or body is CSGShape3D):
		apply_damage((_last_speed - crash_damage_from) * crash_damage, body.global_position if body is Node3D else global_position, &"impact")
		Vfx.impact(get_parent(), global_position + global_basis.z * 2.0 + Vector3.UP * 0.6, -global_basis.z, &"metal", 1.2)
	if _last_speed < ram_min_speed:
		return
	# Props always take the hit. People and vehicles only from a car the
	# player is driving (or just bailed out of): a parked car shoved by
	# traffic mustn't hurt them, or raise an alarm blamed on the player.
	if (body is Enemy or body is VehicleBody3D) and not rams_units():
		return
	Sfx.play(&"car_crash", global_position, minf(-8.0 + _last_speed, 4.0))
	if body.has_method("apply_damage"):
		body.call(&"apply_damage", _last_speed * ram_damage_per_mps, global_position, &"impact")
