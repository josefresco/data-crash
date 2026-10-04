class_name Playground
extends Node3D
## A patch of the park fenced off for a playground (a good deed). Hold [F]
## to build it: `cost` in all, paid as you go. Finished, it has swings, a
## slide, a see-saw, and a sandbox with kids playing, and the moms who
## bring them join the fight their way: `moms_earned` Moms who march up to
## the police with picket signs and keep them busy.

signal built(playground: Playground)

@export var cost := 120
@export var build_time := 5.0
@export var reach := 7.0
@export var moms_earned := 3

var progress := 0.0
var is_fixed := false

var _paid := 0.0
var _equipment: Node3D
var _tape: Node3D
var _sign: Label3D


func _ready() -> void:
	add_to_group("fixables")
	add_to_group("playgrounds")
	set_meta(&"poi", "Y")
	set_meta(&"poi_color", Color(1.0, 0.7, 0.9))
	add_to_group("map_pois")
	# Wood-chip ground and a caution-taped outline until it's built.
	Models.box(self, Vector3(12.0, 0.04, 10.0), Vector3(0.0, 0.03, 0.0), Models.mat(Color(0.75, 0.55, 0.4), &"wood"))
	_tape = Node3D.new()
	add_child(_tape)
	var yellow := Models.mat(Color(1.0, 0.85, 0.1), &"paint")
	for corner: Vector3 in [Vector3(-6, 0, -5), Vector3(6, 0, -5), Vector3(6, 0, 5), Vector3(-6, 0, 5)]:
		Models.cylinder(_tape, 0.04, 1.0, corner + Vector3.UP * 0.5, Models.mat(Color(0.95, 0.4, 0.1), &"paint"), 6)
	for spec in [[Vector3(12.0, 0.06, 0.02), Vector3(0, 0.9, -5)], [Vector3(12.0, 0.06, 0.02), Vector3(0, 0.9, 5)],
			[Vector3(0.02, 0.06, 10.0), Vector3(-6, 0.9, 0)], [Vector3(0.02, 0.06, 10.0), Vector3(6, 0.9, 0)]]:
		Models.box(_tape, spec[0], spec[1], yellow)
	var board := Models.box(self, Vector3(2.6, 1.0, 0.08), Vector3(0.0, 1.4, 5.3), Models.mat(Color(0.95, 0.94, 0.88), &"paint"))
	Models.box(self, Vector3(0.1, 1.4, 0.1), Vector3(0.0, 0.7, 5.3), Models.mat(Color(0.62, 0.5, 0.4), &"wood"))
	_sign = Label3D.new()
	_sign.modulate = Color(0.6, 0.2, 0.5)
	_sign.outline_size = 0
	_sign.position = Vector3(0.0, 0.0, 0.05)
	board.add_child(_sign)
	_set_sign("FUTURE PLAYGROUND\n(hold F to build)")
	_equipment = Node3D.new()
	_equipment.visible = false
	add_child(_equipment)
	_build_equipment(_equipment)


func _set_sign(text: String) -> void:
	_sign.text = text
	Models.fit_label(_sign, Vector2(2.5, 0.9))


func label() -> String:
	return "the playground ($%d)" % (cost - int(_paid))


## Called every frame the player holds [F] nearby. Returns true when done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	if Game.cash <= 0:
		Game.notify("Out of cash: the playground kit costs money ($%d to go)." % (cost - int(_paid)), 2.0)
		return false
	# Never more than what's left, or than the cash covers.
	var step := minf(minf(delta / build_time, 1.0 - progress), float(Game.cash) / cost)
	var price := step * cost
	_paid += price
	var dollars := int(_paid) - int(_paid - price)
	if dollars > 0:
		Game.add_cash(-dollars)
	var before := progress
	progress = minf(progress + step, 1.0)
	if floorf(before * 6.0) != floorf(progress * 6.0):
		Sfx.play(&"hit_metal", global_position + Vector3.UP, -6.0, 1.2)
	if progress >= 1.0:
		_finish()
	return is_fixed


