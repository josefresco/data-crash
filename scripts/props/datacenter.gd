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
var _blinkers: Array[Node3D] = []
var _clock := 0.0


func _ready() -> void:
	_build_shell()
	_decorate_shell()
	_build_cooling_units()
	_build_turbines()


func _process(delta: float) -> void:
	_clock += delta
	for fan in _fans:
		if is_instance_valid(fan):
			fan.rotate_y(delta * 12.0)
	# Aviation lights: a short flash every 1.5 s.
	var lit := fmod(_clock, 1.5) < 0.25 and not is_neutralized
	for light in _blinkers:
		if is_instance_valid(light):
			light.visible = lit


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


## Surface detail on the shell: plinth, steel columns, parapet, a glowing
## server-hall window band, the glass entrance and backlit sign (front, +Z),
## loading docks (west, -X), louvered vents, cameras, and a rooftop of
## chillers, cable trays, a dish, and an antenna with blinking aviation lights.
## Everything is a visual child of the segment it sits on, so it falls with it.
func _decorate_shell() -> void:
	var concrete := Models.mat(Color(0.6, 0.6, 0.58), &"concrete")
	var steel := Models.mat(Color(0.32, 0.34, 0.37), &"metal")
	var dark := Models.mat(Color(0.1, 0.11, 0.13), &"metal")
	var band := Models.mat(Color(0.08, 0.1, 0.13), &"window")
	var leds: Array[Material] = [Models.glow(Color(0.3, 0.8, 1.0), 3.0), Models.glow(Color(0.3, 1.0, 0.5), 3.0),
		Models.glow(Color(1.0, 0.7, 0.2), 3.0)]
	var index := 0
	for piece in _structure:
		index += 1
		var along := piece.size.x > piece.size.z
		var normal := Vector3(0.0, 0.0, signf(piece.position.z)) if along else Vector3(signf(piece.position.x), 0.0, 0.0)
		var depth := (piece.size.z if along else piece.size.x) * 0.5
		var width := piece.size.x if along else piece.size.z
		var tangent := Vector3.RIGHT if along else Vector3.BACK
		var face := normal * depth
		# Sizes as (along the wall, height, out of the wall).
		var sized := func(w: float, h: float, d: float) -> Vector3:
			return Vector3(w, h, d) if along else Vector3(d, h, w)
		Models.box(piece, sized.call(width, 0.9, 0.16), face + normal * 0.08 + Vector3.UP * 0.45, concrete)
		Models.box(piece, sized.call(width + 0.02, 0.9, 0.6), face + normal * 0.1 + Vector3.UP * (height + 0.45), steel)
		Models.box(piece, sized.call(0.4, height, 0.26), face + normal * 0.13 - tangent * (width * 0.5 - 0.2) + Vector3.UP * height * 0.5, steel)
		var west := not along and normal.x < 0.0
		var east := not along and normal.x > 0.0
		if not east:
			# Narrow dark window band with server racks glowing behind it.
			Models.box(piece, sized.call(width - 0.8, 0.8, 0.06), face + normal * 0.03 + Vector3.UP * height * 0.66, band)
			Models.box(piece, sized.call(width - 0.8, 0.05, 0.07), face + normal * 0.04 + Vector3.UP * (height * 0.66 - 0.36), leds[0])
			for k in 5:
				var along_wall := -width * 0.5 + 0.8 + k * (width - 1.6) / 4.0
				Models.box(piece, sized.call(0.08, 0.08, 0.08), face + normal * 0.05 + tangent * along_wall
					+ Vector3.UP * (height * 0.66 + 0.15 - (k % 2) * 0.25), leds[(index + k) % leds.size()])
		# Louvered vent banks low on the walls, wall-pack lights up top.
		if not west:
			var vent := Models.box(piece, sized.call(1.8, 1.2, 0.08), face + normal * 0.04 + Vector3.UP * 2.0, dark)
			for k in 4:
				Models.box(vent, sized.call(1.8, 0.06, 0.14), normal * 0.05 + Vector3.UP * (-0.45 + k * 0.3), steel)
		Models.box(piece, sized.call(0.5, 0.2, 0.25), face + normal * 0.12 + Vector3.UP * (height * 0.45), Models.glow(Color(1.0, 0.92, 0.75), 2.0))
		if west and index % 2 == 0:
			_add_dock_door(piece, face, normal, sized, steel, concrete)
	_decorate_front(steel, dark)
	_decorate_roof(steel, dark)
	_add_cameras(dark)


