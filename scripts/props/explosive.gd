class_name Explosive
extends Node3D
## Planted charge (C4 / satchel). Counts down, then damages everything with
## `apply_damage` in a radius and pushes rigid bodies away.

signal detonated(position: Vector3)

@export var fuse_time := 4.0
@export var radius := 6.0
@export var damage := 220.0
## Velocity change (m/s) given to rigid bodies at the center of the blast.
@export var push_speed := 14.0

var _time_left := 0.0
var _armed := false
var _light: OmniLight3D


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.2, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.22, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.1, 0.05)
	mat.emission_energy_multiplier = 0.5
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	add_child(mesh)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.1)
	_light.omni_range = 2.5
	_light.light_energy = 0.0
	add_child(_light)


func arm() -> void:
	_armed = true
	_time_left = fuse_time


func _process(delta: float) -> void:
	if not _armed:
		return
	_time_left -= delta
	# Blink faster as the fuse runs down.
	var rate := lerpf(2.0, 12.0, 1.0 - _time_left / fuse_time)
	var phase := fmod(Time.get_ticks_msec() / 1000.0 * rate, 1.0)
	_light.light_energy = 3.0 if phase < 0.5 else 0.0
	if _time_left <= 0.0:
		detonate()


func detonate() -> void:
	if not is_inside_tree():
		return
	_armed = false
	var origin := global_position

	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), origin)
	query.collision_mask = 1 | 2 | 4 | 8 | 16 | 32
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 128)

	var seen := {}
	for hit: Dictionary in hits:
		var body := hit.get("collider") as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true

		var distance: float
		if body is Destructible:
			distance = (body as Destructible).distance_to_point(origin)
		else:
			distance = origin.distance_to(body.global_position)
		var falloff := clampf(1.0 - distance / radius, 0.0, 1.0)
		if falloff <= 0.0:
			continue

		if body.has_method("apply_damage"):
			body.call(&"apply_damage", damage * falloff, origin, &"explosive")
		if body is RigidBody3D:
			var rigid := body as RigidBody3D
			var direction := (rigid.global_position - origin + Vector3.UP * 0.5).normalized()
			rigid.apply_central_impulse(direction * push_speed * falloff * rigid.mass)

	spawn_flash(get_tree().current_scene, origin, radius * 0.6)
	detonated.emit(origin)
	queue_free()


## Expanding fireball plus light. Static so other scripts (bosses, rockets) can reuse it.
static func spawn_flash(parent: Node, at: Vector3, size: float,
		color := Color(1.0, 0.6, 0.15)) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.9)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var flash := MeshInstance3D.new()
	flash.mesh = sphere
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(flash)
	flash.global_position = at
	flash.scale = Vector3.ONE * 0.3

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 12.0
	light.omni_range = size * 4.0
	parent.add_child(light)
	light.global_position = at

	var tween := flash.create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * size, 0.35) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_property(light, "light_energy", 0.0, 0.5)
	tween.chain().tween_callback(light.queue_free)
	tween.chain().tween_callback(flash.queue_free)
