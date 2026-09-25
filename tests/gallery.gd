extends Node
## Screenshots of bosses and props for visual review: tests/output/gallery_*.png.
## Needs a real window (no --headless):
##   Godot_console.exe --path . res://tests/gallery.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	await _wait(1.0)
	for node in get_tree().get_nodes_in_group("hostiles"):
		if not node is SentryTurret:
			(node as Enemy).apply_damage(9999.0, Vector3.ZERO)

	await _shot("crapya", Vector3(-10, 0.2, -18), Vector3(-18, 1.5, -30))
	await _shot("dozer", Vector3(18, 0.2, 48), Vector3(25, 1.0, 57))
	await _shot("gunshow", Vector3(-4, 0.2, 52), Vector3(-12, 1.2, 57))

	var field := Vector3(-84, 0.1, 40)
	for kind: GDScript in [ShamCrapman, FarkPod]:
		var boss := kind.new() as Enemy
		boss.position = field
		level.add_child(boss)
		boss.set_physics_process(false)
		await _wait(1.5)
		await _shot("boss_%s" % kind.get_global_name().to_lower(), field + Vector3(3, 0.1, 9), field + Vector3(0, 2.0, 0))
		boss.apply_damage(99999.0, field, &"explosive")
		await _wait(0.5)
		for node in get_tree().get_nodes_in_group("hostiles"):
			if node is Drone or node is HoloClone:
				(node as Enemy).apply_damage(9999.0, Vector3.ZERO)

	var harry := HarryPerckerson.new()
	harry.position = Vector3(18, 0.2, 97)
	level.add_child(harry)
	harry.set_physics_process(false)
	await _wait(1.0)
	await _shot("boss_harry", Vector3(10, 0.2, 90), Vector3(18, 1.5, 97))
	get_tree().quit()


func _shot(label: String, from: Vector3, look_at: Vector3) -> void:
	player.global_position = from
	await _wait(0.3)
	player.aim_at(look_at)
	await _wait(0.2)
	await RenderingServer.frame_post_draw
	var path := "res://tests/output/gallery_%s.png" % label
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (err=%d)" % [path, err])


func _wait(duration: float) -> void:
	await get_tree().create_timer(duration).timeout