func _finish() -> void:
	is_fixed = true
	_tape.visible = false
	_equipment.visible = true
	_set_sign("COMMUNITY PLAYGROUND\nBUILT BY NEIGHBORS")
	Vfx.dust(get_parent(), global_position + Vector3.UP, 3.0)
	# Kids playing, and their moms, who join the cause.
	for i in 2:
		var kid := Resident.new()
		kid.set_role(&"kid")
		kid.position = to_global(Vector3(-2.0 + i * 4.0, 0.2, 0.0))
		get_parent().add_child(kid)
	for i in moms_earned:
		var mom := Mom.new()
		mom.position = to_global(Vector3(-3.0 + i * 3.0, 0.2, 3.5))
		get_parent().add_child(mom)
		if i == 0:
			mom.speak("Thank you! Now, about those police officers...")
	get_tree().call_group(&"nav_baker", &"request_rebake")
	built.emit(self)


func _build_equipment(root: Node3D) -> void:
	var red := Models.mat(Color(0.85, 0.15, 0.15), &"paint")
	var blue := Models.mat(Color(0.2, 0.45, 0.85), &"paint")
	var yellow := Models.mat(Color(0.98, 0.8, 0.15), &"paint")
	var steel := Models.mat(Color(0.65, 0.66, 0.68), &"metal")
	var sand := Models.mat(Color(0.9, 0.82, 0.6), &"dirt")
	# Swing set: an A-frame each end, a top bar, two seats on chains.
	for x: float in [-4.8, -1.8]:
		for z: float in [-0.6, 0.6]:
			var leg := Models.cylinder(root, 0.05, 2.6, Vector3(x, 1.25, -3.0 + z), red, 6)
			leg.rotation.x = z * 0.35
	Models.cylinder(root, 0.05, 3.0, Vector3(-3.3, 2.5, -3.0), red, 6).rotation.z = PI * 0.5
	for x: float in [-4.0, -2.6]:
		for dx: float in [-0.2, 0.2]:
			Models.box(root, Vector3(0.02, 1.8, 0.02), Vector3(x + dx, 1.55, -3.0), steel)
		Models.box(root, Vector3(0.5, 0.05, 0.2), Vector3(x, 0.65, -3.0), blue)
	Models.collider(root, Vector3(3.4, 2.6, 1.6), Vector3(-3.3, 1.3, -3.0))
	# Slide: a ladder tower and a sloped chute.
	Models.box(root, Vector3(1.2, 0.1, 1.2), Vector3(3.0, 1.8, -2.5), yellow)
	for x: float in [2.5, 3.5]:
		for z: float in [-3.0, -2.0]:
			Models.cylinder(root, 0.05, 2.6, Vector3(x, 1.3, z), blue, 6)
	var chute := Models.box(root, Vector3(0.8, 0.06, 3.0), Vector3(3.0, 1.0, -0.6), red)
	chute.rotation.x = -0.6
	Models.collider(root, Vector3(1.4, 2.6, 1.4), Vector3(3.0, 1.3, -2.5))
	# See-saw.
	Models.box(root, Vector3(0.3, 0.4, 0.3), Vector3(-3.0, 0.2, 2.0), steel)
	var plank := Models.box(root, Vector3(3.2, 0.08, 0.3), Vector3(-3.0, 0.45, 2.0), yellow)
	plank.rotation.z = 0.2
	# Sandbox with a bucket.
	for spec in [[Vector3(3.0, 0.3, 0.12), Vector3(3.0, 0.15, 0.8)], [Vector3(3.0, 0.3, 0.12), Vector3(3.0, 0.15, 3.2)],
			[Vector3(0.12, 0.3, 2.4), Vector3(1.5, 0.15, 2.0)], [Vector3(0.12, 0.3, 2.4), Vector3(4.5, 0.15, 2.0)]]:
		Models.box(root, spec[0], spec[1], Models.mat(Color(0.75, 0.6, 0.48), &"wood"))
	Models.box(root, Vector3(2.9, 0.12, 2.3), Vector3(3.0, 0.1, 2.0), sand)
	Models.cylinder(root, 0.12, 0.2, Vector3(3.4, 0.25, 2.2), blue, 8)
