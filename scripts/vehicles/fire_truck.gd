class_name FireTruck
extends Car
## The fire department's truck: heavy and slow, with a roof water cannon.
## While driving, the fire button sprays forward like a giant fire hose:
## people get knocked flat and soaked, protesters scatter, fires go out.
## Built from car.tscn (new_from_scene): the Kenney box van painted red, with
## a roof ladder, a light bar, and a white stripe.

const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")

var cannon: Weapon
var _nozzle: Node3D
var _jet: GPUParticles3D
var _hiss: AudioStreamPlayer3D
var _spray_left := 0.0
var _tick_left := 0.0


static func new_from_scene() -> FireTruck:
	var truck := CAR_SCENE.instantiate()
	truck.set_script(FireTruck)
	return truck as FireTruck


func _init() -> void:
	model_path = "res://assets/kenney/cars/delivery.glb"
	model_scale = 1.55
	fit_to_model = true
	mass = 4000.0
	max_engine_force = 8000.0
	max_brake = 80.0
	max_speed = 14.0
	ram_min_speed = 3.0
	ram_damage_per_mps = 18.0
	max_health = 1600.0
	lower_center_of_mass = 0.35
	turbo_seconds = 0.0
	engine_cue = &"dozer_loop"
	cannon = Weapon.make("Roof cannon", {"kind": Weapon.Kind.SPRAY, "damage": 10.0, "cooldown": 0.1,
		"reach": 22.0, "knockback": 0.9, "douse": 12.0, "stuns": true, "sound": &"hiss_loop"})


func _ready() -> void:
	super()
	add_to_group("fire_trucks")
	_paint_red()
	var box := get_node("CollisionShape3D") as CollisionShape3D
	var size := (box.shape as BoxShape3D).size
	var steel := Models.mat(Color(0.75, 0.76, 0.78), &"metal")
	var roof := _model_top()
	# Ladder along the roof, a light bar over the cab, a white stripe.
	for x in [-0.35, 0.35]:
		Models.box(self, Vector3(0.06, 0.06, size.z * 0.8), Vector3(x, roof + 0.08, box.position.z - size.z * 0.05), steel)
	for k in 9:
		Models.box(self, Vector3(0.7, 0.04, 0.05), Vector3(0.0, roof + 0.08, box.position.z - size.z * 0.42 + k * size.z * 0.09), steel)
	Models.box(self, Vector3(1.2, 0.14, 0.25), Vector3(0.0, roof + 0.1, box.position.z + size.z * 0.36), Models.glow(Color(1.0, 0.1, 0.05), 3.0))
	for side in [-1.0, 1.0]:
		Models.box(self, Vector3(0.02, 0.14, size.z * 0.85), box.position + Vector3(side * (size.x * 0.5 + 0.02), -size.y * 0.1, 0.0),
			Models.mat(Color(0.95, 0.95, 0.9), &"paint"))
	# Roof cannon: a swivel base and a brass barrel pointing forward (+Z).
	_nozzle = Node3D.new()
	_nozzle.position = Vector3(0.0, roof + 0.25, box.position.z + size.z * 0.12)
	add_child(_nozzle)
	Models.cylinder(_nozzle, 0.22, 0.25, Vector3.ZERO, steel, 12)
	Models.cylinder(_nozzle, 0.07, 1.1, Vector3(0.0, 0.2, 0.5), Models.mat(Color(0.8, 0.62, 0.25), &"metal"), 10).rotation.x = PI * 0.5
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.0, 0.2, 1.1)
	_nozzle.add_child(muzzle)
	_jet = Vfx.water_jet(muzzle)
	_jet.rotation.y = PI  # the emitter sprays along its -Z; the cannon points +Z
	var jet_material := _jet.process_material as ParticleProcessMaterial
	jet_material.initial_velocity_min = cannon.reach * 1.25
	jet_material.initial_velocity_max = cannon.reach * 1.4
	jet_material.scale_min = 0.5
	jet_material.scale_max = 0.9


## Height of the model's roof above this body's origin.
func _model_top() -> float:
	var top := 1.5
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.visible and mesh.mesh and mesh.get_parent() is not VehicleWheel3D:
			top = maxf(top, (mesh.global_transform * mesh.mesh.get_aabb()).end.y - global_position.y)
	return top


## Fire-engine red body, keeping the glass and tires dark.
func _paint_red() -> void:
	var red := Models.mat(Color(0.78, 0.08, 0.06), &"paint")
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.visible and mesh.get_parent() is not VehicleWheel3D and mesh.material_override == null:
			mesh.material_override = red


func _physics_process(delta: float) -> void:
	super(delta)
	_spray_left = maxf(_spray_left - delta, 0.0)
	if driver and not wrecked and Input.is_action_pressed("fire"):
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = cannon.cooldown
			fire_cannon()
	if _spray_left <= 0.0:
		if _jet and _jet.emitting:
			_jet.emitting = false
		if _hiss and _hiss.playing:
			_hiss.stop()


## One tick of the roof cannon along the truck's nose. Public for tests.
func fire_cannon() -> void:
	_spray_left = 0.2
	_jet.emitting = true
	if _hiss == null:
		_hiss = Sfx.loop(self, cannon.sound, -4.0)
	if _hiss and not _hiss.playing:
		_hiss.play()
	var aim := (global_basis.z + Vector3.UP * 0.06).normalized()
	Hose.spray_tick(self, _nozzle.global_position + aim * 1.2, aim, cannon, [get_rid()])
	Game.tip("fire_truck", "The fire truck's roof cannon: hold fire while driving to blast people off their feet and put out fires.")
