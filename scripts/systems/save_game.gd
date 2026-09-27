class_name SaveGame
extends RefCounted
## Defense checkpoint (user://save.json): written when the defense starts and
## after every cleared wave, deleted on a win or loss. Holds what a resumed
## run needs: waves cleared, cash, district state, pending bribes, stats,
## core health, and every player-built structure (BuildController item
## index, position, rotation, health). The title's Continue loads it.

## The real checkpoint. Anything run from a res://tests/ scene (tests,
## screenshots, probes) uses TEST_PATH instead, so it never touches a real save.
static var path := "user://save.json"
const TEST_PATH := "user://save_test.json"
const VERSION := 1


static func _file() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene and tree.current_scene.scene_file_path.begins_with("res://tests/"):
		return TEST_PATH
	return path


static func has_save() -> bool:
	return FileAccess.file_exists(_file())


static func write(data: Dictionary) -> bool:
	data["version"] = VERSION
	var file := FileAccess.open(_file(), FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: can't write %s (error %d)" % [_file(), FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


## The saved checkpoint, or {} if there isn't a readable one.
static func read() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(_file(), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != VERSION:
		push_warning("SaveGame: ignoring an unreadable or old save")
		return {}
	return parsed


static func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_file()))
