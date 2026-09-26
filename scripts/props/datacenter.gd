@tool
class_name Datacenter
extends Node3D
## A corporate "bad" datacenter: a destructible shell plus external cooling units.
## Destroying every cooling unit collapses the building and heals the district.

signal cooling_unit_destroyed(remaining: int)
signal neutralized
signal turbine_destroyed(remaining: int)
## Every gas turbine is down: powered defenses (sentries, vents, crushers) are off.
signal power_cut

@export var footprint := Vector2(24.0, 16.0)
@export var height := 8.0
## Width of each destructible wall / roof segment.
@export var segment_size := 4.0
@export var cooling_unit_count := 3
## Gas turbine generators behind the building (north side).
@export var turbine_count := 3
@export var turbine_smog := 0.06
@export var turbine_noise := 0.08
@export var turbine_cash := 75
@export var wall_color := Color(0.72, 0.74, 0.76)
@export var roof_color := Color(0.55, 0.56, 0.58)
@export var cooling_color := Color(0.85, 0.9, 0.95)

@export_group("District impact")
@export var smog_contribution := 0.85
@export var noise_contribution := 0.85
@export var water_restored := 0.6
@export var trust_gain := 0.3
@export var cash_reward := 500

var cooling_remaining := 0
var turbines_remaining := 0
var is_neutralized := false

var _structure: Array[Destructible] = []
var _roof: Array[Destructible] = []
var _fans: Array[Node3D] = []


func _ready() -> void:
	_build_shell()
	_decorate_shell()
	_build_cooling_units()
	_build_turbines()


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
			var piece := _make_segment(roof_size, roof_color, Vector3i(2, 1, 2), &"plates")
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


func _make_segment(seg_size: Vector3, seg_color: Color, seg_chunks: Vector3i,
		kind: StringName = &"corrugated") -> Destructible:
	var piece := Destructible.new()
	piece.set_meta(&"generated", true)
	piece.surface_kind = kind
	piece.size = seg_size
	piece.color = seg_color
	piece.chunks = seg_chunks
	piece.max_health = 250.0
	piece.damage_threshold = 50.0
	piece.density = 150.0
	piece.label = "Datacenter wall"
	add_child(piece)
	return piece


## Surface detail: wall vents, rooftop HVAC, and the corporate sign. All are
## children of the segments they sit on, so they fall with them.
func _decorate_shell() -> void:
	var grille := Models.mat(Color(0.12, 0.13, 0.15))
	for piece in _structure:
		var along := piece.size.x > piece.size.z
		var out := Vector3(0.0, 0.0, piece.size.z * 0.5 + 0.03) if along else Vector3(piece.size.x * 0.5 + 0.03, 0.0, 0.0)
		out *= signf(piece.position.z) if along else signf(piece.position.x)
		var vent_size := Vector3(1.6, 1.0, 0.06) if along else Vector3(0.06, 1.0, 1.6)
		Models.box(piece, vent_size, out + Vector3.UP * height * 0.7, grille)
		Models.box(piece, vent_size * Vector3(1.0, 0.25, 1.0), out + Vector3.UP * 0.3, Models.mat(Color(0.5, 0.52, 0.55)))
	var metal := Models.mat(Color(0.55, 0.57, 0.6))
	for i in range(0, _roof.size(), 2):
		var hvac := _roof[i]
		Models.box(hvac, Vector3(1.8, 1.0, 1.4), Vector3(0.0, hvac.size.y + 0.5, 0.0), metal)
		Models.cylinder(hvac, 0.5, 0.1, Vector3(0.0, hvac.size.y + 1.05, 0.0), grille, 10)
	# Sign over the front (the wall facing the neighborhood, +Z).
	var front: Array[Destructible] = _structure.filter(func(p: Destructible) -> bool:
		return p.size.x > p.size.z and p.position.z > 0.0)
	if not front.is_empty():
		var middle: Destructible = front[front.size() >> 1]
		var sign_label := Label3D.new()
		sign_label.text = "FELSA CLOUD  //  REGION US-SUBURB-1"
		sign_label.pixel_size = 0.02
		sign_label.font_size = 64
		sign_label.outline_size = 8
		sign_label.modulate = Color(0.75, 0.9, 1.0)
		sign_label.position = Vector3(0.0, height * 0.85, middle.size.z * 0.5 + 0.06)
		middle.add_child(sign_label)


func _build_cooling_units() -> void:
	var unit_size := Vector3(3.0, 3.0, 3.0)
	var spacing := footprint.y / maxi(cooling_unit_count, 1)
	for i in cooling_unit_count:
		var unit := Destructible.new()
		unit.set_meta(&"generated", true)
		unit.name = "CoolingUnit%d" % i
		unit.size = unit_size
		unit.color = cooling_color
		unit.surface_kind = &"plates"
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


func _build_turbines() -> void:
	var spacing := 7.5
	for i in turbine_count:
		var turbine := GasTurbine.new()
		turbine.set_meta(&"generated", true)
		turbine.name = "Turbine%d" % i
		turbine.position = Vector3((i - (turbine_count - 1) * 0.5) * spacing, 0.0, -footprint.y * 0.5 - 5.0)
		add_child(turbine)
		if not Engine.is_editor_hint():
			turbine.destroyed.connect(_on_turbine_destroyed)
	turbines_remaining = turbine_count


func _on_turbine_destroyed(_turbine: Destructible) -> void:
	turbines_remaining -= 1
	var district := Game.district
	if district and not is_neutralized:
		district.smog -= turbine_smog
		district.noise -= turbine_noise
	Game.add_cash(turbine_cash)
	turbine_destroyed.emit(turbines_remaining)
	if turbines_remaining <= 0 and not is_neutralized:
		get_tree().call_group(&"crapya_defenses", &"shut_down")
		power_cut.emit()


func _collapse(origin: Vector3) -> void:
	if is_neutralized:
		return
	is_neutralized = true
	# Crapya's automated defenses and the generators go too, clearing the lot.
	get_tree().call_group(&"crapya_defenses", &"dismantle")
	for node in get_tree().get_nodes_in_group("gas_turbines"):
		var turbine := node as GasTurbine
		if turbine and is_ancestor_of(turbine) and not turbine.is_destroyed:
			turbine.shut_down()
			get_tree().create_timer(2.5).timeout.connect(_dismantle.bind(turbine))

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


## `turbine` is untyped: it may have been blown up in the meantime.
func _dismantle(turbine: Variant) -> void:
	if is_instance_valid(turbine) and not (turbine as Destructible).is_destroyed:
		var quiet := turbine as GasTurbine
		quiet.destroyed.disconnect(_on_turbine_destroyed)
		quiet.dismantled = true
		quiet.shatter(quiet.global_position + Vector3.UP * 4.0, 30.0)


func _heal_district() -> void:
	var district := Game.district
	if district:
		district.smog -= smog_contribution
		district.noise -= noise_contribution * 0.5
		district.water_table += water_restored
		district.trust += trust_gain
	Game.add_cash(cash_reward)
	neutralized.emit()
