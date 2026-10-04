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
	# Lay the menu out at a real resolution (the headless window is 64x64).
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.size = Vector2(1600, 900)
	for c: Control in title.find_children("*", "Container", true, false):
		c.queue_sort()
	await seconds(0.1)
	# Mouse: nothing invisible sits on top of the menu buttons (an empty
	# full-screen container used to swallow every click).
	for node in title.find_children("*", "Button", true, false):
		var button := node as Button
		var hit := _control_at(title, button.get_global_rect().get_center())
		check(hit == button, "a mouse click reaches the %s button (%s)" % [button.text, hit.name if hit else "nothing"])
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

	var home: Vector3 = Game.get_meta(&"home", Vector3.ZERO)
	check(home != Vector3.ZERO and level.get_node_or_null("HomeSign") != null, "the player has a home with a HOME sign")
	await _test_irrigation()
	var hardware: Vector3 = Game.get_meta(&"hardware_door")
	check(level.call("guidance_point") == hardware, "the minimap points an unarmed player to DUECE Hardware")
	var hud := level.get_node("Hud") as Hud
	check(not hud.is_map_expanded(), "the minimap starts small")
	var press := InputEventAction.new()
	press.action = &"map"
	press.pressed = true
	hud.call("_unhandled_input", press)
	check(hud.is_map_expanded(), "[M] opens the full map")
	hud.call("_unhandled_input", press)
	await _test_hud_overlay(hud, hardware)
	await _test_hud_layout(hud)
	await _test_animation_layers()
	check(Sfx.music_track == &"calm", "calm music plays in the neighborhood (%s)" % Sfx.music_track)
	await _test_aim_hold()
	await _test_pickups()
	check(level.call("guidance_point") != hardware, "once armed, it points at the next good deed")
	await _test_grounding()
	await _test_dogs()
	await _test_grock_cameras()
	await _test_parked_cars()
	await _test_market_and_residents()
	await _test_canadians()
	check(hud.ally_count() >= 2, "the HUD counts recruited Canadians as allies (%d)" % hud.ally_count())
	check(level.call("canadian_allies") >= 2, "the level counts recruited Canadians toward the RV cap")
	level.call("_send_canadians_home")
	await seconds(0.5)
	check(level.call("canadian_allies") == 0 and get_tree().get_nodes_in_group("canadians").all(
		func(n: Node) -> bool: return not n.is_in_group("allies")), "after a wave the Canadians say goodbye and head home")
	await _test_vehicles()
	await _test_traffic_dogs_bubbles()
	await _test_reply_guys()
	await _test_site_life()
	await _test_town_hall()
	await _test_solid_props()
	await _test_heat_reset()
	await _test_pause_and_end()


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
	var felsa := level.get_node("FelsaSite/PatrolFelsa") as FelsaCar
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
	var dog := level.get_node("FelsaSite/FrontDog") as Dog
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
	# Inside the fence: quiet site dogs don't attack on sight (they sniff
	# first; stealth_test covers being noticed and the alarm).
	player.global_position = Vector3(5, 0.2, -20)
	await seconds(0.5)
	check(dog.target != player and not Game.is_alarmed(&"felsa"), "guard dog holds off until the site is attacked")
	var guard := level.get_node("FelsaSite/PatrolGuard") as Enemy
	guard.apply_damage(5.0, player.global_position, &"bullet")
	check(Game.is_alarmed(&"felsa") and not Game.is_alarmed(&"forprofit"), "hurting a guard raises the site alarm")
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
	check(Game.cash >= cash + reward, "camera pays $%d" % (Game.cash - cash))  # other payouts can land in the same moment
	check(Game.district.trust > trust, "smashing it raises trust")


func _test_parked_cars() -> void:
	var car := _parked_cars()[0]
	var details := car.get_node_or_null("Details")
	check(details != null and not details.find_children("*", "Label3D", false, false).is_empty(),
		"parked cars carry plates, mirrors, and trim")
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


