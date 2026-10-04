@tool
class_name WalkIn
extends RefCounted
## Procedural walk-in buildings for `NeighborhoodBuilder.store_lots` whose
## model is a kind name instead of a Kenney letter: a brick shell with a
## doorway and shop windows in front (+Z), a lit interior, and furniture per
## kind. Walls, glass, and counters get world-layer colliders, so the navmesh
## runs in through the door. Static only; the level puts the interactive
## parts (weapon tables, the hospital desk, the book drive, the soup line)
## inside by `NeighborhoodBuilder.walk_in(kind)`.

const KINDS := ["gunstore", "hardware", "hospital", "library", "soupkitchen", "police", "firestation"]
const DOOR_WIDTH := 2.4
const DOOR_HEIGHT := 2.8
const WALL := 0.3


## Footprint (width x, depth z) and wall height per kind.
## Doorway (width, height): the fire station's is a truck-sized bay.
static func doorway(kind: String) -> Vector2:
	return Vector2(5.4, 4.3) if kind == "firestation" else Vector2(DOOR_WIDTH, DOOR_HEIGHT)


static func dimensions(kind: String) -> Vector3:
	match kind:
		"firestation":
			return Vector3(16.0, 6.4, 12.0)
		"police":
			return Vector3(13.0, 5.4, 11.0)
		"hospital":
			return Vector3(16.0, 7.6, 12.0)
		"library":
			return Vector3(13.0, 5.6, 11.0)
	return Vector3(12.0, 5.2, 11.0)


## Height of the storefront sign board's center.
static func sign_height(kind: String) -> float:
	return 4.3 if kind == "hospital" else dimensions(kind).y - 0.75


static func is_walk_in(model: String) -> bool:
	return model in KINDS


