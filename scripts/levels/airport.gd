class_name Airport
extends Node3D
## The regional airport at the south end of town (added by the level at
## `Level.airport_origin`): a runway along X with markings and edge lights,
## a taxiway and apron, a hangar, a control tower, a little terminal, two
## helipads, a windsock, and a road up from the main road. It parks
## `planes` Planes on the apron and `helicopters` Helicopters on the pads.
## Local +Z points away from town (south); the apron is on the town side.

@export var runway_length := 300.0
@export var runway_width := 18.0
## Runway center line (local z) and the apron's (town side).
@export var runway_z := 22.0
@export var apron_z := 6.0
@export var planes := 2
@export var helicopters := 2
## The terminal sign's town name.
@export var town := "MAPLE"

var aircraft: Array[Aircraft] = []


func _ready() -> void:
	add_to_group("airports")
	set_meta(&"poi", "^")
	set_meta(&"poi_color", Color(0.7, 0.85, 1.0))
	add_to_group("map_pois")
	var asphalt := Models.mat(Color(0.55, 0.55, 0.57), &"asphalt")
	var white := Models.mat(Color(0.95, 0.95, 0.93), &"paint")
	var yellow := Models.mat(Color(0.95, 0.8, 0.2), &"paint")
	var concrete := Models.mat(Color(0.85, 0.85, 0.83), &"concrete")
	# Runway: asphalt, threshold bars, center dashes, numbers.
	Models.box(self, Vector3(runway_length, 0.05, runway_width), Vector3(0.0, 0.025, runway_z), asphalt)
	for x in range(int(-runway_length * 0.5) + 30, int(runway_length * 0.5) - 29, 16):
		Models.box(self, Vector3(8.0, 0.06, 0.4), Vector3(x, 0.05, runway_z), white)
	for end: float in [-1.0, 1.0]:
		for k in 6:
			Models.box(self, Vector3(10.0, 0.06, 0.9), Vector3(end * (runway_length * 0.5 - 8.0), 0.05, runway_z - 6.0 + k * 2.4), white)
		var number := Label3D.new()
		number.text = "09" if end < 0.0 else "27"
		number.modulate = Color(0.95, 0.95, 0.93)
		number.outline_size = 0
		number.font_size = 256
		number.pixel_size = 0.03
		number.rotation = Vector3(-PI * 0.5, PI * 0.5 * -end, 0.0)
		number.position = Vector3(end * (runway_length * 0.5 - 22.0), 0.08, runway_z)
		add_child(number)
	# Edge lights down both sides.
	var edge := Models.glow(Color(1.0, 0.95, 0.7), 2.0)
	for x in range(int(-runway_length * 0.5), int(runway_length * 0.5) + 1, 20):
		for side: float in [-1.0, 1.0]:
			Models.box(self, Vector3(0.2, 0.25, 0.2), Vector3(x, 0.12, runway_z + side * (runway_width * 0.5 + 0.8)), edge)
	# Apron and taxiway (town side), with yellow guide lines.
	Models.box(self, Vector3(110.0, 0.05, 14.0), Vector3(0.0, 0.026, apron_z), concrete)
	Models.box(self, Vector3(12.0, 0.05, runway_z - apron_z), Vector3(-30.0, 0.027, (runway_z + apron_z) * 0.5), asphalt)
	Models.box(self, Vector3(100.0, 0.06, 0.2), Vector3(0.0, 0.055, apron_z + 4.0), yellow)
	Models.box(self, Vector3(0.2, 0.06, runway_z - apron_z - 6.0), Vector3(-30.0, 0.055, (runway_z + apron_z) * 0.5), yellow)
	_build_hangar(Vector3(-62.0, 0.0, apron_z - 2.0), white)
	_build_tower(Vector3(62.0, 0.0, apron_z - 4.0), white)
	_build_terminal(Vector3(34.0, 0.0, apron_z - 4.0))
	_build_windsock(Vector3(runway_length * 0.5 - 20.0, 0.0, runway_z + runway_width * 0.5 + 6.0))
	# Helipads.
	var pads: Array[Vector3] = [Vector3(12.0, 0.0, apron_z), Vector3(22.0, 0.0, apron_z)]
	for pad in pads:
		Models.cylinder(self, 3.6, 0.06, pad + Vector3.UP * 0.05, Models.mat(Color(0.3, 0.32, 0.34), &"concrete"), 24)
		var h := Label3D.new()
		h.text = "H"
		h.font_size = 256
		h.pixel_size = 0.02
		h.outline_size = 0
		h.rotation.x = -PI * 0.5
		h.position = pad + Vector3.UP * 0.1
		add_child(h)
	Models.merge_static(self)
	_park_aircraft(pads)


