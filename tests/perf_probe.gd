extends Node
## Frame-time report per graphics quality, at the level start and during a big
## wave. Vsync off. Needs a real window (no --headless):
##   Godot_console.exe --path . res://tests/perf_probe.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var driver: EnvironmentDriver


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	driver = level.get_node("EnvironmentDriver") as EnvironmentDriver
	await _wait(2.0)
	print("scene                quality  fps   cpu_process  cpu_physics  draw_calls  objects")
	await _sample_all("start")

	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	while level.phase != level.Phase.BUILD:
		await _wait(0.25)
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	spawner.current_wave = 3
	level.call("start_next_wave")
	await _wait(20.0)
	var player := level.get_node("Player") as Player
	player.global_position = Vector3(0, 0.2, -8)
	player.aim_at(Vector3(0, 1.0, -30))
	await _sample_all("wave 4 (%d units)" % get_tree().get_nodes_in_group("hostiles").size())
	get_tree().quit()


func _sample_all(label: String) -> void:
	for quality in [EnvironmentDriver.Quality.HIGH, EnvironmentDriver.Quality.MEDIUM, EnvironmentDriver.Quality.LOW]:
		driver.set_quality(quality)
		await _wait(1.5)
		var frames := 0
		var process_ms := 0.0
		var physics_ms := 0.0
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - start < 2_000_000:
			await get_tree().process_frame
			frames += 1
			process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var seconds := (Time.get_ticks_usec() - start) / 1_000_000.0
		print("%-20s %-8s %-5d %-12.2f %-12.2f %-11d %d" % [label, EnvironmentDriver.QUALITY_NAMES[quality],
			roundi(frames / seconds), process_ms / frames, physics_ms / frames,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


func _wait(duration: float) -> void:
	await get_tree().create_timer(duration).timeout