func _test_market_and_residents() -> void:
	var residents := get_tree().get_nodes_in_group("residents")
	check(residents.size() >= 24, "neighbors are out on the block (%d)" % residents.size())
	var market := level.get_node("FarmersMarket") as FarmersMarket
	player.global_position = market.global_position + Vector3(0, 0.2, 4)
	await seconds(0.1)
	check(player.nearest_interactable() == market, "[E] reaches the farmer's market")
	player.health = 50.0
	Game.cash = 100
	var trust := Game.district.trust
	check(market.buy(0, player), "bought fresh bread")
	check(Game.cash == 85 and is_equal_approx(player.health, 75.0), "bread costs $15 and heals 25 ($%d, %d hp)" % [Game.cash, int(player.health)])
	check(Game.district.trust > trust, "buying local raises trust")
	check(market.buy(4, player) and Game.cash == 5, "the $80 quilt leaves $5")
	check(not market.buy(0, player), "can't afford bread with $5")


## Hold right click: zoom in (narrower FOV) and a steadier aim.
func _test_aim_hold() -> void:
	var saved := player.weapons.map(func(w: Weapon) -> Array: return [w.owned, w.ammo])
	var index := player.weapon_index
	player.arm_all()
	for i in player.weapons.size():
		if player.weapons[i].display_name == "Pistol":
			player.select_weapon(i)
	var camera := get_viewport().get_camera_3d()
	var fov_before := camera.fov
	Input.action_press("aim")
	await seconds(0.5)
	check(player.aiming, "holding right click aims the pistol")
	check(camera.fov < fov_before - 10.0, "aiming zooms in (fov %.0f -> %.0f)" % [fov_before, camera.fov])
	Input.action_release("aim")
	await seconds(0.5)
	check(not player.aiming and absf(camera.fov - fov_before) < 1.0, "releasing it zooms back out")
	for i in saved.size():
		player.weapons[i].owned = saved[i][0]
		player.weapons[i].ammo = saved[i][1]
	player.select_weapon(index)


## Held upper-body poses and ragdoll deaths (Quaternius clips on the Kenney rig).
func _test_animation_layers() -> void:
	var spot := player.global_position + Vector3(0.0, 0.1, -8.0)
	var cop := Police.new()
	cop.position = spot + Vector3(-2.0, 0.0, 0.0)
	cop.site = &"police"  # dormant: stands still, shield up
	level.add_child(cop)
	var fan := ReplyGuy.new()
	fan.position = spot + Vector3(2.0, 0.0, 0.0)
	level.add_child(fan)
	await seconds(0.8)
	check((cop.get("_rig") as CharacterModel).upper_clip() == &"shield_idle", "riot police hold their shields up")
	check((fan.get("_rig") as CharacterModel).upper_clip() == &"zombie_walk", "reply guys shamble with zombie arms")
	check(fan.move_speed < 2.0 and fan.girth.x >= 2.0, "reply guys are fat and slow (%.1f m/s)" % fan.move_speed)
	var guard := SecurityGuard.new()
	guard.position = spot + Vector3(0.0, 0.0, -4.0)
	level.add_child(guard)
	await seconds(1.0)
	var pose := (guard.get("_rig") as CharacterModel).upper_clip()
	check(pose == &"pistol_aim" or pose == &"pistol_idle", "guards carry and aim their pistols (%s)" % pose)
	var before := Ragdoll.active
	guard.apply_damage(9999.0, player.global_position, &"bullet")
	await seconds(0.2)
	check(Ragdoll.active > before, "a guard killed near the camera goes limp (ragdoll)")
	fan.log_off()
	cop.queue_free()
	player.heal(9999.0)
	await seconds(0.5)