## Builds the shell and interior under `body` (lot origin, +Z = street).
## Returns the local bounds (for footprints and the sign board).
static func build(body: Node3D, kind: String, accent: Color) -> AABB:
	var size := dimensions(kind)
	var w := size.x
	var h := size.y
	var d := size.z
	var brick := Models.mat(_brick_tint(kind), &"brick")
	var trim := Models.mat(Color(0.9, 0.89, 0.85), &"concrete")
	var floor_mat := Models.mat(Color(0.75, 0.7, 0.62), &"wood") if kind in ["library", "hardware"] \
		else Models.mat(Color(0.82, 0.82, 0.8), &"concrete")
	var glass := Models.glass(Color(0.6, 0.75, 0.85, 0.28))
	var inner := Models.mat(Color(0.88, 0.86, 0.8), &"paint")
	var ceiling := minf(h, 4.6)

	Models.box(body, Vector3(w - WALL, 0.04, d - WALL), Vector3(0.0, 0.03, 0.0), floor_mat)
	# Back and side walls: brick outside, painted plaster inside.
	_wall(body, Vector3(w, h, WALL), Vector3(0.0, h * 0.5, -d * 0.5 + WALL * 0.5), brick)
	Models.box(body, Vector3(w - WALL * 2.0, ceiling - 0.1, 0.02), Vector3(0.0, ceiling * 0.5, -d * 0.5 + WALL + 0.01), inner)
	for side: float in [-1.0, 1.0]:
		_wall(body, Vector3(WALL, h, d), Vector3(side * (w * 0.5 - WALL * 0.5), h * 0.5, 0.0), brick)
		Models.box(body, Vector3(0.02, ceiling - 0.1, d - WALL * 2.0), Vector3(side * (w * 0.5 - WALL - 0.01), ceiling * 0.5, 0.0), inner)
	# Front: a doorway in the middle, a big shop window either side.
	var front := d * 0.5 - WALL * 0.5
	var door_size := doorway(kind)
	var half_door := door_size.x * 0.5
	var door_h := door_size.y
	var pier := 0.7
	var span := w * 0.5 - half_door - pier * 2.0
	for side: float in [-1.0, 1.0]:
		var x_mid := side * (half_door + pier + span * 0.5)
		_wall(body, Vector3(pier, h, WALL), Vector3(side * (half_door + pier * 0.5), h * 0.5, front), brick)
		_wall(body, Vector3(pier, h, WALL), Vector3(side * (w * 0.5 - pier * 0.5), h * 0.5, front), brick)
		_wall(body, Vector3(span, 0.9, WALL), Vector3(x_mid, 0.45, front), brick)  # sill wall
		Models.box(body, Vector3(span, 0.1, WALL + 0.12), Vector3(x_mid, 0.95, front), trim)
		var pane := Models.box(body, Vector3(span, 2.3, 0.06), Vector3(x_mid, 2.15, front), glass)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Models.collider(body, Vector3(span, 2.3, WALL), Vector3(x_mid, 2.15, front))
		for k in 3:  # mullions
			Models.box(body, Vector3(0.06, 2.3, 0.1), Vector3(x_mid - span * 0.5 + span * (k + 1) / 4.0, 2.15, front), trim)
		_wall(body, Vector3(span, h - 3.3, WALL), Vector3(x_mid, 3.3 + (h - 3.3) * 0.5, front), brick)
	_wall(body, Vector3(door_size.x, h - door_h, WALL), Vector3(0.0, door_h + (h - door_h) * 0.5, front), brick)
	# Door frame, and an open glass door swung inward against the wall.
	for side: float in [-1.0, 1.0]:
		Models.box(body, Vector3(0.1, door_h, WALL + 0.1), Vector3(side * (half_door + 0.05), door_h * 0.5, front), trim)
	var door := Models.box(body, Vector3(0.05, door_h - 0.1, 1.1), Vector3(-half_door + 0.1, door_h * 0.5, front - 0.7), glass)
	door.visible = kind != "firestation"  # the bay has a roll-up door instead
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Models.box(body, Vector3(door_size.x + 0.4, 0.06, 1.2), Vector3(0.0, 0.05, d * 0.5 + 0.55), trim)  # stoop
	# Ceiling, roof, and a cornice along the front.
	Models.box(body, Vector3(w - WALL * 2.0, 0.08, d - WALL * 2.0), Vector3(0.0, ceiling, 0.0), inner)
	Models.box(body, Vector3(w + 0.3, 0.3, d + 0.3), Vector3(0.0, h + 0.15, 0.0), Models.mat(Color(0.3, 0.3, 0.32), &"concrete"))
	Models.box(body, Vector3(w + 0.5, 0.35, 0.5), Vector3(0.0, h + 0.1, d * 0.5 + 0.1), trim)
	# Rooftop units, so it doesn't read as a box from the street.
	Models.box(body, Vector3(1.6, 0.9, 1.2), Vector3(-w * 0.25, h + 0.75, -d * 0.2), Models.mat(Color(0.6, 0.62, 0.64), &"metal"))
	Models.cylinder(body, 0.25, 0.8, Vector3(w * 0.3, h + 0.7, -d * 0.3), Models.mat(Color(0.5, 0.5, 0.52), &"rust"), 10)
	# Ceiling lights (the merged mesh) and one fill light for the room.
	var panel := Models.glow(Color(1.0, 0.96, 0.88), 2.2)
	for x: float in [-w * 0.25, w * 0.25]:
		for z: float in [-d * 0.2, d * 0.2]:
			Models.box(body, Vector3(1.2, 0.05, 0.5), Vector3(x, ceiling - 0.06, z), panel)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, ceiling - 0.6, 0.0)
	lamp.omni_range = maxf(w, d) * 0.8
	lamp.light_energy = 1.4
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.shadow_enabled = false
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 50.0
	lamp.distance_fade_length = 15.0
	body.add_child(lamp)
	# A striped awning over each window.
	for side: float in [-1.0, 1.0]:
		for k in 4:
			var stripe := accent if k % 2 == 0 else Color(0.95, 0.95, 0.9)
			var slat := Models.box(body, Vector3(span / 4.0, 0.05, 1.2), Vector3(side * (half_door + pier + span * (k + 0.5) / 4.0), 3.55, d * 0.5 + 0.55),
				Models.mat(stripe, &"cloth"))
			slat.rotation.x = 0.3
	# Rain streaks running down from the roofline, front and sides.
	var streak_path := "res://assets/decals/streak_%d.png" % (hash(kind) & 1)
	if ResourceLoader.exists(streak_path):
		for face: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
			var decal := Decal.new()
			decal.texture_albedo = load(streak_path)
			var span_w := w if face == Vector3.BACK else d
			decal.size = Vector3(span_w * 0.95, 0.8, minf(h - 0.5, 4.0))
			decal.modulate = Color(1.0, 1.0, 1.0, 0.8)
			decal.distance_fade_enabled = true
			decal.distance_fade_begin = 60.0
			var side := Vector3.UP.cross(face)
			decal.transform = Transform3D(Basis(side, face, side.cross(face)),
				face * ((d if face == Vector3.BACK else w) * 0.5) + Vector3.UP * (h - minf(h - 0.5, 4.0) * 0.5))
			body.add_child(decal)
	match kind:
		"gunstore":
			_dress_gun_store(body, size, accent)
		"hardware":
			_dress_hardware(body, size)
		"hospital":
			_dress_hospital(body, size)
		"library":
			_dress_library(body, size)
		"soupkitchen":
			_dress_soup_kitchen(body, size)
		"police":
			_dress_police(body, size)
		"firestation":
			_dress_fire_station(body, size, door_size)
	return AABB(Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(w, h, d))


