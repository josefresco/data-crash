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
## Empty lots zoned for affordable housing (the level puts a HousingSite on
## each; no house or SOLD sign here).
@export var housing_lots: Array[Vector3] = [Vector3(-62.0, 0.0, 124.0), Vector3(-46.0, 0.0, 124.0)]
## The street (index) whose north side is the park and the construction site
## instead of houses (-1: houses on both sides of every street).
@export var park_street := 1
## The park's x range, and the construction site's center (x, and z offset
## from the park street).
@export var park_x := Vector2(-64.0, -10.0)
@export var construction_site := Vector3(34.0, 0.0, -12.0)
## Cars parked along the curbs: (x, z, yaw). Keep them off the driveway
## mouths (6 m to one side of each house's center) and west of the main
## road: the blocks east of it carry the neighbors' traffic.
@export var parked_cars: Array[Vector3] = [Vector3(-34, 27.3, PI * 0.5), Vector3(-22, 27.3, PI * 0.5),
	Vector3(-50, 27.3, PI * 0.5), Vector3(-66, 27.3, PI * 0.5), Vector3(-46, 112.7, -PI * 0.5),
	Vector3(-14, 112.7, -PI * 0.5), Vector3(-30, 112.7, -PI * 0.5)]
## Streets (by index) lined with street trees.
@export var tree_streets: Array[int] = [0, 2]
## Names on the corner signs: one per cross street, and the main road's.
@export var street_names: Array[String] = ["FIRST ST", "SECOND ST", "THIRD ST"]
@export var main_street_name := "MAIN ST"
## Share of the driveways long enough for a car that have one parked in them.
@export_range(0.0, 1.0) var driveway_car_share := 0.4
@export_group("East side")
## Extra lot columns east of the main grid (not mirrored: the strip west of
## the houses stays open), on every street the avenue reaches.
@export var east_columns: Array[float] = [78.0, 94.0]
## A north-south avenue joining the cross streets at their east end, which
## turns the streets into blocks traffic can loop (0: none). It stops short
## of a river.
@export var east_avenue_x := 108.0
@export var avenue_name := "EAST AVE"
## Shops on the east lots, in the `store_lots` format.
@export var east_store_lots: Array = [
	[Vector3(78.0, 0.0, 16.0), "b", "BEAN THERE COFFEE", Color(0.75, 0.5, 0.3)],
	[Vector3(94.0, 0.0, 16.0), "e", "GREEN GROCER", Color(0.45, 0.85, 0.35)],
	[Vector3(78.0, 0.0, 44.0), "f", "RISE & SHINE BAKERY", Color(1.0, 0.8, 0.45)],
	[Vector3(94.0, 0.0, 44.0), "g", "TOOL & TIRE AUTO", Color(0.95, 0.35, 0.2)],
	[Vector3(78.0, 0.0, 84.0), "i", "LUCKY'S BARBER SHOP", Color(0.9, 0.9, 0.95)],
]
@export_group("River")
## A river along X at `river_z` (bed, reedy banks, a water surface that
## follows the water table, and bridges where the main road crosses). Lots,
## lights, trees, and parked cars inside it are skipped.
@export var has_river := false
@export var river_z := 90.0
@export var river_width := 18.0
@export var river_length := 420.0
## Whose river it is now, per the fishing pier's sign.
@export var river_owner := "THE COUNTY"
@export_group("")
## Shops on house lots: [lot position, Kenney commercial model letter, sign,
## sign color]. A WalkIn kind name in place of the letter ("gunstore",
## "hardware", "hospital", "library", "soupkitchen") builds a walk-in
## building with an interior instead (`walk_in(kind)`).
@export var store_lots: Array = [
	[Vector3(-14.0, 0.0, 16.0), "hardware", "DUECE HARDWARE", Color(0.9, 0.2, 0.15)],
	[Vector3(14.0, 0.0, 16.0), "h", "MABEL'S DINER", Color(0.2, 0.65, 0.95)],
	[Vector3(-30.0, 0.0, 16.0), "police", "POLICE", Color(0.25, 0.4, 1.0)],
	[Vector3(30.0, 0.0, 16.0), "c", "CORNER PHARMACY", Color(0.3, 0.85, 0.45)],
	[Vector3(-14.0, 0.0, 44.0), "a", "SUDS LAUNDROMAT", Color(0.5, 0.8, 1.0)],
	[Vector3(14.0, 0.0, 44.0), "d", "SLICE OF LIFE PIZZA", Color(1.0, 0.6, 0.15)],
	[Vector3(-30.0, 0.0, 44.0), "l", "TOWN HALL", Color(0.95, 0.82, 0.4)],
	[Vector3(-46.0, 0.0, 44.0), "gunstore", "TREY'S GUNS & AMMO", Color(0.95, 0.55, 0.15)],
	[Vector3(46.0, 0.0, 44.0), "hospital", "ST. MERCY HOSPITAL", Color(0.95, 0.25, 0.2)],
	[Vector3(-62.0, 0.0, 44.0), "library", "PUBLIC LIBRARY", Color(0.55, 0.75, 0.95)],
	[Vector3(62.0, 0.0, 44.0), "soupkitchen", "COMMUNITY SOUP KITCHEN", Color(0.5, 0.85, 0.45)],
	[Vector3(62.0, 0.0, 16.0), "firestation", "FIRE STATION 7", Color(0.95, 0.2, 0.15)],
]
## Kenney commercial kit: about 1 unit per floor width.
const STORE_SCALE := 9.0

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
## Driveways: the center's offset along the house front, and the slab's width.
const DRIVEWAY_OFFSET := 6.0
const DRIVEWAY_WIDTH := 2.8
## Curbs are visual only (no collider: cars and people cross them freely).
const CURB_WIDTH := 0.18
const CURB_HEIGHT := 0.12
## Center lines stop this far from an intersection's middle.
const CROSSING_CLEAR := 8.0

