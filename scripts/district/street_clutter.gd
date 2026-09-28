class_name StreetClutter
extends Node3D
## Everyday clutter around the neighborhood (added by the level after the
## NeighborhoodBuilder, deterministic from its layout seed): trash and
## recycling bins at every house's curb, yard things (kids' bikes,
## basketball hoops, grills, gnomes, plastic flamingos, lawn chairs), fire
## hydrants at the corners, power poles with sagging lines along the cross
## streets, newspaper boxes and benches by the shops, rusty dumpsters behind
## them, and a bus shelter on the main road. Bins, hydrants, poles, hoops,
## dumpsters, and the shelter are solid. Static parts are merged per
## CHUNK-meter grid cell (one mesh per material each) and hidden past
## `view_distance`.

const CHUNK := 48.0

@export var view_distance := 110.0

var _rng := RandomNumberGenerator.new()
var _chunks := {}
var _hood: NeighborhoodBuilder
var _skip: Array[Vector3] = []


## Builds everything for `hood`. `avoid`: world points to keep clear (the
## burst hydrant, deed props) within 4 m.
func setup(hood: NeighborhoodBuilder, avoid: Array[Vector3] = []) -> void:
	_hood = hood
	_skip = avoid
	_rng.seed = hood.layout_seed * 131 + 17
	var mats := {
		"green": Models.mat(Color(0.2, 0.42, 0.25), &"paint"),
		"blue": Models.mat(Color(0.18, 0.35, 0.7), &"paint"),
		"black": Models.mat(Color(0.1, 0.1, 0.11), &"paint"),
		"steel": Models.mat(Color(0.55, 0.56, 0.58), &"metal"),
		"red": Models.mat(Color(0.75, 0.12, 0.1), &"paint"),
		"wood": Models.mat(Color(0.55, 0.42, 0.3), &"wood"),
		"rust": Models.mat(Color(0.75, 0.65, 0.55), &"rust"),
		"white": Models.mat(Color(0.92, 0.92, 0.9), &"paint"),
		"pink": Models.mat(Color(1.0, 0.45, 0.65), &"paint"),
		"yellow": Models.mat(Color(0.95, 0.78, 0.2), &"paint"),
		"orange": Models.mat(Color(0.95, 0.5, 0.15), &"paint"),
		"glass": Models.glass(Color(0.6, 0.75, 0.85, 0.3)),
	}
	for entry: Array in hood.house_doors():
		_house_clutter(hood.to_global(entry[0]), hood.global_basis * (entry[1] as Vector3), mats)
	_hydrants(mats)
	_power_lines(mats)
	_shop_clutter(mats)
	_bus_stop(mats)
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		Models.merge_static(chunk)
		for child in chunk.get_children():
			if child is GeometryInstance3D:
				(child as GeometryInstance3D).visibility_range_end = view_distance


## The merge cell for a world point.
func _chunk(at: Vector3) -> Node3D:
	var key := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	if not _chunks.has(key):
		var node := Node3D.new()
		node.name = "Chunk_%d_%d" % [key.x, key.y]
		add_child(node)
		_chunks[key] = node
	return _chunks[key]


## A prop root at `at` (world, yaw), in its chunk, or null if too close to
## something that must stay clear, or in the river.
func _prop(at: Vector3, yaw := 0.0) -> Node3D:
	for point in _skip:
		if Vector2(point.x - at.x, point.z - at.z).length() < 4.0:
			return null
	if _hood.in_river(_hood.to_local(at), 1.0):
		return null
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	_chunk(at).add_child(root)
	return root


