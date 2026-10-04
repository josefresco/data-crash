extends TestCase
## Mechanics of the Phase 3 cast: police shields, FROST abductions, Orange Hat
## pickets, townsperson and player repairs, guards fighting from cover and
## flanking, and recruited Canadians holding the core.
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
	await _test_guard_cover()
	await _test_guard_flank()
	await _test_shield_wall()
	await _test_canadian_post()
	await _test_robot()
	await _test_carports()


## The T-800: plating halves bullets, water shorts it out, the first kill
## leaves it crawling, the second finishes it; a blast scraps it outright.
func _test_robot() -> void:
	var robot := RoboGuard.new()
	robot.position = Vector3(-84.0, 0.1, 40.0)
	level.add_child(robot)
	robot.set_physics_process(false)
	await seconds(0.2)
	var hp := robot.health
	robot.apply_damage(20.0, player.global_position, &"bullet")
	check(is_equal_approx(hp - robot.health, 10.0), "bullets glance off its plating (%d)" % roundi(hp - robot.health))
	hp = robot.health
	robot.apply_damage(10.0, player.global_position, &"water")
	check(is_equal_approx(hp - robot.health, 30.0), "water shorts it out (x3)")
	# Just enough after the x3 (a bigger hit would count as overkill).
	robot.apply_damage(robot.health / 3.0 + 1.0, player.global_position, &"water")
	await seconds(0.1)
	check(robot.is_alive() and robot.crawling, "the first kill leaves it crawling")
	robot.apply_damage(robot.health + 50.0, player.global_position, &"explosive")
	await seconds(0.1)
	check(not robot.is_alive(), "the second kill finishes it")
	var scrap := RoboGuard.new()
	scrap.position = Vector3(-84.0, 0.1, 44.0)
	level.add_child(scrap)
	await seconds(0.1)
	scrap.apply_damage(9999.0, Vector3.ZERO, &"explosive")
	await seconds(0.1)
	check(not scrap.is_alive(), "a big blast scraps it on the spot")


## The green datacenter's parking gets solar canopies that pay out.
func _test_carports() -> void:
	var carports := get_tree().get_nodes_in_group("solar_carports")
	check(carports.size() == 3, "solar canopies cover the parking lots (%d)" % carports.size())
	var cash := Game.cash
	await seconds(4.5)
	check(Game.cash > cash, "they pay while the core stands")


func _enter_defense_phase() -> void:
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in 80:
		if level.phase == level.Phase.BUILD:
			break
		await seconds(0.25)
	check(level.phase == level.Phase.BUILD, "defense phase reached")
	level.set("auto_wave_delay", 9999.0)
	level.set("_auto_wave_left", 9999.0)
	await seconds(12.0)  # debris clears
	# Keep the test player out of every fight.
	player.global_position = Vector3(-85, 0.2, 100)
	check(get_tree().get_nodes_in_group("townspeople").size() >= 2, "townspeople joined (%d)"
		% get_tree().get_nodes_in_group("townspeople").size())


## Samples a fight for `duration` s with the player held still (and healed):
## returns [times hit, samples the guard was hidden, tactics seen].
func _watch_guard(guard: SecurityGuard, duration: float) -> Array:
	var hits := 0
	var hidden := 0
	var seen := {}
	var eye := player.global_position + Vector3.UP * 1.4
	var space := player.get_world_3d().direct_space_state
	for i in int(duration / 0.25):
		await seconds(0.25)
		if not is_instance_valid(guard) or not guard.is_alive():
			break
		seen[guard.tactic] = true
		var model := guard.get("_rig") as CharacterModel
		if model and model.stance_clip() == &"crouch_idle":
			seen["crouched"] = true
		if player.health < player.max_health:
			hits += 1
			player.heal(9999.0)
		var query := PhysicsRayQueryParameters3D.create(eye, guard.global_position + Vector3.UP * 1.2, SecurityGuard.COVER_MASK)
		if not space.intersect_ray(query).is_empty():
			hidden += 1
	return [hits, hidden, seen]


func _test_guard_cover() -> void:
	# A free-standing wall in the open strip, baked into the navmesh.
	var wall := StaticBody3D.new()
	wall.name = "CoverWall"
	wall.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 2.6, 0.6)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 1.3
	wall.add_child(collider)
	level.add_child(wall)
	wall.global_position = Vector3(-84, 0, 60)
	var baker := level.get_node("NavBaker") as NavBaker
	var bakes := baker.bake_count
	get_tree().call_group(&"nav_baker", &"request_rebake")
	for i in 120:
		if baker.bake_count > bakes:
			break
		await seconds(0.25)
	await seconds(0.5)

	player.global_position = Vector3(-84, 0.2, 72)
	player.heal(9999.0)
	player.set_physics_process(false)
	var guard := _spawn(SecurityGuard.new(), Vector3(-84, 0.1, 65)) as SecurityGuard
	var result: Array = await _watch_guard(guard, 12.0)
	var seen: Dictionary = result[2]
	check(seen.has(SecurityGuard.Tactic.COVER), "a guard in the open runs for cover")
	check(result[1] >= 4, "the guard spends time out of sight behind the wall (%d samples)" % result[1])
	check(seen.has("crouched"), "the guard crouches while in cover")
	check(seen.has(SecurityGuard.Tactic.PEEK) and result[0] >= 1, "…and pops out to shoot (hit %d times)" % result[0])
	guard.apply_damage(9999.0, Vector3.ZERO)
	wall.queue_free()
	player.set_physics_process(true)
	player.global_position = Vector3(-85, 0.2, 100)
	await seconds(0.5)