const CAR_COLORS: Array[Color] = [
	Color(0.7, 0.15, 0.15), Color(0.2, 0.3, 0.6), Color(0.85, 0.85, 0.8), Color(0.2, 0.2, 0.22),
]

var _doors: Array[Vector3] = []
## [door position, outward direction] per house (not stores).
var _house_doors: Array = []
## Sign text -> the spot just outside that store's door.
var _store_doors := {}
## WalkIn kind -> [the building's transform (this node's space), sign text].
var _walk_ins := {}
## Footprints on the ground plane (x, z) for the minimap: [Rect2, is_store].
var _footprints: Array = []
var _rng := RandomNumberGenerator.new()
var _river: River
## Dressing picks (yard signs, river litter) draw from their own stream so
## adding them never shifts the houses, trees, and cars `_rng` lays out.
var _decor_rng := RandomNumberGenerator.new()
## Driveway picks (which have a car, which way it faces): a third stream, for
## the same reason.
var _lot_rng := RandomNumberGenerator.new()
## The east side's houses and trees draw from their own stream too.
var _east_rng := RandomNumberGenerator.new()
## Where each driveway meets the street (this node's space): the curb drops there.
var _curb_cuts: Array[Vector3] = []
## [position, yaw] of the cars parked in driveways.
var _driveway_cars: Array = []
const YARD_SIGNS := ["NO DATACENTERS\nIN OUR BACKYARD", "SAVE OUR\nWATER", "HONK FOR\nCLEAN AIR",
	"THIS FAMILY\nSUPPORTS TAPS", "UNPLUG\nTHE FARM"]


func _ready() -> void:
	build()


## World positions just outside each front door (townspeople walk out of these).
func door_positions() -> Array[Vector3]:
	return _doors


## The house door nearest `near` and its outward direction: [position, facing].
func home_spot(near: Vector3) -> Array:
	var best: Array = []
	for entry: Array in _house_doors:
		if best.is_empty() or (entry[0] as Vector3).distance_to(near) < (best[0] as Vector3).distance_to(near):
			best = entry
	return best


## [door position, outward direction] for every house (not stores).
func house_doors() -> Array:
	return _house_doors


## Where a car is parked in a driveway (this node's space).
func driveway_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for entry: Array in _driveway_cars:
		spots.append(entry[0])
	return spots


## Building footprints for the minimap: [Rect2 (x, z), is_store] pairs.
func footprints() -> Array:
	return _footprints


func _record_footprint(body: Node3D, bounds: AABB, is_store: bool) -> void:
	var center := body.position + bounds.get_center().rotated(Vector3.UP, body.rotation.y)
	var extent := Vector2(bounds.size.x, bounds.size.z)
	_footprints.append([Rect2(Vector2(center.x, center.z) - extent * 0.5, extent), is_store])


## True when `point` (this node's space) is in the river, grown by `margin`.
func in_river(point: Vector3, margin := 0.0) -> bool:
	return has_river and absf(point.z - river_z) <= river_width * 0.5 + margin


func river() -> River:
	return _river


## A walk-in building by WalkIn kind: its transform in this node's space
## (origin at the lot center, +Z out the front door), or null.
func walk_in(kind: String) -> Variant:
	return (_walk_ins[kind] as Array)[0] if _walk_ins.has(kind) else null


## The sign text of the walk-in of `kind` ("" if there is none).
func walk_in_sign(kind: String) -> String:
	return (_walk_ins[kind] as Array)[1] if _walk_ins.has(kind) else ""


## Just outside a store's door (by its sign text), in this node's space.
func store_door(sign_text: String) -> Vector3:
	return _store_doors.get(sign_text, Vector3.ZERO)