func _test_hud_layout(hud: Hud) -> void:
	await seconds(0.3)
	check(hud.checklist_rows("deeds").size() == 15, "good deeds are a checklist on the right (%d rows)" % hud.checklist_rows("deeds").size())
	check(hud.checklist_rows("sites").size() == 3, "datacenter status is a checklist (%d rows)" % hud.checklist_rows("sites").size())
	# Speech: only the nearest few talk, and neighbors' bubbles stack.
	var crowd: Array[Resident] = []
	for i in 6:
		var r := Resident.new()
		r.position = player.global_position + Vector3(1.0 + i * 0.4, 0.1, 3.0 + i * 2.0)
		level.add_child(r)
		r.set_process(false)
		r.set_physics_process(false)
		crowd.append(r)
	await seconds(0.1)
	# Whoever else is mid-sentence nearby would take the talker slots.
	for t: Variant in Enemy._talkers.duplicate():
		if is_instance_valid(t):
			(t as Enemy).speak("")
	Enemy._talkers.clear()
	for r in crowd:
		r.speak("Hello there, neighbor!")
	var talking := crowd.filter(func(r: Resident) -> bool:
		var label := r.get("_speech_label") as Label3D
		return label != null and not label.text.is_empty())
	check(talking.size() <= Enemy.MAX_TALKERS, "at most %d townspeople talk at once (%d)" % [Enemy.MAX_TALKERS, talking.size()])
	check(talking.has(crowd[0]), "the nearest one gets to talk")
	var heights := talking.map(func(r: Resident) -> float: return (r.get("_speech_label") as Label3D).position.y - r.body_height)
	check(heights.max() - heights.min() > 0.3, "bubbles of people standing together stack upward")
	for r in crowd:
		r.speak("")
		r.queue_free()


## Traffic stops for people; the patrol has no electric whine; tamed dogs
## only defend; speech bubbles don't show through walls.
func _test_traffic_dogs_bubbles() -> void:
	var van := SupplyVan.new()
	van.route = [Vector3(-84, 0.2, 90), Vector3(-84, 0.2, 20)] as Array[Vector3]
	van.position = Vector3(-84, 0.2, 20)
	level.add_child(van)
	var walker := Resident.new()
	walker.position = Vector3(-84, 0.1, 42)
	level.add_child(walker)
	walker.set_physics_process(false)
	var closest := [INF]
	for i in 40:
		await seconds(0.2)
		closest[0] = minf(closest[0], van.global_position.distance_to(walker.global_position))
	check(walker.is_alive() and walker.health >= walker.max_health, "traffic stops for a neighbor in the road (closest %.1f m)" % closest[0])
	van.queue_free()
	walker.queue_free()
	var cruiser: PoliceCruiser = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		if node is PoliceCruiser:
			cruiser = node
	check(cruiser != null and cruiser.motor_cue == &"engine_loop", "police cruisers have an engine, not an electric whine")

	var dog := Dog.new()
	dog.position = player.global_position + Vector3(2, 0.1, 0)
	level.add_child(dog)
	await seconds(0.3)
	dog.befriend()
	var decoy := Barricade.new()
	decoy.position = player.global_position + Vector3(9, 0, 0)
	level.add_child(decoy)
	var guard := SecurityGuard.new()
	guard.position = player.global_position + Vector3(7, 0.1, 3)
	level.add_child(guard)
	guard.set_physics_process(false)
	guard.target = decoy
	await seconds(1.0)
	check(dog.target != guard, "a tamed dog ignores a hostile that isn't after you")
	guard.target = player
	await seconds(1.0)
	check(dog.target == guard, "…and goes for one that is")
	guard.queue_free()
	decoy.queue_free()
	dog.queue_free()


func _test_hud_overlay(hud: Hud, hardware: Vector3) -> void:
	var overlay := hud.overlay()
	await seconds(0.3)
	check(overlay.objective_point() == hardware, "an on-screen marker points at the objective")
	Game.show_banner("TEST BANNER", "sub")
	check(overlay.current_banner() == "TEST BANNER", "phase banners show center screen")
	player.damage_dealt.emit(player.global_position + Vector3(0, 2, -5), 15.0, false)
	player.apply_damage(1.0, player.global_position + Vector3(6.0, 0.0, 0.0))
	check((overlay.get("_numbers") as Array).size() == 1, "hits pop floating damage numbers")
	check((overlay.get("_arcs") as Array).size() == 1, "getting hurt shows which way it came from")
	player.heal(10.0)
	var fx := get_tree().get_first_node_in_group(&"camera_fx") as CameraFx
	Game.shake(player.global_position, 1.0)
	check(fx != null and fx.trauma() > 0.5, "a nearby blast shakes the camera")
	await seconds(1.0)
	check(fx.trauma() < 0.5, "the shake settles")


