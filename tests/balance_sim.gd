extends TestCase
## Balance report: plays every wave with a scripted builder and NO player help
## (the player is parked off-map). Prints one row per wave. Tuning target:
## hands-off defense survives the early waves but is in real danger by 4-5,
## so the player's shooting, repairs, and talk-downs matter.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/balance_sim.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")
const WAVE_TIMEOUT := 300.0

## Build order: [item index, offset from core, rotation steps]. 0 barricade,
## 1 turret, 2 solar, 3 EMP. Built in order whenever cash allows.
const BUILD_PLAN := [
	[1, Vector3(-4, 0, 7), 0], [1, Vector3(4, 0, 7), 0], [2, Vector3(-8, 0, -5), 0],
	[0, Vector3(0, 0, 12), 0], [3, Vector3(0, 0, 16), 0], [1, Vector3(0, 0, 9), 0],
	[2, Vector3(8, 0, -5), 0], [1, Vector3(-8, 0, 3), 0], [1, Vector3(8, 0, 3), 0],
	[3, Vector3(-4, 0, 16), 0], [3, Vector3(4, 0, 16), 0], [0, Vector3(-6, 0, 13), 0],
	[0, Vector3(6, 0, 13), 0], [1, Vector3(-3, 0, -8), 0], [1, Vector3(3, 0, -8), 0],
]

var _next_build := 0


func _run() -> void:
	var level := MAIN_SCENE.instantiate()
	add_child(level)
	var player := level.get_node("Player") as Player
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	var build := level.get_node("BuildController") as BuildController

	# Phase 2 outcome as a player would leave it: guards dead, gate open, datacenter down.
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in [9, 10]:
		(level.get_node("FenceFront/Panel%d" % i) as Destructible).shatter(Vector3(0, 1, 0), 50.0)
	while level.phase != level.Phase.BUILD:
		await seconds(0.25)
	level.set("_auto_wave_left", 9999.0)
	player.global_position = Vector3(-55, 0.2, 60)
	player.set_physics_process(false)
	await seconds(10.0)

	var core := level.get("core") as GreenCore
	print("\nstart cash $%d, townspeople %d" % [Game.cash, get_tree().get_nodes_in_group("townspeople").size()])
	print("wave | core hp | built | cash after | crew | trust | seconds")
	var survived := 0
	for wave in spawner.total_waves():
		var built := _answer_breach(level, build, core.global_position)
		built += _build_what_we_can(build, core.global_position)
		var started := Time.get_ticks_msec()
		var game_time := 0.0
		level.call("start_next_wave")
		while spawner.wave_active and is_instance_valid(core) and not core.is_destroyed and game_time < WAVE_TIMEOUT:
			await seconds(0.5)
			game_time += 0.5
		var alive := is_instance_valid(core) and not core.is_destroyed
		print("%4d | %7s | %5d | %10d | %4d | %5.2f | %4.0f%s" % [wave + 1,
			str(ceili(core.health)) if alive else "LOST", built, Game.cash,
			get_tree().get_nodes_in_group("townspeople").size(), Game.district.trust, game_time,
			"  (timeout)" if game_time >= WAVE_TIMEOUT else ""])
		if not alive or spawner.wave_active:
			for node in get_tree().get_nodes_in_group("hostiles") + get_tree().get_nodes_in_group("protesters"):
				var e := node as Enemy
				print("    straggler %s at %s target=%s rushing=%s vel=%s path=%d next=%s los=%s" % [
					(e.get_script() as Script).get_global_name(), e.global_position.snapped(Vector3.ONE * 0.1),
					e.target, e.rushing, e.velocity.snapped(Vector3.ONE * 0.1),
					e._nav.get_current_navigation_path().size(), e._nav.get_next_path_position().snapped(Vector3.ONE * 0.1),
					e._has_los])
			break
		survived += 1
		level.set("_auto_wave_left", 9999.0)
		await seconds(5.0)  # townspeople repair between waves
	print("survived %d/%d waves (real %.0fs)\n" % [survived, spawner.total_waves(), Time.get_ticks_msec() / 1000.0])
	check(survived >= 2, "hands-off defense survives the opening waves")


## A sensible player reacts to the breach intel: a turret between the core and
## the announced gap, plus a barricade in front of it if cash allows.
func _answer_breach(level: Node, build: BuildController, center: Vector3) -> int:
	if not level.call("has_planned_breach"):
		return 0
	var toward: Vector3 = (level.call("next_breach_point") as Vector3) - center
	toward.y = 0.0
	toward = toward.normalized()
	var placed := 0
	for step in [[1, 7.0], [0, 11.0]]:
		if Game.cash < build.item_cost(step[0]):
			break
		var rotation := 0 if absf(toward.z) > absf(toward.x) else 1
		for nudge in [0.0, 2.0, -2.0, 4.0]:
			var side: Vector3 = toward.cross(Vector3.UP) * nudge
			if build.place(step[0], center + toward * step[1] + side, rotation) != null:
				placed += 1
				break
	return placed


## Builds down the plan while affordable. Returns how many pieces were placed.
func _build_what_we_can(build: BuildController, center: Vector3) -> int:
	var placed := 0
	while _next_build < BUILD_PLAN.size():
		var step: Array = BUILD_PLAN[_next_build]
		if Game.cash < build.item_cost(step[0]):
			break
		if build.place(step[0], center + (step[1] as Vector3), step[2]) != null:
			placed += 1
		_next_build += 1  # skip blocked slots too
	return placed