func build() -> void:
	for child in get_children():
		child.queue_free()
	_doors.clear()
	_house_doors.clear()
	_store_doors.clear()
	_walk_ins.clear()
	_footprints.clear()
	_curb_cuts.clear()
	_driveway_cars.clear()
	_rng.seed = layout_seed
	_decor_rng.seed = layout_seed * 31 + 5
	_lot_rng.seed = layout_seed * 53 + 11
	_east_rng.seed = layout_seed * 71 + 29

	var asphalt := Models.mat(Color(0.75, 0.75, 0.75), &"asphalt")
	var sidewalk := Models.mat(Color(0.92, 0.92, 0.9), &"sidewalk")
	var line := Models.mat(Color(0.85, 0.75, 0.3))
	var half_road := road_width * 0.5

	# Main road (north-south, x = 0) from just south of the fence. Sidewalks
	# and curbs stop at the cross streets instead of running over them.
	var main_len := main_road_end_z + 10.0
	Models.box(self, Vector3(road_width, 0.04, main_len), Vector3(0.0, 0.02, main_road_end_z - main_len * 0.5), asphalt)
	var street_cuts: Array[Vector2] = []
	var corner_cuts: Array[Vector2] = []
	for z: float in street_z:
		street_cuts.append(Vector2(z, half_road))
		corner_cuts.append(Vector2(z, half_road + 2.0))
	for side in [-1.0, 1.0]:
		for span in _spans(-10.0, main_road_end_z, street_cuts):
			Models.box(self, Vector3(2.0, 0.06, span.y - span.x), Vector3(side * (half_road + 1.0), 0.03, (span.x + span.y) * 0.5), sidewalk)
		for span in _spans(-10.0, main_road_end_z, corner_cuts):
			Models.box(self, Vector3(CURB_WIDTH, CURB_HEIGHT, span.y - span.x),
				Vector3(side * (half_road + CURB_WIDTH * 0.5), CURB_HEIGHT * 0.5, (span.x + span.y) * 0.5), _curb_material())
	for z in range(-6, int(main_road_end_z), 6):
		if street_z.any(func(street: float) -> bool: return absf(z - street) < CROSSING_CLEAR):
			continue  # no center line through the intersections
		Models.box(self, Vector3(0.15, 0.05, 3.0), Vector3(0.0, 0.035, z), line)

	for side in [-1.0, 1.0]:
		var reach := access_road_x - street_half_length
		Models.box(self, Vector3(reach, 0.04, road_width), Vector3(side * (street_half_length + reach * 0.5), 0.021, street_z[0]), asphalt)
	var avenue := avenue_streets()
	for i in street_z.size():
		var z: float = street_z[i]
		Models.box(self, Vector3(street_half_length * 2.0, 0.04, road_width), Vector3(0.0, 0.021, z), asphalt)
		if i > 0 and i in avenue:
			# On out to the avenue (the first street already runs to the gates).
			var far := east_avenue_x + half_road
			Models.box(self, Vector3(far - street_half_length, 0.04, road_width), Vector3((far + street_half_length) * 0.5, 0.021, z), asphalt)
		for side in [-1.0, 1.0]:
			for span in _spans(-street_half_length, street_east_end(i), [Vector2(0.0, half_road + 2.0)]):
				Models.box(self, Vector3(span.y - span.x, 0.06, 2.0), Vector3((span.x + span.y) * 0.5, 0.03, z + side * (half_road + 1.0)), sidewalk)
		# Center line (the first street's runs on out to the side gates).
		var west_reach := access_road_x if i == 0 else street_half_length
		var east_reach := access_road_x if i == 0 else (east_avenue_x - 4.0 if i in avenue else street_half_length)
		for x in range(-int(west_reach) + 4, int(east_reach) - 3, 6):
			if absf(x) < CROSSING_CLEAR or (i in avenue and absf(x - east_avenue_x) < CROSSING_CLEAR):
				continue
			Models.box(self, Vector3(3.0, 0.05, 0.15), Vector3(x, 0.036, z), line)
		_build_intersection(i)
	if not avenue.is_empty():
		_build_avenue(avenue)

	# Houses: both sides of every street except the second, whose north side is
	# the park and the construction site. Reserved lots stay empty.
	for i in street_z.size():
		var z: float = street_z[i]
		var sides: Array[float] = [1.0]
		if i != park_street:
			sides.append(-1.0)
		for side: float in sides:
			for column: float in house_columns:
				for mirror in [-1.0, 1.0]:
					var at := Vector3(column * mirror, 0.0, z + side * house_setback)
					if reserved_lots.any(func(lot: Vector3) -> bool: return lot.distance_to(at) < reserved_radius):
						continue
					if housing_lots.any(func(lot: Vector3) -> bool: return lot.distance_to(at) < 2.0):
						continue
					if in_river(at, 8.0):
						continue
					var store := _store_at(at)
					if store.is_empty():
						_add_house(at, side)
					else:
						_add_store(at, side, store)
	for lot in reserved_lots:
		_add_for_sale_sign(lot + Vector3(0.0, 0.0, 8.0))

	# The east side, from its own stream so the main grid's picks never move.
	var grid_rng := _rng
	_rng = _east_rng
	for i: int in avenue:
		var z: float = street_z[i]
		var sides: Array[float] = [1.0]
		if i != park_street:
			sides.append(-1.0)
		for side: float in sides:
			for column: float in east_columns:
				var at := Vector3(column, 0.0, z + side * house_setback)
				if in_river(at, 8.0) or reserved_lots.any(func(lot: Vector3) -> bool: return lot.distance_to(at) < reserved_radius):
					continue
				var store := _store_at(at)
				if store.is_empty():
					_add_house(at, side)
				else:
					_add_store(at, side, store)
			if i in tree_streets:
				for x in range(74, int(street_east_end(i)) - 4, 16):
					var spot := Vector3(x, 0.0, z + side * 6.5)
					if not in_river(spot, 2.0):
						_add_tree(spot, _rng.randf_range(4.5, 6.0))
	_rng = grid_rng

	# Curbs along the cross streets, dropped at the corners and every driveway.
	for z: float in street_z:
		for side: float in [-1.0, 1.0]:
			var cuts: Array[Vector2] = [Vector2(0.0, half_road + 2.0)]
			for mouth in _curb_cuts:
				if absf(mouth.z - (z + side * house_setback)) < 1.0:
					cuts.append(Vector2(mouth.x, DRIVEWAY_WIDTH * 0.5 + 0.2))
			for span in _spans(-street_half_length, street_east_end(street_z.find(z)), cuts):
				Models.box(self, Vector3(span.y - span.x, CURB_HEIGHT, CURB_WIDTH),
					Vector3((span.x + span.y) * 0.5, CURB_HEIGHT * 0.5, z + side * (half_road + CURB_WIDTH * 0.5)), _curb_material())

	# Streetlights along the main road and the first street.
	for z in range(0, int(main_road_end_z), 16):
		if street_z.any(func(street: float) -> bool: return absf(z - street) < 7.0):
			continue  # keep intersections clear
		if in_river(Vector3(0.0, 0.0, z), 3.0):
			continue
		for side in [-1.0, 1.0]:
			var lamp := Models.streetlight()
			lamp.position = Vector3(side * (road_width * 0.5 + 1.6), 0.0, z)
			lamp.rotation.y = PI * 0.5 * side
			add_child(lamp)

	# Parked cars along the curbs.
	for car in parked_cars:
		if not in_river(Vector3(car.x, 0.0, car.y), 2.0):
			_add_parked_car(Vector3(car.x, 0.0, car.y), car.z)

	if park_street >= 0 and park_street < street_z.size():
		var park_z: float = street_z[park_street]
		_build_park(park_x, Vector2(park_z - 18.0, park_z - 6.0))
		_build_construction_site(Vector3(construction_site.x, 0.0, park_z + construction_site.z))

	# Street trees between houses.
	var tree_rows: Array[float] = []
	for index in tree_streets:
		if index < street_z.size():
			tree_rows.append_array([street_z[index] - 6.5, street_z[index] + 6.5])
	for z: float in tree_rows:
		for x in range(-70, 71, 16):
			if absf(x) > 8.0 and not in_river(Vector3(x, 0.0, z), 2.0):
				_add_tree(Vector3(x, 0.0, z), _rng.randf_range(4.5, 6.0))
	if has_river:
		_build_river()
	# Last, so the cars' model picks never shift the layout drawn from `_rng`.
	for entry: Array in _driveway_cars:
		_add_parked_car(entry[0], entry[1])
	if not Engine.is_editor_hint():
		_batch_details()


