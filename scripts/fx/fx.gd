class_name Fx
extends RefCounted
## Small reusable visual effects. Static only; never instantiated.


## A hitscan shot: a glowing streak that flies from `from` to `to` at bullet
## speed (crossed quads with the trace texture), over a faint line that marks
## the whole path for a moment.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color,
		width := 0.04, lifetime := 0.07) -> void:
	var length := from.distance_to(to)
	if length < 0.05 or parent == null:
		return
	var direction := (to - from) / length
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	# The faint full-length line.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width * 0.5, width * 0.5, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.35)
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(line)
	line.global_position = (from + to) * 0.5
	line.look_at(to, up)
	var fade := line.create_tween()
	fade.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	fade.tween_callback(line.queue_free)
	# The streak.
	var streak_length := minf(length, 5.0)
	var streak := Node3D.new()
	parent.add_child(streak)
	streak.global_position = from
	streak.look_at(to, up)
	var glow := _streak_material(color)
	for k in 2:
		var spin := Node3D.new()
		spin.rotation.z = k * PI * 0.5
		streak.add_child(spin)
		var quad := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(width * 5.0, streak_length)
		quad.mesh = q
		quad.material_override = glow
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		quad.rotation.x = -PI * 0.5
		quad.position = Vector3(0.0, 0.0, -streak_length * 0.5)
		spin.add_child(quad)
	var travel := maxf(length - streak_length, 0.0)
	var flight := streak.create_tween()
	flight.tween_property(streak, "global_position", from + direction * travel, maxf(travel / 320.0, 0.03))
	flight.tween_callback(streak.queue_free)


static var _streak_mats := {}


static func _streak_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _streak_mats.has(key):
		return _streak_mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/kenney/particles/trace_01_alpha.png")
	mat.albedo_color = Color(color.r * 2.5, color.g * 2.2, color.b * 1.6)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_streak_mats[key] = mat
	return mat


## Short-lived flame burst (flamethrowers). Particles via Vfx.fire_puff.
static func flame_puff(parent: Node, at: Vector3, size := 0.6, _lifetime := 0.45) -> void:
	Vfx.fire_puff(parent, at, size)
