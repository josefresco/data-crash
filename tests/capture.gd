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
	get_tree().quit()


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/output/%s.png" % label
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (err=%d)" % [path, err])