## The parts of `from`..`to` left after removing `cuts` ([center, half
## width] each): [start, end] pairs.
func _spans(from: float, to: float, cuts: Array[Vector2]) -> Array[Vector2]:
	var sorted := cuts.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var spans: Array[Vector2] = []
	var at := from
	for cut: Vector2 in sorted:
		var low := minf(cut.x - cut.y, to)
		if low - at > 0.3:
			spans.append(Vector2(at, low))
		at = maxf(at, cut.x + cut.y)
	if to - at > 0.3:
		spans.append(Vector2(at, to))
	return spans


func _curb_material() -> StandardMaterial3D:
	return Models.mat(Color(0.8, 0.8, 0.78), &"concrete")


## Where cross street `index` meets the main road: zebra crossings on all four
## sides, stop lines and stop signs for the cross street (the main road has
## the right of way), and a street-name sign on the corner.
func _build_intersection(index: int) -> void:
	var z: float = street_z[index]
	var half_road := road_width * 0.5
	var paint := Models.mat(Color(0.9, 0.9, 0.88))
	var bars := int(road_width / 0.9)
	for side: float in [-1.0, 1.0]:
		for k in bars:
			var across := -half_road + 0.45 + k * 0.9
			# Over the main road (north and south), then over the cross street.
			Models.box(self, Vector3(0.45, 0.05, 2.0), Vector3(across, 0.037, z + side * (half_road + 1.0)), paint)
			Models.box(self, Vector3(2.0, 0.05, 0.45), Vector3(side * (half_road + 1.0), 0.037, z + across), paint)
		# Traffic keeps right: the lane heading for the crossing from +X is the
		# north one (-Z), and its stop sign stands on the driver's right.
		Models.box(self, Vector3(0.4, 0.05, half_road - 0.4), Vector3(side * (half_road + 2.8), 0.037, z - side * half_road * 0.5), paint)
		_add_stop_sign(Vector3(side * (half_road + 3.0), 0.0, z - side * (half_road + 2.3)), side * PI * 0.5)
	_add_street_sign(Vector3(half_road + 2.4, 0.0, z + half_road + 2.4), _street_name(index), main_street_name)


func _street_name(index: int) -> String:
	return street_names[index] if index < street_names.size() else "%d ST" % (index + 1)


## The east avenue between the first and last of `joined` (street indices):
## asphalt, a center line, sidewalks and curbs, corner signs, and stop signs.
## The first street runs through (the avenue stops for it); every other
## street stops for the avenue.
func _build_avenue(joined: Array[int]) -> void:
	var half_road := road_width * 0.5
	var x := east_avenue_x
	var north: float = street_z[joined[0]]
	var south: float = street_z[joined[-1]]
	var paint := Models.mat(Color(0.9, 0.9, 0.88))
	var walk := Models.mat(Color(0.92, 0.92, 0.9), &"sidewalk")
	Models.box(self, Vector3(road_width, 0.04, south - north + road_width), Vector3(x, 0.02, (north + south) * 0.5), Models.mat(Color(0.75, 0.75, 0.75), &"asphalt"))
	for z in range(int(north) + 8, int(south) - 7, 6):
		if not joined.any(func(i: int) -> bool: return absf(z - street_z[i]) < CROSSING_CLEAR):
			Models.box(self, Vector3(0.15, 0.05, 3.0), Vector3(x, 0.035, z), Models.mat(Color(0.85, 0.75, 0.3)))
	# West side: broken at every street. East side: only the first runs through.
	var west_cuts: Array[Vector2] = []
	var west_corners: Array[Vector2] = []
	for i: int in joined:
		west_cuts.append(Vector2(street_z[i], half_road))
		west_corners.append(Vector2(street_z[i], half_road + 2.0))
	var east_cuts: Array[Vector2] = [Vector2(north, half_road)]
	var east_corners: Array[Vector2] = [Vector2(north, half_road + 2.0)]
	var sides := [[-1.0, west_cuts, west_corners], [1.0, east_cuts, east_corners]]
	for entry: Array in sides:
		var side: float = entry[0]
		var walk_cuts: Array[Vector2] = entry[1]
		var curb_cuts: Array[Vector2] = entry[2]
		for span in _spans(north - half_road - 2.0, south + half_road + 2.0, walk_cuts):
			Models.box(self, Vector3(2.0, 0.06, span.y - span.x), Vector3(x + side * (half_road + 1.0), 0.03, (span.x + span.y) * 0.5), walk)
		for span in _spans(north - half_road - 2.0, south + half_road + 2.0, curb_cuts):
			Models.box(self, Vector3(CURB_WIDTH, CURB_HEIGHT, span.y - span.x),
				Vector3(x + side * (half_road + CURB_WIDTH * 0.5), CURB_HEIGHT * 0.5, (span.x + span.y) * 0.5), _curb_material())
	# The last street's far sidewalk carries on around the avenue's south end.
	Models.box(self, Vector3(road_width + 2.0, 0.06, 2.0), Vector3(x + 1.0, 0.03, south + half_road + 1.0), walk)
	for i: int in joined:
		var z: float = street_z[i]
		_add_street_sign(Vector3(x - half_road - 2.4, 0.0, z - half_road - 2.4), _street_name(i), avenue_name)
		if i == joined[0]:
			# Northbound (the east lane) stops for the first street.
			Models.box(self, Vector3(half_road - 0.4, 0.05, 0.4), Vector3(x + half_road * 0.5, 0.037, z + half_road + 2.8), paint)
			_add_stop_sign(Vector3(x + half_road + 2.3, 0.0, z + half_road + 3.0), 0.0)
		else:
			# Eastbound (the south lane) stops for the avenue.
			Models.box(self, Vector3(0.4, 0.05, half_road - 0.4), Vector3(x - half_road - 2.8, 0.037, z + half_road * 0.5), paint)
			_add_stop_sign(Vector3(x - half_road - 3.0, 0.0, z + half_road + 2.3), -PI * 0.5)