## Glass entrance vestibule, canopy, and a backlit sign on the front wall.
func _decorate_front(steel: Material, dark: Material) -> void:
	var front: Array[Destructible] = _structure.filter(func(p: Destructible) -> bool:
		return p.size.x > p.size.z and p.position.z > 0.0)
	if front.is_empty():
		return
	var middle: Destructible = front[front.size() >> 1]
	var face := Vector3(0.0, 0.0, middle.size.z * 0.5)
	var glass := Models.glass(Color(0.35, 0.55, 0.7, 0.45))
	Models.box(middle, Vector3(3.6, 3.0, 1.6), face + Vector3(0.0, 1.5, 0.8), glass)
	for x in [-1.8, 1.8]:
		Models.box(middle, Vector3(0.15, 3.0, 1.7), face + Vector3(x, 1.5, 0.85), steel)
	Models.box(middle, Vector3(1.6, 2.4, 0.05), face + Vector3(0.0, 1.2, 1.62), dark)  # doors
	var canopy := Models.box(middle, Vector3(6.0, 0.25, 3.0), face + Vector3(0.0, 3.3, 1.5), steel)
	Models.box(canopy, Vector3(5.6, 0.04, 0.12), Vector3(0.0, -0.14, 1.3), Models.glow(Color(1.0, 0.95, 0.85), 3.0))
	# Backlit sign panel with the logo ring and the name.
	Models.box(middle, Vector3(13.0, 1.8, 0.2), face + Vector3(0.0, height * 0.85, 0.2), dark)
	Models.box(middle, Vector3(13.2, 0.06, 0.24), face + Vector3(0.0, height * 0.85 - 0.93, 0.2), Models.glow(Color(0.3, 0.8, 1.0), 2.5))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.62
	ring.mesh = torus
	ring.material_override = Models.glow(Color(0.3, 0.85, 1.0), 4.0)
	ring.rotation.x = PI * 0.5
	ring.position = face + Vector3(-5.4, height * 0.85, 0.35)
	middle.add_child(ring)
	for line in [["FELSA CLOUD", 0.016, 0.22], ["REGION US-SUBURB-1  //  99.99% UPTIME, 0% WATER LEFT", 0.0055, -0.5]]:
		var sign_label := Label3D.new()
		sign_label.text = line[0]
		sign_label.pixel_size = line[1]
		sign_label.font_size = 72
		sign_label.outline_size = 0
		sign_label.modulate = Color(0.8, 0.95, 1.0)
		sign_label.position = face + Vector3(0.9, height * 0.85 + float(line[2]), 0.32)
		middle.add_child(sign_label)


## Roll-up loading door with ribs, dock bumpers, bollards, and a dock light.
func _add_dock_door(piece: Destructible, face: Vector3, normal: Vector3, sized: Callable,
		steel: Material, concrete: Material) -> void:
	var door := Models.box(piece, sized.call(3.0, 3.6, 0.1), face + normal * 0.05 + Vector3.UP * 1.8,
		Models.mat(Color(0.5, 0.52, 0.55), &"corrugated"))
	for k in 8:
		Models.box(door, sized.call(3.0, 0.05, 0.08), normal * 0.05 + Vector3.UP * (-1.6 + k * 0.45), steel)
	Models.box(piece, sized.call(3.6, 0.3, 0.3), face + normal * 0.15 + Vector3.UP * 3.75, steel)
	var yellow := Models.mat(Color(0.95, 0.75, 0.1), &"paint")
	var rubber := Models.mat(Color(0.08, 0.08, 0.08))
	var tangent := Vector3.BACK if absf(normal.x) > 0.0 else Vector3.RIGHT
	for side in [-1.0, 1.0]:
		Models.box(piece, sized.call(0.3, 0.5, 0.3), face + normal * 0.15 + tangent * side * 1.3 + Vector3.UP * 1.0, rubber)
		Models.cylinder(piece, 0.14, 1.1, face + normal * 1.6 + tangent * side * 2.0 + Vector3.UP * 0.55, yellow, 10)
	Models.box(piece, sized.call(4.0, 0.06, 2.4), face + normal * 1.2 + Vector3.UP * 0.03, concrete)
	Models.box(piece, sized.call(0.4, 0.15, 0.3), face + normal * 0.2 + Vector3.UP * 4.2, Models.glow(Color(1.0, 0.85, 0.5), 2.5))


