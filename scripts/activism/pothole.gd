class_name Pothole
extends Node3D
## A pothole in the road: a ragged dark crater with loose gravel and a
## puddle in the bottom. Hold [F] next to it to shovel in cold patch and
## tamp it down; it leaves a fresh black square of asphalt. Until then, cars
## that drive over it take a jolt (and a little damage).

signal fixed(hole: Pothole)

@export var fix_time := 2.0
@export var reach := 2.4
@export var radius := 0.9

var progress := 0.0
var is_fixed := false

var _crater: Node3D
var _patch: MeshInstance3D
var _jolted := {}


func _ready() -> void:
	add_to_group("fixables")
	add_to_group("potholes")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)))
	_crater = Node3D.new()
	add_child(_crater)
	# The hole: a dark irregular disc with a ring of chipped asphalt.
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.07, 0.065, 0.06)
	hole.roughness = 0.95
	var edge := Models.mat(Color(0.55, 0.55, 0.55), &"asphalt")
	var disc := Models.cylinder(_crater, radius, 0.02, Vector3(0.0, 0.046, 0.0), hole, 9)
	disc.scale = Vector3(1.0, 1.0, rng.randf_range(0.65, 0.9))
	disc.rotation.y = rng.randf() * TAU
	for k in 7:
		var angle := k * TAU / 7.0 + rng.randf_range(-0.3, 0.3)
		var chip := Models.box(_crater, Vector3(rng.randf_range(0.3, 0.45), 0.035, rng.randf_range(0.18, 0.26)),
			Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.8 + Vector3.UP * 0.045, edge)
		chip.rotation.y = -angle
	var gravel := Models.mat(Color(0.55, 0.53, 0.5), &"gravel")
	for k in 6:
		Models.ball(_crater, rng.randf_range(0.04, 0.07), Vector3(rng.randf_range(-0.9, 0.9), 0.06, rng.randf_range(-0.9, 0.9)) * radius, gravel)
	var puddle := StandardMaterial3D.new()
	puddle.albedo_color = Color(0.2, 0.25, 0.3, 0.75)
	puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle.roughness = 0.05
	Models.cylinder(_crater, radius * 0.45, 0.01, Vector3(rng.randf_range(-0.2, 0.2), 0.058, 0.0), puddle, 10)
	# The patch it becomes: a neat dark square, hidden until it's filled.
	_patch = Models.box(self, Vector3(radius * 2.3, 0.03, radius * 2.0), Vector3(0.0, 0.05, 0.0),
		Models.mat(Color(0.28, 0.28, 0.3), &"asphalt"))
	_patch.visible = false


func label() -> String:
	return "pothole"


## Called every frame the player holds [F] nearby. Returns true when done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	var before := progress
	progress = minf(progress + delta / fix_time, 1.0)
	if floorf(before * 4.0) != floorf(progress * 4.0):
		Sfx.play(&"hit_wood", global_position, -6.0, 0.6)  # a shovel of cold patch
	if progress >= 1.0:
		is_fixed = true
		_crater.visible = false
		_patch.visible = true
		Vfx.dust(get_parent(), global_position + Vector3.UP * 0.1, 0.6)
		fixed.emit(self)
	return is_fixed


func _physics_process(_delta: float) -> void:
	if is_fixed:
		return
	# Cars rolling through it: one jolt per pass.
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as RigidBody3D
		if car == null:
			continue
		var flat := car.global_position - global_position
		flat.y = 0.0
		var inside := flat.length() < radius + 1.1
		var id := car.get_instance_id()
		if inside and not _jolted.has(id) and car.linear_velocity.length() > 4.0:
			_jolted[id] = true
			car.apply_central_impulse(Vector3.UP * car.mass * 1.2)
			car.apply_torque_impulse(car.global_basis.x * car.mass * 0.4)
			Sfx.play(&"hit_metal", car.global_position, -4.0, 0.5)
			if car.has_method("apply_damage"):
				car.call(&"apply_damage", 5.0, global_position, &"impact")
		elif not inside:
			_jolted.erase(id)
