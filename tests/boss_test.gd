extends TestCase
## Felsa Cars and the Elmo Mushbrains boss fight (inside Felsa, then his
## Cyberdouche, then on foot), then clearing all three sites into Phase 3.
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
	# Open field west of the houses.
	player.global_position = Vector3(-84, 0.2, 70)
	var car := FelsaCar.new()
	car.position = Vector3(-84, 0.2, 50)
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
	var felsa := level.get_node("FelsaSite") as DatacenterSite
	var inside := felsa.elmo
	var truck := felsa.elmo_truck
	check(inside != null and felsa.datacenter.global_position.distance_to(inside.global_position) < 15.0,
		"Elmo waits inside the Felsa datacenter")
	check(truck != null and truck.parked, "his Cyberdouche is parked at the back dock")
	await seconds(1.0)
	check(Game.stat("time") > 0.0 and not inside.is_posting, "no Twats while the site is quiet")

	# Clear the regular security everywhere (keep the bosses): that sets off the alarms.
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if (unit is SecurityGuard and not unit is SentryTurret) or unit is Dog or (unit is FelsaCar and not unit is ElmoTruck):
			unit.apply_damage(9999.0, Vector3.ZERO)
	check(Game.is_alarmed(&"felsa"), "attacking Felsa's security raises its alarm")
	player.global_position = Vector3(20, 0.2, -20)
	for i in 120:
		if not truck.parked:
			break
		await seconds(0.25)
	check(not truck.parked and not is_instance_valid(inside), "on the alarm, Elmo runs to his Cyberdouche and takes the wheel")

	var hp := truck.health
	truck.stun(5.0)
	check(not truck.is_burning and truck.health < hp, "EMP only dents the boss truck")

	# Let it hunt the player for a while: it should ram or shockwave.
	player.global_position = Vector3(-24, 0.2, -64)  # the open yard behind the building
	var hurt := [false]
	player.health_changed.connect(func(_h: float, _m: float) -> void: hurt[0] = true)
	for i in 240:
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
	await seconds(0.5)
	check(felsa.boss_defeated, "Felsa's boss is down")
	# Finish the other two sites: Sham, Crapya's room, and every cooling unit.
	var forprofit := level.get_node("ForProfitSite") as DatacenterSite
	forprofit.sham.apply_damage(99999.0, forprofit.sham.global_position, &"explosive")
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in 40:
		if level.phase == level.Phase.BUILD:
			break
		await seconds(0.25)
	check(level.phase == level.Phase.BUILD and level.get("core") != null, "all three datacenters and their bosses down starts Phase 3")
