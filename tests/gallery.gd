extends Node
## Screenshots of bosses and props for visual review: tests/output/gallery_*.png.
## Needs a real window (no --headless):
##   Godot_console.exe --path . res://tests/gallery.tscn [-- only=felsa,parked]

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player
## Sections to capture (user arg only=a,b); empty = all.
var only: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=").split(",")
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", not only.is_empty() and _want("sites"))
	add_child(level)
	player = level.get_node("Player") as Player
	await _wait(1.0)
	if not _want("sites") or only.is_empty():
		for node in get_tree().get_nodes_in_group("hostiles"):
			if not node is SentryTurret:
				(node as Enemy).apply_damage(9999.0, Vector3.ZERO)

	if _want("felsa"):
		var truck := FelsaCar.new()
		truck.position = Vector3(-84, -FelsaCar.CLEARANCE, 40)
		level.add_child(truck)
		truck.set_physics_process(false)
		var elmo := ElmoTruck.new()
		elmo.position = Vector3(-84, -FelsaCar.CLEARANCE, 52)
		level.add_child(elmo)
		elmo.set_physics_process(false)
		await _wait(1.0)
		await _shot("felsa", Vector3(-78, 0.2, 35), Vector3(-84, 1.0, 40))
		await _shot("felsa_side", Vector3(-76, 0.2, 46), Vector3(-84, 1.2, 46))
		truck.queue_free()
		elmo.queue_free()
	if _want("people"):
		# Hats and Elmo's Twatter crowd, lined up and frozen.
		var kinds: Array[GDScript] = [SecurityGuard, Police, Frost, OrangeHat, Townsperson, ReplyGuy, ReplyGuy, ElmoOnFoot]
		var lineup: Array[Enemy] = []
		for i in kinds.size():
			var unit := kinds[i].new() as Enemy
			unit.position = Vector3(-90.0 + i * 1.8, 0.1, 60.0)
			level.add_child(unit)
			unit.set_physics_process(false)
			unit.rotation.y = PI
			lineup.append(unit)
		await _wait(1.0)
		await _shot("people", Vector3(-84, 0.2, 67), Vector3(-84, 1.2, 60))
		await _shot("hats", Vector3(-88, 0.2, 63.5), Vector3(-88, 1.6, 60))
		for unit in lineup:
			unit.queue_free()
		# Townsperson roles and a group of lost Canadians.
		lineup.clear()
		var roles: Array[StringName] = [&"jogger", &"kid", &"gardener", &"mail_carrier", &"busker"]
		for i in roles.size() + 3:
			var unit: Enemy
			if i < roles.size():
				var resident := Resident.new()
				resident.set_role(roles[i])
				unit = resident
			else:
				var tourist := Canuck.new()
				tourist.setup(i == roles.size() + 2)
				unit = tourist
			unit.position = Vector3(-91.0 + i * 1.6, 0.1, 60.0)
			level.add_child(unit)
			unit.set_physics_process(false)
			unit.set_process(false)
			unit.rotation.y = PI
			lineup.append(unit)
		await _wait(1.0)
		await _shot("townsfolk", Vector3(-84.5, 0.2, 66), Vector3(-84.5, 1.1, 60))
		for unit in lineup:
			unit.queue_free()
	if _want("structures"):
		# Build-phase pieces, side by side on the open strip.
		var pieces: Array[Node3D] = [Barricade.new(), Turret.new(), SolarPanel.new(), EmpTrap.new()]
		for i in pieces.size():
			pieces[i].position = Vector3(-92.0 + i * 5.0, 0.0, 60.0)
			level.add_child(pieces[i])
		await _wait(1.0)
		await _shot("structures", Vector3(-84.5, 2.4, 65.5), Vector3(-84.5, 0.6, 60))
		for piece in pieces:
			piece.queue_free()
	if _want("deaths"):
		# Ragdolls: five guards killed five ways, caught mid-fall and settled.
		var kinds := [[&"bullet", 80.0], [&"bullet", 200.0], [&"melee", 99.0], [&"impact", 99.0], [&"explosive", 99.0]]
		var victims: Array[Enemy] = []
		for i in kinds.size():
			var guard := SecurityGuard.new()
			guard.position = Vector3(-90.0 + i * 3.0, 0.1, 58.0)
			level.add_child(guard)
			guard.set_physics_process(false)
			victims.append(guard)
		await _wait(0.8)
		for i in victims.size():
			var guard := victims[i]
			guard.set_physics_process(true)
			guard.max_health = 1.0
			guard.health = 1.0
			guard.apply_damage(kinds[i][1], guard.global_position + Vector3(0.0, 1.0, 6.0), kinds[i][0])
		await _wait(0.35)
		await _shot("deaths_fall", Vector3(-84, 1.8, 67), Vector3(-84, 0.6, 56))
		await _wait(2.0)
		await _shot("deaths_down", Vector3(-84, 1.8, 67), Vector3(-84, 0.3, 54))
		await _shot("deaths_close", Vector3(-86.5, 1.6, 61.5), Vector3(-87.5, 0.2, 57.5))
	if _want("parked"):
		await _shot("parked", Vector3(-30, 0.2, 21), Vector3(-22, 0.8, 26.5))
		await _shot("parked2", Vector3(46, 0.2, 21), Vector3(54, 0.8, 26.5))
	if _want("datacenter"):
		await _shot("dc_front", Vector3(14, 0.2, -4), Vector3(0, 5.0, -26))
		await _shot("dc_side", Vector3(40, 6.0, -14), Vector3(8, 4.0, -32))
		await _shot("dc_back", Vector3(-20, 0.2, -58), Vector3(-2, 5.0, -38))
		await _shot("dc_cooling", Vector3(21, 0.2, -18), Vector3(15, 1.5, -28))
		await _shot("dc_dock", Vector3(-20, 0.2, -22), Vector3(-12, 2.0, -34))
	if _want("shots"):
		player.arm_all()
		var wall := Destructible.new()
		wall.size = Vector3(6.0, 3.0, 0.4)
		wall.surface_kind = &"plates"
		wall.color = Color(0.6, 0.62, 0.65)
		wall.max_health = 99999.0
		wall.position = Vector3(-84, 0, 50)
		level.add_child(wall)
		var cam := Camera3D.new()
		level.add_child(cam)
		for weapon_name in ["Pistol", "Shotgun", "Machine gun", "Hunting rifle"]:
			player.global_position = Vector3(-84, 0.1, 58)
			player.select_weapon(player.weapons.find(player.weapon_named(weapon_name)))
			player.aim_at(Vector3(-84, 1.4, 50))
			await _wait(0.5)
			if weapon_name == "Machine gun":
				for k in 6:
					player.fire()
					await _wait(0.08)
			cam.global_position = player.global_position + Vector3(3.0, 1.6, -1.2)
			cam.look_at(player.global_position + Vector3(0, 1.3, -3.0))
			cam.make_current()
			player.fire()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/output/gallery_shot_%s.png" % weapon_name.to_snake_case())
			print("saved shot %s" % weapon_name)
			await _wait(0.12)
			cam.global_position = Vector3(-81, 1.8, 54)
			cam.look_at(Vector3(-84, 1.3, 50.2))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/output/gallery_impact_%s.png" % weapon_name.to_snake_case())
			cam.clear_current()
			await _wait(0.6)
		# Dirt: shoot the ground.
		player.select_weapon(player.weapons.find(player.weapon_named("Pistol")))
		player.aim_at(Vector3(-84, 0.0, 53))
		await _wait(0.3)
		cam.global_position = Vector3(-81.5, 1.2, 55)
		cam.look_at(Vector3(-84, 0.3, 53))
		cam.make_current()
		player.fire()
		await _wait(0.08)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/output/gallery_impact_dirt.png")
		print("saved dirt")
		cam.clear_current()
		cam.queue_free()
	if _want("hands"):
		player.arm_all()
		var side := Camera3D.new()
		level.add_child(side)
		for weapon_name in ["Pistol", "Shotgun", "Machine gun", "Rocket launcher", "Shovel", "Molotov"]:
			player.global_position = Vector3(-84, 0.1, 60)
			player.select_weapon(player.weapons.find(player.weapon_named(weapon_name)))
			player.aim_at(Vector3(-84, 1.4, 40))
			if weapon_name != "Shovel" and weapon_name != "Molotov":
				player.fire()
			await _wait(0.35)
			side.global_position = player.global_position + Vector3(3.2, 1.5, -1.6)
			side.look_at(player.global_position + Vector3(0, 1.2, -0.4))
			side.make_current()
			await _wait(0.05)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/output/gallery_hands_%s.png" % weapon_name.to_snake_case())
			print("saved hands %s" % weapon_name)
			side.clear_current()
		side.queue_free()
	if _want("stores"):
		await _shot("store_hardware", Vector3(-8, 0.2, 31), Vector3(-14, 2.0, 21))
		await _shot("store_row", Vector3(6, 0.2, 34), Vector3(-26, 4.0, 18))
		await _shot("store_south", Vector3(0, 0.2, 27), Vector3(14, 4.0, 42))
	if _want("sites"):
		await _shot("site_felsa_gate", Vector3(10, 0.2, 2), Vector3(0, 3.0, -30))
		await _shot("site_felsa_lobby", Vector3(-3, 0.2, -30), Vector3(4, 1.5, -39))
		await _shot("site_felsa_racks", Vector3(-2, 0.2, -40), Vector3(-12, 1.2, -46))
		await _wait(6.0)  # let the cheese truck reach the dock
		await _shot("site_felsa_dock", Vector3(12, 0.2, -66), Vector3(0, 1.5, -60))
		var forprofit := level.get_node("ForProfitSite") as DatacenterSite
		await _shot("site_forprofit_sham", forprofit.to_global(Vector3(-3, 0.2, 14)), forprofit.sham.global_position + Vector3.UP * 1.5)
		var scg := level.get_node("ScgrewgleSite") as DatacenterSite
		await _shot("site_scgrewgle_crapya", scg.to_global(Vector3(-2, 0.2, 13)), scg.crapya_room.global_position + Vector3.UP * 1.5)
		await _shot("site_scgrewgle", Vector3(-100, 0.2, 38), Vector3(-140, 5.0, 30))
		await _shot("site_forprofit", Vector3(100, 0.2, 22), Vector3(140, 5.0, 30))
	if _want("deeds"):
		var lady := get_tree().get_nodes_in_group("neighbors")[0] as Node3D
		await _shot("deed_grandma", lady.global_position + Vector3(3.5, 0.1, 3.0), lady.global_position + Vector3(0, 1.0, 0))
		var job := level.get_node("PaintJob") as Node3D
		await _shot("deed_paint", job.global_position + job.global_basis.z * 5.0 + Vector3(2.5, 0.1, 0), job.global_position - job.global_basis.z * 2.0 + Vector3.UP * 2.0)
		await _shot("south_street", Vector3(-4, 0.2, 100), Vector3(20, 2.0, 112))
		await _shot("sold_lot", Vector3(8, 0.2, 110), Vector3(18, 1.5, 100))
	if _want("cannon"):
		level.call("raise_alarm", "test")
		player.global_position = Vector3(6, 0.2, -6)
		for i in 8:
			player.health = player.max_health  # stay alive for the shot
			await _wait(0.25)
		await _shot("cannon", Vector3(4, 0.2, -4), Vector3(10, 7.0, -26))
		await _shot("cannon_side", Vector3(-8, 0.2, -2), Vector3(6, 3.0, -14))
	if _want("cache"):
		await _shot("cache", Vector3(-14, 0.2, -40), Vector3(-18, 0.8, -44))
	if not only.is_empty() and not _want("rest"):
		get_tree().quit()
		return

	# Car kit lineup (labels above), each turned to show its +Z side to the camera.
	var names := ["sedan", "sedan-sports", "suv", "van", "delivery", "police", "truck", "tractor-shovel", "garbage-truck", "hatchback-sports"]
	for i in names.size():
		var car := Models.model("res://assets/kenney/cars/%s.glb" % names[i], 1.45)
		car.position = Vector3(-88.0 + i * 4.5, 0.0, 30.0)
		car.rotation.y = PI * 0.5  # +Z (model front?) faces +X, toward the camera's right
		level.add_child(car)
		var tag := Label3D.new()
		tag.text = names[i]
		tag.pixel_size = 0.006
		tag.position = car.position + Vector3(0, 3.2, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		level.add_child(tag)
	await _shot("cars", Vector3(-68, 0.2, 44), Vector3(-68, 1.0, 30))

	# Particle effects: a burning Felsa car, a molotov fire, then an explosion.
	var car := FelsaCar.new()
	car.position = Vector3(-86, 0.2, 80)
	level.add_child(car)
	car.set_physics_process(false)
	car.call("_ignite")
	var fire := FireZone.new()
	fire.duration = 60.0
	level.add_child(fire)
	fire.global_position = Vector3(-80, 0.05, 86)
	await _wait(2.5)
	Vfx.explosion(level, Vector3(-88, 0.5, 80), 6.0)
	await _wait(0.2)
	await _shot("vfx", Vector3(-76, 0.2, 72), Vector3(-83, 2.0, 86))
	await _wait(1.2)
	await _shot("vfx_smoke", Vector3(-76, 0.2, 72), Vector3(-83, 2.5, 86))

	await _shot("datacenter", Vector3(22, 0.2, -12), Vector3(8, 4.0, -28))
	await _shot("turbines", Vector3(-4, 0.2, -57), Vector3(0, 5.0, -45))
	await _shot("crapya", Vector3(-10, 0.2, -18), Vector3(-18, 1.5, -30))
	await _shot("dozer", Vector3(18, 0.2, 48), Vector3(25, 1.0, 57))
	await _shot("hardware", Vector3(-6, 0.2, 30), Vector3(-14, 2.5, 20))

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


func _want(section: String) -> bool:
	return only.is_empty() or section in only


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
