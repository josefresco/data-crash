class_name WaterMain
extends Node3D
## Sabotaged water main spraying into the street. Hold [F] next to it to fix it.

signal fixed(main: WaterMain)

@export var fix_time := 2.5
@export var reach := 3.0

var progress := 0.0
var is_fixed := false

var _spray: GPUParticles3D


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
	_spray = Vfx.water_spray(self, Vector3.UP * 0.8)


func label() -> String:
	return "water main"


## Called every frame the player holds [F] nearby. Returns true when done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	progress = minf(progress + delta / fix_time, 1.0)
	if progress >= 1.0:
		is_fixed = true
		_spray.emitting = false
		fixed.emit(self)
	return is_fixed
