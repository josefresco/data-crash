extends Node
## Renders the main scene and saves screenshots to tests/output/ (polluted, then
## restored after a scripted datacenter takedown). Needs a real window, not --headless.
##
##   Godot_console.exe --path . res://tests/capture.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var level := MAIN_SCENE.instantiate()
	add_child(level)
	await get_tree().create_timer(1.5).timeout
	await _save("polluted")

	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	await get_tree().create_timer(2.0).timeout
	await _save("collapsing")
	await get_tree().create_timer(12.0).timeout
	await _save("restored")

	# Phase 3: a few defenses, then a wave, seen from behind the turrets.
	var core := level.get("core") as GreenCore
	var build := level.get_node("BuildController") as BuildController
	for i in [9, 10]:
		(level.get_node("FenceFront/Panel%d" % i) as Destructible).shatter(Vector3(0, 1, 0), 50.0)
	Game.cash = 2000
	var center := core.global_position
	build.place(1, center + Vector3(-5, 0, 8))
	build.place(1, center + Vector3(5, 0, 8))
	build.place(0, center + Vector3(0, 0, 13))
	build.place(2, center + Vector3(-8, 0, -6))
	build.place(3, center + Vector3(0, 0, 16))
	build.set_active(true)
	var player := level.get_node("Player") as Player
	player.global_position = center + Vector3(3, 0.2, 4)
	(player.get_node("CameraPivot") as Node3D).rotation.y = PI
	await get_tree().create_timer(1.0).timeout
	level.call("start_next_wave")
	await get_tree().create_timer(14.0).timeout
	await _save("wave")
	get_tree().quit()


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/output/%s.png" % label
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (err=%d)" % [path, err])
