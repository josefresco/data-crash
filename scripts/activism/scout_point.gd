class_name ScoutPoint
extends Node3D
## Vantage point overlooking the datacenter. Stand inside the ring for
## `watch_time` seconds to scout it: every cooling unit gets a marker you can
## see through walls.

signal scouted(point: ScoutPoint)

@export var radius := 2.5
@export var watch_time := 2.0

var is_scouted := false
var watched := 0.0

var _ring_mat: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	add_to_group("scout_points")
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.15
	ring.outer_radius = radius
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.85, 0.2)
	var mesh := MeshInstance3D.new()
	mesh.mesh = ring
	mesh.material_override = _ring_mat
	mesh.position.y = 0.1
	add_child(mesh)
	_label = Label3D.new()
	_label.text = "Scout the datacenter"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.02
	_label.outline_size = 8
	_label.position.y = 2.5
	add_child(_label)


func _physics_process(delta: float) -> void:
	if is_scouted:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.is_visible_in_tree():
		return
	var offset := player.global_position - global_position
	if Vector2(offset.x, offset.z).length() > radius:
		watched = 0.0
		return
	watched += delta
	_label.text = "Scouting... %d%%" % roundi(watched / watch_time * 100.0)
	if watched >= watch_time:
		_complete()


func _complete() -> void:
	is_scouted = true
	_ring_mat.albedo_color = Color(0.3, 0.9, 0.4)
	_label.text = "Scouted"
	for node in get_tree().get_nodes_in_group("cooling_units"):
		var marker := Label3D.new()
		marker.text = "v COOLING UNIT v"
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.pixel_size = 0.012
		marker.outline_size = 10
		marker.modulate = Color(1.0, 0.35, 0.3)
		marker.position.y = 5.0
		(node as Node3D).add_child(marker)
	scouted.emit(self)