## A stop sign facing local +Z. Knock-over: a car that cuts the corner
## flattens it instead of stopping dead.
func _add_stop_sign(at: Vector3, yaw: float) -> void:
	var root := _prop_root(at, yaw)
	Models.cylinder(root, 0.04, 2.5, Vector3(0.0, 1.25, 0.0), Models.mat(Color(0.55, 0.56, 0.58), &"metal"), 6)
	var face := Models.cylinder(root, 0.4, 0.03, Vector3(0.0, 2.2, 0.06), Models.mat(Color(0.8, 0.1, 0.08), &"paint"), 8)
	# An octagon on edge, flat side up.
	face.basis = Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI / 8.0)
	var text := Label3D.new()
	text.text = "STOP"
	text.font_size = 48
	text.pixel_size = 0.005
	text.outline_size = 0
	text.position = Vector3(0.0, 2.2, 0.08)
	Models.fit_label(text, Vector2(0.66, 0.3))
	root.add_child(text)
	_prop_done(root)


## A corner post with a blade for the cross street and one for the main road.
func _add_street_sign(at: Vector3, cross_name: String, other_name: String) -> void:
	var root := _prop_root(at)
	Models.cylinder(root, 0.04, 3.1, Vector3(0.0, 1.55, 0.0), Models.mat(Color(0.55, 0.56, 0.58), &"metal"), 6)
	var blades := [[cross_name, 2.75, 0.0], [other_name, 3.0, PI * 0.5]]
	for entry: Array in blades:
		var blade := Node3D.new()
		blade.position = Vector3(0.0, entry[1], 0.0)
		blade.rotation.y = entry[2]
		root.add_child(blade)
		Models.box(blade, Vector3(1.4, 0.24, 0.03), Vector3.ZERO, Models.mat(Color(0.1, 0.4, 0.22), &"paint"))
		for face: float in [1.0, -1.0]:
			var text := Label3D.new()
			text.text = entry[0]
			text.font_size = 48
			text.pixel_size = 0.005
			text.outline_size = 0
			text.position = Vector3(0.0, 0.0, face * 0.02)
			text.rotation.y = 0.0 if face > 0.0 else PI
			Models.fit_label(text, Vector2(1.4, 0.24))
			blade.add_child(text)
	_prop_done(root)


## A root for a small prop: a Knockable at runtime (vehicles and blasts send
## it flying), a plain node in the editor preview. Call `_prop_done()` once
## its parts are in.
func _prop_root(at: Vector3, yaw := 0.0) -> Node3D:
	var root: Node3D = Node3D.new() if Engine.is_editor_hint() else Knockable.new()
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	return root


func _prop_done(root: Node3D) -> void:
	if root is Knockable:
		(root as Knockable).finish()


## Draw calls: each house, store, and tree lot (a static body) bakes its
## model, path, bushes, and flowers into a few meshes; roads, markings,
## mailboxes, and streetlight poles merge into the builder's own mesh.
func _batch_details() -> void:
	for child in get_children():
		if child is StaticBody3D and child.get_script() == null:
			Models.merge_static(child as Node3D)
	Models.merge_static(self, [_river] if _river else [])


## Every shop lot: the main grid's and the east side's.
func all_store_lots() -> Array:
	return store_lots + east_store_lots


## The cross streets (by index) the east avenue joins: from the first street
## south, stopping at a river.
func avenue_streets() -> Array[int]:
	var joined: Array[int] = []
	if east_avenue_x <= 0.0:
		return joined
	for i in street_z.size():
		if has_river and street_z[i] > river_z - river_width * 0.5:
			break
		joined.append(i)
	if joined.size() < 2:
		joined.clear()
	return joined


## Where cross street `index`'s sidewalks end in the east: at the avenue's
## sidewalk if it joins the avenue.
func street_east_end(index: int) -> float:
	if index in avenue_streets():
		return east_avenue_x - road_width * 0.5 - 2.0
	return street_half_length


func _store_at(at: Vector3) -> Array:
	for lot: Array in all_store_lots():
		if (lot[0] as Vector3).distance_to(at) < 2.0:
			return lot
	return []


