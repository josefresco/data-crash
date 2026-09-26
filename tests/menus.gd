extends Node
## Screenshots of the menus for visual review: tests/output/menu_*.png.
## Needs a real window (no --headless):
##   Godot_console.exe --path . res://tests/menus.tscn

const TITLE_SCENE := preload("res://scenes/ui/title.tscn")
const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var title := TITLE_SCENE.instantiate()
	add_child(title)
	await _wait(1.0)
	await _shot("title")
	title.queue_free()

	var level := MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	await _wait(3.0)
	await _shot("hud_tip")
	var menu: PauseMenu = null
	var end: EndScreen = null
	for node in level.get_children():
		if node is PauseMenu:
			menu = node
		elif node is EndScreen:
			end = node
	menu.open()
	await _shot("pause")
	menu.call("_show_panel", SettingsPanel)
	await _shot("settings")
	menu.call("_show_panel", ControlsPanel)
	await _shot("controls")
	menu.close()
	Game.count("kills", 57)
	Game.count("shots", 812)
	Game.count("time", 1325.0)
	Game.count("built", 14)
	Game.count("cameras", 5)
	end.show_result(true, 5, 5)
	await _wait(0.5)
	await _shot("end")
	get_tree().quit()


func _shot(label: String) -> void:
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	var path := "res://tests/output/menu_%s.png" % label
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (err=%d)" % [path, err])


func _wait(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout
