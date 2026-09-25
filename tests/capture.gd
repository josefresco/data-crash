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

	# Boss: watch the truck come up the road, then Elmo on foot.
	var player := level.get_node("Player") as Player
	while level.phase != level.Phase.BOSS:
		await get_tree().create_timer(0.25).timeout
	player.global_position = Vector3(-6, 0.2, 8)
	await get_tree().create_timer(2.5).timeout
	var truck := _find(ElmoTruck)
	if truck:
		player.aim_at(truck.global_position + Vector3.UP)
		await _save("boss_truck")
		truck.apply_damage(99999.0, truck.global_position + Vector3.UP * 5.0, &"explosive")
	await get_tree().create_timer(3.5).timeout
	var elmo := _find(ElmoOnFoot)
	if elmo:
		player.global_position = elmo.global_position + Vector3(-5, 0, 5)
		await get_tree().create_timer(0.5).timeout
		player.aim_at(elmo.aim_point())
		await _save("boss_elmo")
		elmo.apply_damage(99999.0, Vector3.ZERO, &"explosive")
	while level.phase != level.Phase.BUILD:
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(8.0).timeout
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
	player.global_position = center + Vector3(3, 0.2, 4)
	(player.get_node("CameraPivot") as Node3D).rotation.y = PI
	await get_tree().create_timer(1.0).timeout
	level.call("start_next_wave")
	await get_tree().create_timer(14.0).timeout
	await _save("wave")

	# Cast lineup: one of each unit, frozen in a row in front of the camera.
	player.global_position = Vector3(-40, 0.2, 45)
	(player.get_node("CameraPivot") as Node3D).rotation.y = 0.0
	var cast: Array[Enemy] = [SecurityGuard.new(), Dog.new(), Police.new(), Frost.new(),
		OrangeHat.new(), Townsperson.new()]
	for i in cast.size():
		cast[i].position = Vector3(-45.0 + i * 2.0, 0.1, 38.0)
		level.add_child(cast[i])
		cast[i].set_physics_process(false)
	await get_tree().create_timer(0.5).timeout
	for unit in cast:
		unit._visual.rotation.y = PI * 0.9  # face the camera
	await _save("cast")
	get_tree().quit()


func _find(kind: GDScript) -> Node3D:
	for node in get_tree().get_nodes_in_group("hostiles"):
		if node.get_script() == kind:
			return node as Node3D
	return null


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/output/%s.png" % label
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (err=%d)" % [path, err])
