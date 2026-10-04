class_name Aircraft
extends CharacterBody3D
## Base for the airport's flyable aircraft (Airplane, Helicopter): boarding
## ([E] nearby; the player hides and this camera takes over), flying
## (`_fly(delta)` in subclasses, arcade physics on a CharacterBody3D),
## health (bullets, blasts, crashes), and passengers: allies within
## `board_radius` climb aboard with you (up to `seats`) and climb out where
## you land (`_unload()`). A hard hit on anything (`crash_speed`) ends in an
## explosion (`crash_damage` in `crash_radius`) and a burnt wreck.

signal crashed(craft: Aircraft)

@export var max_health := 300.0
@export var seats := 4
@export var board_radius := 15.0
@export var crash_speed := 14.0
@export var crash_radius := 10.0
@export var crash_damage := 500.0
@export var reach := 5.0

var health := 0.0
var pilot: Player = null
var passengers: Array[Enemy] = []
var is_wrecked := false
## Forward speed (m/s) along -Z.
var speed := 0.0

var _camera: Camera3D
var _cam_rig: Node3D
var _yaw := 0.0
var _cam_pitch := -0.25
var _visual: Node3D
var _board_frame := -1
var _engine: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("aircraft")
	add_to_group("interactables")
	add_to_group("vehicles_air")
	health = max_health
	collision_layer = Game.LAYER_VEHICLES
	collision_mask = Game.LAYER_WORLD | Game.LAYER_DESTRUCTIBLE | Game.LAYER_VEHICLES
	_visual = Node3D.new()
	add_child(_visual)
	_build_model(_visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _body_size()
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)
	_cam_rig = Node3D.new()
	_cam_rig.top_level = true
	add_child(_cam_rig)
	_camera = Camera3D.new()
	_camera.far = 900.0
	_cam_rig.add_child(_camera)
	_yaw = global_rotation.y
	Models.set_gi_mode(self, GeometryInstance3D.GI_MODE_DYNAMIC)


## Overrides: the model (origin at the ground, nose -Z) and collider size.
func _build_model(_root: Node3D) -> void:
	pass


func _body_size() -> Vector3:
	return Vector3(2.0, 2.0, 6.0)


func _fly(_delta: float) -> void:
	pass


func _chase_distance() -> float:
	return 14.0


func in_reach(player: Node3D) -> bool:
	return not is_wrecked and pilot == null and player.global_position.distance_to(global_position) <= reach


func offer_text(_player: Player) -> String:
	return "[E] Climb in and fly (allies nearby come too)"


func interact(player: Player) -> void:
	board(player)


func board(player: Player) -> void:
	if is_wrecked or pilot != null:
		return
	pilot = player
	_board_frame = Engine.get_physics_frames()
	player.board_aircraft(self)
	_camera.make_current()
	_yaw = global_rotation.y
	# Allies close by pile in.
	passengers.clear()
	var orders := get_tree().get_first_node_in_group("ally_orders") as AllyOrders
	var team: Array[Enemy] = orders.squad() if orders else []
	for unit in team:
		if passengers.size() >= seats:
			break
		if unit.global_position.distance_to(global_position) <= board_radius:
			passengers.append(unit)
			unit.visible = false
			unit.process_mode = Node.PROCESS_MODE_DISABLED
			unit.collision_layer = 0
			unit.global_position = global_position
	if not passengers.is_empty():
		Game.notify("%d allies climbed aboard." % passengers.size(), 3.0)
	if _engine == null:
		_engine = Sfx.loop(self, &"engine_loop", -8.0)
	if _engine:
		_engine.play()
	# get_class() is the native class for both; the script's name tells them apart.
	Game.tip("aircraft_%s" % (get_script() as Script).get_global_name(), _controls_tip())


func _controls_tip() -> String:
	return "Flying: WASD, mouse to look, [E] to get out."


## Out of the cockpit at `at` (and passengers with you, via _unload).
func leave(at: Vector3) -> void:
	if pilot == null:
		return
	var player := pilot
	pilot = null
	player.leave_aircraft(at)
	_unload(at)
	if _engine:
		_engine.stop()