## A Kenney commercial building with a lit sign board over the storefront.
func _add_store(at: Vector3, facing_side: float, lot: Array) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = 0.0 if facing_side < 0.0 else PI
	add_child(body)
	var color: Color = lot[3]
	var bounds: AABB
	var board_y := 4.6
	var board_width := 10.0
	if WalkIn.is_walk_in(lot[1]):
		bounds = WalkIn.build(body, lot[1], color)
		board_y = WalkIn.sign_height(lot[1])
		board_width = bounds.size.x * 0.5
		_walk_ins[lot[1]] = [body.transform, lot[2]]
	else:
		var building := Models.model("%scommercial/building-%s.glb" % [KENNEY, lot[1]], STORE_SCALE)
		body.add_child(building)
		Models.wall_detail(building, 3.0)
		bounds = Models.model_bounds(building)
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = bounds.get_center()
		body.add_child(collider)
	_record_footprint(body, bounds, true)
	var front := bounds.end.z
	board_width = minf(bounds.size.x * 0.8, board_width)
	var board := Models.box(body, Vector3(board_width, 1.3, 0.25), Vector3(0.0, board_y, front + 0.2),
		Models.mat(Color(0.1, 0.1, 0.12), &"paint"))
	Models.box(board, Vector3(board_width + 0.1, 0.08, 0.3), Vector3(0.0, -0.66, 0.0), Models.glow(color, 2.5))
	var text := Label3D.new()
	text.text = lot[2]
	text.font_size = 96
	text.pixel_size = 0.009
	text.outline_size = 0
	text.modulate = color.lerp(Color.WHITE, 0.35)
	text.position = Vector3(0.0, 0.0, 0.14)
	Models.fit_label(text, Vector2(board_width, 1.3))
	board.add_child(text)
	var door := at + Vector3(0.0, 0.0, front + 3.0).rotated(Vector3.UP, body.rotation.y) + Vector3.UP * 0.2
	_doors.append(door)
	_store_doors[lot[2]] = door
	if lot[2] == "TOWN HALL":
		_dress_town_hall(body, bounds)


## Civic front for the Town Hall: white columns under a pediment, steps, and
## a flagpole, so it reads apart from the shops.
func _dress_town_hall(body: Node3D, bounds: AABB) -> void:
	var front := bounds.end.z
	var marble := Models.mat(Color(0.93, 0.92, 0.88), &"concrete")
	var width := minf(bounds.size.x * 0.8, 11.0)
	for k in 6:
		var x := -width * 0.5 + 0.4 + k * (width - 0.8) / 5.0
		Models.cylinder(body, 0.28, 3.6, Vector3(x, 1.9, front + 1.4), marble, 12)
	Models.box(body, Vector3(width + 0.6, 0.5, 2.2), Vector3(0.0, 3.95, front + 1.1), marble)
	# Triangular prism across the facade (extrude runs along X; the profile is (z, y)).
	Models.extrude(body, PackedVector2Array([Vector2(-1.1, 0.0), Vector2(1.1, 0.0), Vector2(0.0, 1.2)]),
		width + 0.6, marble, Vector3(0.0, 4.2, front + 1.1))
	for step in 3:
		Models.box(body, Vector3(width + 0.4 - step * 0.4, 0.15, 2.6 - step * 0.5),
			Vector3(0.0, 0.075 + step * 0.15, front + 1.3 - step * 0.1), marble)
	Models.collider(body, Vector3(width + 0.6, 4.2, 2.2), Vector3(0.0, 2.1, front + 1.1))
	var pole := Vector3(width * 0.5 + 2.0, 0.0, front + 3.0)
	Models.cylinder(body, 0.07, 8.0, pole + Vector3.UP * 4.0, Models.mat(Color(0.8, 0.8, 0.82), &"metal"), 8)
	Models.collider(body, Vector3(0.25, 8.0, 0.25), pole + Vector3.UP * 4.0)
	Models.box(body, Vector3(1.6, 1.0, 0.04), pole + Vector3(0.85, 7.3, 0.0), Models.mat(Color(0.25, 0.6, 0.35), &"cloth"))


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
	Models.wall_detail(house)

	var bounds := Models.model_bounds(house)
	_record_footprint(body, bounds, false)
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
	_house_doors.append([at + front + Vector3.UP * 0.2, front.normalized()])
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
	var mailbox := _prop_root(at + Vector3(2.5, 0.0, 0.0).rotated(Vector3.UP, body.rotation.y) + front * 1.35)
	Models.box(mailbox, Vector3(0.08, 1.0, 0.08), Vector3(0.0, 0.5, 0.0), Models.mat(Color(0.3, 0.25, 0.2)))
	Models.box(mailbox, Vector3(0.25, 0.25, 0.45), Vector3(0.0, 1.05, 0.0), Models.mat(Color(0.2, 0.25, 0.5), &"metal"))
	Models.collider(mailbox, Vector3(0.3, 1.2, 0.5), Vector3(0.0, 0.6, 0.0))
	_prop_done(mailbox)
	if _decor_rng.randf() < 0.35:
		_add_yard_sign(at + Vector3(-2.6, 0.0, 0.0).rotated(Vector3.UP, body.rotation.y) + front * 1.3, body.rotation.y)

	# A concrete driveway from the house front to the sidewalk, on the side
	# away from the bins and between the street trees; the corner lots keep
	# theirs away from the main road. A shallow front yard has room for a car.
	var drive_x := DRIVEWAY_OFFSET
	var mouth_x := at.x + drive_x * cos(body.rotation.y)
	if absf(mouth_x) < 10.0 or (east_avenue_x > 0.0 and absf(mouth_x - east_avenue_x) < 10.0):
		drive_x = -drive_x
	var drive_from := front_depth + 0.15
	var drive_to := house_setback - road_width * 0.5 - 2.0
	Models.box(body, Vector3(DRIVEWAY_WIDTH, 0.05, drive_to - drive_from),
		Vector3(drive_x, 0.025, (drive_from + drive_to) * 0.5), Models.mat(Color(0.78, 0.78, 0.76), &"concrete"))
	_curb_cuts.append(at + Vector3(drive_x, 0.0, 0.0).rotated(Vector3.UP, body.rotation.y))
	var parks := _lot_rng.randf() < driveway_car_share
	var nose_in := _lot_rng.randf() < 0.5
	if parks and drive_to - drive_from >= 3.7:
		var spot := at + Vector3(drive_x, 0.0, drive_from + 2.05).rotated(Vector3.UP, body.rotation.y)
		_driveway_cars.append([spot, body.rotation.y + (PI if nose_in else 0.0)])