func _test_canadians() -> void:
	var roles := {}
	for node in get_tree().get_nodes_in_group("residents"):
		roles[(node as Resident).role] = true
	check(roles.has(&"jogger") and roles.has(&"dog_walker") and roles.has(&"busker") and roles.has(&"kid"),
		"many kinds of townspeople (%s)" % ", ".join(roles.keys()))
	check(not get_tree().get_nodes_in_group("pets").is_empty(), "dog walkers bring their pets")
	var rv: TouristRV = level.call("spawn_tourists")
	for i in 120:
		if rv.leg == TouristRV.Leg.PARKED:
			break
		await seconds(0.25)
	check(rv.leg == TouristRV.Leg.PARKED and rv.tourists.size() >= 2, "a camper of lost Canadians pulls over (%d aboard)" % rv.tourists.size())
	var tourist := rv.tourists[0]
	check(tourist.is_in_group("tourists") and not tourist.is_in_group("allies"), "lost tourists aren't in the fight")
	player.global_position = tourist.global_position + Vector3(1.0, 0.2, 0.0)
	await seconds(0.1)
	check(player.nearest_interactable() == tourist, "[E] reaches the lost tourists")
	tourist.interact(player)
	check(rv.tourists.all(func(t: Canuck) -> bool: return t.state == Canuck.State.ALLY and t.is_in_group("allies")),
		"helping one brings the whole group onto your side")
	var goon := SecurityGuard.new()
	goon.position = tourist.global_position + Vector3(2.5, 0.1, 0.0)
	level.add_child(goon)
	goon.set_physics_process(false)
	var hp := goon.health
	for i in 24:
		if goon.health < hp:
			break
		await seconds(0.25)
	check(goon.health < hp, "Canadian allies fight hostiles with hockey sticks")
	goon.apply_damage(9999.0, Vector3.ZERO)


## Cars right themselves, turbo boosts and drains, and a dog in the road
## gets shoved aside instead of stopping the car dead.
func _test_vehicles() -> void:
	var car := level.get_node("Car") as Car
	car.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(-84, 1.5, 10))
	car.linear_velocity = Vector3.ZERO
	for i in 20:
		if car.global_basis.y.dot(Vector3.UP) > 0.9:
			break
		await seconds(0.25)
	check(car.global_basis.y.dot(Vector3.UP) > 0.9, "a flipped car rights itself")

	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(-84, 0.8, -6))  # facing +Z
	await seconds(0.5)
	player.global_position = car.global_position + Vector3(2, 0.2, 0)
	await seconds(0.1)
	car.enter(player)
	var dog := Dog.new()
	dog.stray = true
	dog.position = Vector3(-84, 0.1, 5)
	level.add_child(dog)
	dog.set_physics_process(false)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await seconds(1.0)
	check(car.boosting or car.turbo_left < car.turbo_seconds, "Shift fires the turbo (%.1fs left)" % car.turbo_left)
	Input.action_release("sprint")
	await seconds(3.5)
	Input.action_release("move_forward")
	check(car.global_position.z > 7.0 and is_instance_valid(dog) and dog.is_alive(),
		"the car drives on through a dog in the road instead of getting stuck (car z %.1f)" % car.global_position.z)
	car.exit()
	await seconds(0.3)
	if is_instance_valid(dog):
		dog.queue_free()


