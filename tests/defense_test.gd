extends Node
## Headless check of enemies and Phase 3: navmesh, guard fire, dog treats,
## build placement, and one full wave against turrets.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/defense_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	var level := MAIN_SCENE.instantiate()
	add_child(level)
	var baker := level.get_node("NavBaker") as NavBaker
	if baker.bake_count == 0:
		await baker.navmesh_ready
	await _seconds(0.5)  # let the region sync into the navigation map
	_check(baker.bake_count >= 1, "navmesh baked at startup")

	var player := level.get_node("Player") as Player
	var nav_map := player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(nav_map, Vector3(-40, 0, -30), Vector3(-20, 0, -20), true)
	# The path should stop outside the west fence (x = -25), never reaching the target.
	_check(path.size() > 0 and path[-1].x < -25.0,
		"fence blocks outside-in path (ends at %s)" % [path[-1] if path.size() > 0 else "none"])

	# Guard spots and shoots the player inside the fence.
	var hits := [0]
	player.health_changed.connect(func(_h: float, _m: float) -> void: hits[0] += 1)
	player.global_position = Vector3(-18, 0.2, -28)
	await _seconds(3.0)
	_check(hits[0] > 0, "guard shot the player (%d hits)" % hits[0])

	# Treat converts a dog.
	var dog := level.get_node("Dog2") as Dog
	player.global_position = dog.global_position + Vector3(1.5, 0.2, 0)
	var treats_before := player.treats
	_check(player.give_treat(), "give_treat succeeded")
	_check(dog.faction == Enemy.Faction.ALLY and dog.is_in_group("allies"), "dog is now an ally")
	_check(player.treats == treats_before - 1, "treat consumed")

	# Clear remaining Phase 2 hostiles so the wave test is deterministic.
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	player.global_position = Vector3(-5, 0.2, 20)

	# Phase 3: take the datacenter down, open the front gate, wait for the core.
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in [9, 10]:
		(level.get_node("FenceFront/Panel%d" % i) as Destructible).shatter(Vector3(0, 1, 0), 50.0)
	for i in 80:
		if level.phase == level.Phase.BUILD:
			break
		await _seconds(0.25)
	_check(level.phase == level.Phase.BUILD, "defense phase began after collapse")
	var core := level.core as GreenCore
	_check(core != null and core.is_in_group("structures"), "green core spawned")
	await _seconds(12.0)  # debris clears, navmesh rebakes

	var build := level.get_node("BuildController") as BuildController
	Game.cash = 2000
	var center := core.global_position
	var turret_a := build.place(1, center + Vector3(-5, 0, 8))
	var turret_b := build.place(1, center + Vector3(5, 0, 8))
	var turret_c := build.place(1, center + Vector3(0, 0, 11))
	_check(turret_a is Turret and turret_b is Turret and turret_c is Turret, "three turrets placed")
	_check(build.place(1, center + Vector3(-5, 0, 8)) == null, "overlapping placement rejected")
	_check(build.place(0, center + Vector3(0, 0, 40)) == null, "out-of-zone placement rejected")
	_check(build.place(2, center + Vector3(-8, 0, -6)) is SolarPanel, "solar panel placed")
	_check(build.place(3, center + Vector3(0, 0, 16)) is EmpTrap, "EMP trap placed")
	_check(Game.cash == 2000 - 150 * 3 - 100 - 75, "costs deducted ($%d)" % Game.cash)
	Game.cash = 0
	var income_start := Game.cash
	await _seconds(2.5)
	_check(Game.cash > income_start, "solar panel pays income")

	# One wave.
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	var cleared := [false]
	spawner.wave_cleared.connect(func(_n: int, _t: int) -> void: cleared[0] = true)
	# Park the (passive) test player out of sight so guards go for the core, not us.
	player.global_position = Vector3(-55, 0.2, 60)
	level.start_next_wave()
	_check(spawner.wave_active and level.phase == level.Phase.WAVE, "wave 1 started")
	var closest := [INF]
	for i in 480:
		if cleared[0] or core.is_destroyed:
			break
		for node in get_tree().get_nodes_in_group("hostiles"):
			closest[0] = minf(closest[0], (node as Node3D).global_position.distance_to(center))
		await _seconds(0.25)
	_check(closest[0] < 30.0, "hostiles pathed toward the core (closest %.1fm)" % closest[0])
	_check(cleared[0], "wave 1 cleared")
	if not cleared[0]:
		print("  remaining=%d queue_empty? active=%s" % [spawner.remaining, spawner.wave_active])
		for node in get_tree().get_nodes_in_group("hostiles"):
			var e := node as Enemy
			print("  left: %s at %s hp=%.0f target=%s nav_done=%s" % [e.get_class() if e.get_script() == null else (e.get_script() as Script).get_global_name(),
				e.global_position.snapped(Vector3.ONE * 0.1), e.health, e.target, e._nav.is_navigation_finished()])
	_check(is_instance_valid(core) and not core.is_destroyed, "core survived (%s hp)"
		% (str(ceili(core.health)) if is_instance_valid(core) else "gone"))
	_check(level.phase == level.Phase.BUILD, "back to build phase")
	_finish()


func _seconds(duration: float) -> Signal:
	return get_tree().create_timer(duration).timeout


func _check(condition: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)


func _finish() -> void:
	print("\n%d failure(s)" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
