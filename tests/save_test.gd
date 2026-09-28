extends TestCase
## Replay structure: the defense checkpoint and Continue, the between-waves
## summary card, difficulty scaling, and the intro overlay.

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")


func _run() -> void:
	SaveGame.clear()  # tests always use SaveGame.TEST_PATH
	var level := MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	await seconds(1.5)
	# Every navmesh region baked first: pathing against a half-baked map hits
	# an engine error (the walk-in buildings made the first bake slower).
	for node in get_tree().get_nodes_in_group("nav_baker"):
		while (node as NavBaker).bake_count == 0:
			await (node as NavBaker).navmesh_ready
	level.call("start_defense")
	await seconds(1.0)
	check(SaveGame.has_save(), "starting the defense writes a checkpoint")
	var build := level.get_node("BuildController") as BuildController
	var core := level.get("core") as GreenCore
	var placed := 0
	for spot in [[0, Vector3(0, 0, 12)], [1, Vector3(-4, 0, 7)], [3, Vector3(0, 0, 16)]]:
		if build.place(spot[0], core.global_position + (spot[1] as Vector3), 0, true) != null:
			placed += 1
	check(placed == 3, "placed a barricade, a turret, and an EMP trap")
	Game.cash = 777
	Game.district.trust = 0.66
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	spawner.current_wave = 2
	level.call("_show_wave_summary", 2)
	var hud := level.get_node("Hud") as Hud
	check(hud.wave_summary_visible(), "a wave-cleared summary card shows")
	level.call("save_checkpoint")
	var save := SaveGame.read()
	check(int(save.get("waves_cleared", -1)) == 2 and (save.get("structures", []) as Array).size() == 3,
		"the checkpoint has the wave and the built structures")
	check(str(save.get("scene", "")) == Game.district_scene(0), "the checkpoint remembers which district it's in")

	# Continue into a fresh level.
	level.queue_free()
	await seconds(0.5)
	Game.pending_save = save
	Game.pending_intro = true
	var resumed := MAIN_SCENE.instantiate()
	resumed.set("boss_enabled", false)
	add_child(resumed)
	await seconds(2.0)
	var intro := resumed.get_children().filter(func(n: Node) -> bool: return n is IntroOverlay)
	check(intro.size() == 1, "the intro plays when starting from Play")
	check(resumed.get("phase") == resumed.get("Phase").BUILD, "Continue jumps straight to the defense")
	check((resumed.get_node("WaveSpawner") as WaveSpawner).current_wave == 2, "…at the saved wave")
	check(Game.cash == 777, "…with the saved cash ($%d)" % Game.cash)
	check(absf(Game.district.trust - 0.66) < 0.01, "…and the district state")
	var rebuilt := 0
	for node in get_tree().get_nodes_in_group("structures") + get_tree().get_nodes_in_group("traps"):
		if node is Barricade or node is Turret or node is EmpTrap:
			rebuilt += 1
	check(rebuilt == 3, "…and the structures rebuilt (%d)" % rebuilt)
	check(resumed.find_children("*", "DatacenterSite", false, false).is_empty(), "the fallen datacenters stay gone")

	# Difficulty scales hostile health.
	Game.difficulty = 0
	var easy := SecurityGuard.new()
	easy.position = Vector3(-84, 0.1, 40)
	resumed.add_child(easy)
	Game.difficulty = 2
	var hard := SecurityGuard.new()
	hard.position = Vector3(-84, 0.1, 44)
	resumed.add_child(hard)
	Game.difficulty = 1
	check(easy.max_health < hard.max_health, "difficulty scales enemy health (%.0f easy, %.0f hard)" % [easy.max_health, hard.max_health])
	SaveGame.clear()
	# The campaign: District 2 is locked until District 1 is won.
	Game.reset_progress()
	var title := (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
	add_child(title)
	await seconds(0.2)
	var locked := title.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
		return "Riverbend" in (b as Button).text)
	check(locked.size() == 1 and (locked[0] as Button).disabled, "the title shows Riverbend, locked")
	title.queue_free()
	check(Game.unlock_district(1) and not Game.unlock_district(1), "winning Maple Grove unlocks Riverbend (once)")
	Game.load_progress()
	check(Game.districts_unlocked == 2, "the unlock is saved")
	title = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
	add_child(title)
	await seconds(0.2)
	var open := title.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
		return (b as Button).text == "Play: Riverbend" and not (b as Button).disabled)
	check(open.size() == 1, "then the title offers Play: Riverbend")
	title.queue_free()
	var ending := resumed.get("_end_screen") as EndScreen
	ending.show_result(true, 5, 5)
	await seconds(0.1)
	var next := ending.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
		return (b as Button).text == "Next: Riverbend")
	check(next.size() == 1, "the win screen offers the next district")
	Game.reset_progress()