## Scgrewgle's cheese truck rolls in the back gate and leaves with money; the
## ForProfitSI tech flees when that site's alarm goes off.
func _test_site_life() -> void:
	for site_name in ["ScgrewgleSite", "FelsaSite"]:
		var site_node := level.get_node(site_name) as DatacenterSite
		var truck := site_node.truck
		var gate := site_node.get_node("BackGate") as SiteGate
		# Follow one full cycle from wherever the loop is: cheese in, gate open, money out.
		var saw_cheese := false
		var opened := false
		var loaded := false
		var deepest := 999.0
		for i in 240:
			saw_cheese = saw_cheese or (truck.cargo == CargoTruck.Cargo.CHEESE and truck.visible)
			opened = opened or gate.open_amount > 0.6  # any sample: it may open before the cheese check
			if truck.visible:
				deepest = minf(deepest, truck.global_position.distance_to(site_node.datacenter.global_position))
			if saw_cheese and truck.cargo == CargoTruck.Cargo.MONEY:
				loaded = true
				break
			await seconds(0.25)
		check(saw_cheese, "%s: trucks arrive with Government Cheese" % site_node.display_name)
		check(opened, "%s: the back gate slides open for the truck" % site_node.display_name)
		check(loaded and deepest < 20.0, "%s: it drives onto the property to the dock and leaves full of money (closest %.0f m)"
			% [site_node.display_name, deepest])
	var forprofit := level.get_node("ForProfitSite") as DatacenterSite
	var worker := forprofit.worker
	check(not worker.fled, "the tech works quietly until the alarm")
	level.call("raise_alarm", &"forprofit", "test")
	await seconds(1.0)
	check(worker.fled, "the tech flees when the alarm goes off")
	var eta: float = level.call("police_eta", &"forprofit")
	check(eta > 20.0, "police take a while to respond (%.0f s)" % eta)
	var early := get_tree().get_nodes_in_group("hostiles").any(func(n: Node) -> bool:
		return n is PoliceCruiser and (n as PoliceCruiser).respond_site == &"forprofit")
	check(not early, "no cruiser is sent right away")
	level.call("_tick_police_calls", eta + 0.1)  # skip the wait
	var cruiser: PoliceCruiser = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		if node is PoliceCruiser and (node as PoliceCruiser).respond_site == &"forprofit":
			cruiser = node
	check(cruiser != null and cruiser.responding, "the alarm dispatches a police cruiser")
	for i in 240:
		if cruiser == null or cruiser.deployed:
			break
		await seconds(0.25)
	check(cruiser != null and cruiser.deployed, "it drives the roads to ForProfitSI and deploys (at %s)"
		% (cruiser.global_position.snapped(Vector3.ONE) if cruiser else Vector3.ZERO))
	var officers := get_tree().get_nodes_in_group("hostiles").filter(func(n: Node) -> bool:
		return n is Police and (n as Police).site == &"forprofit")
	check(officers.size() == 2, "two riot officers join the fight (%d)" % officers.size())


## Market stalls and park benches are solid (people and the player used to clip through).
## Bribes happen at the Town Hall only.
## Corporate lawns: sprinklers, a controller, and a fountain per site; smashing
## them saves water; the controller shuts its sprinklers off.
func _test_irrigation() -> void:
	var site_node := level.get_node("FelsaSite") as DatacenterSite
	check(site_node.irrigation.size() >= 12, "Felsa's lawn has irrigation (%d parts)" % site_node.irrigation.size())
	var status: Array = level.call("irrigation_status")
	check(status[0] == 0 and status[1] >= 36, "all irrigation starts running (%d parts)" % status[1])
	var water := Game.district.water_table
	var head: IrrigationPart = null
	var controller: IrrigationPart = null
	for part in site_node.irrigation:
		if part.kind == IrrigationPart.Kind.SPRINKLER and head == null:
			head = part
		elif part.kind == IrrigationPart.Kind.CONTROLLER:
			controller = part
	head.apply_damage(999.0, head.global_position + Vector3(0, 1, 3), &"bullet")
	await seconds(0.3)
	check(Game.district.water_table > water, "smashing a sprinkler saves water")
	check(not Game.is_alarmed(&"felsa"), "wrecking the landscaping doesn't trip the alarm")
	controller.apply_damage(999.0, controller.global_position + Vector3(0, 1, 3), &"bullet")
	await seconds(0.3)
	check(site_node.irrigation_running() < 0.1, "the controller takes its sprinklers down with it (%.0f%% running)" % (site_node.irrigation_running() * 100.0))
	var cars := 0
	for node in site_node.get_children():
		if node is Car:
			cars += 1
	check(cars >= 6, "Felsa has parking lots full of drivable cars (%d)" % cars)


