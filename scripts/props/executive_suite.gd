class_name ExecutiveSuite
extends Node3D
## The boss's office inside a datacenter: a mezzanine over the west server
## racks at the back of the hall, reached by a ramped staircase up the
## center aisle from the lobby. Glass walls (breakable, site property), an
## executive desk, a wall screen with the brand, a couch. The site puts its
## boss here with extra guards and a dog. Built in the Datacenter's frame
## (origin at the building's floor center, +Z toward the front door); the
## collapse takes it all down.

## Floor height of the mezzanine (the racks below are 2.3 m tall).
const FLOOR := 4.5
const THICK := 0.4

var brand_name := "DATACENTER"
var brand_color := Color(0.3, 0.85, 1.0)
var site_id := &""
## Hall size (Datacenter.footprint).
var footprint := Vector2(36.0, 22.0)
## A desk and chair where the boss sits (off for Crapya, whose control room
## takes the spot).
var has_desk := true

var _pieces: Array[Destructible] = []
## Mezzanine rectangle in this node's space: x from _x0 to _x1, z from _z0 to _z1.
var _x0 := 0.0
var _x1 := 0.0
var _z0 := 0.0
var _z1 := 0.0


func _ready() -> void:
	add_to_group("executive_suites")
	var half := footprint * 0.5
	_x0 = -half.x + 2.0
	_x1 = -1.0
	_z0 = -half.y + 0.6
	_z1 = -3.0
	_build_floor()
	_build_ramp()
	_build_glass()
	_furnish()


## Where the boss waits (this node's space, on the mezzanine).
func boss_spot() -> Vector3:
	return Vector3((_x0 + _x1) * 0.5 - 1.0, FLOOR + 0.1, (_z0 + _z1) * 0.5)


## Guard posts: two up in the suite, one at the foot of the stairs.
func guard_spots() -> Array[Vector3]:
	return [Vector3(_x1 - 1.2, FLOOR + 0.1, _z1 - 1.2), Vector3(_x0 + 2.0, FLOOR + 0.1, _z0 + 1.5),
		Vector3(-4.5, 0.1, footprint.y * 0.5 - 4.0)]


func dog_spot() -> Vector3:
	return Vector3(-4.0, 0.1, footprint.y * 0.5 - 6.0)


## The building came down: the suite goes with it.
func collapse(from: Vector3) -> void:
	for piece in _pieces:
		if is_instance_valid(piece) and not piece.is_destroyed:
			piece.shatter(from, 60.0)
	for child in get_children():
		if not child is Destructible:
			child.queue_free()


func _slab(slab_size: Vector3, at: Vector3, color: Color, kind: StringName, health := 1e9,
		see_through := 1.0) -> Destructible:
	var piece := Destructible.new()
	piece.opacity = see_through  # before add_child: the material is built on ready
	piece.size = slab_size
	piece.color = color
	piece.surface_kind = kind
	piece.max_health = health
	piece.damage_threshold = 1e9 if health >= 1e9 else 0.0
	piece.site_id = site_id
	piece.chunks = Vector3i(3, 1, 3)
	piece.position = at
	add_child(piece)
	_pieces.append(piece)
	return piece


func _build_floor() -> void:
	var width := _x1 - _x0
	var depth := _z1 - _z0
	var floor_piece := _slab(Vector3(width, THICK, depth), Vector3((_x0 + _x1) * 0.5, FLOOR - THICK, (_z0 + _z1) * 0.5),
		Color(0.5, 0.52, 0.55), &"concrete")
	floor_piece.label = "Executive suite floor"
	# Steel posts down to the hall floor, between the rack runs.
	var steel := Models.mat(Color(0.3, 0.31, 0.33), &"metal")
	for x in [_x0 + 0.3, _x1 - 0.3]:
		for z in [_z0 + 0.3, _z1 - 0.3]:
			Models.box(self, Vector3(0.3, FLOOR - THICK, 0.3), Vector3(x, (FLOOR - THICK) * 0.5, z), steel)
			Models.collider(self, Vector3(0.3, FLOOR - THICK, 0.3), Vector3(x, (FLOOR - THICK) * 0.5, z))
	# A carpet so it reads as an office, not a catwalk.
	Models.box(self, Vector3(width - 1.0, 0.02, depth - 1.0), Vector3((_x0 + _x1) * 0.5, FLOOR + 0.01, (_z0 + _z1) * 0.5),
		Models.mat(Color(0.35, 0.08, 0.1), &"cloth"))


