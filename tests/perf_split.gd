extends Node

func _measure(label: String) -> void:
	await get_tree().create_timer(1.5).timeout
	var total := 0.0
	var frames := 0
	for i in 240:
		await get_tree().process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		frames += 1
	print("%-28s fps=%4d cpu_ms=%.2f" % [label, Engine.get_frames_per_second(), total / frames])

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var level := (load("res://scenes/levels/test_block.tscn") as PackedScene).instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout
	await _measure("baseline")
	for n in get_tree().get_nodes_in_group("residents"):
		n.queue_free()
	await _measure("no residents")
	(level.get_node("Hud") as CanvasLayer).visible = false
	for n in level.get_node("Hud").find_children("*", "Minimap", true, false):
		n.set_process(false)
	await _measure("no minimap/hud")
	for n in get_tree().get_nodes_in_group("datacenter_sites"):
		n.set_process(false)
	await _measure("no water boards")
	for n in get_tree().get_nodes_in_group("hostiles"):
		n.set_physics_process(false)
		n.set_process(false)
	await _measure("hostiles frozen")
	get_tree().quit()