func _test_town_hall() -> void:
	var menu := get_tree().get_first_node_in_group("bribe_menu") as BribeMenu
	var hall: Vector3 = Game.get_meta(&"town_hall_door", Vector3.ZERO)
	check(hall != Vector3.ZERO, "the neighborhood has a Town Hall")
	player.global_position = hall + Vector3(0.0, 0.0, 30.0)
	await seconds(0.4)
	check(not menu.near_town_hall(), "away from the Town Hall, no bribe option")
	var press := InputEventAction.new()
	press.action = &"bribe_menu"
	press.pressed = true
	menu.call("_unhandled_input", press)
	check(not menu.is_open, "[V] does nothing away from the Town Hall")
	player.global_position = hall
	await seconds(0.4)
	check(menu.near_town_hall(), "at the Town Hall door, bribes are on offer")
	menu.call("_unhandled_input", press)
	check(menu.is_open, "[V] opens the bribe menu at the Town Hall")
	player.global_position = hall + Vector3(0.0, 0.0, 30.0)
	await seconds(0.5)
	check(not menu.is_open, "walking away closes the bribe menu")
	# Driving: the check follows the car, not where the player got in.
	var car := level.get_node("Car") as Car
	player.global_position = hall + Vector3(3.0, 0.0, 0.0)
	car.global_transform = Transform3D(Basis.IDENTITY, hall + Vector3(0.0, 0.6, -60.0))
	car.linear_velocity = Vector3.ZERO
	await seconds(0.3)
	player.vehicle = car
	check(not menu.near_town_hall(), "driving away from the Town Hall turns bribes off")
	player.vehicle = null


func _test_solid_props() -> void:
	var market := get_tree().get_first_node_in_group("markets") as Node3D
	var stall := market.global_transform * Vector3(-7.5, 1.0, 0.0)
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(stall + market.global_basis.z * 3.0, stall - market.global_basis.z * 3.0, 1)
	check(not space.intersect_ray(ray).is_empty(), "farmer's market stalls are solid")
	var benches := 0
	for body in level.get_node("Neighborhood").find_children("*", "StaticBody3D", true, false):
		if (body as Node3D).get_parent().get_child_count() > 0 and body.get_parent().get_parent() == level.get_node("Neighborhood"):
			benches += 1
	check(benches > 0, "neighborhood props have colliders (%d)" % benches)


