extends TestCase
## Vehicle handling report: drives the level's car through scripted
## maneuvers and measures how much it tilts, leaves the ground, and flips.
## Pass/fail only on gross misbehavior (a flip or a long jump on flat ground).
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/vehicle_probe.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")
const STRIP := Vector3(-84, 0.8, -40)

var level: Node
var player: Player
var car: Car
var _wheels: Array[VehicleWheel3D] = []


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	car = level.get_node("Car") as Car
	for wheel in car.find_children("*", "VehicleWheel3D", false, false):
		_wheels.append(wheel as VehicleWheel3D)
	await seconds(2.0)
	print("\nVEHICLE HANDLING (%s, %.0f kg)" % [car.model_path.get_file(), car.mass])
	print("%-18s | %8s | %9s | %8s | %5s | %6s" % ["maneuver", "max tilt", "airborne", "max up v", "flips", "speed"])
	var worst_flips := 0
	var worst_air := 0.0
	var top_speed := 0.0
	for maneuver in ["straight+turbo", "slalom", "full-lock turn", "hard brake", "curb crossing", "reverse turn"]:
		var result: Array = await _drive(maneuver)
		print("%-18s | %7.0f° | %8.2fs | %7.1f  | %5d | %5.1f" % [maneuver, result[0], result[1], result[2], result[3], result[4]])
		worst_flips = maxi(worst_flips, result[3])
		top_speed = maxf(top_speed, result[4])
		if maneuver != "curb crossing":
			worst_air = maxf(worst_air, result[1])
	check(Car._skid_marks.size() > 0, "hard driving leaves skid marks (%d)" % Car._skid_marks.size())
	await _collisions()
	await _damage()
	check(worst_flips == 0, "no flips in normal driving")
	check(top_speed <= car.max_speed * 1.4 + 1.0, "turbo respects the top speed (%.1f m/s, cap %.1f)" % [top_speed, car.max_speed * 1.4])
	check(worst_air < 0.3, "wheels stay on flat ground (worst airborne %.2fs)" % worst_air)


func _place(at: Vector3, facing: Vector3) -> void:
	if car.driver:
		car.exit()
		await seconds(0.2)
	car.global_transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), at)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await seconds(0.8)
	player.global_position = car.global_position + Vector3(2.5, 0.2, 0.0)
	await seconds(0.1)
	car.enter(player)
	await seconds(0.1)


## Returns [max tilt degrees, airborne seconds, max upward speed, flips, top speed].
func _drive(maneuver: String) -> Array:
	var start := STRIP
	var facing := Vector3.BACK  # +Z, down the strip
	if maneuver == "curb crossing":
		start = Vector3(-14.0, 0.8, 90.0)
		facing = Vector3.RIGHT
	await _place(start, facing)
	var stats := [0.0, 0.0, 0.0, 0, 0.0]
	var flipped := false
	var clock := 0.0
	var length := 6.0
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)
	while clock < length:
		match maneuver:
			"straight+turbo":
				_hold("move_forward", true)
				_hold("sprint", clock > 2.0 and clock < 4.5)
			"slalom":
				_hold("move_forward", true)
				_hold("move_left", clock > 1.5 and int(clock / 0.8) % 2 == 0)
				_hold("move_right", clock > 1.5 and int(clock / 0.8) % 2 == 1)
			"full-lock turn":
				_hold("move_forward", true)
				_hold("sprint", clock < 2.5)
				_hold("move_left", clock > 2.5)
			"hard brake":
				_hold("move_forward", clock < 3.5)
				_hold("sprint", clock > 1.0 and clock < 3.5)
				_hold("jump", clock >= 3.5)
			"curb crossing":
				_hold("move_forward", clock < 3.0)
			"reverse turn":
				_hold("move_back", clock < 3.0)
				_hold("move_right", clock > 1.2 and clock < 3.0)
				_hold("move_forward", clock >= 3.0)
		await get_tree().physics_frame
		var delta := 1.0 / 60.0
		clock += delta
		var tilt := rad_to_deg(car.global_basis.y.angle_to(Vector3.UP))
		stats[0] = maxf(stats[0], tilt)
		if _wheels.all(func(w: VehicleWheel3D) -> bool: return not w.is_in_contact()) and clock > 0.3:
			stats[1] += delta
		stats[2] = maxf(stats[2], car.linear_velocity.y)
		if tilt > 80.0 and not flipped:
			flipped = true
			stats[3] += 1
		elif tilt < 30.0:
			flipped = false
		stats[4] = maxf(stats[4], car.linear_velocity.length())
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)
	return stats


func _hold(action: String, pressed: bool) -> void:
	if pressed and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not pressed and Input.is_action_pressed(action):
		Input.action_release(action)