## Bins at the curb, and one or two things in the front yard.
func _house_clutter(door: Vector3, facing: Vector3, mats: Dictionary) -> void:
	var out := Vector3(facing.x, 0.0, facing.z).normalized()
	var side := out.cross(Vector3.UP)
	var yaw := atan2(out.x, out.z)
	# The door sits ~10 m back from the street center; the curb strip is ~6.6.
	var street := _nearest_street(_hood.to_local(door))
	var curb_offset := absf(_hood.to_local(door).z - street) - _hood.road_width * 0.5 - 2.6
	var curb := door + out * curb_offset + side * 3.2
	var bins := _prop(curb, yaw)
	if bins:
		for k in 2:
			var bin := Node3D.new()
			bin.position = Vector3(k * 0.8, 0.0, 0.0)
			bins.add_child(bin)
			var body_mat: Material = mats["green"] if k == 0 else mats["blue"]
			Models.box(bin, Vector3(0.62, 0.95, 0.7), Vector3(0.0, 0.5, 0.0), body_mat)
			Models.box(bin, Vector3(0.66, 0.06, 0.76), Vector3(0.0, 1.0, -0.02), body_mat)  # lid
			for x: float in [-0.25, 0.25]:
				var wheel := Models.cylinder(bin, 0.08, 0.06, Vector3(x, 0.08, -0.38), mats["black"], 8)
				wheel.rotation.z = PI * 0.5
		Models.collider(bins, Vector3(1.5, 1.05, 0.8), Vector3(0.4, 0.52, 0.0))
	# Yard things: between the curb and the house.
	for n in _rng.randi_range(1, 2):
		var spot := door + out * _rng.randf_range(1.8, curb_offset - 1.2) + side * _rng.randf_range(-4.0, 1.5)
		var thing := _prop(spot, _rng.randf() * TAU)
		if thing == null:
			continue
		match _rng.randi() % 6:
			0:
				_bike(thing, mats)
			1:
				thing.position = door + out * 1.5 + side * 4.5
				thing.rotation.y = yaw + PI
				_hoop(thing, mats)
			2:
				_grill(thing, mats)
			3:
				_gnome(thing, mats)
			4:
				_flamingos(thing, mats)
			_:
				_lawn_chairs(thing, mats)


func _nearest_street(point: Vector3) -> float:
	var best: float = _hood.street_z[0]
	for z: float in _hood.street_z:
		if absf(z - point.z) < absf(best - point.z):
			best = z
	return best


func _bike(root: Node3D, mats: Dictionary) -> void:
	# Lying on its side in the grass.
	var frame: Material = [mats["red"], mats["blue"], mats["pink"]][_rng.randi() % 3]
	for z: float in [-0.45, 0.45]:
		var wheel := Models.cylinder(root, 0.3, 0.04, Vector3(0.0, 0.03, z), mats["black"], 12)
		wheel.rotation.x = 0.0
	Models.box(root, Vector3(0.04, 0.04, 0.8), Vector3(0.05, 0.06, 0.0), frame)
	Models.box(root, Vector3(0.45, 0.04, 0.04), Vector3(0.2, 0.06, -0.4), mats["black"])


func _hoop(root: Node3D, mats: Dictionary) -> void:
	Models.cylinder(root, 0.06, 3.0, Vector3(0.0, 1.5, 0.0), mats["steel"], 8)
	Models.box(root, Vector3(1.2, 0.8, 0.04), Vector3(0.0, 3.1, 0.35), mats["white"])
	Models.box(root, Vector3(0.45, 0.35, 0.05), Vector3(0.0, 2.95, 0.36), mats["red"])
	var rim := Models.cylinder(root, 0.23, 0.03, Vector3(0.0, 2.75, 0.62), mats["orange"], 12)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Models.collider(root, Vector3(0.2, 3.0, 0.2), Vector3(0.0, 1.5, 0.0))


func _grill(root: Node3D, mats: Dictionary) -> void:
	Models.ball(root, 0.32, Vector3(0.0, 0.85, 0.0), mats["black"]).scale = Vector3(1.0, 0.7, 1.0)
	for k in 3:
		var a := k * TAU / 3.0
		var leg := Models.cylinder(root, 0.02, 0.8, Vector3(cos(a) * 0.2, 0.4, sin(a) * 0.2), mats["steel"], 4)
		leg.rotation = Vector3(sin(a) * 0.25, 0.0, -cos(a) * 0.25)


func _gnome(root: Node3D, mats: Dictionary) -> void:
	Models.cylinder(root, 0.1, 0.22, Vector3(0.0, 0.11, 0.0), mats["blue"], 8)
	Models.ball(root, 0.08, Vector3(0.0, 0.28, 0.0), Models.mat(Color(0.95, 0.75, 0.6), &"paint"))
	Models.ball(root, 0.07, Vector3(0.0, 0.24, 0.06), mats["white"])  # beard
	var hat := Models.cylinder(root, 0.02, 0.2, Vector3(0.0, 0.42, 0.0), mats["red"], 6)
	(hat.mesh as CylinderMesh).bottom_radius = 0.09


func _flamingos(root: Node3D, mats: Dictionary) -> void:
	for k in 2:
		var bird := Node3D.new()
		bird.position = Vector3(k * 0.5, 0.0, k * 0.2)
		bird.rotation.y = k * 0.8
		root.add_child(bird)
		Models.cylinder(bird, 0.01, 0.55, Vector3(0.0, 0.28, 0.0), mats["black"], 4)
		Models.ball(bird, 0.13, Vector3(0.0, 0.65, 0.0), mats["pink"]).scale = Vector3(0.7, 0.75, 1.3)
		Models.cylinder(bird, 0.025, 0.3, Vector3(0.0, 0.85, 0.12), mats["pink"], 6)
		Models.ball(bird, 0.05, Vector3(0.0, 1.0, 0.15), mats["pink"])


