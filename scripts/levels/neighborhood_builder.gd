@tool
class_name NeighborhoodBuilder
extends Node3D
## Procedural suburb south of the datacenter: a main road running north to the
## fence, two cross streets lined with houses, a park, and a construction site.
## Houses and tree trunks get static colliders (layer 1), so the
## navmesh routes around them. Deterministic via `layout_seed`.

@export var layout_seed := 7
@export var main_road_end_z := 148.0
@export var street_z: Array[float] = [30.0, 70.0, 110.0]
@export var street_half_length := 76.0
## The first street runs on out to the side datacenters' front gates.
@export var access_road_x := 121.0
@export var road_width := 8.0
## House x positions along each street side (mirrored across the main road).
@export var house_columns: Array[float] = [14.0, 30.0, 46.0, 62.0]
@export var house_setback := 14.0
## Empty lots (no house within `reserved_radius`): Harry's boardroom site.
@export var reserved_lots: Array[Vector3] = [Vector3(18.0, 0.0, 97.0)]
@export var reserved_radius := 13.0

const WALL_COLORS: Array[Color] = [
	Color(0.85, 0.8, 0.7), Color(0.72, 0.78, 0.82), Color(0.82, 0.72, 0.6),
	Color(0.7, 0.75, 0.62), Color(0.9, 0.88, 0.84), Color(0.78, 0.66, 0.66),
]
const ROOF_COLORS: Array[Color] = [
	Color(0.35, 0.2, 0.18), Color(0.25, 0.27, 0.3), Color(0.4, 0.3, 0.22), Color(0.3, 0.35, 0.28),
]
const KENNEY := "res://assets/kenney/"
## City Kit (Suburban) houses: 1 kit unit is about 8 m of street frontage.
const HOUSE_SCALE := 8.0
const HOUSE_TYPES := "abcdefghijklmnopqrstu"
const ROOF_VARIANTS := 5
## Kenney houses face +Z (door side); flip here if a kit update changes that.
const HOUSE_YAW := 0.0
const TREE_MODELS: Array[String] = ["tree_oak", "tree_default", "tree_detailed", "tree_fat", "tree_oak_dark", "tree_default_dark"]
const BUSH_MODELS: Array[String] = ["plant_bush", "plant_bushLarge", "plant_bushDetailed", "plant_bushSmall"]
const FLOWER_MODELS: Array[String] = ["flower_redA", "flower_yellowA", "flower_purpleA"]
const PARKED_CARS: Array[String] = ["sedan", "suv", "hatchback-sports", "taxi", "van", "suv-luxury"]
## Kenney Car Kit is about 1/1.45 real size.
const CAR_SCALE := 1.45
const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")

const CAR_COLORS: Array[Color] = [
	Color(0.7, 0.15, 0.15), Color(0.2, 0.3, 0.6), Color(0.85, 0.85, 0.8), Color(0.2, 0.2, 0.22),
]

var _doors: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	build()


## World positions just outside each front door (townspeople walk out of these).
func door_positions() -> Array[Vector3]:
	return _doors


