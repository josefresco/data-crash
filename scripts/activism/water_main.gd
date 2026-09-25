class_name WaterMain
extends Node3D
## Sabotaged water main spraying into the street. Hold [F] next to it to fix it.

signal fixed(main: WaterMain)

@export var fix_time := 2.5
@export var reach := 3.0

var progress := 0.0
var is_fixed := false

var _spray_left := 0.0


func _ready() -> void:
	add_to_group("fixables")
	var pipe := BoxMesh.new()
	pipe.size = Vector3(0.5, 0.5, 2.5)
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.35, 0.38, 0.42)
	var mesh := MeshInstance3D.new()
	mesh.mesh = pipe
	mesh.material_override = pipe_mat
	mesh.position.y = 0.25
	add_child(mesh)
	var valve := BoxMesh.new()
	valve.size = Vector3(0.8, 0.8, 0.8)
	var valve_mesh := MeshInstance3D.new()
	valve_mesh.mesh = valve
	valve_mesh.material_override = pipe_mat
	valve_mesh.position.y = 0.4
	add_child(valve_mesh)


func label() -> String:
	return "water main"


## Called every frame the player holds [F] nearby. Returns true when done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	progress = minf(progress + delta / fix_time, 1.0)
	if progress >= 1.0:
		is_fixed = true
		fixed.emit(self)
	return is_fixed


func _process(delta: float) -> void:
	if is_fixed:
		return
	_spray_left -= delta
	if _spray_left > 0.0:
		return
	_spray_left = 0.08
	# Leak: blue-white puffs shooting up and falling off.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.85, 1.0, 0.8)
	var drop := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.2
	drop.mesh = box
	drop.material_override = mat
	add_child(drop)
	drop.position = Vector3(0.0, 0.8, 0.0)
	var peak := Vector3(randf_range(-0.8, 0.8), randf_range(2.5, 3.5), randf_range(-0.8, 0.8))
	var tween := drop.create_tween()
	tween.tween_property(drop, "position", peak, 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(drop, "position", Vector3(peak.x * 1.8, 0.0, peak.z * 1.8), 0.35).set_ease(Tween.EASE_IN)
	tween.tween_callback(drop.queue_free)