## Passengers climb out around `at` (subclasses can drop them elsewhere).
func _unload(at: Vector3) -> void:
	for i in passengers.size():
		var unit := passengers[i]
		if not is_instance_valid(unit):
			continue
		unit.global_position = at + Vector3(cos(i * 1.6) * 2.0, 0.2, sin(i * 1.6) * 2.0)
		unit.visible = true
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		unit.collision_layer = Game.LAYER_ENEMIES
	passengers.clear()


func _physics_process(delta: float) -> void:
	if is_wrecked:
		# The shell falls and stays where it lands.
		if not is_on_floor():
			velocity.y -= 9.8 * delta
			velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
			move_and_slide()
		return
	if pilot and Engine.get_physics_frames() != _board_frame and Input.is_action_just_pressed("interact"):
		_on_exit_pressed()
		return
	var before := velocity
	_fly(delta)
	var hit := move_and_slide()
	if hit:
		var impact := (before - velocity).length()
		if impact > crash_speed:
			crash()
			return
		# Buildings and props aren't runways: touching one at speed (a roof
		# counts as "floor" to a body) is a crash.
		if before.length() > crash_speed:
			for i in get_slide_collision_count():
				var other := get_slide_collision(i).get_collider() as CollisionObject3D
				if other and other.collision_layer & Game.LAYER_DESTRUCTIBLE:
					crash()
					return
	# The hidden pilot rides along (minimap, tips, ranges read the player).
	if pilot:
		pilot.global_position = global_position
	_update_camera(delta)


## [E] while flying: subclasses decide (land and step out, or bail out).
func _on_exit_pressed() -> void:
	leave(global_position + global_basis.x * 3.0 + Vector3.UP * 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if pilot == null or not event is InputEventMouseMotion or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	_mouse(motion.relative * Game.mouse_sensitivity)


## Mouse look (subclasses may steer with it).
func _mouse(relative: Vector2) -> void:
	_cam_pitch = clampf(_cam_pitch - relative.y, -1.2, 0.5)


func _update_camera(delta: float) -> void:
	if pilot == null:
		return
	var back := Basis(Vector3.UP, global_rotation.y) * Basis(Vector3.RIGHT, _cam_pitch)
	var target := global_position + Vector3.UP * 2.5 + back * Vector3(0.0, 0.0, _chase_distance())
	_cam_rig.global_position = _cam_rig.global_position.lerp(target, 1.0 - exp(-8.0 * delta))
	_cam_rig.look_at(global_position + Vector3.UP * 1.5)


func apply_damage(amount: float, _from: Vector3, _kind: StringName = &"generic") -> void:
	if is_wrecked:
		return
	health -= amount
	if health <= 0.0:
		crash()


## Boom: a big blast here, the pilot (if still aboard) is thrown clear, and
## a charred shell stays.
func crash() -> void:
	if is_wrecked:
		return
	is_wrecked = true
	var at := global_position
	# Passengers go down with it: take them off the list before leave()
	# unloads (or rappels) them.
	var aboard := passengers.duplicate()
	passengers.clear()
	if pilot:
		leave(at + Vector3(4.0, 2.0, 0.0))
	for unit in aboard:
		if is_instance_valid(unit):
			unit.queue_free()
	var blast := Explosive.new()
	blast.radius = crash_radius
	blast.damage = crash_damage
	get_parent().add_child(blast)
	blast.global_position = at + Vector3.UP
	blast.detonate.call_deferred()
	var burnt := Models.mat(Color(0.12, 0.11, 0.1), &"rough")
	for mesh: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = burnt
	Vfx.fire_patch(self, Vector3.UP * 1.0, 1.2)
	Vfx.smoke_column(self, Vector3.UP * 2.0, 1.6)
	if _engine:
		_engine.stop()
	velocity = Vector3.ZERO
	collision_layer = Game.LAYER_DEBRIS
	remove_from_group("interactables")
	crashed.emit(self)
