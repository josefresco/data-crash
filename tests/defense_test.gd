extends TestCase
## Headless check of enemies and Phase 3: navmesh, guard fire, dog treats,
## build placement, and one full wave against turrets.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/defense_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

func _run() -> void:
	var level := MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	var baker := level.get_node("NavBaker") as NavBaker
	if baker.bake_count == 0:
		await baker.navmesh_ready
	await seconds(0.5)  # let the region sync into the navigation map
	check(baker.bake_count >= 1, "navmesh baked at startup")

	var player := level.get_node("Player") as Player
	var nav_map := player.get_world_3d().navigation_map
	# The bigger map takes a moment to sync into the navigation server.
	for i in 40:
		if NavigationServer3D.map_get_closest_point(nav_map, Vector3(-40, 0, -30)) != Vector3.ZERO:
			break
		await seconds(0.25)
	var path := NavigationServer3D.map_get_path(nav_map, Vector3(-40, 0, -30), Vector3(-20, 0, -20), true)
	var across := NavigationServer3D.map_get_path(nav_map, Vector3(-84, 0, 30), Vector3(-110, 0, 30), true)
	check(across.size() > 0 and across[-1].distance_to(Vector3(-110, 0.5, 30)) < 1.5,
		"paths cross from the center navmesh into the west one (ends at %s)" % [across[-1] if across.size() > 0 else "none"])
	# The path must stop somewhere outside the fenced Felsa compound
	# (x -34..34, z -72..-12), never reaching the target inside it.
	var end: Vector3 = path[-1] if path.size() > 0 else Vector3.ZERO
	var inside := end.x > -34.0 and end.x < 34.0 and end.z > -72.0 and end.z < -12.0
	check(path.size() > 0 and not inside,
		"fence blocks outside-in path (ends at %s)" % [path[-1] if path.size() > 0 else "none"])

	# Security holds fire until the site alarm, then a guard shoots the player.
	var hits := [0]
	player.health_changed.connect(func(_h: float, _m: float) -> void: hits[0] += 1)
	player.global_position = Vector3(-18, 0.2, -28)
	await seconds(2.0)
	check(hits[0] == 0 and not Game.any_alarm(), "site security ignores a player who hasn't attacked")
	(level.get_node("FelsaSite/FenceFront/Panel3") as Destructible).apply_damage(1.0, player.global_position, &"bullet")
	check(Game.is_alarmed(&"felsa"), "hitting the fence raises the site alarm")
	await seconds(3.0)
	check(hits[0] > 0, "guard shot the player (%d hits)" % hits[0])

	# Treat converts a dog.
	var dog := level.get_node("FelsaSite/FrontDog") as Dog
	player.global_position = dog.global_position + Vector3(1.5, 0.2, 0)
	var treats_before := player.treats
	check(player.give_treat(), "give_treat succeeded")
	check(dog.faction == Enemy.Faction.ALLY and dog.is_in_group("allies"), "dog is now an ally")
	check(player.treats == treats_before - 1, "treat consumed")

	# Clear remaining Phase 2 hostiles so the wave test is deterministic.
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	player.global_position = Vector3(-5, 0.2, 20)

	# Phase 3: take all three datacenters down (their gates come down too), wait for the core.
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in 80:
		if level.phase == level.Phase.BUILD:
			break
		await seconds(0.25)
	check(level.phase == level.Phase.BUILD, "defense phase began after collapse")
	var core := level.core as GreenCore
	check(core != null and core.is_in_group("structures"), "green core spawned")
	var arrays := get_tree().get_nodes_in_group("structures").filter(func(n: Node) -> bool: return n is SolarArray)
	check(arrays.size() == 18, "green datacenter comes with a solar field (%d arrays)" % arrays.size())
	await seconds(12.0)  # debris clears, navmesh rebakes
	check(get_tree().get_nodes_in_group("gas_turbines").all(func(n: Node) -> bool: return (n as Destructible).is_destroyed),
		"old gas turbines are hauled off")
	check(get_tree().get_nodes_in_group("crapya_defenses").is_empty(), "Crapya's vents and crushers are cleared")

	var build := level.get_node("BuildController") as BuildController
	Game.cash = 2000
	var center := core.global_position
	var turret_a := build.place(1, center + Vector3(-5, 0, 8))
	var turret_b := build.place(1, center + Vector3(5, 0, 8))
	var turret_c := build.place(1, center + Vector3(0, 0, 11))
	check(turret_a is Turret and turret_b is Turret and turret_c is Turret, "three turrets placed")
	check(build.place(1, center + Vector3(-5, 0, 8)) == null, "overlapping placement rejected")
	check(build.place(0, center + Vector3(0, 0, 40)) == null, "out-of-zone placement rejected")
	check(build.place(2, center + Vector3(-8, 0, -6)) is SolarPanel, "solar panel placed")
	# Townspeople wander the site, so allow a couple of nearby tiles.
	var trap: Node3D = null
	for offset in [Vector3(0, 0, 16), Vector3(3, 0, 16), Vector3(-3, 0, 16), Vector3(0, 0, 19)]:
		trap = build.place(3, center + offset)
		if trap:
			break
	check(trap is EmpTrap, "EMP trap placed")
	check(Game.cash == 2000 - build.item_cost(1) * 3 - build.item_cost(2) - build.item_cost(3), "costs deducted ($%d)" % Game.cash)
	Game.cash = 0
	var income_start := Game.cash
	await seconds(2.5)
	check(Game.cash > income_start, "solar panel pays income")

	# One wave.
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	var cleared := [false]
	spawner.wave_cleared.connect(func(_n: int, _t: int) -> void: cleared[0] = true)
	# Park the (passive) test player out of sight so guards go for the core, not us.
	player.global_position = Vector3(-85, 0.2, 100)
	level.start_next_wave()
	check(spawner.wave_active and level.phase == level.Phase.WAVE, "wave 1 started")
	var closest := [INF]
	for i in 480:
		if cleared[0] or core.is_destroyed:
			break
		for node in get_tree().get_nodes_in_group("hostiles"):
			closest[0] = minf(closest[0], (node as Node3D).global_position.distance_to(center))
		await seconds(0.25)
	check(closest[0] < 30.0, "hostiles pathed toward the core (closest %.1fm)" % closest[0])
	check(cleared[0], "wave 1 cleared")
	if not cleared[0]:
		print("  remaining=%d queue_empty? active=%s" % [spawner.remaining, spawner.wave_active])
		for node in get_tree().get_nodes_in_group("hostiles"):
			var e := node as Enemy
			print("  left: %s at %s hp=%.0f target=%s nav_done=%s" % [e.get_class() if e.get_script() == null else (e.get_script() as Script).get_global_name(),
				e.global_position.snapped(Vector3.ONE * 0.1), e.health, e.target, e._nav.is_navigation_finished()])
	check(is_instance_valid(core) and not core.is_destroyed, "core survived (%s hp)"
		% (str(ceili(core.health)) if is_instance_valid(core) else "gone"))
	check(level.phase == level.Phase.BUILD, "back to build phase")

