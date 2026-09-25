extends TestCase
## Mechanics of the Phase 3 cast: police shields, FROST abductions, Orange Hat
## pickets, townsperson and player repairs.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/units_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	await _enter_defense_phase()

	await _test_police_shield()
	await _test_frost_rescue()
	await _test_frost_abduction()
	await _test_orange_hat()
	await _test_repairs()


func _enter_defense_phase() -> void:
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	# The player always breaches the fence in Phase 2; open the gate the same way.
	for i in [9, 10]:
		(level.get_node("FenceFront/Panel%d" % i) as Destructible).shatter(Vector3(0, 1, 0), 50.0)
	for i in 80:
		if level.phase == level.Phase.BUILD:
			break
		await seconds(0.25)
	check(level.phase == level.Phase.BUILD, "defense phase reached")
	level.set("auto_wave_delay", 9999.0)
	level.set("_auto_wave_left", 9999.0)
	await seconds(12.0)  # debris clears
	# Keep the test player out of every fight.
	player.global_position = Vector3(-55, 0.2, 60)
	check(get_tree().get_nodes_in_group("townspeople").size() >= 2, "townspeople joined (%d)"
		% get_tree().get_nodes_in_group("townspeople").size())


func _spawn(unit: Enemy, at: Vector3) -> Enemy:
	unit.position = at
	level.add_child(unit)
	return unit


func _test_police_shield() -> void:
	var cop := _spawn(Police.new(), Vector3(-40, 0.1, 40)) as Police
	await seconds(0.1)
	cop.set_physics_process(false)  # hold still, face -Z
	var facing := -cop._visual.global_basis.z
	var front := cop.global_position + facing * 5.0
	var back := cop.global_position - facing * 5.0
	var hp := cop.health
	cop.apply_damage(10.0, front, &"bullet")
	check(is_equal_approx(cop.health, hp - 10.0 * cop.shield_leak), "shield blocks most frontal bullet damage (%.1f)" % (hp - cop.health))
	hp = cop.health
	cop.apply_damage(10.0, back, &"bullet")
	check(is_equal_approx(cop.health, hp - 10.0), "full damage from behind")
	hp = cop.health
	cop.stun(1.0)
	cop.apply_damage(10.0, front, &"bullet")
	check(not cop.is_shield_up() and is_equal_approx(cop.health, hp - 10.0), "stun drops the shield")
	cop.apply_damage(9999.0, front, &"explosive")


func _test_frost_rescue() -> void:
	var person := _spawn(Townsperson.new(), Vector3(-30, 0.1, 45)) as Townsperson
	var agent := _spawn(Frost.new(), Vector3(-30, 0.1, 50)) as Frost
	agent.home = Vector3(-55, 0.1, 50)
	for i in 40:
		if agent.captive:
			break
		await seconds(0.25)
	check(agent.captive == person and person.is_captured(), "FROST grabbed a townsperson")
	agent.apply_damage(9999.0, Vector3.ZERO, &"explosive")
	await seconds(0.2)
	check(not person.is_captured() and person.is_in_group("townspeople"), "killing FROST frees the captive")
	person.queue_free()


func _test_frost_abduction() -> void:
	var trust := Game.district.trust
	var person := _spawn(Townsperson.new(), Vector3(-35, 0.1, 45)) as Townsperson
	var agent := _spawn(Frost.new(), Vector3(-35, 0.1, 48)) as Frost
	agent.home = Vector3(-35, 0.1, 55)
	var gone := [false]
	person.abducted.connect(func(_p: Townsperson) -> void: gone[0] = true)
	for i in 80:
		if gone[0]:
			break
		await seconds(0.25)
	check(gone[0], "FROST carried a townsperson off the map")
	check(Game.district.trust < trust, "abduction cost trust (%.2f -> %.2f)" % [trust, Game.district.trust])


func _test_orange_hat() -> void:
	var build := level.get_node("BuildController") as BuildController
	var core := level.get("core") as GreenCore
	Game.cash = 1000
	# Inside the fence, behind the core, clear of other structures.
	var turret := build.place(1, core.global_position + Vector3(-10, 0, -4)) as Turret
	check(turret != null, "turret placed for picket test")
	var protester := _spawn(OrangeHat.new(), turret.global_position + Vector3(6, 0.1, 0)) as OrangeHat
	for i in 40:
		if turret.is_picketed():
			break
		await seconds(0.25)
	check(turret.is_picketed(), "protester pickets the turret")

	var guard := _spawn(SecurityGuard.new(), turret.global_position + Vector3(0, 0.1, -10)) as SecurityGuard
	guard.set_physics_process(false)
	await seconds(2.0)
	check(is_equal_approx(guard.health, guard.max_health), "picketed turret holds fire")

	player.global_position = protester.global_position + Vector3(1.5, 0.2, 0)
	var trust := Game.district.trust
	check(player.talk_down(), "player talks the protester down")
	check(Game.district.trust > trust, "talking down earns trust")
	player.global_position = Vector3(-55, 0.2, 60)
	await seconds(2.0)
	check(guard.health < guard.max_health or not guard.is_alive(), "turret fires once the picket ends")
	if guard.is_alive():
		guard.apply_damage(9999.0, Vector3.ZERO)


func _test_repairs() -> void:
	var build := level.get_node("BuildController") as BuildController
	var core := level.get("core") as GreenCore
	Game.cash = 1000
	var wall := build.place(0, core.global_position + Vector3(-12, 0, 4)) as Barricade
	check(wall != null, "barricade placed for repair test")
	wall.apply_damage(200.0, wall.global_position + Vector3(0, 1, 3))
	var damaged := wall.health
	for i in 80:
		if not wall.needs_repair():
			break
		await seconds(0.25)
	check(not wall.needs_repair(), "townspeople repaired the barricade (%.0f -> %.0f)" % [damaged, wall.health])
	if wall.needs_repair():
		for node in get_tree().get_nodes_in_group("townspeople"):
			var t := node as Townsperson
			print("    crew at %s target=%s nav_done=%s dist=%.1f" % [t.global_position.snapped(Vector3.ONE * 0.1),
				t.target, t._nav.is_navigation_finished(), wall.distance_to_point(t.global_position)])
		return

	# Player repair costs cash.
	for node in get_tree().get_nodes_in_group("townspeople"):
		(node as Enemy).set_physics_process(false)  # keep the crew out of this one
	wall.apply_damage(200.0, wall.global_position + Vector3(0, 1, 3))
	player.global_position = wall.global_position + Vector3(0, 0.2, 1.5)
	await seconds(0.1)
	var cash := Game.cash
	for i in 30:
		player.call("_repair", 0.1)
	check(wall.health > wall.max_health - 200.0 + 100.0, "player repair restores health (%.0f)" % wall.health)
	check(Game.cash < cash, "player repair costs cash ($%d -> $%d)" % [cash, Game.cash])