func build() -> void:
	for child in get_children():
		child.queue_free()
	_doors.clear()
	_rng.seed = layout_seed

	var asphalt := Models.mat(Color(0.75, 0.75, 0.75), &"asphalt")
	var sidewalk := Models.mat(Color(0.92, 0.92, 0.9), &"concrete")
	var line := Models.mat(Color(0.85, 0.75, 0.3))

	# Main road (north-south, x = 0) from just south of the fence.
	var main_len := main_road_end_z + 10.0
	Models.box(self, Vector3(road_width, 0.04, main_len), Vector3(0.0, 0.02, main_road_end_z - main_len * 0.5), asphalt)
	for side in [-1.0, 1.0]:
		Models.box(self, Vector3(2.0, 0.06, main_len), Vector3(side * (road_width * 0.5 + 1.0), 0.03, main_road_end_z - main_len * 0.5), sidewalk)
	for z in range(-6, int(main_road_end_z), 6):
		Models.box(self, Vector3(0.15, 0.05, 3.0), Vector3(0.0, 0.035, z), line)

	for side in [-1.0, 1.0]:
		var reach := access_road_x - street_half_length
		Models.box(self, Vector3(reach, 0.04, road_width), Vector3(side * (street_half_length + reach * 0.5), 0.021, street_z[0]), asphalt)
	for z: float in street_z:
		Models.box(self, Vector3(street_half_length * 2.0, 0.04, road_width), Vector3(0.0, 0.021, z), asphalt)
		for side in [-1.0, 1.0]:
			Models.box(self, Vector3(street_half_length * 2.0, 0.06, 2.0), Vector3(0.0, 0.03, z + side * (road_width * 0.5 + 1.0)), sidewalk)

	# Houses: both sides of every street except the second, whose north side is
	# the park and the construction site. Reserved lots stay empty.
	for i in street_z.size():
		var z: float = street_z[i]
		var sides: Array[float] = [1.0]
		if i != 1:
			sides.append(-1.0)
		for side: float in sides:
			for column: float in house_columns:
				for mirror in [-1.0, 1.0]:
					var at := Vector3(column * mirror, 0.0, z + side * house_setback)
					if reserved_lots.any(func(lot: Vector3) -> bool: return lot.distance_to(at) < reserved_radius):
						continue
					_add_house(at, side)
	for lot in reserved_lots:
		_add_for_sale_sign(lot + Vector3(0.0, 0.0, 8.0))

	# Streetlights along the main road and the first street.
	for z in range(0, int(main_road_end_z), 16):
		if street_z.any(func(street: float) -> bool: return absf(z - street) < 7.0):
			continue  # keep intersections clear
		for side in [-1.0, 1.0]:
			var lamp := Models.streetlight()
			lamp.position = Vector3(side * (road_width * 0.5 + 1.6), 0.0, z)
			lamp.rotation.y = PI * 0.5 * side
			add_child(lamp)

	# Parked cars along the curbs of the first and third streets.
	for x in [-38.0, -22.0, 22.0, 54.0]:
		_add_parked_car(Vector3(x, 0.0, street_z[0] - road_width * 0.5 + 1.3), PI * 0.5)
	if street_z.size() > 2:
		for x in [-46.0, -14.0, 38.0]:
			_add_parked_car(Vector3(x, 0.0, street_z[2] + road_width * 0.5 - 1.3), -PI * 0.5)

	_build_park(Vector2(-64.0, -10.0), Vector2(street_z[1] - 18.0, street_z[1] - 6.0))
	_build_construction_site(Vector3(34.0, 0.0, street_z[1] - 12.0))

	# Street trees between houses.
	var tree_rows: Array[float] = [street_z[0] - 6.5, street_z[0] + 6.5]
	if street_z.size() > 2:
		tree_rows.append_array([street_z[2] - 6.5, street_z[2] + 6.5])
	for z: float in tree_rows:
		for x in range(-70, 71, 16):
			if absf(x) > 8.0:
				_add_tree(Vector3(x, 0.0, z), _rng.randf_range(4.5, 6.0))


func _add_house(at: Vector3, facing_side: float) -> void:
	var body := StaticBody3D.new()
	body.position = at
	# Front door faces the street: +Z for houses north of it (side -1), -Z south.
	body.rotation.y = (0.0 if facing_side < 0.0 else PI) + HOUSE_YAW
	add_child(body)

	var kind := HOUSE_TYPES[_rng.randi() % HOUSE_TYPES.length()]
	var house := Models.model("%ssuburban/building-type-%s.glb" % [KENNEY, kind], HOUSE_SCALE)
	body.add_child(house)
	var roof := _rng.randi() % (ROOF_VARIANTS + 1)
	if roof < ROOF_VARIANTS:  # the last pick keeps the kit's green roofs
		Models.retexture(house, load("%ssuburban/Textures/colormap_roof_%d.png" % [KENNEY, roof]))

	var bounds := Models.model_bounds(house)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	body.add_child(collider)

	# Path to the door, a couple of bushes, and a mailbox out front.
	var front_depth := bounds.end.z
	var front := Vector3(0.0, 0.0, front_depth + 2.2).rotated(Vector3.UP, body.rotation.y)
	_doors.append(at + front + Vector3.UP * 0.2)
	var path := Models.model(KENNEY + "suburban/path-long.glb", HOUSE_SCALE * 0.5)
	path.position = Vector3(0.0, 0.02, front_depth + 1.6)
	body.add_child(path)
	for side in [-1.0, 1.0]:
		var bush := Models.model("%snature/%s.glb" % [KENNEY, BUSH_MODELS[_rng.randi() % BUSH_MODELS.size()]], _rng.randf_range(2.5, 3.5))
		bush.position = Vector3(side * bounds.size.x * 0.32, 0.0, front_depth + 0.8)
		body.add_child(bush)
		if _rng.randf() < 0.5:
			var flower := Models.model("%snature/%s.glb" % [KENNEY, FLOWER_MODELS[_rng.randi() % FLOWER_MODELS.size()]], 3.0)
			flower.position = Vector3(side * bounds.size.x * 0.18, 0.0, front_depth + 1.2)
			body.add_child(flower)
	var mailbox := Node3D.new()
	mailbox.position = at + Vector3(2.5, 0.0, 0.0).rotated(Vector3.UP, body.rotation.y) + front * 1.35
	add_child(mailbox)
	Models.box(mailbox, Vector3(0.08, 1.0, 0.08), Vector3(0.0, 0.5, 0.0), Models.mat(Color(0.3, 0.25, 0.2)))
	Models.box(mailbox, Vector3(0.25, 0.25, 0.45), Vector3(0.0, 1.05, 0.0), Models.mat(Color(0.2, 0.25, 0.5), &"metal"))


