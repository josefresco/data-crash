class_name RoadRoller
extends Car
## A road roller from the construction site: walking pace, and it flattens
## any hostile it rolls into (it rams at nearly any speed, for huge damage).
## Built from car.tscn (new_from_scene) with a procedural body: a steel drum
## up front, a yellow engine body, and a canopy over the seat.

const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")

var _drum: Node3D


static func new_from_scene() -> RoadRoller:
	var roller := CAR_SCENE.instantiate()
	roller.set_script(RoadRoller)
	return roller as RoadRoller


func _init() -> void:
	model_path = ""
	mass = 6000.0
	max_engine_force = 9000.0
	max_brake = 90.0
	max_speed = 5.0
	ram_min_speed = 0.8
	ram_damage_per_mps = 150.0
	max_health = 3000.0
	lower_center_of_mass = 0.0
	turbo_seconds = 0.0
	engine_cue = &"dozer_loop"


func _ready() -> void:
	super()
	add_to_group("rollers")
	# Hide the placeholder car body and the front tires (the drum covers them).
	for part in ["Chassis", "Cabin", "WheelFL/Mesh", "WheelFR/Mesh"]:
		var node := get_node_or_null(part) as Node3D
		if node:
			node.visible = false
	var yellow := Models.mat(Color(0.95, 0.72, 0.1), &"paint")
	var steel := Models.mat(Color(0.4, 0.41, 0.43), &"metal")
	var dark := Models.mat(Color(0.1, 0.1, 0.11), &"metal")
	Models.box(self, Vector3(1.9, 1.0, 2.2), Vector3(0.0, 1.0, -0.8), yellow)  # engine body
	Models.box(self, Vector3(1.2, 0.9, 1.0), Vector3(0.0, 1.9, -0.6), Models.glass(Color(0.2, 0.25, 0.3, 0.6)))  # seat area
	Models.box(self, Vector3(1.6, 0.08, 1.6), Vector3(0.0, 2.45, -0.6), yellow)  # canopy
	for x in [-0.7, 0.7]:
		Models.box(self, Vector3(0.08, 0.95, 0.08), Vector3(x, 1.95, -0.05), dark)
	Models.box(self, Vector3(2.3, 0.35, 1.4), Vector3(0.0, 1.25, 1.35), yellow)  # drum frame
	_drum = Node3D.new()
	_drum.position = Vector3(0.0, 0.75, 1.55)
	add_child(_drum)
	Models.cylinder(_drum, 0.75, 2.1, Vector3.ZERO, steel, 20).rotation.z = PI * 0.5
	Models.box(self, Vector3(0.12, 0.7, 0.12), Vector3(0.5, 2.2, -1.6), dark)  # exhaust
	Models.set_gi_mode(self, GeometryInstance3D.GI_MODE_DYNAMIC)


func _physics_process(delta: float) -> void:
	super(delta)
	if _drum:
		# Roll the drum with the ground speed.
		_drum.rotate_x(global_basis.z.dot(linear_velocity) / 0.75 * delta)