func _decorate_roof(steel: Material, dark: Material) -> void:
	var fan_mat := Models.mat(Color(0.18, 0.19, 0.2), &"metal")
	var pipe := Models.mat(Color(0.7, 0.72, 0.74), &"metal")
	for i in _roof.size():
		var tile := _roof[i]
		var top := tile.size.y
		match i % 3:
			0:
				# Air-cooled chiller: housing, two fan shrouds with spinning blades.
				var chiller := Models.box(tile, Vector3(2.8, 1.3, 1.6), Vector3(0.0, top + 0.65, 0.0), Models.mat(Color(0.78, 0.8, 0.82), &"plates"))
				for x in [-0.7, 0.7]:
					Models.cylinder(chiller, 0.6, 0.12, Vector3(x, 0.7, 0.0), fan_mat, 16)
					var blades := Node3D.new()
					blades.position = Vector3(x, 0.78, 0.0)
					chiller.add_child(blades)
					for k in 3:
						Models.box(blades, Vector3(1.05, 0.03, 0.18), Vector3.ZERO, dark).rotation.y = k * PI / 3.0
					_fans.append(blades)
			1:
				# Cable tray and coolant pipes running across the tile.
				Models.box(tile, Vector3(tile.size.x, 0.12, 0.6), Vector3(0.0, top + 0.45, -0.8), steel)
				for k in 3:
					Models.box(tile, Vector3(0.08, 0.4, 0.08), Vector3(-tile.size.x * 0.4 + k * tile.size.x * 0.4, top + 0.2, -0.8), steel)
				for z in [0.6, 1.0]:
					Models.cylinder(tile, 0.14, tile.size.x, Vector3(0.0, top + 0.35, z), pipe, 10).rotation.z = PI * 0.5
			2:
				Models.box(tile, Vector3(1.2, 0.8, 1.2), Vector3(0.6, top + 0.4, 0.4), Models.mat(Color(0.6, 0.62, 0.65), &"plates"))
				Models.box(tile, Vector3(1.0, 0.1, 1.0), Vector3(0.6, top + 0.85, 0.4), dark)
	if _roof.size() > 4:
		# Antenna mast with a blinking aviation light, and a satellite dish.
		var mast_tile := _roof[1]
		var mast_top := mast_tile.size.y + 6.0
		Models.cylinder(mast_tile, 0.08, 6.0, Vector3(-1.0, mast_tile.size.y + 3.0, 1.0), steel, 8)
		for y in [2.5, 4.5]:
			Models.box(mast_tile, Vector3(0.9, 0.05, 0.05), Vector3(-1.0, mast_tile.size.y + y, 1.0), steel)
		_blinkers.append(Models.ball(mast_tile, 0.14, Vector3(-1.0, mast_top, 1.0), Models.glow(Color(1.0, 0.1, 0.05), 6.0)))
		var dish_tile := _roof[_roof.size() - 2]
		var dish_mesh := SphereMesh.new()
		dish_mesh.radius = 1.0
		dish_mesh.height = 0.6
		dish_mesh.is_hemisphere = true
		var dish := MeshInstance3D.new()
		dish.mesh = dish_mesh
		dish.material_override = Models.mat(Color(0.88, 0.88, 0.9), &"paint")
		dish.position = Vector3(0.5, dish_tile.size.y + 1.4, 0.0)
		dish.rotation = Vector3(deg_to_rad(-120.0), 0.4, 0.0)
		dish_tile.add_child(dish)
		Models.cylinder(dish_tile, 0.1, 1.2, Vector3(0.5, dish_tile.size.y + 0.6, 0.0), steel, 8)
	# Corner beacons on the parapet.
	for piece in _structure:
		if piece.size.x > piece.size.z and absf(absf(piece.position.x) - footprint.x * 0.5 + segment_size * 0.5) < 0.5:
			var corner := Vector3(signf(piece.position.x) * (piece.size.x * 0.5 - 0.3), height + 1.0, 0.0)
			_blinkers.append(Models.ball(piece, 0.1, corner, Models.glow(Color(1.0, 0.1, 0.05), 5.0)))