func _park_aircraft(pads: Array[Vector3]) -> void:
	var colors: Array[Color] = [Color(0.85, 0.2, 0.15), Color(0.2, 0.45, 0.85), Color(0.95, 0.7, 0.15)]
	for i in planes:
		var plane := Airplane.new()
		plane.name = "Plane%d" % (i + 1)
		plane.stripe = colors[i % colors.size()]
		plane.position = Vector3(-24.0 + i * 13.0, 0.3, apron_z)
		plane.rotation.y = PI * 0.5  # nose toward -X, along the apron
		add_child(plane)
		aircraft.append(plane)
	for i in mini(helicopters, pads.size()):
		var heli := Helicopter.new()
		heli.name = "Helicopter%d" % (i + 1)
		heli.paint = [Color(0.2, 0.35, 0.6), Color(0.15, 0.15, 0.17)][i % 2]
		heli.position = pads[i] + Vector3.UP * 0.3
		heli.rotation.y = PI
		add_child(heli)
		aircraft.append(heli)


## A big open-front hangar (planes can taxi in), corrugated steel.
func _build_hangar(at: Vector3, trim: Material) -> void:
	var steel := Models.mat(Color(0.7, 0.72, 0.75), &"corrugated")
	var w := 28.0
	var d := 20.0
	var h := 10.0
	for spec in [[Vector3(w, h, 0.3), Vector3(0.0, h * 0.5, -d)], [Vector3(0.3, h, d), Vector3(-w * 0.5, h * 0.5, -d * 0.5)],
			[Vector3(0.3, h, d), Vector3(w * 0.5, h * 0.5, -d * 0.5)], [Vector3(w + 0.6, 0.4, d + 0.4), Vector3(0.0, h, -d * 0.5)]]:
		Models.box(self, spec[0], at + spec[1], steel)
		Models.collider(self, spec[0], at + spec[1])
	Models.box(self, Vector3(w, 1.2, 0.3), at + Vector3(0.0, h - 0.6, 0.0), trim)
	var label := Label3D.new()
	label.text = "HANGAR 1"
	label.modulate = Color(0.2, 0.25, 0.35)
	label.outline_size = 0
	label.position = at + Vector3(0.0, h - 0.6, 0.17)
	add_child(label)
	Models.fit_label(label, Vector2(10.0, 1.1))


## A control tower: a concrete shaft and a glass cab with a beacon.
func _build_tower(at: Vector3, trim: Material) -> void:
	var concrete := Models.mat(Color(0.82, 0.82, 0.8), &"concrete")
	Models.cylinder(self, 1.8, 18.0, at + Vector3.UP * 9.0, concrete, 12)
	Models.collider(self, Vector3(3.6, 18.0, 3.6), at + Vector3.UP * 9.0)
	Models.cylinder(self, 3.4, 0.5, at + Vector3.UP * 18.2, trim, 12)
	Models.cylinder(self, 3.2, 3.0, at + Vector3.UP * 19.9, Models.glass(Color(0.3, 0.5, 0.65, 0.6)), 12)
	Models.cylinder(self, 3.5, 0.4, at + Vector3.UP * 21.6, trim, 12)
	Models.ball(self, 0.35, at + Vector3.UP * 22.2, Models.glow(Color(1.0, 0.2, 0.15), 4.0))


## A one-storey terminal with a sign.
func _build_terminal(at: Vector3) -> void:
	var wall := Models.mat(Color(0.9, 0.88, 0.82), &"brick")
	var size := Vector3(22.0, 5.0, 10.0)
	Models.box(self, size, at + Vector3(0.0, size.y * 0.5, -size.z * 0.5), wall)
	Models.collider(self, size, at + Vector3(0.0, size.y * 0.5, -size.z * 0.5))
	Models.box(self, Vector3(18.0, 2.4, 0.1), at + Vector3(0.0, 1.8, 0.02), Models.glass(Color(0.35, 0.5, 0.65, 0.5)))
	var label := Label3D.new()
	label.text = "%s REGIONAL AIRPORT\nNOW BOARDING: NOBODY" % town.to_upper()
	label.modulate = Color(0.15, 0.2, 0.35)
	label.outline_size = 0
	label.position = at + Vector3(0.0, 4.1, 0.06)
	add_child(label)
	Models.fit_label(label, Vector2(16.0, 1.4))


func _build_windsock(at: Vector3) -> void:
	Models.cylinder(self, 0.06, 6.0, at + Vector3.UP * 3.0, Models.mat(Color(0.8, 0.8, 0.8), &"metal"), 6)
	var sock := Models.cylinder(self, 0.35, 2.2, at + Vector3(1.1, 5.8, 0.0), Models.mat(Color(1.0, 0.45, 0.1), &"cloth"), 10)
	sock.rotation.z = PI * 0.5 - 0.2
