class_name Fx
extends RefCounted
## Small reusable visual effects. Static only; never instantiated.


## Brief bright line for a hitscan shot.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color,
		width := 0.04, lifetime := 0.07) -> void:
	var length := from.distance_to(to)
	if length < 0.05 or parent == null:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(line)
	line.global_position = (from + to) * 0.5
	var direction := (to - from) / length
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	line.look_at(to, up)
	var tween := line.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_callback(line.queue_free)


## Short-lived rising fireball chunk (flamethrowers, burning puddles, wrecks).
static func flame_puff(parent: Node, at: Vector3, size := 0.6, lifetime := 0.45) -> void:
	if parent == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, randf_range(0.35, 0.65), 0.1, 0.85)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var puff := MeshInstance3D.new()
	puff.mesh = box
	puff.material_override = mat
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(puff)
	puff.global_position = at
	puff.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "global_position", at + Vector3.UP * 1.2, lifetime)
	tween.tween_property(puff, "scale", Vector3.ONE * 0.2, lifetime)
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.chain().tween_callback(puff.queue_free)