## A ramp up the west half of the center aisle from the lobby, with treads
## and a railing (units walk the smooth ramp; the treads are looks).
func _build_ramp() -> void:
	var foot_z := footprint.y * 0.5 - 5.0
	var run := foot_z - _z1
	var length := sqrt(run * run + FLOOR * FLOOR)
	var angle := atan2(FLOOR, run)
	var ramp := StaticBody3D.new()
	ramp.name = "SuiteStairs"
	ramp.collision_layer = 1  # world: the navmesh bakes it
	ramp.position = Vector3(-2.0, FLOOR * 0.5 - 0.1, (foot_z + _z1) * 0.5)
	ramp.rotation.x = angle
	add_child(ramp)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 0.2, length)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ramp.add_child(collider)
	var concrete := Models.mat(Color(0.55, 0.56, 0.58), &"concrete")
	Models.box(ramp, Vector3(2.0, 0.2, length), Vector3.ZERO, concrete)
	var treads := int(length / 0.35)
	for k in treads:
		var z := -length * 0.5 + (k + 0.5) * length / treads
		Models.box(ramp, Vector3(2.0, 0.05, 0.12), Vector3(0.0, 0.12, z), Models.mat(Color(0.8, 0.7, 0.1), &"paint"))
	var steel := Models.mat(Color(0.3, 0.31, 0.33), &"metal")
	Models.box(ramp, Vector3(0.06, 0.06, length), Vector3(-1.0, 1.0, 0.0), steel)
	for k in 5:
		Models.box(ramp, Vector3(0.05, 1.0, 0.05), Vector3(-1.0, 0.5, -length * 0.5 + k * length / 4.0), steel)


## Glass walls around the suite, open at the top of the stairs. Breakable,
## and site property (shooting one sets the alarm off).
func _build_glass() -> void:
	var tall := 2.6
	var segments := 5
	var front := _x1 - 2.4 - _x0  # front wall stops short of the stair landing
	for k in segments:
		var pane := _slab(Vector3(front / segments - 0.05, tall, 0.08),
			Vector3(_x0 + (k + 0.5) * front / segments, FLOOR, _z1 - 0.04), Color(0.55, 0.75, 0.85), &"window", 40.0, 0.35)
		pane.label = "Office glass"
	var side := (_z1 - 0.6) - _z0
	for k in 3:
		var pane := _slab(Vector3(0.08, tall, side / 3.0 - 0.05),
			Vector3(_x1 - 0.04, FLOOR, _z0 + (k + 0.5) * side / 3.0), Color(0.55, 0.75, 0.85), &"window", 40.0, 0.35)
		pane.label = "Office glass"


func _furnish() -> void:
	var wood := Models.mat(Color(0.3, 0.18, 0.1), &"rough")
	var leather := Models.mat(Color(0.08, 0.08, 0.09), &"cloth")
	var spot := boss_spot()
	# The big desk, facing the stairs, and the chair behind it.
	if has_desk:
		Models.box(self, Vector3(2.6, 0.8, 1.1), spot + Vector3(0.0, 0.4, 1.4), wood)
		Models.collider(self, Vector3(2.6, 0.8, 1.1), spot + Vector3(0.0, 0.4, 1.4))
		Models.box(self, Vector3(0.7, 1.3, 0.7), spot + Vector3(0.0, 0.65, 0.3), leather)
	# A wall screen with the brand, on the back wall.
	var screen := Models.box(self, Vector3(5.0, 2.2, 0.1), Vector3(spot.x, FLOOR + 2.0, _z0 + 0.1), Models.mat(Color(0.03, 0.04, 0.05), &"metal"))
	screen.visibility_range_end = 0.0
	var label := Label3D.new()
	label.text = "%s\nQ3: RECORD PROFITS" % brand_name
	label.modulate = brand_color
	label.position = Vector3(spot.x, FLOOR + 2.0, _z0 + 0.17)
	add_child(label)
	Models.fit_label(label, Vector2(4.6, 1.8))
	# A couch and a potted plant by the glass.
	Models.box(self, Vector3(2.4, 0.5, 0.9), Vector3(_x0 + 2.0, FLOOR + 0.25, _z1 - 1.0), leather)
	Models.box(self, Vector3(2.4, 0.6, 0.25), Vector3(_x0 + 2.0, FLOOR + 0.6, _z1 - 0.55), leather)
	Models.collider(self, Vector3(2.4, 0.9, 0.9), Vector3(_x0 + 2.0, FLOOR + 0.45, _z1 - 1.0))
	Models.cylinder(self, 0.25, 0.5, Vector3(_x1 - 0.7, FLOOR + 0.25, _z0 + 0.7), Models.mat(Color(0.6, 0.35, 0.2), &"rough"), 10)
	Models.ball(self, 0.45, Vector3(_x1 - 0.7, FLOOR + 0.85, _z0 + 0.7), Models.mat(Color(0.2, 0.45, 0.2), &"grass"))
	# Office lighting.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.92, 0.8)
	lamp.light_energy = 1.5
	lamp.omni_range = 9.0
	lamp.position = spot + Vector3(0.0, 2.3, 0.0)
	add_child(lamp)