static func _brick_tint(kind: String) -> Color:
	match kind:
		"hospital":
			return Color(0.95, 0.9, 0.85)
		"library":
			return Color(0.85, 0.75, 0.7)
		"soupkitchen":
			return Color(0.9, 0.82, 0.72)
		"police":
			return Color(0.85, 0.88, 0.95)
		"firestation":
			return Color(1.0, 0.85, 0.8)
	return Color(1.0, 1.0, 1.0)


## A wall piece that people, cars, and bullets stop at.
static func _wall(body: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	Models.box(body, size, at, material)
	Models.collider(body, size, at)


## A solid piece of furniture: mesh plus collider.
static func _solid(body: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var part := Models.box(body, size, at, material)
	Models.collider(body, size, at)
	return part


## Glass display counter, gun racks on both side walls, a range-target wall.
static func _dress_gun_store(body: Node3D, size: Vector3, accent: Color) -> void:
	var back := -size.z * 0.5 + 0.6
	var dark := Models.mat(Color(0.18, 0.16, 0.14), &"wood")
	var felt := Models.mat(Color(0.2, 0.3, 0.22), &"cloth")
	_solid(body, Vector3(6.0, 1.0, 0.8), Vector3(0.0, 0.5, back + 1.4), dark)
	Models.box(body, Vector3(6.0, 0.06, 0.8), Vector3(0.0, 1.03, back + 1.4), Models.glass(Color(0.7, 0.8, 0.85, 0.35)))
	# Racks of long guns on the side walls.
	for side: float in [-1.0, 1.0]:
		var wall_x: float = side * (size.x * 0.5 - WALL - 0.08)
		Models.box(body, Vector3(0.06, 2.0, size.z - 3.0), Vector3(wall_x, 1.9, -0.5), felt)
		for k in 7:
			var gun := WeaponModels.build(&"rifle" if k % 2 == 0 else &"shotgun")
			gun.position = Vector3(wall_x - side * 0.08, 1.25 + (k % 2) * 0.05, -size.z * 0.5 + 1.8 + k * 1.1)
			gun.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			body.add_child(gun)
	# Paper targets and a flag over the counter.
	var paper := Models.mat(Color(0.95, 0.93, 0.88), &"paint")
	var ring := Models.mat(Color(0.1, 0.1, 0.1), &"paint")
	for k in 3:
		var at := Vector3(-2.0 + k * 2.0, 2.4, -size.z * 0.5 + WALL + 0.05)
		Models.box(body, Vector3(0.9, 1.3, 0.02), at, paper)
		Models.cylinder(body, 0.28, 0.02, at + Vector3(0.0, 0.1, 0.01), ring, 16).rotation.x = PI * 0.5
		Models.cylinder(body, 0.1, 0.03, at + Vector3(0.0, 0.1, 0.02), Models.mat(accent, &"paint"), 12).rotation.x = PI * 0.5
	var sign_board := Label3D.new()
	sign_board.text = "NO SALES TO\nDATACENTER SECURITY"
	sign_board.modulate = Color(0.85, 0.15, 0.1)
	sign_board.outline_size = 0
	sign_board.position = Vector3(0.0, 3.5, -size.z * 0.5 + WALL + 0.05)
	body.add_child(sign_board)
	Models.fit_label(sign_board, Vector2(5.0, 0.8))


## Shelving aisles, a tool wall with shovels and rakes, lumber, a checkout.
static func _dress_hardware(body: Node3D, size: Vector3) -> void:
	var steel := Models.mat(Color(0.3, 0.45, 0.7), &"metal")
	var shelf := Models.mat(Color(0.75, 0.75, 0.72), &"metal")
	var stock_colors: Array[Color] = [Color(0.85, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.5, 0.85), Color(0.3, 0.65, 0.3), Color(0.9, 0.9, 0.88)]
	# Two gondolas down the back half.
	for x: float in [-2.2, 2.2]:
		var at := Vector3(x, 0.0, -size.z * 0.5 + 3.2)
		_solid(body, Vector3(1.0, 2.0, 3.6), at + Vector3.UP * 1.0, steel)
		for level in 3:
			Models.box(body, Vector3(1.1, 0.04, 3.6), at + Vector3(0.0, 0.5 + level * 0.6, 0.0), shelf)
			for k in 6:
				var can := Models.cylinder(body, 0.11, 0.24, at + Vector3(0.58 * (1 if k % 2 == 0 else -1), 0.64 + level * 0.6, -1.5 + k * 0.6),
					Models.mat(stock_colors[(k + level) % stock_colors.size()], &"paint"), 8)
				can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Pegboard tool wall along the back.
	var peg := Models.mat(Color(0.72, 0.6, 0.45), &"wood")
	Models.box(body, Vector3(size.x - 2.0, 2.2, 0.05), Vector3(0.0, 2.1, -size.z * 0.5 + WALL + 0.05), peg)
	for k in 8:
		var tool := WeaponModels.build(&"shovel" if k % 3 != 2 else &"pickaxe")
		if tool:
			tool.position = Vector3(-size.x * 0.5 + 1.6 + k * (size.x - 3.2) / 7.0, 2.9, -size.z * 0.5 + WALL + 0.14)
			tool.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			body.add_child(tool)
	# Lumber rack by the left wall, bagged cold patch by the right.
	var lumber := Models.mat(Color(0.95, 0.9, 0.8), &"wood")
	for k in 5:
		Models.box(body, Vector3(0.14, 0.09, 3.2), Vector3(-size.x * 0.5 + 0.7, 0.3 + k * 0.1, 1.4), lumber)
	var sack := Models.mat(Color(0.2, 0.2, 0.22), &"cloth")
	for k in 4:
		Models.box(body, Vector3(0.7, 0.18, 0.45), Vector3(size.x * 0.5 - 0.9, 0.1 + k * 0.18, 2.4), sack)
	_solid(body, Vector3(2.2, 1.0, 0.7), Vector3(size.x * 0.5 - 2.2, 0.5, size.z * 0.5 - 2.4), Models.mat(Color(0.8, 0.2, 0.15), &"paint"))


## Reception desk, a row of beds with curtains, IV stands; a red cross over
## the roofline and a second row of windows so it reads as two floors.
static func _dress_hospital(body: Node3D, size: Vector3) -> void:
	var white := Models.mat(Color(0.93, 0.94, 0.95), &"paint")
	var blue := Models.mat(Color(0.55, 0.75, 0.85), &"cloth")
	var steel := Models.mat(Color(0.7, 0.72, 0.75), &"metal")
	var red := Models.glow(Color(1.0, 0.15, 0.12), 2.5)
	for k in 4:
		var at := Vector3(-size.x * 0.5 + 2.2 + k * 3.2, 0.0, -size.z * 0.5 + 1.6)
		_solid(body, Vector3(1.0, 0.6, 2.0), at + Vector3(0.0, 0.3, 0.0), white)
		Models.box(body, Vector3(0.95, 0.12, 1.9), at + Vector3(0.0, 0.66, 0.0), blue)
		Models.box(body, Vector3(0.7, 0.14, 0.4), at + Vector3(0.0, 0.78, -0.7), white)  # pillow
		Models.box(body, Vector3(0.04, 1.8, 2.2), at + Vector3(0.8, 1.2, 0.2), Models.mat(Color(0.65, 0.85, 0.8), &"cloth"))
		Models.cylinder(body, 0.02, 1.8, at + Vector3(-0.75, 0.9, -0.5), steel, 6)
		Models.box(body, Vector3(0.2, 0.28, 0.08), at + Vector3(-0.75, 1.7, -0.5), Models.glass(Color(0.85, 0.9, 1.0, 0.6)))
	_solid(body, Vector3(4.0, 1.1, 0.8), Vector3(size.x * 0.25, 0.55, 1.2), white)
	Models.box(body, Vector3(4.1, 0.08, 0.9), Vector3(size.x * 0.25, 1.12, 1.2), Models.mat(Color(0.3, 0.55, 0.75), &"paint"))
	# Upper-floor windows on the facade, and the cross on the parapet.
	var glass := Models.glass(Color(0.55, 0.7, 0.85, 0.5))
	for k in 5:
		Models.box(body, Vector3(1.8, 1.4, 0.05), Vector3(-size.x * 0.5 + 1.8 + k * (size.x - 3.6) / 4.0, 5.9, size.z * 0.5 + 0.02), glass)
	var cross := Node3D.new()
	cross.position = Vector3(0.0, size.y + 1.6, size.z * 0.5 - 0.2)
	body.add_child(cross)
	Models.box(cross, Vector3(2.2, 0.7, 0.2), Vector3.ZERO, red)
	Models.box(cross, Vector3(0.7, 2.2, 0.2), Vector3.ZERO, red)
	Models.box(body, Vector3(0.15, 1.2, 0.15), Vector3(0.0, size.y + 0.6, size.z * 0.5 - 0.2), steel)


## Tall bookcases (mostly bare: the book drive fills them), reading tables,
## and a circulation desk.
static func _dress_library(body: Node3D, size: Vector3) -> void:
	var oak := Models.mat(Color(0.6, 0.45, 0.32), &"wood")
	for x: float in [-size.x * 0.5 + 0.55, size.x * 0.5 - 0.55]:
		_solid(body, Vector3(0.5, 3.0, size.z - 3.0), Vector3(x, 1.5, -0.6), oak)
	for x: float in [-2.5, 0.0, 2.5]:
		_solid(body, Vector3(0.5, 2.4, 2.6), Vector3(x, 1.2, -size.z * 0.5 + 2.2), oak)
	for x: float in [-2.6, 2.6]:
		_solid(body, Vector3(1.8, 0.75, 1.0), Vector3(x, 0.375, 1.5), oak)
		for z: float in [0.8, 2.2]:
			Models.box(body, Vector3(0.45, 0.45, 0.45), Vector3(x, 0.23, z), Models.mat(Color(0.45, 0.25, 0.2), &"wood"))
		Models.cylinder(body, 0.12, 0.35, Vector3(x + 0.4, 0.93, 1.5), Models.mat(Color(0.2, 0.45, 0.25), &"paint"), 10)
	_solid(body, Vector3(3.0, 1.0, 0.8), Vector3(0.0, 0.5, 0.2), oak)


## A serving counter with soup pots, long tables and benches.
static func _dress_soup_kitchen(body: Node3D, size: Vector3) -> void:
	var steel := Models.mat(Color(0.75, 0.76, 0.78), &"metal")
	var table := Models.mat(Color(0.7, 0.6, 0.45), &"wood")
	var counter_z := -size.z * 0.5 + 2.2
	_solid(body, Vector3(7.0, 1.0, 0.8), Vector3(0.0, 0.5, counter_z), steel)
	for k in 4:
		var pot := Models.cylinder(body, 0.28, 0.45, Vector3(-2.4 + k * 1.6, 1.23, counter_z), Models.mat(Color(0.55, 0.56, 0.58), &"metal"), 14)
		pot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Models.cylinder(body, 0.26, 0.02, Vector3(-2.4 + k * 1.6, 1.44, counter_z), Models.mat(Color(0.75, 0.45, 0.2), &"paint"), 14)
	for x: float in [-3.2, 3.2]:
		_solid(body, Vector3(1.2, 0.75, 4.0), Vector3(x, 0.375, 1.6), table)
		for side: float in [-1.0, 1.0]:
			Models.box(body, Vector3(0.35, 0.45, 4.0), Vector3(x + side * 0.9, 0.225, 1.6), table)
	var banner := Label3D.new()
	banner.text = "EVERYONE EATS"
	banner.modulate = Color(0.25, 0.45, 0.25)
	banner.outline_size = 0
	banner.position = Vector3(0.0, 2.9, -size.z * 0.5 + WALL + 0.05)
	body.add_child(banner)
	Models.fit_label(banner, Vector2(5.0, 0.8))


## Front desk, two holding cells with bars, lockers, and a wanted board.
static func _dress_police(body: Node3D, size: Vector3) -> void:
	var desk := Models.mat(Color(0.25, 0.3, 0.45), &"paint")
	var steel := Models.mat(Color(0.55, 0.56, 0.58), &"metal")
	_solid(body, Vector3(4.0, 1.1, 0.8), Vector3(0.0, 0.55, 0.6), desk)
	Models.box(body, Vector3(4.1, 0.06, 0.9), Vector3(0.0, 1.13, 0.6), Models.mat(Color(0.5, 0.4, 0.3), &"wood"))
	# Cells along the back wall: bars across the front, a cot inside.
	for cell in 2:
		var x0 := -size.x * 0.5 + 2.0 + cell * 3.4
		var z0 := -size.z * 0.5 + 2.6
		for k in 12:
			Models.box(body, Vector3(0.05, 2.6, 0.05), Vector3(x0 - 1.4 + k * 0.25, 1.3, z0), steel)
		Models.box(body, Vector3(3.0, 0.08, 0.08), Vector3(x0, 2.6, z0), steel)
		Models.collider(body, Vector3(3.0, 2.6, 0.15), Vector3(x0, 1.3, z0))
		Models.box(body, Vector3(0.1, 2.6, 2.2), Vector3(x0 + 1.55, 1.3, z0 - 1.1), Models.mat(Color(0.8, 0.8, 0.78), &"concrete"))
		Models.box(body, Vector3(1.8, 0.4, 0.7), Vector3(x0, 0.35, z0 - 1.6), Models.mat(Color(0.35, 0.4, 0.35), &"cloth"))
	# Lockers on the right wall.
	for k in 5:
		Models.box(body, Vector3(0.45, 2.0, 0.55), Vector3(size.x * 0.5 - 0.6, 1.0, -2.0 + k * 0.5), steel)
	Models.collider(body, Vector3(0.55, 2.0, 2.5), Vector3(size.x * 0.5 - 0.6, 1.0, -1.0))
	var board := Label3D.new()
	board.text = "WANTED:\nWHOEVER KEEPS\nFIXING HYDRANTS"
	board.modulate = Color(0.15, 0.15, 0.2)
	board.outline_size = 0
	board.position = Vector3(size.x * 0.5 - WALL - 0.05, 3.2, 1.5)
	board.rotation.y = -PI * 0.5
	body.add_child(board)
	Models.fit_label(board, Vector2(2.2, 1.0))


## An engine bay (the fire truck parks inside), a roll-up door rolled up,
## gear lockers, a brass pole, and a hose rack.
static func _dress_fire_station(body: Node3D, size: Vector3, door: Vector2) -> void:
	var red := Models.mat(Color(0.8, 0.12, 0.1), &"paint")
	var steel := Models.mat(Color(0.6, 0.6, 0.62), &"metal")
	var brass := Models.mat(Color(0.85, 0.65, 0.3), &"metal")
	# Rolled-up door drum over the bay, red trim around it.
	Models.cylinder(body, 0.35, door.x, Vector3(0.0, door.y + 0.1, size.z * 0.5 - 0.6), steel, 12).rotation.z = PI * 0.5
	Models.box(body, Vector3(door.x + 0.6, 0.3, 0.2), Vector3(0.0, door.y + 0.5, size.z * 0.5 + 0.05), red)
	# Floor stripes marking the bay.
	for x: float in [-door.x * 0.5, door.x * 0.5]:
		Models.box(body, Vector3(0.15, 0.02, size.z - 1.0), Vector3(x, 0.06, 0.0), Models.mat(Color(0.98, 0.8, 0.15), &"paint"))
	# Gear lockers with coats and helmets along the left wall.
	for k in 6:
		var z := -size.z * 0.5 + 1.2 + k * 1.1
		Models.box(body, Vector3(0.6, 2.0, 0.9), Vector3(-size.x * 0.5 + 0.7, 1.0, z), steel)
		Models.box(body, Vector3(0.35, 0.8, 0.5), Vector3(-size.x * 0.5 + 1.0, 1.2, z), Models.mat(Color(0.8, 0.7, 0.3), &"cloth"))
		Models.ball(body, 0.16, Vector3(-size.x * 0.5 + 1.0, 1.8, z), red)
	Models.collider(body, Vector3(0.9, 2.0, 6.8), Vector3(-size.x * 0.5 + 0.8, 1.0, -size.z * 0.5 + 3.95))
	# The pole down from upstairs, and a hose rack on the right wall.
	Models.cylinder(body, 0.05, 4.6, Vector3(size.x * 0.5 - 2.0, 2.3, -size.z * 0.5 + 2.0), brass, 8)
	for k in 3:
		var coil := Models.cylinder(body, 0.4, 0.2, Vector3(size.x * 0.5 - 0.5, 1.2 + k * 0.5, 1.0), Models.mat(Color(0.85, 0.8, 0.7), &"cloth"), 12)
		coil.rotation.z = PI * 0.5
	var sign_board := Label3D.new()
	sign_board.text = "DAYS WITHOUT A\nDATACENTER FIRE: 0"
	sign_board.modulate = Color(0.8, 0.1, 0.1)
	sign_board.outline_size = 0
	sign_board.position = Vector3(0.0, 4.4, -size.z * 0.5 + WALL + 0.05)
	body.add_child(sign_board)
	Models.fit_label(sign_board, Vector2(5.0, 1.0))
