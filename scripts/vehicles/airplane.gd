class_name Airplane
extends Aircraft
## A little prop plane from the regional airport. [W/S] throttle, [A/D]
## turn (it banks), mouse up/down to pitch once it's fast enough to fly
## (`takeoff_speed`). Too slow in the air and it sinks. [E] on the ground at
## a crawl climbs out; [E] in the air bails out: the pilot pops a parachute
## and the plane flies on, nose down, until it hits something. Flown into a
## datacenter it's a big blast (`crash_damage`, `crash_radius`).

@export var max_speed := 46.0
@export var takeoff_speed := 22.0
@export var throttle_rate := 9.0
@export var turn_rate := 0.9
@export var paint := Color(0.92, 0.92, 0.9)
@export var stripe := Color(0.85, 0.2, 0.15)

var pitch := 0.0
var bank := 0.0
## Pilotless: flying on after a bail-out.
var autopilot := false

var _prop: Node3D
## Seconds off the ground (a touchdown only counts after real flight).
var _air_time := 0.0
var _flew := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _init() -> void:
	max_health = 260.0
	seats = 0
	crash_speed = 9.0
	crash_radius = 13.0
	crash_damage = 900.0
	reach = 6.0


func _body_size() -> Vector3:
	return Vector3(1.8, 1.9, 7.0)


func _chase_distance() -> float:
	return 16.0


func _controls_tip() -> String:
	return "Plane: W/S throttle, A/D turn, mouse up/down to climb once you're fast. E on the ground to get out; E in the air to bail out (the plane flies on, into whatever's ahead)."


func _fly(delta: float) -> void:
	var grounded := is_on_floor()
	_air_time = 0.0 if grounded else _air_time + delta
	var turn := 0.0
	if pilot:
		speed = clampf(speed + Input.get_axis("move_back", "move_forward") * throttle_rate * delta, 0.0, max_speed)
		turn = Input.get_axis("move_right", "move_left")
	elif autopilot:
		# Nose gently down (never pulls out of a steeper dive), and a
		# pilotless plane touching down is a crash.
		pitch = minf(pitch, move_toward(pitch, -0.14, delta * 0.2))
		if grounded and _air_time == 0.0 and _flew:
			crash()
			return
		if _air_time > 0.3:
			_flew = true
	else:
		speed = move_toward(speed, 0.0, 10.0 * delta)
	if grounded:
		pitch = maxf(pitch, 0.0) if speed >= takeoff_speed else 0.0
	global_rotation.y += turn * turn_rate * delta * clampf(speed / 10.0, 0.0, 1.0)
	bank = move_toward(bank, turn * 0.5 * clampf(speed / takeoff_speed, 0.0, 1.0), delta * 1.5)
	var forward := -global_basis.z
	velocity = forward * speed * cos(pitch) + Vector3.UP * speed * sin(pitch)
	var lift := clampf(speed / takeoff_speed, 0.0, 1.0)
	if not grounded:
		velocity.y -= _gravity * (1.0 - lift) * 2.0
	_visual.rotation = Vector3(pitch, 0.0, bank)
	if _prop:
		_prop.rotation.z += delta * (6.0 + speed * 1.5)


func _mouse(relative: Vector2) -> void:
	# Pitch with the mouse once there's flying speed.
	if speed >= takeoff_speed * 0.9:
		pitch = clampf(pitch - relative.y * 0.8, -0.6, 0.6)
	else:
		super(relative)


func _on_exit_pressed() -> void:
	# On the ground (even rolling): step out, and the plane coasts to a stop.
	if is_on_floor():
		leave(global_position + global_basis.x * 4.0 + Vector3.UP * 0.5)
		return
	# Bail out: a parachute for the pilot, and the plane flies on.
	var player := pilot
	autopilot = true
	leave(global_position + Vector3.UP * 3.0 + global_basis.x * 3.0)
	player.parachute()
	Game.notify("You bailed out! The plane's on its own now...", 3.0)


func _build_model(root: Node3D) -> void:
	var body := Models.mat(paint, &"paint")
	var red := Models.mat(stripe, &"paint")
	var dark := Models.mat(Color(0.1, 0.1, 0.12), &"metal")
	var glass := Models.glass(Color(0.4, 0.55, 0.7, 0.5))
	var fuselage := Models.cylinder(root, 0.7, 6.5, Vector3(0.0, 1.3, 0.2), body, 12)
	fuselage.rotation.x = PI * 0.5
	Models.cylinder(root, 0.72, 0.4, Vector3(0.0, 1.3, -2.2), red, 12).rotation.x = PI * 0.5
	Models.box(root, Vector3(1.0, 0.6, 1.4), Vector3(0.0, 1.95, -0.6), glass)  # canopy
	Models.box(root, Vector3(10.5, 0.14, 1.6), Vector3(0.0, 1.5, -0.4), body)  # wings
	for x: float in [-4.6, 4.6]:
		Models.box(root, Vector3(1.2, 0.16, 1.62), Vector3(x, 1.5, -0.4), red)
	Models.box(root, Vector3(3.6, 0.1, 1.0), Vector3(0.0, 1.5, 3.1), body)  # tailplane
	Models.box(root, Vector3(0.1, 1.4, 1.1), Vector3(0.0, 2.2, 3.1), red)  # fin
	# Propeller on the nose, and fixed gear.
	_prop = Node3D.new()
	_prop.position = Vector3(0.0, 1.3, -3.05)
	root.add_child(_prop)
	Models.box(_prop, Vector3(2.2, 0.16, 0.05), Vector3.ZERO, dark)
	Models.ball(root, 0.22, Vector3(0.0, 1.3, -3.0), dark)
	for x: float in [-1.1, 1.1]:
		Models.box(root, Vector3(0.08, 0.9, 0.08), Vector3(x, 0.65, -0.6), dark)
		var wheel := Models.cylinder(root, 0.3, 0.18, Vector3(x, 0.3, -0.6), dark, 12)
		wheel.rotation.z = PI * 0.5
	Models.cylinder(root, 0.15, 0.1, Vector3(0.0, 0.5, 3.0), dark, 8).rotation.z = PI * 0.5