func _lawn_chairs(root: Node3D, mats: Dictionary) -> void:
	for k in 2:
		var chair := Node3D.new()
		chair.position = Vector3(k * 0.9, 0.0, 0.0)
		chair.rotation.y = (k - 0.5) * 0.4
		root.add_child(chair)
		var webbing: Material = [mats["green"], mats["blue"], mats["yellow"]][_rng.randi() % 3]
		Models.box(chair, Vector3(0.55, 0.04, 0.5), Vector3(0.0, 0.38, 0.0), webbing)
		var back := Models.box(chair, Vector3(0.55, 0.6, 0.04), Vector3(0.0, 0.68, -0.27), webbing)
		back.rotation.x = -0.25
		for x: float in [-0.27, 0.27]:
			Models.box(chair, Vector3(0.03, 0.38, 0.5), Vector3(x, 0.19, 0.0), mats["steel"])
	Models.cylinder(root, 0.3, 0.02, Vector3(0.45, 0.45, 0.7), mats["white"], 12)  # side table top
	Models.cylinder(root, 0.03, 0.45, Vector3(0.45, 0.22, 0.7), mats["steel"], 6)


## Hydrants on the corners where the cross streets meet the main road.
func _hydrants(mats: Dictionary) -> void:
	var reach := _hood.road_width * 0.5 + 1.7
	for z: float in _hood.street_z:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var at := _hood.to_global(Vector3(sx * reach, 0.0, z + sz * reach))
				var hydrant := _prop(at)
				if hydrant == null:
					continue
				Models.cylinder(hydrant, 0.14, 0.6, Vector3(0.0, 0.3, 0.0), mats["red"], 10)
				Models.ball(hydrant, 0.15, Vector3(0.0, 0.62, 0.0), mats["red"]).scale = Vector3(1.0, 0.6, 1.0)
				for side: float in [-1.0, 1.0]:
					var outlet := Models.cylinder(hydrant, 0.05, 0.12, Vector3(side * 0.17, 0.42, 0.0), mats["red"], 8)
					outlet.rotation.z = PI * 0.5
				Models.collider(hydrant, Vector3(0.4, 0.75, 0.4), Vector3(0.0, 0.37, 0.0))


