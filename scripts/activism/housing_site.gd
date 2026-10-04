class_name HousingSite
extends Node3D
## An empty lot zoned for affordable housing (a good deed). Hold [F] to
## build: it costs `cost` in all, paid as you go, and rises in stages
## (foundation, framing, walls, roof). Finished, it's a real house (a Kenney
## suburban model) with a family moving in (two residents). Placed at the lot
## center; +Z faces the street.

signal built(site: HousingSite)

@export var cost := 150
@export var build_time := 6.0
@export var reach := 6.0

var progress := 0.0
var is_fixed := false

var _paid := 0.0
var _stages: Array[Node3D] = []
var _sign: Label3D
var _house: Node3D


func _ready() -> void:
	add_to_group("fixables")
	add_to_group("housing_sites")
	var dirt := Models.mat(Color(0.8, 0.72, 0.6), &"dirt")
	Models.box(self, Vector3(10.0, 0.03, 10.0), Vector3(0.0, 0.015, 0.0), dirt)
	# The sign out front.
	var board := Models.box(self, Vector3(3.2, 1.3, 0.08), Vector3(3.0, 1.6, 5.5), Models.mat(Color(0.95, 0.94, 0.88), &"paint"))
	for x: float in [-1.4, 1.4]:
		Models.box(self, Vector3(0.1, 1.6, 0.1), Vector3(3.0 + x, 0.8, 5.5), Models.mat(Color(0.62, 0.5, 0.4), &"wood"))
	_sign = Label3D.new()
	_sign.modulate = Color(0.15, 0.3, 0.15)
	_sign.outline_size = 0
	_sign.position = Vector3(0.0, 0.0, 0.05)
	board.add_child(_sign)
	_set_sign("FUTURE HOME OF\nAFFORDABLE HOUSING\n(hold F to build)")
	var concrete := Models.mat(Color(0.85, 0.85, 0.83), &"concrete")
	var lumber := Models.mat(Color(0.9, 0.8, 0.62), &"wood")
	var siding := Models.mat(Color(0.75, 0.82, 0.88), &"paint")
	var roofing := Models.mat(Color(0.35, 0.25, 0.22), &"rough")
	# Stage 1: foundation. Stage 2: framing. Stage 3: walls. Stage 4: the house.
	var foundation := Node3D.new()
	Models.box(foundation, Vector3(8.0, 0.35, 7.0), Vector3(0.0, 0.18, 0.0), concrete)
	var framing := Node3D.new()
	for x in range(-4, 5, 2):
		for z: float in [-3.4, 3.4]:
			Models.box(framing, Vector3(0.12, 3.0, 0.12), Vector3(x * 0.95, 1.85, z), lumber)
	for z: float in [-3.4, 3.4]:
		Models.box(framing, Vector3(8.0, 0.12, 0.12), Vector3(0.0, 3.3, z), lumber)
	var walls := Node3D.new()
	for spec in [[Vector3(8.0, 3.0, 0.15), Vector3(0.0, 1.85, -3.45)], [Vector3(0.15, 3.0, 7.0), Vector3(-4.0, 1.85, 0.0)],
			[Vector3(0.15, 3.0, 7.0), Vector3(4.0, 1.85, 0.0)], [Vector3(3.0, 3.0, 0.15), Vector3(-2.5, 1.85, 3.45)],
			[Vector3(3.0, 3.0, 0.15), Vector3(2.5, 1.85, 3.45)]]:
		Models.box(walls, spec[0], spec[1], siding)
	Models.extrude(walls, PackedVector2Array([Vector2(-3.8, 0.0), Vector2(3.8, 0.0), Vector2(0.0, 2.0)]), 8.4, roofing,
		Vector3(0.0, 3.35, 0.0))
	for stage: Node3D in [foundation, framing, walls]:
		stage.visible = false
		add_child(stage)
		_stages.append(stage)
	Models.collider(self, Vector3(8.0, 0.35, 7.0), Vector3(0.0, 0.18, 0.0))


func _set_sign(text: String) -> void:
	_sign.text = text
	Models.fit_label(_sign, Vector2(3.1, 1.2))


func label() -> String:
	return "affordable housing ($%d)" % (cost - int(_paid))


## Called every frame the player holds [F] nearby: builds while the cash
## lasts. Returns true when the house is done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	# Never more than what's left, or than the cash covers.
	var step := minf(minf(delta / build_time, 1.0 - progress), float(Game.cash) / cost)
	var price := step * cost
	if Game.cash <= 0:
		Game.notify("Out of cash: materials for the house cost money ($%d to go)." % (cost - int(_paid)), 2.0)
		return false
	_paid += price
	if _paid >= 1.0:
		var dollars := int(_paid) - int(_paid - price)
		Game.add_cash(-dollars)
	var before := progress
	progress = minf(progress + step, 1.0)
	if floorf(before * 8.0) != floorf(progress * 8.0):
		Sfx.play(&"hit_wood", global_position + Vector3.UP, -4.0, 0.9)
	for i in _stages.size():
		_stages[i].visible = progress >= [0.02, 0.3, 0.6][i]
	if progress >= 1.0:
		_finish()
	return is_fixed


func _finish() -> void:
	is_fixed = true
	for stage in _stages:
		stage.visible = false
	# The finished house, facing the street.
	_house = Models.model("res://assets/kenney/suburban/building-type-%s.glb" % "abcd"[randi() % 4], 8.0)
	_house.position.z = -1.0
	add_child(_house)
	var bounds := Models.model_bounds(_house)
	Models.collider(self, bounds.size, bounds.get_center())
	_set_sign("AFFORDABLE HOUSING\nWELCOME HOME,\nNEIGHBORS!")
	Vfx.dust(get_parent(), global_position + Vector3.UP, 3.0)
	# A family moves in.
	for i in 2:
		var neighbor := Resident.new()
		neighbor.set_role(&"walker" if i == 0 else &"kid")
		neighbor.position = to_global(Vector3(-1.0 + i * 2.0, 0.2, 6.0))
		neighbor.destinations = [global_position + Vector3(0.0, 0.2, 8.0)]
		get_parent().add_child(neighbor)
	get_tree().call_group(&"nav_baker", &"request_rebake", global_position)
	built.emit(self)
