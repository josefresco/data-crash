class_name FelsaCar
extends Enemy
## Felsa Cyberdouche: unmanned "self-driving" EV that hunts people by ramming them. Steers
## erratically. An EMP hacks it into a battery fire: it stalls, burns out,
## and explodes (hurting whatever is nearby, including its friends).
## A stainless-steel wedge truck with a red sensor bar (see
## _build_cyberdouche); subclasses can swap in a Kenney model via model_path.

## Collider floats this far off the ground; visuals are raised to match.
const CLEARANCE := 0.25
## Cyberdouche side profile, (z, y) with -Z forward, for a 5.1 m x 1.9 m truck.
const WEDGE: Array[Vector2] = [
	Vector2(-2.5, 0.45), Vector2(-2.28, 0.45), Vector2(-2.12, 0.98), Vector2(-1.3, 0.98),
	Vector2(-1.14, 0.45), Vector2(0.84, 0.45), Vector2(1.0, 0.98), Vector2(1.82, 0.98),
	Vector2(1.98, 0.45), Vector2(2.55, 0.45), Vector2(2.55, 1.3), Vector2(-0.35, 1.9),
	Vector2(-2.45, 1.08), Vector2(-2.56, 0.98),
]
const WEDGE_LENGTH := 5.1
const WEDGE_HEIGHT := 1.9

@export var top_speed := 11.0
@export var acceleration := 6.0
## Radians per second of steering.
@export var turn_rate := 2.2
@export var wobble := 0.25
@export var ram_min_speed := 4.0
@export var ram_damage_per_mps := 3.0
@export var body_size := Vector3(2.0, 1.4, 4.8)
@export var explosion_radius := 5.0
@export var explosion_damage := 90.0
@export var battery_fire_dps := 25.0
## Optional Kenney Car Kit model shown instead of the Cyberdouche (faces +Z;
## this body drives toward -Z, so it's turned around).
@export_file("*.glb") var model_path := ""
@export var model_scale := 1.5

var speed := 0.0
var is_burning := false

var _reverse_left := 0.0
var _reverse_steer := 1.0
var _stuck := 0.0
var _ram_cooldowns := {}
var _wobble_phase := randf() * TAU
var _fire_light: OmniLight3D
## Game-time clock and recent reversal times, for spotting a car that is wedged.
var _clock := 0.0
var _reversals: Array[float] = []
var _motor: AudioStreamPlayer3D


func _init() -> void:
	max_health = 150.0
	sight_range = 50.0
	attack_range = 0.0
	structure_engage_range = 0.0
	waypoint_reach = 3.0  # a 4 m car can't thread 0.8 m waypoints
	bounty = 30
	body_color = Color(0.74, 0.75, 0.77)  # brushed stainless
	outfit = ""


## An EMP "hacks" the car: it stalls for good and its battery catches fire.
func stun(duration: float) -> void:
	super(duration)
	_stun_timer = INF
	_ignite()


func _candidates() -> Array[Node3D]:
	var list := super()
	for node in get_tree().get_nodes_in_group("townspeople"):
		var person := node as Townsperson
		if person and not person.is_captured():
			list.append(person)
	return list


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_clock += delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	for id: int in _ram_cooldowns.keys():
		_ram_cooldowns[id] -= delta
		if _ram_cooldowns[id] <= 0.0:
			_ram_cooldowns.erase(id)

	if is_burning:
		health -= battery_fire_dps * delta
		if health <= 0.0:
			_die()
			return

	if _stun_timer > 0.0:
		_stun_timer -= delta
		speed = move_toward(speed, 0.0, 12.0 * delta)
	else:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer = THINK_INTERVAL
			_think()
		_drive(delta)

	var forward := -global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	move_and_slide()
	_handle_collisions()

	if global_position.y < -30.0:
		_die()


