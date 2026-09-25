@tool
class_name Datacenter
extends Node3D
## A corporate "bad" datacenter: a destructible shell plus external cooling units.
## Destroying every cooling unit collapses the building and heals the district.

signal cooling_unit_destroyed(remaining: int)
signal neutralized

@export var footprint := Vector2(24.0, 16.0)
@export var height := 8.0
## Width of each destructible wall / roof segment.
@export var segment_size := 4.0
@export var cooling_unit_count := 3
@export var wall_color := Color(0.28, 0.29, 0.31)
@export var roof_color := Color(0.2, 0.2, 0.22)
@export var cooling_color := Color(0.62, 0.68, 0.72)

@export_group("District impact")
@export var smog_contribution := 0.85
@export var noise_contribution := 0.85
@export var water_restored := 0.6
@export var trust_gain := 0.3
@export var cash_reward := 500

var cooling_remaining := 0
var is_neutralized := false

var _structure: Array[Destructible] = []
var _roof: Array[Destructible] = []
var _fans: Array[Node3D] = []


func _ready() -> void:
	_build_shell()
	_build_cooling_units()


func _process(delta: float) -> void:
	for fan in _fans:
		if is_instance_valid(fan):
			fan.rotate_y(delta * 12.0)


func _build_shell() -> void:
	var half := footprint * 0.5
	var wall := 0.4
	# Front/back walls run along X, side walls along Z.
	_add_wall_run(Vector3(-half.x, 0.0, half.y), Vector3.RIGHT, footprint.x, wall)
	_add_wall_run(Vector3(-half.x, 0.0, -half.y), Vector3.RIGHT, footprint.x, wall)
	_add_wall_run(Vector3(-half.x, 0.0, -half.y + wall), Vector3.BACK, footprint.y - wall * 2.0, wall)
	_add_wall_run(Vector3(half.x, 0.0, -half.y + wall), Vector3.BACK, footprint.y - wall * 2.0, wall)

	var nx := maxi(int(round(footprint.x / segment_size)), 1)
	var nz := maxi(int(round(footprint.y / segment_size)), 1)
	var roof_size := Vector3(footprint.x / nx, 0.4, footprint.y / nz)
	for ix in nx:
		for iz in nz:
			var piece := _make_segment(roof_size, roof_color, Vector3i(2, 1, 2))
			piece.position = Vector3(
				-half.x + (ix + 0.5) * roof_size.x, height, -half.y + (iz + 0.5) * roof_size.z)
			_roof.append(piece)


func _add_wall_run(start: Vector3, direction: Vector3, run_length: float, thickness: float) -> void:
	var count := maxi(int(round(run_length / segment_size)), 1)
	var width := run_length / count
	for i in count:
		var along := direction.x != 0.0
		var seg_size := Vector3(width, height, thickness) if along else Vector3(thickness, height, width)
		var piece := _make_segment(seg_size, wall_color, Vector3i(3, 3, 1) if along else Vector3i(1, 3, 3))
		var offset := direction * ((i + 0.5) * width)
		# Keep walls inside the footprint edge.
		var inset := Vector3(0.0, 0.0, -thickness * 0.5 * signf(start.z)) if along \
			else Vector3(-thickness * 0.5 * signf(start.x), 0.0, 0.0)
		piece.position = start + offset + inset
		_structure.append(piece)


func _make_segment(seg_size: Vector3, seg_color: Color, seg_chunks: Vector3i) -> Destructible:
	var piece := Destructible.new()
	piece.set_meta(&"generated", true)
	piece.size = seg_size
	piece.color = seg_color
	piece.chunks = seg_chunks
	piece.max_health = 250.0
	piece.damage_threshold = 50.0
	piece.density = 150.0
	piece.label = "Datacenter wall"
	add_child(piece)
	return piece


func _build_cooling_units() -> void:
	var unit_size := Vector3(3.0, 3.0, 3.0)
	var spacing := footprint.y / maxi(cooling_unit_count, 1)
	for i in cooling_unit_count:
		var unit := Destructible.new()
		unit.set_meta(&"generated", true)
		unit.name = "CoolingUnit%d" % i
		unit.size = unit_size
		unit.color = cooling_color
		unit.chunks = Vector3i(3, 3, 3)
		unit.max_health = 150.0
		unit.damage_threshold = 50.0
		unit.label = "Cooling unit"
		unit.position = Vector3(
			footprint.x * 0.5 + unit_size.x * 0.5 + 1.5, 0.0, -footprint.y * 0.5 + (i + 0.5) * spacing)
		add_child(unit)
		unit.add_to_group("cooling_units")
		_add_fan(unit, unit_size)
		if not Engine.is_editor_hint():
			unit.destroyed.connect(_on_cooling_unit_destroyed)
	cooling_remaining = cooling_unit_count


func _add_fan(unit: Destructible, unit_size: Vector3) -> void:
	var blade := BoxMesh.new()
	blade.size = Vector3(2.4, 0.08, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	var fan := Node3D.new()
	fan.position.y = unit_size.y + 0.1
	for i in 2:
		var mesh := MeshInstance3D.new()
		mesh.mesh = blade
		mesh.material_override = mat
		mesh.rotation.y = i * PI * 0.5
		fan.add_child(mesh)
	unit.add_child(fan)
	_fans.append(fan)


func _on_cooling_unit_destroyed(unit: Destructible) -> void:
	cooling_remaining -= 1
	var district := Game.district
	if district and cooling_unit_count > 0:
		# Each unit knocked out quiets the hum a little before the full collapse.
		district.noise -= noise_contribution * 0.5 / cooling_unit_count
	cooling_unit_destroyed.emit(cooling_remaining)
	if cooling_remaining <= 0:
		_collapse(unit.global_position)


func _collapse(origin: Vector3) -> void:
	if is_neutralized:
		return
	is_neutralized = true

	# Roof drops first, then the walls fold in from the side that was hit.
	var delay := 0.3
	for piece in _roof:
		get_tree().create_timer(delay).timeout.connect(_shatter_piece.bind(piece, origin, 60.0))
	# Some segments may already be gone (blasted earlier), so skip freed ones.
	var walls := _structure.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	walls.sort_custom(func(a: Destructible, b: Destructible) -> bool:
		return a.global_position.distance_to(origin) < b.global_position.distance_to(origin))
	for piece: Destructible in walls:
		delay += 0.12
		get_tree().create_timer(delay).timeout.connect(_shatter_piece.bind(piece, origin, 120.0))

	get_tree().create_timer(delay + 0.5).timeout.connect(_heal_district)


## `piece` is untyped: it may already be freed by the time the timer fires.
func _shatter_piece(piece: Variant, origin: Vector3, force: float) -> void:
	if is_instance_valid(piece) and not (piece as Destructible).is_destroyed:
		# Pull debris inward so the building caves in rather than exploding outward.
		var center := global_position + Vector3.UP * height
		(piece as Destructible).shatter(center.lerp(origin, 0.3), force)


func _heal_district() -> void:
	var district := Game.district
	if district:
		district.smog -= smog_contribution
		district.noise -= noise_contribution * 0.5
		district.water_table += water_restored
		district.trust += trust_gain
	Game.add_cash(cash_reward)
	neutralized.emit()