## A hand-lettered protest sign on a stake in the front lawn.
func _add_yard_sign(at: Vector3, yaw: float) -> void:
	var stake := _prop_root(at, yaw + _decor_rng.randf_range(-0.25, 0.25))
	Models.box(stake, Vector3(0.05, 0.9, 0.05), Vector3(0.0, 0.45, 0.0), Models.mat(Color(0.45, 0.32, 0.2)))
	var colors: Array[Color] = [Color(0.96, 0.95, 0.9), Color(0.98, 0.85, 0.3), Color(0.55, 0.8, 0.95)]
	Models.box(stake, Vector3(0.9, 0.6, 0.03), Vector3(0.0, 1.05, 0.0), Models.mat(colors[_decor_rng.randi() % colors.size()], &"paint"))
	var label := Label3D.new()
	label.text = YARD_SIGNS[_decor_rng.randi() % YARD_SIGNS.size()]
	label.modulate = Color(0.1, 0.1, 0.12)
	label.outline_size = 0
	label.position = Vector3(0.0, 1.05, 0.02)
	stake.add_child(label)
	Models.fit_label(label, Vector2(0.84, 0.54))
	_prop_done(stake)


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
	var wood := Models.mat(Color(0.62, 0.5, 0.4), &"wood")
	for x in [-0.7, 0.7]:
		Models.box(sign_root, Vector3(0.1, 1.6, 0.1), Vector3(x, 0.8, 0.0), wood)
	Models.box(sign_root, Vector3(1.8, 0.9, 0.06), Vector3(0.0, 1.3, 0.0), Models.mat(Color(0.95, 0.95, 0.92)))
	Models.collider(sign_root, Vector3(1.9, 1.8, 0.2), Vector3(0.0, 0.9, 0.0))
	var text := Label3D.new()
	text.text = "SOLD\nPerckerson Capital"
	text.font_size = 48
	text.pixel_size = 0.006
	text.outline_size = 0
	text.modulate = Color(0.7, 0.1, 0.1)
	text.position = Vector3(0.0, 1.3, 0.04)
	Models.fit_label(text, Vector2(1.8, 0.9))
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
	for x in [x_range.x + 14.0, x_range.x + 28.0, x_range.x + 40.0]:
		var bench := _prop_root(Vector3(x, 0.0, z_range.y - 1.0))
		Models.box(bench, Vector3(1.8, 0.1, 0.5), Vector3(0.0, 0.45, 0.0), Models.mat(Color(0.45, 0.3, 0.2)))
		Models.box(bench, Vector3(1.8, 0.5, 0.08), Vector3(0.0, 0.75, 0.22), Models.mat(Color(0.45, 0.3, 0.2)))
		Models.collider(bench, Vector3(1.9, 1.0, 0.6), Vector3(0.0, 0.5, 0.05))
		_prop_done(bench)


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
		Models.box(pile, Vector3(6.0, 0.3, 0.6), Vector3(0.0, 0.15 + (i % 3) * 0.32, -1.0 + i * 0.5), Models.mat(Color(0.85, 0.75, 0.6), &"wood"))
	Models.box(pile, Vector3(2.5, 1.6, 2.5), Vector3(-1.5, 0.8, 0.5), Models.mat(Color(0.8, 0.8, 0.8), &"gravel"))


## The riverbed (dark mud), reeds and rocks along the banks, a bridge where
## the main road crosses, and the River node (the water).
func _build_river() -> void:
	var bed := ShaderMaterial.new()
	bed.shader = preload("res://shaders/riverbed.gdshader")
	bed.set_shader_parameter(&"mud_color", preload("res://assets/generated/mud_color.png"))
	bed.set_shader_parameter(&"mud_normal", preload("res://assets/generated/mud_normal.png"))
	var bank := Models.mat(Color(0.45, 0.38, 0.28), &"dirt")
	Models.box(self, Vector3(river_length, 0.02, river_width), Vector3(0.0, 0.012, river_z), bed)
	for side in [-1.0, 1.0]:
		Models.box(self, Vector3(river_length, 0.03, 2.0), Vector3(0.0, 0.015, river_z + side * (river_width * 0.5 + 1.0)), bank)
	# Reeds and rocks along both banks.
	var reed := Models.mat(Color(0.35, 0.45, 0.2), &"grass")
	var stone := Models.mat(Color(0.45, 0.45, 0.43), &"rough")
	for i in 90:
		var x := _rng.randf_range(-river_length * 0.5, river_length * 0.5)
		if absf(x) < road_width * 0.5 + 4.0:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var z := river_z + side * (river_width * 0.5 + _rng.randf_range(-1.5, 0.8))
		if _rng.randf() < 0.65:
			for k in 4:
				var tall := _rng.randf_range(0.7, 1.4)
				Models.box(self, Vector3(0.05, tall, 0.05), Vector3(x + _rng.randf_range(-0.4, 0.4), tall * 0.5, z + _rng.randf_range(-0.3, 0.3)), reed)
		else:
			Models.ball(self, _rng.randf_range(0.25, 0.6), Vector3(x, 0.1, z), stone)
	# The main road's bridge: concrete parapets and piers over the bed.
	var concrete := Models.mat(Color(0.7, 0.7, 0.68), &"concrete")
	var span := river_width + 6.0
	for side in [-1.0, 1.0]:
		var x: float = side * (road_width * 0.5 + 1.8)
		Models.box(self, Vector3(0.4, 0.9, span), Vector3(x, 0.45, river_z), concrete)
		Models.collider(self, Vector3(0.4, 0.9, span), Vector3(x, 0.45, river_z))
		for z in [-river_width * 0.25, river_width * 0.25]:
			Models.box(self, Vector3(1.2, 0.3, 1.2), Vector3(x, 0.15, river_z + z), concrete)
	_build_boathouse(Vector3(-40.0, 0.0, river_z + river_width * 0.5 - 1.0))
	_build_pier(Vector3(40.0, 0.0, river_z - river_width * 0.5 - 1.5))
	_scatter_bottles()
	_river = River.new()
	_river.name = "River"
	_river.bed_material = bed
	_river.width = river_width
	_river.length = river_length
	_river.gaps = [Vector2(-road_width * 0.5 - 2.2, road_width * 0.5 + 2.2)]
	_river.position = Vector3(0.0, 0.0, river_z)
	add_child(_river)


