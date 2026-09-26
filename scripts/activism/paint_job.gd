class_name PaintJob
extends Node3D
## A neighbor repainting a peeling house front. Hold [F] in the ring to help;
## the grimy patches fade as the paint goes on. Local -Z faces the house wall,
## `wall_distance` meters away.

signal fixed(job: PaintJob)

@export var fix_time := 6.0
@export var reach := 3.2
@export var wall_distance := 2.3

var progress := 0.0
var is_fixed := false

var _patches: Array[MeshInstance3D] = []
var _neighbor_line: Label3D


func _ready() -> void:
	add_to_group("paint_jobs")
	var wall := Vector3(0.0, 0.0, -wall_distance)
	# Peeling, grimy patches on the facade.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 7:
		var patch := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = Vector3(rng.randf_range(0.8, 1.8), rng.randf_range(0.5, 1.2), 0.02)
		patch.mesh = quad
		var grime := StandardMaterial3D.new()
		grime.albedo_color = Color(0.42, 0.38, 0.3, 0.92)
		grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		Models.surface(grime, &"rough")
		patch.material_override = grime
		patch.position = wall + Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(0.8, 3.4), 0.05)
		add_child(patch)
		_patches.append(patch)
	# Ladder, drop cloth, paint cans, and the neighbor with a roller.
	var wood := Models.mat(Color(0.7, 0.55, 0.3))
	for x in [-0.25, 0.25]:
		var rail := Models.box(self, Vector3(0.06, 3.2, 0.06), wall + Vector3(1.8 + x, 1.5, 0.55), wood)
		rail.rotation.x = -0.18
	for k in 6:
		Models.box(self, Vector3(0.5, 0.04, 0.05), wall + Vector3(1.8, 0.3 + k * 0.5, 0.62 - k * 0.09), wood)
	Models.box(self, Vector3(3.0, 0.02, 1.6), wall + Vector3(-0.5, 0.01, 0.9), Models.mat(Color(0.9, 0.88, 0.82), &"cloth"))
	for i in 3:
		var can := Models.cylinder(self, 0.14, 0.26, wall + Vector3(-1.4 + i * 0.35, 0.13, 1.0), Models.mat(Color(0.85, 0.85, 0.88), &"metal"), 10)
		Models.cylinder(can, 0.13, 0.02, Vector3(0.0, 0.14, 0.0), Models.mat([Color(0.3, 0.55, 0.8), Color(0.95, 0.9, 0.7), Color(0.6, 0.8, 0.5)][i]), 10)
	var neighbor := CharacterModel.create("townsperson")
	neighbor.position = wall + Vector3(-1.2, 0.0, 1.2)
	neighbor.rotation.y = PI
	add_child(neighbor)
	Models.box(neighbor.anchor(&"hand_r"), Vector3(0.05, 0.05, 0.6), Vector3(0.0, 0.0, -0.3), wood)
	Models.cylinder(neighbor.anchor(&"hand_r"), 0.06, 0.25, Vector3(0.0, 0.0, -0.62), Models.mat(Color(0.3, 0.55, 0.8), &"cloth"), 8).rotation.z = PI * 0.5
	_neighbor_line = Label3D.new()
	_neighbor_line.text = "Could use a hand with this!"
	_neighbor_line.pixel_size = 0.008
	_neighbor_line.outline_size = 8
	_neighbor_line.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_neighbor_line.position = neighbor.position + Vector3.UP * 2.3
	add_child(_neighbor_line)
	# Where to stand.
	var ring := TorusMesh.new()
	ring.inner_radius = 1.3
	ring.outer_radius = 1.45
	var marker := MeshInstance3D.new()
	marker.mesh = ring
	marker.material_override = Models.glow(Color(0.5, 0.8, 1.0), 1.2)
	marker.position = Vector3(0.0, 0.05, -0.3)
	marker.name = "Ring"
	add_child(marker)


func label() -> String:
	return "house paint"


## Called every frame the player holds [F] nearby. Returns true when done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	progress = minf(progress + delta / fix_time, 1.0)
	for patch in _patches:
		(patch.material_override as StandardMaterial3D).albedo_color.a = 0.92 * (1.0 - progress)
	if progress >= 1.0:
		is_fixed = true
		for patch in _patches:
			patch.queue_free()
		_patches.clear()
		(get_node("Ring") as Node3D).visible = false
		_neighbor_line.text = "Looks brand new! Thank you!"
		fixed.emit(self)
	return is_fixed