## Security cameras on the corners of the front and back walls.
func _add_cameras(dark: Material) -> void:
	var body := Models.mat(Color(0.85, 0.86, 0.88), &"paint")
	for piece in _structure:
		if piece.size.x <= piece.size.z or absf(absf(piece.position.x) - footprint.x * 0.5 + segment_size * 0.5) > 0.5:
			continue
		var out := signf(piece.position.z)
		var corner := Vector3(signf(piece.position.x) * (piece.size.x * 0.5 - 0.4), height - 0.8, out * (piece.size.z * 0.5 + 0.3))
		Models.box(piece, Vector3(0.08, 0.08, 0.5), corner - Vector3(0.0, 0.0, out * 0.15), dark)
		var cam := Models.box(piece, Vector3(0.22, 0.2, 0.45), corner + Vector3(0.0, -0.1, out * 0.2), body)
		cam.rotation.x = deg_to_rad(-20.0) * out
		Models.box(cam, Vector3(0.05, 0.05, 0.02), Vector3(0.06, 0.05, out * 0.23), Models.glow(Color(1.0, 0.1, 0.05), 3.0))


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
		_dress_cooling_unit(unit, unit_size)
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


## Coil grilles on each face, a base frame, a status light, and coolant pipes
## running into the building's east wall.
func _dress_cooling_unit(unit: Destructible, unit_size: Vector3) -> void:
	var grille := Models.mat(Color(0.14, 0.15, 0.17), &"metal")
	var frame := Models.mat(Color(0.35, 0.37, 0.4), &"metal")
	var half := unit_size * 0.5
	for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var along_x := absf(side.z) > 0.0
		var panel_size := Vector3(unit_size.x - 0.5, unit_size.y - 1.0, 0.05) if along_x else Vector3(0.05, unit_size.y - 1.0, unit_size.z - 0.5)
		var panel := Models.box(unit, panel_size, side * (half.x + 0.02) + Vector3.UP * (half.y + 0.1), grille)
		for k in 6:
			var slat := Vector3(unit_size.x - 0.5, 0.04, 0.07) if along_x else Vector3(0.07, 0.04, unit_size.z - 0.5)
			Models.box(panel, slat, side * 0.03 + Vector3.UP * (-0.8 + k * 0.32), frame)
	Models.box(unit, Vector3(unit_size.x + 0.3, 0.25, unit_size.z + 0.3), Vector3.UP * 0.12, frame)
	Models.box(unit, Vector3(0.12, 0.12, 0.05), Vector3(half.x - 0.35, unit_size.y - 0.3, half.z + 0.03), Models.glow(Color(0.3, 1.0, 0.4), 4.0))
	var pipe := Models.mat(Color(0.2, 0.45, 0.75), &"paint")
	var gap := unit.position.x - unit_size.x * 0.5 - footprint.x * 0.5
	for y: float in [1.2, 2.0]:
		var run := Models.cylinder(unit, 0.16, gap + 0.4, Vector3(-half.x - gap * 0.5, y, 0.4 if y > 1.5 else -0.4), pipe, 10)
		run.rotation.z = PI * 0.5


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