## Parked cars are real, drivable Cars (keys in the ignition, this is a nice
## neighborhood). In the editor they're shown as plain models.
func _add_parked_car(at: Vector3, yaw: float) -> void:
	var path := "%scars/%s.glb" % [KENNEY, PARKED_CARS[_rng.randi() % PARKED_CARS.size()]]
	if Engine.is_editor_hint():
		var preview := Models.model(path, CAR_SCALE)
		preview.position = at
		preview.rotation.y = yaw
		add_child(preview)
		return
	var car := CAR_SCENE.instantiate() as Node3D
	car.set(&"model_path", path)
	car.set(&"model_scale", CAR_SCALE)
	car.set(&"model_offset", Vector3(0.0, 0.05, 0.0))
	car.set(&"fit_to_model", true)
	car.position = at + Vector3.UP * 0.3
	car.rotation.y = yaw
	add_child(car)


## "FOR SALE" sign on an empty lot (Perckerson Capital is buying up the block).
func _add_for_sale_sign(at: Vector3) -> void:
	var sign_root := Node3D.new()
	sign_root.position = at
	add_child(sign_root)
	var wood := Models.mat(Color(0.45, 0.32, 0.2))
	for x in [-0.7, 0.7]:
		Models.box(sign_root, Vector3(0.1, 1.6, 0.1), Vector3(x, 0.8, 0.0), wood)
	Models.box(sign_root, Vector3(1.8, 0.9, 0.06), Vector3(0.0, 1.3, 0.0), Models.mat(Color(0.95, 0.95, 0.92)))
	var text := Label3D.new()
	text.text = "SOLD\nPerckerson Capital"
	text.font_size = 48
	text.pixel_size = 0.006
	text.outline_size = 0
	text.modulate = Color(0.7, 0.1, 0.1)
	text.position = Vector3(0.0, 1.3, 0.04)
	sign_root.add_child(text)


func _add_tree(at: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = _rng.randf() * TAU
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = height * 0.5
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = height * 0.25
	body.add_child(collider)
	# Nature Kit trees are about 1.2 units tall.
	var tree := Models.model("%snature/%s.glb" % [KENNEY, TREE_MODELS[_rng.randi() % TREE_MODELS.size()]], height / 1.2)
	body.add_child(tree)


func _build_park(x_range: Vector2, z_range: Vector2) -> void:
	# The lawn itself is the regrowing ground shader; the park adds trees and benches.
	for i in 14:
		var spot := Vector3(_rng.randf_range(x_range.x + 2.0, x_range.y - 8.0), 0.0,
			_rng.randf_range(z_range.x + 1.5, z_range.y - 1.5))
		_add_tree(spot, _rng.randf_range(4.0, 7.0))
	# Benches.
	for x in [-50.0, -36.0, -24.0]:
		var bench := Node3D.new()
		bench.position = Vector3(x, 0.0, z_range.y - 1.0)
		add_child(bench)
		Models.box(bench, Vector3(1.8, 0.1, 0.5), Vector3(0.0, 0.45, 0.0), Models.mat(Color(0.45, 0.3, 0.2)))
		Models.box(bench, Vector3(1.8, 0.5, 0.08), Vector3(0.0, 0.75, 0.22), Models.mat(Color(0.45, 0.3, 0.2)))


func _build_construction_site(center: Vector3) -> void:
	Models.box(self, Vector3(34.0, 0.03, 12.0), center + Vector3.UP * 0.015, Models.mat(Color(0.95, 0.9, 0.85), &"dirt"))
	var orange := Models.mat(Color(1.0, 0.5, 0.1))
	for x in range(-16, 17, 4):
		Models.cone(self, 0.25, 0.7, center + Vector3(x, 0.35, -6.2), orange)  # traffic cones
	var pile := StaticBody3D.new()
	pile.position = center + Vector3(10.0, 0.0, 1.0)
	add_child(pile)
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 1.6, 3.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.8
	pile.add_child(collider)
	for i in 5:  # stacked lumber and pipe
		Models.box(pile, Vector3(6.0, 0.3, 0.6), Vector3(0.0, 0.15 + (i % 3) * 0.32, -1.0 + i * 0.5), Models.mat(Color(0.6, 0.45, 0.25)))
	Models.box(pile, Vector3(2.5, 1.6, 2.5), Vector3(-1.5, 0.8, 0.5), Models.mat(Color(0.4, 0.42, 0.45)))
