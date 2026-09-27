class_name CameraFx
extends Node
## Works on whichever camera is current (on foot or in a car):
## - FOV kick while sprinting or on turbo
## - shake from nearby explosions (Game.shake -> group "camera_fx")
## - dust motes drifting around the player, fewer as the smog clears

const SPRINT_KICK := 7.0
const TURBO_KICK := 14.0
## FOV narrowing while the player holds aim.
const AIM_ZOOM := -22.0

var _player: Player
var _camera: Camera3D
var _base_fov := 75.0
var _kick := 0.0
var _trauma := 0.0
var _time := 0.0
var _motes: GPUParticles3D


func _ready() -> void:
	add_to_group(&"camera_fx")


## Adds shake from a blast of `strength` at `at` (falls off over ~40 m).
func shake(at: Vector3, strength: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var falloff := clampf(1.0 - camera.global_position.distance_to(at) / 40.0, 0.0, 1.0)
	_trauma = minf(_trauma + strength * falloff * falloff, 1.0)


## Current shake amount 0..1 (tests).
func trauma() -> float:
	return _trauma


func _process(delta: float) -> void:
	_time += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var camera := get_viewport().get_camera_3d()
	if camera != _camera:
		if is_instance_valid(_camera):
			_camera.fov = _base_fov
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0
		_camera = camera
		if _camera == null:
			return
		_base_fov = _camera.fov
	var target := 0.0
	var sprinting := Input.is_action_pressed("sprint")
	if _player.vehicle != null:
		if sprinting and _player.vehicle.turbo_left > 0.0 and _player.vehicle.linear_velocity.length() > 4.0:
			target = TURBO_KICK
	elif _player.aiming:
		target = AIM_ZOOM
	elif sprinting and Vector2(_player.velocity.x, _player.velocity.z).length() > _player.walk_speed + 0.5:
		target = SPRINT_KICK
	_kick = move_toward(_kick, target, delta * 90.0)
	_camera.fov = _base_fov + _kick
	_trauma = maxf(_trauma - delta * 1.4, 0.0)
	var amount := _trauma * _trauma * 0.35
	_camera.h_offset = amount * sin(_time * 53.0)
	_camera.v_offset = amount * sin(_time * 41.0 + 1.3)
	_update_motes()


func _update_motes() -> void:
	if _motes == null:
		_motes = _build_motes()
		_player.get_parent().add_child(_motes)
	_motes.global_position = _player.global_position + Vector3.UP * 1.5
	var smog := Game.district.smog if Game.district else 0.5
	_motes.amount_ratio = clampf(0.2 + smog, 0.0, 1.0)


func _build_motes() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "DustMotes"
	particles.amount = 90
	particles.lifetime = 6.0
	particles.preprocess = 6.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-14, -6, -14), Vector3(28, 12, 28))
	particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(12, 4, 12)
	process.gravity = Vector3(0.15, -0.02, 0.05)
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.15
	process.direction = Vector3(1, 0.2, 0)
	process.spread = 180.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.scale_min = 0.5
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.92, 0.75, 0.45)
	mesh.material = mat
	particles.draw_pass_1 = mesh
	return particles
