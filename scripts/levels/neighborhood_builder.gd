@tool
class_name NeighborhoodBuilder
extends Node3D
## Procedural suburb south of the datacenter: a main road running north to the
## fence, two cross streets lined with houses, a park, and a construction site.
## Houses, parked cars, and tree trunks get static colliders (layer 1), so the
## navmesh routes around them. Deterministic via `layout_seed`.

@export var layout_seed := 7
@export var main_road_end_z := 104.0
@export var street_z: Array[float] = [30.0, 70.0]
@export var street_half_length := 76.0
@export var road_width := 8.0
## House x positions along each street side (mirrored across the main road).
@export var house_columns: Array[float] = [14.0, 30.0, 46.0, 62.0]
@export var house_setback := 14.0

const WALL_COLORS: Array[Color] = [
	Color(0.85, 0.8, 0.7), Color(0.72, 0.78, 0.82), Color(0.82, 0.72, 0.6),
	Color(0.7, 0.75, 0.62), Color(0.9, 0.88, 0.84), Color(0.78, 0.66, 0.66),
]
const ROOF_COLORS: Array[Color] = [
	Color(0.35, 0.2, 0.18), Color(0.25, 0.27, 0.3), Color(0.4, 0.3, 0.22), Color(0.3, 0.35, 0.28),
]
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

	var asphalt := Models.mat(Color(0.17, 0.17, 0.18), &"asphalt")
	var sidewalk := Models.mat(Color(0.55, 0.55, 0.52))
	var line := Models.mat(Color(0.85, 0.75, 0.3))

	# Main road (north-south, x = 0) from just south of the fence.
	var main_len := main_road_end_z + 10.0
	Models.box(self, Vector3(road_width, 0.04, main_len), Vector3(0.0, 0.02, main_road_end_z - main_len * 0.5), asphalt)
	for side in [-1.0, 1.0]:
		Models.box(self, Vector3(2.0, 0.06, main_len), Vector3(side * (road_width * 0.5 + 1.0), 0.03, main_road_end_z - main_len * 0.5), sidewalk)
	for z in range(-6, int(main_road_end_z), 6):
		Models.box(self, Vector3(0.15, 0.05, 3.0), Vector3(0.0, 0.035, z), line)

	for z: float in street_z:
		Models.box(self, Vector3(street_half_length * 2.0, 0.04, road_width), Vector3(0.0, 0.021, z), asphalt)
		for side in [-1.0, 1.0]:
			Models.box(self, Vector3(street_half_length * 2.0, 0.06, 2.0), Vector3(0.0, 0.03, z + side * (road_width * 0.5 + 1.0)), sidewalk)

	# Houses: both sides of the first street, the south side of the second.
	for i in street_z.size():
		var z: float = street_z[i]
		var sides: Array[float] = [1.0]
		if i == 0:
			sides.append(-1.0)
		for side: float in sides:
			for column: float in house_columns:
				for mirror in [-1.0, 1.0]:
					_add_house(Vector3(column * mirror, 0.0, z + side * house_setback), side)

	# Streetlights along the main road and the first street.
	for z in range(0, int(main_road_end_z), 16):
		if street_z.any(func(street: float) -> bool: return absf(z - street) < 7.0):
			continue  # keep intersections clear
		for side in [-1.0, 1.0]:
			var lamp := Models.streetlight()
			lamp.position = Vector3(side * (road_width * 0.5 + 1.6), 0.0, z)
			lamp.rotation.y = PI * 0.5 * side
			add_child(lamp)

	# Parked cars along the curb of the first street.
	for x in [-38.0, -22.0, 22.0, 54.0]:
		_add_parked_car(Vector3(x, 0.0, street_z[0] - road_width * 0.5 + 1.3), PI * 0.5)

	_build_park(Vector2(-64.0, -10.0), Vector2(street_z[1] - 18.0, street_z[1] - 6.0))
	_build_construction_site(Vector3(34.0, 0.0, street_z[1] - 12.0))

	# Street trees between houses.
	for z: float in [street_z[0] - 6.5, street_z[0] + 6.5]:
		for x in range(-70, 71, 16):
			if absf(x) > 8.0:
				_add_tree(Vector3(x, 0.0, z), _rng.randf_range(4.5, 6.0))


func _add_house(at: Vector3, facing_side: float) -> void:
	var size := Vector3(_rng.randf_range(9.0, 11.0), _rng.randf_range(4.2, 5.4), _rng.randf_range(7.5, 8.5))
	var body := StaticBody3D.new()
	body.position = at
	# Front door faces the street: +Z for houses north of it (side -1), -Z south.
	body.rotation.y = 0.0 if facing_side < 0.0 else PI
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = size.y * 0.5
	body.add_child(collider)
	var wall: Color = WALL_COLORS[_rng.randi() % WALL_COLORS.size()]
	var roof: Color = ROOF_COLORS[_rng.randi() % ROOF_COLORS.size()]
	body.add_child(Models.house(size, wall, roof, Color(0.95, 0.95, 0.92)))
	# Lawn and a mailbox out front.
	var front := Vector3(0.0, 0.0, size.z * 0.5 + 2.2).rotated(Vector3.UP, body.rotation.y)
	_doors.append(at + front + Vector3.UP * 0.2)
	var mailbox := Node3D.new()
	mailbox.position = at + Vector3(2.5, 0.0, 0.0).rotated(Vector3.UP, body.rotation.y) + front * 1.6
	add_child(mailbox)
	Models.box(mailbox, Vector3(0.08, 1.0, 0.08), Vector3(0.0, 0.5, 0.0), Models.mat(Color(0.3, 0.25, 0.2)))
	Models.box(mailbox, Vector3(0.25, 0.25, 0.45), Vector3(0.0, 1.05, 0.0), Models.mat(Color(0.2, 0.25, 0.5)))


func _add_parked_car(at: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.4, 4.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.8
	body.add_child(collider)
	body.add_child(Models.parked_car(CAR_COLORS[_rng.randi() % CAR_COLORS.size()]))


func _add_tree(at: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = at
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = height * 0.5
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = height * 0.25
	body.add_child(collider)
	body.add_child(Models.tree(height))


func _build_park(x_range: Vector2, z_range: Vector2) -> void:
	var center := Vector3((x_range.x + x_range.y) * 0.5, 0.0, (z_range.x + z_range.y) * 0.5)
	var size := Vector2(x_range.y - x_range.x, z_range.y - z_range.x)
	Models.box(self, Vector3(size.x, 0.03, size.y), center + Vector3.UP * 0.015, Models.mat(Color(0.3, 0.5, 0.25)))
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
	Models.box(self, Vector3(34.0, 0.03, 12.0), center + Vector3.UP * 0.015, Models.mat(Color(0.5, 0.42, 0.3)))
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