## GTA-style: getting knocked out clears the alarms; damage stays.
func _test_heat_reset() -> void:
	var hud_rows := func() -> int: return (level.get_node("Hud") as Hud).checklist_rows("deeds").size()
	level.call("raise_alarm", &"scgrewgle", "test")
	# A hunter with no site (like Elmo once he's out of his datacenter), whose
	# standing objective is the player.
	var hunter := SecurityGuard.new()
	hunter.position = player.global_position + Vector3(9.0, 0.2, 0.0)
	hunter.objective = player
	level.add_child(hunter)
	await seconds(1.5)
	check(Game.is_alarmed(&"scgrewgle"), "the Scgrewgle alarm is up")
	var others := 0
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and unit.is_alive() and unit.site in [&"felsa", &"forprofit"] and not unit.is_dormant() and not Game.is_alarmed(unit.site):
			others += 1
	check(others == 0, "one site's alarm leaves the other sites' security asleep (%d awake)" % others)
	check(level.phase == level.Phase.ASSAULT and hud_rows.call() > 0, "the good deeds stay on the list while a site is on alert")
	check(hunter.target == player, "a hunter with no site is on the player")
	var hud := level.get_node("Hud") as Hud
	player.apply_damage(99999.0, player.global_position + Vector3(0, 0, -3), &"bullet")
	await seconds(0.3)
	check(not Game.is_alarmed(&"scgrewgle"), "getting knocked out calls off the Scgrewgle alarm")
	check(hud.overlay().current_banner() == "KNOCKED OUT", "a KNOCKED OUT banner shows")
	var hunting := 0
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and unit.site == &"scgrewgle" and unit.is_alive() and is_instance_valid(unit.target):
			hunting += 1
	await seconds(0.6)
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and unit.site == &"scgrewgle" and unit.is_alive() and is_instance_valid(unit.target):
			hunting += 100
	check(hunting < 100, "Scgrewgle security stops pursuing and goes back to post")
	player.apply_damage(50.0, player.global_position + Vector3(0, 0, -3), &"bullet")
	check(player.health >= player.max_health - 0.1, "spawn protection absorbs hits right after respawn")
	check(Game.stat("knockouts") >= 1.0, "knockouts are counted for the end screen")
	# The siteless hunter loses the trail too, instead of camping the respawn.
	check(hunter.lost_player and not is_instance_valid(hunter.target), "a hunter with no site loses the trail on a knockout")
	var post := hunter.home
	await seconds(4.0)
	check(not is_instance_valid(hunter.target) and hunter.global_position.distance_to(post) < 6.0,
		"it goes back where it came from, not to the respawn point (%.0f m from its post)" % hunter.global_position.distance_to(post))
	await seconds(5.0)  # past its grace period and the spawn protection
	hunter.global_position = player.global_position + Vector3(0.0, 0.2, 8.0)
	await seconds(1.0)
	check(not hunter.lost_player and hunter.target == player, "walking back into its sight picks the fight up again")
	hunter.queue_free()
	player.health = player.max_health
	await seconds(0.2)
	# Breaking contact works without getting knocked out, too.
	var cooldown: float = level.get("alarm_cooldown")
	level.set("alarm_cooldown", 2.0)
	level.call("raise_alarm", &"scgrewgle", "test")
	check(Game.is_alarmed(&"scgrewgle"), "the alarm is back up")
	await seconds(4.0)
	check(Game.is_alarmed(&"scgrewgle"), "the search goes on while the police are still on their way")
	(level.get("_police_calls") as Dictionary).erase(&"scgrewgle")  # as if they came and found nothing
	await seconds(4.0)
	check(not Game.is_alarmed(&"scgrewgle"), "an alarmed site gives up the search once it loses you")
	level.set("alarm_cooldown", cooldown)


func _test_pause_and_end() -> void:
	var menu: PauseMenu = null
	for node in level.get_children():
		if node is PauseMenu:
			menu = node
	check(menu != null, "level has a pause menu")
	if menu:
		menu.open()
		check(get_tree().paused and menu.is_open, "pause menu pauses the game")
		var root := menu.get("_root") as Control
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.size = Vector2(1600, 900)
		await get_tree().process_frame
		await get_tree().process_frame
		var buttons := root.find_children("*", "Button", true, false)
		check(buttons.all(func(b: Node) -> bool: return _control_at(root, (b as Button).get_global_rect().get_center()) == b),
			"mouse clicks reach every pause menu button")
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


## The control a mouse click at `point` would land on: topmost first, skipping
## click-through (IGNORE) and hidden controls, like Godot's GUI picking.
func _control_at(node: Node, point: Vector2) -> Control:
	var children := node.get_children()
	children.reverse()
	for child in children:
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var hit := _control_at(child, point)
		if hit:
			return hit
	var control := node as Control
	if control and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(point):
		return control
	return null


func _parked_cars() -> Array[Car]:
	var list: Array[Car] = []
	for node in level.get_node("Neighborhood").get_children():
		if node is Car:
			list.append(node)
	return list