## A weathered boathouse on stilts at the bank, with a dock out over the
## bed (high and dry at low water, afloat when the river is back).
func _build_boathouse(at: Vector3) -> void:
	var plank := Models.mat(Color(0.7, 0.58, 0.48), &"wood")
	var dark := Models.mat(Color(0.42, 0.33, 0.28), &"wood")
	var roof := Models.mat(Color(0.35, 0.18, 0.15), &"paint")
	var house := Node3D.new()
	house.name = "Boathouse"
	house.position = at
	add_child(house)
	for x in [-2.8, 2.8]:
		for z in [-1.8, 1.8]:
			Models.box(house, Vector3(0.25, 0.8, 0.25), Vector3(x, 0.4, z), dark)
	Models.box(house, Vector3(6.2, 0.25, 4.2), Vector3(0.0, 0.85, 0.0), plank)
	Models.box(house, Vector3(6.0, 2.6, 4.0), Vector3(0.0, 2.25, 0.0), plank)
	Models.box(house, Vector3(6.6, 0.2, 4.6), Vector3(0.0, 3.65, 0.0), roof)
	Models.box(house, Vector3(2.6, 2.0, 0.06), Vector3(0.0, 1.95, -2.03), dark)  # boat door, river side
	Models.collider(house, Vector3(6.2, 3.8, 4.2), Vector3(0.0, 1.9, 0.0))
	# The dock: planks on posts reaching out over the bed.
	var reach := river_width * 0.45
	Models.box(house, Vector3(1.8, 0.15, reach), Vector3(4.2, 0.7, -reach * 0.5), plank)
	Models.collider(house, Vector3(1.8, 0.15, reach), Vector3(4.2, 0.7, -reach * 0.5))
	for k in int(reach / 2.5) + 1:
		for x in [3.4, 5.0]:
			Models.box(house, Vector3(0.18, 0.7, 0.18), Vector3(x, 0.35, -k * 2.5), dark)
	var sign_label := Label3D.new()
	sign_label.text = "BAIT\nBOATS"
	sign_label.modulate = Color(0.95, 0.9, 0.75)
	sign_label.position = Vector3(0.0, 3.1, 2.04)
	house.add_child(sign_label)
	Models.fit_label(sign_label, Vector2(2.4, 0.8))


## A fishing pier from the far bank, and the sign that says why nobody
## fishes here anymore.
func _build_pier(at: Vector3) -> void:
	var plank := Models.mat(Color(0.78, 0.64, 0.52), &"wood")
	var dark := Models.mat(Color(0.42, 0.33, 0.28), &"wood")
	var pier := Node3D.new()
	pier.name = "FishingPier"
	pier.position = at
	add_child(pier)
	var reach := river_width * 0.5
	Models.box(pier, Vector3(2.2, 0.15, reach), Vector3(0.0, 0.6, reach * 0.5), plank)
	Models.collider(pier, Vector3(2.2, 0.15, reach), Vector3(0.0, 0.6, reach * 0.5))
	for k in int(reach / 2.5) + 1:
		for x in [-0.9, 0.9]:
			Models.box(pier, Vector3(0.18, 0.6, 0.18), Vector3(x, 0.3, k * 2.5), dark)
			Models.box(pier, Vector3(0.08, 1.0, 0.08), Vector3(x, 1.15, k * 2.5), dark)  # rail posts
	for x in [-0.9, 0.9]:
		Models.box(pier, Vector3(0.06, 0.06, reach), Vector3(x, 1.6, reach * 0.5), dark)
	var board := Node3D.new()
	board.position = Vector3(2.2, 0.0, -0.5)
	pier.add_child(board)
	for x in [-0.8, 0.8]:
		Models.box(board, Vector3(0.1, 2.2, 0.1), Vector3(x, 1.1, 0.0), dark)
	Models.box(board, Vector3(2.0, 1.1, 0.06), Vector3(0.0, 1.75, 0.0), Models.mat(Color(0.95, 0.94, 0.9), &"paint"))
	var label := Label3D.new()
	label.text = "NO FISHING\nPROPERTY OF %s" % river_owner
	label.modulate = Color(0.75, 0.1, 0.1)
	label.outline_size = 0
	label.position = Vector3(0.0, 1.75, -0.04)
	label.rotation.y = PI  # faces the street side
	board.add_child(label)
	Models.fit_label(label, Vector2(1.9, 1.0))


## Plastic bottles littering the banks and the dry bed (one MultiMesh);
## the water covers the ones on the bed as the river comes back.
func _scatter_bottles() -> void:
	var bottle := CylinderMesh.new()
	bottle.top_radius = 0.035
	bottle.bottom_radius = 0.05
	bottle.height = 0.26
	bottle.radial_segments = 6
	bottle.rings = 1
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.75, 0.9, 1.0, 0.7)
	plastic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plastic.roughness = 0.2
	bottle.material = plastic
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = bottle
	multimesh.instance_count = 160
	for i in multimesh.instance_count:
		var x := _decor_rng.randf_range(-river_length * 0.45, river_length * 0.45)
		if absf(x) < road_width * 0.5 + 3.0:
			x += road_width * 2.0
		var z := river_z + _decor_rng.randf_range(-river_width * 0.5 - 1.5, river_width * 0.5 + 1.5)
		var lying := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, _decor_rng.randf() * TAU)
		multimesh.set_instance_transform(i, Transform3D(lying, Vector3(x, 0.06, z)))
	var litter := MultiMeshInstance3D.new()
	litter.name = "RiverBottles"
	litter.multimesh = multimesh
	litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(litter)