## Crashes: what happens to the car and to what it hits. Rows report the
## struck body (a parked car) or the driven car (bench, debris).
func _collisions() -> void:
	print("
COLLISIONS")
	print("%-26s | %8s | %8s | %s" % ["case", "max tilt", "max up v", "note"])
	var scene := load("res://scenes/vehicles/car.tscn") as PackedScene
	# 1. Player car rams a parked car at speed.
	var parked := scene.instantiate() as Car
	level.add_child(parked)
	parked.global_transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), STRIP + Vector3(0, 0, 40))
	await _place(STRIP, Vector3.BACK)
	var r := await _watch(parked, 5.0, func(t: float) -> void:
		_hold("move_forward", true)
		_hold("sprint", t > 1.0))
	var mine := [rad_to_deg(car.global_basis.y.angle_to(Vector3.UP))]
	check(car.health < car.max_health and car.health > 0.0, "a crash dents the car without killing it (%.0f/%.0f)" % [car.health, car.max_health])
	check(r[0] < 80.0 and r[1] < 3.0, "a rammed parked car isn't flipped or launched (%.0f°, %.1f m/s up)" % [r[0], r[1]])
	print("%-26s | %7.0f° | %7.1f  | player car ended tilted %.0f°" % ["ram a parked car", r[0], r[1], mine[0]])
	parked.queue_free()
	_hold("move_forward", false)
	_hold("sprint", false)
	car.exit()
	# 2. A police cruiser (kinematic) drives into a parked car.
	parked = scene.instantiate() as Car
	level.add_child(parked)
	parked.global_transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), STRIP + Vector3(0, 0, 60))
	var cruiser := PoliceCruiser.new()
	cruiser.site = &"police"
	cruiser.position = STRIP + Vector3(0, -0.6, 20)
	level.add_child(cruiser)
	await seconds(0.2)
	cruiser.dispatch([STRIP + Vector3(0, 0, 100)] as Array[Vector3], &"felsa")
	r = await _watch(parked, 8.0, func(_t: float) -> void: pass)
	print("%-26s | %7.0f° | %7.1f  | parked car moved %.1f m" % ["cruiser hits a parked car", r[0], r[1],
		parked.global_position.distance_to(STRIP + Vector3(0, 0, 60))])
	cruiser.queue_free()
	parked.queue_free()
	# 3. Player car over wreckage (loose debris boxes).
	for i in 30:
		var chunk := RigidBody3D.new()
		chunk.collision_layer = 8
		chunk.collision_mask = 1 | 4 | 8
		chunk.mass = 40.0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.6, 0.4, 0.6)
		shape.shape = box
		chunk.add_child(shape)
		chunk.add_to_group("debris")
		level.add_child(chunk)
		chunk.global_position = STRIP + Vector3(randf_range(-1.5, 1.5), 0.0, 20.0 + i * 0.6)
	await _place(STRIP, Vector3.BACK)
	r = await _watch(car, 5.0, func(t: float) -> void:
		_hold("move_forward", true)
		_hold("sprint", t > 1.0))
	print("%-26s | %7.0f° | %7.1f  | " % ["drive over debris", r[0], r[1]])
	_hold("move_forward", false)
	_hold("sprint", false)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	# 4. Player car into a solid prop (bench-sized collider) at speed.
	var bench := Models.collider(level, Vector3(1.9, 1.0, 0.6), STRIP + Vector3(0, -0.3, 30))
	await _place(STRIP, Vector3.BACK)
	r = await _watch(car, 5.0, func(t: float) -> void:
		_hold("move_forward", true)
		_hold("sprint", t > 1.0))
	print("%-26s | %7.0f° | %7.1f  | " % ["hit a bench at speed", r[0], r[1]])
	_hold("move_forward", false)
	_hold("sprint", false)
	bench.queue_free()
	car.exit()


## Drives `inputs(time)` for `length` s; returns [max tilt, max up speed] of `body`.
func _watch(body: Node3D, length: float, inputs: Callable) -> Array:
	var worst := [0.0, 0.0]
	var clock := 0.0
	while clock < length:
		inputs.call(clock)
		await get_tree().physics_frame
		clock += 1.0 / 60.0
		if not is_instance_valid(body):
			break
		worst[0] = maxf(worst[0], rad_to_deg(body.global_basis.y.angle_to(Vector3.UP)))
		var velocity: Vector3 = body.get("linear_velocity") if body is RigidBody3D else body.get("velocity")
		worst[1] = maxf(worst[1], velocity.y)
	return worst


## Headlights, smoke, fire, and the explosion into a burnt wreck.
func _damage() -> void:
	await _place(STRIP, Vector3.BACK)
	var beam := car.get("_headlight") as SpotLight3D
	check(beam != null and beam.visible, "the driven car's headlights are on")
	car.health = car.max_health
	car.apply_damage(car.max_health * 0.7, car.global_position + Vector3(5, 0, 0), &"bullet")
	check(car.get("_smoke") != null, "a badly damaged car smokes")
	car.apply_damage(car.max_health * 0.2, car.global_position + Vector3(5, 0, 0), &"bullet")
	check(car.get("_fire") != null, "a nearly dead car catches fire")
	await seconds(5.0)
	check(car.wrecked and car.driver == null and not car.can_enter(), "it explodes into a wreck, throws the driver out, and can't be driven")
	check(player.visible, "the driver is back on foot")