func _drive(delta: float) -> void:
	if _reverse_left > 0.0:
		_reverse_left -= delta
		speed = move_toward(speed, -5.0, acceleration * 2.0 * delta)
		rotation.y += _reverse_steer * turn_rate * 0.6 * delta
		return

	var to_goal := _goal_point() - global_position
	to_goal.y = 0.0
	# Only brake at the end of the route. Stopping short of an intermediate
	# waypoint deadlocks: the agent never advances past it.
	var at_end := not (_is_valid(target) and _has_los) and _nav.is_navigation_finished()
	if to_goal.length() < 1.5 and at_end:
		speed = move_toward(speed, 0.0, acceleration * delta)
		return
	var sway := sin(Time.get_ticks_msec() / 1000.0 * 1.7 + _wobble_phase) * wobble
	var desired := atan2(-to_goal.x, -to_goal.z) + sway
	var diff := wrapf(desired - rotation.y, -PI, PI)
	rotation.y += clampf(diff, -turn_rate * delta, turn_rate * delta)
	# Brake into sharp turns so it doesn't orbit its target forever.
	var target_speed := top_speed * clampf(1.0 - absf(diff) / PI * 1.2, 0.3, 1.0)
	speed = move_toward(speed, target_speed, acceleration * delta)

	var real := get_real_velocity()
	if speed > 3.0 and Vector2(real.x, real.z).length() < 1.0:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck > 0.8:
		_begin_reverse()


func _goal_point() -> Vector3:
	if _is_valid(target) and _has_los:
		return target.global_position  # ram straight at it
	if not _nav.is_navigation_finished():
		return _nav.get_next_path_position()
	return global_position


func _handle_collisions() -> void:
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		if contact.get_normal().y > 0.7:
			continue  # the floor
		var hit := contact.get_collider() as Node
		if hit == null or absf(speed) < ram_min_speed:
			continue
		var id := hit.get_instance_id()
		if _ram_cooldowns.has(id):
			continue
		_ram_cooldowns[id] = 1.0
		if site_security and not Game.alarm:
			_begin_reverse()  # off duty: bump and back off, no ram damage
			continue
		Sfx.play(&"car_crash", global_position, -4.0)
		if not _is_friend(hit) and hit.has_method("apply_damage"):
			hit.call(&"apply_damage", absf(speed) * ram_damage_per_mps, global_position, &"impact")
			if hit.has_method("apply_knockback"):
				var push := -global_basis.z * signf(speed) * absf(speed) * 0.8 + Vector3.UP * 3.0
				hit.call(&"apply_knockback", push)
		_begin_reverse()


func _begin_reverse() -> void:
	_stuck = 0.0
	_reverse_left = randf_range(0.6, 1.1)
	_reverse_steer = 1.0 if randf() < 0.5 else -1.0
	# Wedged (e.g. a fence corner the navmesh thinks it can round): after
	# four reversals in 20s the battery goes into thermal runaway.
	if site_security and not Game.alarm:
		return  # off duty: no thermal runaway from idle bumping
	_reversals.append(_clock)
	_reversals = _reversals.filter(func(t: float) -> bool: return _clock - t < 20.0)
	if _reversals.size() >= 4 and not is_burning:
		_ignite()


func _ignite() -> void:
	if is_burning:
		return
	is_burning = true
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.45, 0.1)
	_fire_light.light_energy = 3.0
	_fire_light.omni_range = 6.0
	_fire_light.position.y = body_size.y + 0.5
	add_child(_fire_light)
	Vfx.fire_patch(self, Vector3.UP * (body_size.y * 0.8), 0.6)
	Vfx.smoke_column(self, Vector3.UP * (body_size.y + 0.6), 1.2)
	Sfx.play(&"emp", global_position, -2.0)
	Sfx.loop(self, &"fire_loop", -6.0)
	Game.tip("battery_fire", "Battery fire! A hacked Cyberdouche burns out and explodes. Keep your distance, and lure its friends close.")


func _on_death() -> void:
	_explode.call_deferred(global_position + Vector3.UP * 0.8)


func _explode(at: Vector3) -> void:
	var blast := Explosive.new()
	blast.radius = explosion_radius
	blast.damage = explosion_damage
	get_parent().add_child(blast)
	blast.global_position = at
	blast.detonate()


func _play_death() -> void:
	_material.albedo_color = Color(0.12, 0.12, 0.12)
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(_visual, "position:y", -2.0, 1.0)
	tween.tween_callback(queue_free)


func _build_body() -> void:
	var shape := BoxShape3D.new()
	shape.size = body_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = body_size.y * 0.5 + CLEARANCE
	add_child(collider)

	# The collider floats CLEARANCE above the ground, so the body origin sits
	# that far below it: lift the visuals back up or the wheels sink in.
	_visual = Node3D.new()
	_visual.position.y = CLEARANCE
	add_child(_visual)
	if not model_path.is_empty():
		_build_model()
	else:
		_build_cyberdouche()
	_decorate(_visual)
	Models.set_gi_mode(_visual, GeometryInstance3D.GI_MODE_DYNAMIC)
	_motor = Sfx.loop(self, &"ev_loop", -10.0)


