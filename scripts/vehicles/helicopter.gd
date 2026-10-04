class_name Helicopter
extends Aircraft
## A news-and-traffic helicopter from the airport, room for four allies.
## [W/S] fly forward/back, [A/D] turn (and the mouse), [Space] climb, [C]
## descend. [E] only works landed: you and your passengers climb out. Landed
## on a datacenter's roof, the allies rappel down the side to the ground
## beside its cooling units (inside the fence, past the gate guards) and go
## straight for them (an order, see AllyOrders).

@export var max_speed := 18.0
@export var climb_speed := 7.0
@export var turn_rate := 1.6
@export var paint := Color(0.2, 0.35, 0.6)

var _rotor: Node3D
var _tail_rotor: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rotor_speed := 0.0


func _init() -> void:
	max_health = 320.0
	seats = 4
	crash_speed = 11.0
	crash_radius = 9.0
	crash_damage = 400.0
	reach = 5.0


func _body_size() -> Vector3:
	return Vector3(2.4, 2.4, 5.0)


func _controls_tip() -> String:
	return "Helicopter: W/S forward/back, A/D or the mouse to turn, Space up, C down. Land and press E to climb out. Land on a datacenter's roof and your allies rappel down to its cooling units."


func _fly(delta: float) -> void:
	var grounded := is_on_floor()
	if pilot:
		_rotor_speed = move_toward(_rotor_speed, 1.0, delta * 0.6)
		var lift := Input.get_axis("descend", "jump") * climb_speed
		var forward := -global_basis.z
		var drive := Input.get_axis("move_back", "move_forward") * max_speed
		speed = move_toward(speed, drive, 10.0 * delta)
		global_rotation.y += Input.get_axis("move_right", "move_left") * turn_rate * delta
		var target := forward * speed
		target.y = lift if _rotor_speed > 0.8 else -2.0
		velocity = velocity.lerp(target, 1.0 - exp(-3.0 * delta))
		_visual.rotation.x = lerpf(_visual.rotation.x, -speed / max_speed * 0.25, 1.0 - exp(-4.0 * delta))
	else:
		_rotor_speed = move_toward(_rotor_speed, 0.0, delta * 0.3)
		speed = 0.0
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		if not grounded:
			velocity.y -= _gravity * delta * (1.0 - _rotor_speed * 0.8)
		_visual.rotation.x = move_toward(_visual.rotation.x, 0.0, delta)
	if grounded and velocity.y < 0.0:
		velocity.y = 0.0
	if _rotor:
		_rotor.rotation.y += delta * 30.0 * _rotor_speed
	if _tail_rotor:
		_tail_rotor.rotation.x += delta * 40.0 * _rotor_speed


func _mouse(relative: Vector2) -> void:
	global_rotation.y -= relative.x * 0.8
	super(relative)


func _on_exit_pressed() -> void:
	if not is_on_floor():
		Game.notify("Land first (C to descend).", 2.0)
		return
	leave(global_position + global_basis.x * 3.0 + Vector3.UP * 0.4)


## Landed on a datacenter: allies rappel to its cooling units.
func _unload(at: Vector3) -> void:
	var site_node := roof_site()
	if site_node == null or passengers.is_empty():
		super(at)
		return
	var goal: Destructible = null
	for node in site_node.datacenter.find_children("*", "Destructible", true, false):
		var part := node as Destructible
		if part.is_in_group(&"cooling_units") and not part.is_destroyed:
			if goal == null or part.global_position.distance_to(global_position) < goal.global_position.distance_to(global_position):
				goal = part
	if goal == null:
		super(at)
		return
	var ground := goal.global_position
	for i in passengers.size():
		var unit := passengers[i]
		if not is_instance_valid(unit):
			continue
		var spot := ground + Vector3(cos(i * 1.6) * 3.5, 0.2, sin(i * 1.6) * 3.5)
		# The rope, from the roof edge to the ground, for a few seconds.
		var rope := Models.box(get_parent() as Node3D, Vector3(0.04, global_position.y, 0.04),
			Vector3(spot.x, global_position.y * 0.5, spot.z), Models.mat(Color(0.2, 0.2, 0.2), &"cloth"))
		var tween := rope.create_tween()
		tween.tween_interval(4.0)
		tween.tween_callback(rope.queue_free)
		unit.global_position = spot
		unit.visible = true
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		unit.collision_layer = Game.LAYER_ENEMIES
		unit.give_order(goal.global_position)
	Game.notify("Your allies rappel down to %s's cooling units!" % site_node.display_name, 4.0)
	passengers.clear()


## The datacenter whose roof this is sitting on, or null.
func roof_site() -> DatacenterSite:
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		var site_node := node as DatacenterSite
		var building := site_node.datacenter
		if building == null or not is_instance_valid(building):
			continue
		var local := building.to_local(global_position)
		if absf(local.x) <= building.footprint.x * 0.5 and absf(local.z) <= building.footprint.y * 0.5 and local.y > building.height * 0.6:
			return site_node
	return null


func _build_model(root: Node3D) -> void:
	var body := Models.mat(paint, &"paint")
	var white := Models.mat(Color(0.92, 0.92, 0.9), &"paint")
	var dark := Models.mat(Color(0.1, 0.1, 0.12), &"metal")
	var glass := Models.glass(Color(0.35, 0.5, 0.65, 0.55))
	var cabin := Models.ball(root, 1.2, Vector3(0.0, 1.6, -0.4), body)
	cabin.scale = Vector3(1.0, 0.9, 1.4)
	Models.ball(root, 0.9, Vector3(0.0, 1.8, -1.3), glass).scale = Vector3(1.05, 0.8, 0.9)
	var boom := Models.cylinder(root, 0.22, 4.2, Vector3(0.0, 1.8, 2.6), body, 8)
	boom.rotation.x = PI * 0.5
	Models.box(root, Vector3(0.1, 1.1, 0.7), Vector3(0.0, 2.3, 4.6), white)  # tail fin
	Models.box(root, Vector3(2.4, 0.3, 0.05), Vector3(0.0, 1.5, -0.4), white)  # stripe
	# Skids.
	for x: float in [-0.9, 0.9]:
		Models.box(root, Vector3(0.08, 0.08, 3.4), Vector3(x, 0.08, -0.3), dark)
		for z: float in [-1.2, 0.6]:
			Models.box(root, Vector3(0.06, 0.6, 0.06), Vector3(x * 0.8, 0.4, z), dark)
	# Rotors.
	Models.cylinder(root, 0.12, 0.5, Vector3(0.0, 2.9, -0.3), dark, 8)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0.0, 3.15, -0.3)
	root.add_child(_rotor)
	for k in 2:
		Models.box(_rotor, Vector3(9.0, 0.05, 0.3), Vector3.ZERO, dark).rotation.y = k * PI * 0.5
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.25, 2.3, 4.6)
	root.add_child(_tail_rotor)
	Models.box(_tail_rotor, Vector3(0.04, 1.4, 0.15), Vector3.ZERO, dark)
	var label := Label3D.new()
	label.text = "CHANNEL 6\nSKY NEWS"
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_size = 0
	label.position = Vector3(1.21, 1.6, 0.2)
	label.rotation.y = PI * 0.5
	root.add_child(label)
	Models.fit_label(label, Vector2(1.4, 0.6))
