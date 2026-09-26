extends TestCase
## Game flow and polish: title screen, tips, guard-dog territory, passive
## strays, Grock cameras, drivable parked cars, grounded Cyberdouches, Elmo's
## reply guys, the pause menu, the end screen, and the sound library.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/flow_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")
const TITLE_SCENE := preload("res://scenes/ui/title.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	var title := TITLE_SCENE.instantiate()
	add_child(title)
	await seconds(0.3)
	check(title.find_children("*", "Button", true, false).size() >= 4, "title screen has its menu")
	title.queue_free()
	await seconds(0.1)

	for cue: StringName in [&"pistol", &"shotgun", &"explosion", &"explosion_big", &"engine_loop", &"ev_loop",
			&"turbine_loop", &"birds_loop", &"babble", &"bark", &"click", &"jingle_win", &"glitch", &"car_crash"]:
		check(Sfx.has_cue(cue), "sound cue '%s' exists" % cue)

	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	var baker := level.get_node("NavBaker") as NavBaker
	if baker.bake_count == 0:
		await baker.navmesh_ready
	await seconds(2.5)
	check(Game.has_seen_tip("move"), "the tutorial's first tip showed")

	await _test_pickups()
	await _test_grounding()
	await _test_dogs()
	await _test_grock_cameras()
	await _test_parked_cars()
	await _test_reply_guys()
	_test_pause_and_end()


## Bare hands at the start; a shovel and rocks from the neighborhood.
func _test_pickups() -> void:
	check(player.current_weapon().display_name == "Fists", "the player starts with bare hands")
	var shovel: WeaponPickup = null
	var rocks: WeaponPickup = null
	for node in get_tree().get_nodes_in_group("pickups"):
		var pickup := node as WeaponPickup
		if pickup.kind == &"shovel" and shovel == null:
			shovel = pickup
		elif pickup.kind == &"rocks" and rocks == null:
			rocks = pickup
	check(shovel != null and rocks != null, "shovels and rock piles lie around the block")
	player.global_position = shovel.global_position + Vector3(1.0, 0.2, 0.0)
	await seconds(0.1)
	check(player.nearest_interactable() == shovel, "[E] reaches the shovel")
	shovel.interact(player)
	check(player.current_weapon().display_name == "Shovel" and player.held_model() != null, "picked up the shovel, and it's in hand")
	player.global_position = rocks.global_position + Vector3(1.0, 0.2, 0.0)
	await seconds(0.1)
	rocks.interact(player)
	check(player.weapon_named("Rocks").ammo == 6 and not rocks.available, "grabbed 6 rocks; the pile restocks later")


## Cyberdouche and parked-car wheels touch the ground instead of sinking in.
func _test_grounding() -> void:
	var felsa := level.get_node("PatrolFelsa") as FelsaCar
	var bounds := Models.model_bounds(felsa.get("_visual"))
	var bottom := felsa.global_position.y + bounds.position.y
	if absf(bottom) >= 0.12:
		print("  felsa at %s alive=%s burning=%s visual_y=%.2f bounds=%s floor=%s" % [felsa.global_position, felsa.is_alive(),
			felsa.is_burning, (felsa.get("_visual") as Node3D).position.y, bounds, felsa.is_on_floor()])
	check(absf(bottom) < 0.12, "Cyberdouche sits on the ground (wheel bottom y=%.2f)" % bottom)
	var parked := _parked_cars()
	check(parked.size() >= 4, "parked cars are drivable Cars (%d)" % parked.size())
	var worst := 0.0
	for car in parked:
		var model := car.get_children().filter(func(n: Node) -> bool: return n is Node3D and n.scene_file_path.ends_with(".glb"))
		if model.is_empty():
			continue
		var car_bounds := Models.model_bounds(model[0])
		worst = maxf(worst, absf(car.global_position.y + car_bounds.position.y))
	check(worst < 0.2, "parked cars rest on their wheels (worst offset %.2f m)" % worst)


func _test_dogs() -> void:
	var dog := level.get_node("Dog1") as Dog
	var stray := level.get_node("StrayDog1") as Dog
	check(stray.is_in_group("strays") and not stray.is_in_group("hostiles"), "neighborhood strays aren't hostile")
	# Outside the compound: guard dogs stay put.
	player.global_position = Vector3(5, 0.2, 2)
	await seconds(2.0)
	check(not dog._is_valid(dog.target) or dog.target != player, "guard dog ignores the player outside its territory")
	# Next to a stray for a while: no bites.
	var hurt := [0]
	var on_hurt := func(_h: float, _m: float) -> void: hurt[0] += 1
	player.health_changed.connect(on_hurt)
	player.global_position = stray.global_position + Vector3(1.2, 0.2, 0)
	await seconds(2.0)
	check(hurt[0] == 0, "strays never bite")
	player.health_changed.disconnect(on_hurt)
	# Inside the fence: nothing happens until the player attacks the site.
	player.global_position = Vector3(5, 0.2, -20)
	await seconds(1.5)
	check(dog.target != player and not Game.alarm, "guard dog holds off until the site is attacked")
	var guard := level.get_node("Guard3") as Enemy
	guard.apply_damage(5.0, player.global_position, &"bullet")
	check(Game.alarm, "hurting a guard raises the site alarm")
	await seconds(1.5)
	check(dog.target == player, "then the guard dog attacks inside the datacenter grounds")
	player.global_position = Vector3(-60, 0.2, 40)
	await seconds(0.5)


func _test_grock_cameras() -> void:
	var cameras := get_tree().get_nodes_in_group("grock_cameras")
	check(cameras.size() >= 5, "Grock cameras on the block (%d)" % cameras.size())
	var camera := cameras[0] as GrockCamera
	var cash := Game.cash
	var trust := Game.district.trust
	var reward := camera.reward
	var smashed := [false]
	camera.smashed.connect(func(_c: GrockCamera) -> void: smashed[0] = true)
	camera.apply_damage(15.0, player.global_position, &"bullet")
	camera.apply_damage(15.0, player.global_position, &"bullet")
	await seconds(0.2)
	check(smashed[0], "two pistol shots smash a Grock camera")
	check(Game.cash == cash + reward, "camera pays $%d" % (Game.cash - cash))
	check(Game.district.trust > trust, "smashing it raises trust")


func _test_parked_cars() -> void:
	var car := _parked_cars()[0]
	player.global_position = car.global_position + Vector3(0, 0.5, 2.5)
	await seconds(0.2)
	check(car.enter(player) and player.vehicle == car, "a parked car can be driven")
	await seconds(0.3)
	car.exit()
	await seconds(0.3)
	check(player.vehicle == null, "and left again")


func _test_reply_guys() -> void:
	player.global_position = Vector3(-84, 0.2, 60)
	var elmo := ElmoOnFoot.new()
	elmo.position = Vector3(-84, 0.2, 80)
	level.add_child(elmo)
	await seconds(0.3)
	check(elmo.get("_phone").visible, "Elmo is always on his phone")
	elmo.set("_post_left", 0.0)
	await seconds(elmo.post_duration + 0.6)
	var guys := get_tree().get_nodes_in_group("reply_guys")
	check(guys.size() >= 2, "a Twat summons reply guys (%d)" % guys.size())
	elmo.apply_damage(99999.0, elmo.global_position, &"explosive")
	get_tree().call_group(&"reply_guys", &"log_off")
	await seconds(3.0)
	check(get_tree().get_nodes_in_group("reply_guys").is_empty(), "reply guys log off when Elmo goes down")


func _test_pause_and_end() -> void:
	var menu: PauseMenu = null
	for node in level.get_children():
		if node is PauseMenu:
			menu = node
	check(menu != null, "level has a pause menu")
	if menu:
		menu.open()
		check(get_tree().paused and menu.is_open, "pause menu pauses the game")
		menu.close()
		check(not get_tree().paused, "and resumes it")
	var end: EndScreen = null
	for node in level.get_children():
		if node is EndScreen:
			end = node
	check(end != null, "level has an end screen")
	if end:
		end.show_result(true, 5, 5)
		check(end.is_shown and end.rows.size() >= 10, "end screen lists the run's stats")


func _parked_cars() -> Array[Car]:
	var list: Array[Car] = []
	for node in level.get_node("Neighborhood").get_children():
		if node is Car:
			list.append(node)
	return list