func _process(delta: float) -> void:
	super(delta)
	if _motor:
		_motor.pitch_scale = 0.6 + absf(speed) / maxf(top_speed, 1.0) * 0.9


## Brushed stainless wedge: extruded side profile, dark glass band, raked
## windshield, red sensor light bars front and back, chunky wheels. Sized from
## body_size (the collider), origin at the ground.
func _build_cyberdouche() -> void:
	var length := body_size.z * 1.06
	var width := body_size.x
	var height := body_size.y + CLEARANCE + 0.25
	var sz := length / WEDGE_LENGTH
	var sy := height / WEDGE_HEIGHT
	var profile := PackedVector2Array()
	for p in WEDGE:
		profile.append(Vector2(p.x * sz, p.y * sy))
	# Its own material: hit flashes and burn-out darkening only touch this truck.
	_material = StandardMaterial3D.new()
	Models.surface(_material, &"paint")
	_material.albedo_color = _base_color()
	_material.metallic = 0.9
	_material.roughness = 0.26
	_material.anisotropy_enabled = true  # brushed steel streaks
	_material.anisotropy = 0.6
	var shell := Models.extrude(_visual, profile, width, _material)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var glass := Models.window()
	var side := PackedVector2Array([Vector2(-1.42, 1.42), Vector2(-0.45, 1.82), Vector2(1.05, 1.56), Vector2(1.05, 1.36)])
	var windshield := PackedVector2Array([Vector2(-2.22, 1.19), Vector2(-0.52, 1.905), Vector2(-0.4, 1.905), Vector2(-2.14, 1.16)])
	for points: PackedVector2Array in [side, windshield]:
		var scaled := PackedVector2Array()
		for p in points:
			scaled.append(Vector2(p.x * sz, p.y * sy + (0.012 if points == windshield else 0.0)))
		Models.extrude(_visual, scaled, width + (0.03 if points == side else -0.2), glass)
	# Full-width light bars: red "sensor" bar up front, tail bar in back.
	var red := Models.glow(Color(1.0, 0.08, 0.05), 3.5)
	Models.box(_visual, Vector3(width * 0.98, 0.1, 0.06), Vector3(0.0, 1.03 * sy, -2.5 * sz), red)
	Models.box(_visual, Vector3(width * 0.98, 0.1, 0.06), Vector3(0.0, 1.22 * sy, 2.57 * sz), Models.glow(Color(0.9, 0.05, 0.05), 2.0))
	# Wheels with flat aero hubcaps.
	var tire := Models.mat(Color(0.06, 0.06, 0.07), &"rough")
	var hub := Models.mat(Color(0.3, 0.31, 0.33), &"metal")
	var radius := 0.44 * sy
	for z in [-1.71, 1.41]:
		for x in [-1.0, 1.0]:
			var wheel := Models.cylinder(_visual, radius, 0.38, Vector3(x * (width * 0.5 - 0.17), radius, z * sz), tire, 16)
			wheel.rotation.z = PI * 0.5
			var cap := Models.cylinder(_visual, radius * 0.7, 0.02, Vector3(x * (width * 0.5 + 0.03), radius, z * sz), hub, 6)
			cap.rotation.z = PI * 0.5
	# Roof sensor pod (it's "self-driving").
	Models.box(_visual, Vector3(0.5, 0.12, 0.3), Vector3(0.0, 1.9 * sy + 0.05, -0.3 * sz), Models.mat(Color(0.12, 0.12, 0.14), &"metal"))
	Models.box(_visual, Vector3(0.3, 0.03, 0.05), Vector3(0.0, 1.9 * sy + 0.12, -0.46 * sz), red)


## Kenney car body with its own copy of the palette material, so flashes and
## burn-out darkening only affect this car. Keeps the red sensor bar.
func _build_model() -> void:
	var car := Models.model(model_path, model_scale)
	car.rotation.y = PI
	_visual.add_child(car)
	for mesh: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if _material == null:
			_material = (mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			_material.metallic = 0.3
			_material.roughness = 0.35
		mesh.material_override = _material
	_material.albedo_color = _base_color()
	var bounds := Models.model_bounds(car)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.1, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.1, 0.05)
	glow.emission_energy_multiplier = 2.5
	_add_box(_visual, Vector3(bounds.size.x * 0.7, 0.08, 0.05),
		Vector3(0.0, bounds.size.y * 0.55, bounds.position.z - 0.03), glow)


func _base_color() -> Color:
	# Models carry their own paint in the palette texture.
	return Color.WHITE if not model_path.is_empty() else body_color