## Wooden power poles along the house side of each cross street, with
## three lines draped between them.
func _power_lines(mats: Dictionary) -> void:
	var wire := Models.mat(Color(0.08, 0.08, 0.08), &"rough")
	var edge := _hood.road_width * 0.5 + 2.4
	for z: float in _hood.street_z:
		var poles: Array[Vector3] = []
		var x := -_hood.street_half_length + 6.0
		while x < _hood.street_half_length - 4.0:
			if absf(x) > 8.0:
				poles.append(_hood.to_global(Vector3(x, 0.0, z - edge)))
			x += 22.0
		var tops: Array[Vector3] = []
		for at in poles:
			var pole := _prop(at)
			if pole == null:
				tops.append(Vector3.INF)
				continue
			Models.cylinder(pole, 0.13, 8.5, Vector3(0.0, 4.25, 0.0), mats["wood"], 8)
			Models.box(pole, Vector3(0.12, 0.12, 1.6), Vector3(0.0, 7.9, 0.0), mats["wood"])  # crossarm
			Models.cylinder(pole, 0.22, 0.6, Vector3(0.0, 6.9, 0.25), mats["steel"], 10)  # transformer can
			Models.collider(pole, Vector3(0.3, 8.5, 0.3), Vector3(0.0, 4.25, 0.0))
			tops.append(at + Vector3.UP * 8.0)
		# Lines: three per span, sagging through a midpoint.
		for i in range(1, tops.size()):
			var a := tops[i - 1]
			var b := tops[i]
			if a == Vector3.INF or b == Vector3.INF or a.distance_to(b) > 30.0:
				continue
			for lane: float in [-0.7, 0.0, 0.7]:
				var from := a + Vector3(0.0, 0.0, lane)
				var to := b + Vector3(0.0, 0.0, lane)
				var mid := (from + to) * 0.5 + Vector3.DOWN * 0.9
				for pair: Array in [[from, mid], [mid, to]]:
					var p0: Vector3 = pair[0]
					var p1: Vector3 = pair[1]
					var span := _prop((p0 + p1) * 0.5)
					if span == null:
						continue
					var line := Models.cylinder(span, 0.012, p0.distance_to(p1), Vector3.ZERO, wire, 3)
					# Cylinders run along Y: turn Y onto the span.
					line.basis = Basis.looking_at(p1 - p0, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
					line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					line.visibility_range_end = 0.0


## By each Kenney shop's door: a newspaper box and a bench; a dumpster
## around the side.
func _shop_clutter(mats: Dictionary) -> void:
	for lot: Array in _hood.store_lots:
		var door := _hood.store_door(lot[2])
		if door == Vector3.ZERO:
			continue
		var world_door := _hood.to_global(door)
		var lot_at := _hood.to_global(lot[0] as Vector3)
		var out := Vector3(0.0, 0.0, signf(world_door.z - lot_at.z))
		var yaw := atan2(out.x, out.z)
		var box := _prop(world_door + Vector3(-3.0, 0.0, 0.0), yaw)
		if box:
			var paper: Material = [mats["blue"], mats["red"], mats["yellow"]][_rng.randi() % 3]
			Models.box(box, Vector3(0.5, 0.9, 0.45), Vector3(0.0, 0.55, 0.0), paper)
			Models.box(box, Vector3(0.4, 0.3, 0.02), Vector3(0.0, 0.8, 0.23), mats["glass"])
			Models.box(box, Vector3(0.06, 0.1, 0.06), Vector3(0.0, 0.05, 0.0), mats["steel"])
			Models.collider(box, Vector3(0.5, 1.0, 0.45), Vector3(0.0, 0.5, 0.0))
		var bench := _prop(world_door + Vector3(4.6, 0.0, 0.0), yaw + PI)
		if bench:
			for k in 3:
				Models.box(bench, Vector3(1.6, 0.05, 0.12), Vector3(0.0, 0.45, -0.15 + k * 0.15), mats["wood"])
			Models.box(bench, Vector3(1.6, 0.35, 0.05), Vector3(0.0, 0.7, -0.25), mats["wood"])
			for x: float in [-0.7, 0.7]:
				Models.box(bench, Vector3(0.06, 0.45, 0.45), Vector3(x, 0.22, -0.05), mats["black"])
			Models.collider(bench, Vector3(1.6, 0.9, 0.5), Vector3(0.0, 0.45, -0.1))
		var dumpster := _prop(lot_at + Vector3(7.5, 0.0, -out.z * 2.0), yaw)
		if dumpster:
			Models.box(dumpster, Vector3(1.8, 1.1, 1.2), Vector3(0.0, 0.65, 0.0), mats["rust"])
			var lid := Models.box(dumpster, Vector3(1.85, 0.06, 1.25), Vector3(0.0, 1.22, -0.05), mats["black"])
			lid.rotation.x = -0.12
			Models.collider(dumpster, Vector3(1.8, 1.25, 1.2), Vector3(0.0, 0.62, 0.0))


## A bus shelter on the main road's east sidewalk, with a Felsa ad.
func _bus_stop(mats: Dictionary) -> void:
	var at := _hood.to_global(Vector3(_hood.road_width * 0.5 + 1.2, 0.0, 52.0))
	var shelter := _prop(at, -PI * 0.5)
	if shelter == null:
		return
	for x: float in [-1.5, 1.5]:
		Models.box(shelter, Vector3(0.08, 2.4, 0.08), Vector3(x, 1.2, 0.5), mats["steel"])
		Models.box(shelter, Vector3(0.08, 2.4, 0.08), Vector3(x, 1.2, -0.5), mats["steel"])
	Models.box(shelter, Vector3(3.3, 0.08, 1.4), Vector3(0.0, 2.45, 0.0), mats["steel"])
	Models.box(shelter, Vector3(3.0, 2.0, 0.03), Vector3(0.0, 1.2, -0.5), mats["glass"])
	Models.box(shelter, Vector3(2.4, 0.05, 0.4), Vector3(0.0, 0.48, -0.25), mats["wood"])
	var ad := Models.box(shelter, Vector3(1.0, 1.6, 0.05), Vector3(1.5, 1.2, 0.0), Models.glow(Color(0.85, 0.9, 1.0), 0.8))
	ad.rotation.y = PI * 0.5
	var text := Label3D.new()
	text.text = "FELSA\nTHE FUTURE\nOF YOU\n(TERMS APPLY)"
	text.modulate = Color(0.12, 0.12, 0.2)
	text.outline_size = 0
	text.position = Vector3(1.53, 1.2, 0.0)
	text.rotation.y = PI * 0.5
	shelter.add_child(text)
	Models.fit_label(text, Vector2(0.9, 1.4))
	Models.collider(shelter, Vector3(3.2, 2.5, 0.2), Vector3(0.0, 1.25, -0.5))
	Models.collider(shelter, Vector3(0.2, 2.5, 1.2), Vector3(1.5, 1.25, 0.0))