func _test_guard_flank() -> void:
	player.global_position = Vector3(-84, 0.2, 30)
	player.heal(9999.0)
	player.set_physics_process(false)
	var guards: Array[SecurityGuard] = []
	var bearings: Array[float] = []
	for x: float in [-87.0, -84.0, -81.0]:
		var guard := _spawn(SecurityGuard.new(), Vector3(x, 0.1, 18)) as SecurityGuard
		guards.append(guard)
		bearings.append(0.0)
	var flanked := false
	var swing := 0.0
	for i in 40:
		await seconds(0.25)
		player.heal(9999.0)
		for g in guards.size():
			var guard := guards[g]
			if not is_instance_valid(guard) or not guard.is_alive():
				continue
			if guard.tactic == SecurityGuard.Tactic.FLANK:
				flanked = true
			var offset := guard.global_position - player.global_position
			var bearing := atan2(offset.x, offset.z)
			if i == 0:
				bearings[g] = bearing
			swing = maxf(swing, absf(angle_difference(bearings[g], bearing)))
	check(flanked, "with three guards on the player, one goes to flank")
	check(swing > deg_to_rad(40.0), "the flanker swings around the player (%.0f degrees)" % rad_to_deg(swing))
	for guard in guards:
		if is_instance_valid(guard):
			guard.apply_damage(9999.0, Vector3.ZERO)
	player.set_physics_process(true)
	player.global_position = Vector3(-85, 0.2, 100)
	await seconds(0.5)


func _test_shield_wall() -> void:
	player.global_position = Vector3(-84, 0.2, 40)
	player.heal(9999.0)
	player.set_physics_process(false)
	var cops: Array[Police] = []
	for at: Vector3 in [Vector3(-88, 0.1, 20), Vector3(-84, 0.1, 25), Vector3(-80, 0.1, 22)]:
		cops.append(_spawn(Police.new(), at) as Police)
	var lined := 0
	var facing_ok := 0
	var facing_all := 0
	var worst_spread := 0.0
	for i in 32:
		await seconds(0.25)
		player.heal(9999.0)
		var depths: Array[float] = []
		for cop in cops:
			if not is_instance_valid(cop) or not cop.is_alive():
				continue
			var to_player := player.global_position - cop.global_position
			to_player.y = 0.0
			if cop.in_line:
				lined += 1
				if cop.velocity.length() > 0.5:
					facing_all += 1
					var facing := -cop._visual.global_basis.z
					facing.y = 0.0
					if facing.normalized().dot(to_player.normalized()) > 0.8:
						facing_ok += 1
			depths.append(to_player.length())
		if i >= 12 and depths.size() == 3:
			worst_spread = maxf(worst_spread, depths.max() - depths.min())
	check(lined > 30, "police on the player form a shield line (%d samples)" % lined)
	check(facing_all > 0 and facing_ok >= facing_all * 0.8, "shields stay toward the player while advancing (%d/%d)" % [facing_ok, facing_all])
	check(worst_spread < 3.5, "the line keeps together (worst depth spread %.1f m)" % worst_spread)
	var close := cops.filter(func(c: Variant) -> bool: return is_instance_valid(c) and (c as Police).global_position.distance_to(player.global_position) < 7.5).size()
	check(close == 3, "the line reaches the player (%d of 3)" % close)
	for cop in cops:
		if is_instance_valid(cop):
			cop.apply_damage(9999.0, cop.global_position + Vector3.UP, &"explosive")
	player.set_physics_process(true)
	player.global_position = Vector3(-85, 0.2, 100)
	await seconds(0.5)


func _test_canadian_post() -> void:
	var core := level.get("core") as GreenCore
	var tourist := Canuck.new()
	tourist.setup(false)
	level.add_child(tourist)
	tourist.global_position = core.global_position + Vector3(0, 0.3, 18)
	tourist.join()
	await seconds(10.0)
	var near_core := tourist.global_position.distance_to(core.global_position)
	check(near_core < 9.0, "with the player away, a recruited Canadian holds the core (%.1f m)" % near_core)
	player.global_position = core.global_position + Vector3(12, 0.2, 12)
	await seconds(6.0)
	var near_player := tourist.global_position.distance_to(player.global_position)
	check(near_player < 7.0, "…and tags along again once you're back (%.1f m)" % near_player)
	player.global_position = Vector3(-85, 0.2, 100)
	tourist.queue_free()


func _spawn(unit: Enemy, at: Vector3) -> Enemy:
	unit.position = at
	level.add_child(unit)
	return unit


func _test_police_shield() -> void:
	var cop := _spawn(Police.new(), Vector3(-84, 0.1, 40)) as Police
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
	var person := _spawn(Townsperson.new(), Vector3(-84, 0.1, 55)) as Townsperson
	var agent := _spawn(Frost.new(), Vector3(-84, 0.1, 60)) as Frost
	agent.home = Vector3(-84, 0.1, 85)
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
	var person := _spawn(Townsperson.new(), Vector3(-86, 0.1, 10)) as Townsperson
	var agent := _spawn(Frost.new(), Vector3(-86, 0.1, 13)) as Frost
	agent.home = Vector3(-86, 0.1, 20)
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
	player.global_position = Vector3(-85, 0.2, 100)
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
