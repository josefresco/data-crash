extends TestCase
## Felsa Cars and the Elmo Mushbrains boss fight, end to end into Phase 3.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/boss_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(0.5)

	await _test_felsa_car()
	await _test_boss()


func _test_felsa_car() -> void:
	player.global_position = Vector3(-40, 0.2, 45)
	var car := FelsaCar.new()
	car.position = Vector3(-40, 0.2, 25)
	level.add_child(car)
	var hits := [0]
	player.health_changed.connect(func(_h: float, _m: float) -> void: hits[0] += 1)
	for i in 60:
		if hits[0] > 0:
			break
		await seconds(0.25)
	check(hits[0] > 0, "Felsa car rams the player")

	# EMP hack: battery fire burns it out, and the blast hurts its friends.
	var bystander := SecurityGuard.new()
	bystander.position = car.global_position + Vector3(2.5, 0, 0)
	level.add_child(bystander)
	bystander.set_physics_process(false)
	car.stun(3.0)
	check(car.is_burning, "EMP hacks the car into a battery fire")
	for i in 40:
		if not car.is_alive():
			break
		await seconds(0.25)
	await seconds(0.3)
	check(not car.is_alive(), "burning car burns out")
	check(bystander.health < bystander.max_health, "battery explosion hits nearby hostiles")
	bystander.apply_damage(9999.0, Vector3.ZERO)


func _test_boss() -> void:
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in 80:
		if level.phase == level.Phase.BOSS:
			break
		await seconds(0.25)
	check(level.phase == level.Phase.BOSS, "boss phase starts after the collapse")

	var truck: ElmoTruck = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		if node is ElmoTruck:
			truck = node
	check(truck != null, "Elmo's truck arrives")
	if truck == null:
		return

	var hp := truck.health
	truck.stun(5.0)
	check(not truck.is_burning and truck.health < hp, "EMP only dents the boss truck")

	# Let it hunt the player for a while: it should ram or shockwave.
	player.global_position = Vector3(0, 0.2, 20)
	var hurt := [false]
	player.health_changed.connect(func(_h: float, _m: float) -> void: hurt[0] = true)
	for i in 120:
		if hurt[0]:
			break
		await seconds(0.25)
	check(hurt[0], "the truck hurts the player (ram or shockwave)")

	truck.apply_damage(99999.0, truck.global_position + Vector3.UP * 5.0, &"explosive")
	var elmo: ElmoOnFoot = null
	for i in 20:
		await seconds(0.25)
		for node in get_tree().get_nodes_in_group("hostiles"):
			if node is ElmoOnFoot:
				elmo = node
		if elmo:
			break
	check(elmo != null, "Elmo climbs out of the wreck")
	if elmo == null:
		return

	for i in 60:
		if elmo.is_posting:
			break
		await seconds(0.25)
	check(elmo.is_posting, "Elmo stops to post an update")
	var before := elmo.health
	elmo.apply_damage(10.0, elmo.global_position + Vector3(0, 0, -3), &"bullet")
	check(is_equal_approx(before - elmo.health, 10.0 * elmo.posting_damage_multiplier),
		"posting takes extra damage (%.1f)" % (before - elmo.health))

	elmo.apply_damage(99999.0, Vector3.ZERO, &"explosive")
	for i in 40:
		if level.phase == level.Phase.BUILD:
			break
		await seconds(0.25)
	check(level.phase == level.Phase.BUILD and level.get("core") != null, "defeating Elmo starts Phase 3")
