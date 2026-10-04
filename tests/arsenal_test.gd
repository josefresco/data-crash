extends TestCase
## Level 3 arsenal: gun show, machine gun, grenades, security cache + rockets,
## and the trust-locked bulldozer.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/arsenal_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(0.5)
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	await seconds(0.3)

	await _test_orders()
	await _test_airport()
	await _test_failurecab()
	await _test_gun_show()
	await _test_machine_gun()
	await _test_grenade()
	await _test_rockets()
	await _test_bulldozer()
	await _test_heavy_equipment()


func _dummy(unit: Enemy, at: Vector3) -> Enemy:
	unit.position = at
	level.add_child(unit)
	unit.set_physics_process(false)
	return unit


## The airport: a helicopter carries allies to a datacenter roof and they
## rappel to its cooling units; a plane you bail out of flies into a
## datacenter and blows a hole in it while you drift down under a canopy.
func _test_airport() -> void:
	var airport := level.get_node("Airport") as Airport
	var planes := airport.aircraft.filter(func(a: Aircraft) -> bool: return a is Airplane)
	var helis := airport.aircraft.filter(func(a: Aircraft) -> bool: return a is Helicopter)
	check(planes.size() == 2 and helis.size() == 2, "the airport has two planes and two helicopters")
	var heli := helis[0] as Helicopter
	var allies: Array[Canuck] = []
	for i in 2:
		var ally := Canuck.new()
		ally.setup(false)
		ally.position = heli.global_position + Vector3(4.0 + i, 0.2, 3.0)
		level.add_child(ally)
		ally.join()
		allies.append(ally)
	await seconds(0.3)
	player.global_position = heli.global_position + Vector3(3.0, 0.2, 0.0)
	await seconds(0.05)
	check(heli.in_reach(player), "[E] reaches the helicopter")
	heli.board(player)
	check(player.aircraft == heli and heli.passengers.size() == 2, "you and two allies climb aboard (%d)" % heli.passengers.size())
	# Fly it to a datacenter roof (teleported for the test) and land.
	var site_node := level.get_node("ScgrewgleSite") as DatacenterSite
	heli.global_position = site_node.datacenter.to_global(Vector3(0.0, site_node.datacenter.height + 0.6, 0.0))
	await seconds(1.0)
	check(heli.roof_site() == site_node, "landed on %s's roof" % site_node.display_name)
	heli.leave(heli.global_position + Vector3(3.0, 0.5, 0.0))
	await seconds(0.3)
	check(player.aircraft == null and player.visible, "you climb out on the roof")
	var near := allies.filter(func(a: Canuck) -> bool:
		for node in site_node.datacenter.find_children("*", "Destructible", true, false):
			if node.is_in_group(&"cooling_units") and a.global_position.distance_to((node as Node3D).global_position) < 8.0:
				return true
		return false).size()
	check(near == 2 and allies.all(func(a: Canuck) -> bool: return a.order_point != Vector3.INF),
		"the allies rappel down to the cooling units with orders to wreck them (%d)" % near)
	for ally in allies:
		ally.queue_free()

	# The plane: take off (placed airborne for the test), aim it at ForProfitSI, bail.
	var plane := planes[0] as Airplane
	player.global_position = plane.global_position + Vector3(4.0, 0.2, 0.0)
	await seconds(0.05)
	plane.board(player)
	var target := level.get_node("ForProfitSite") as DatacenterSite
	# Off the center line: the front and back doorways line up down the aisle.
	var aim := target.datacenter.to_global(Vector3(9.0, 4.0, 0.0))
	var start := aim + Vector3(0.0, 30.0, 140.0)
	plane.global_position = start
	plane.look_at(aim, Vector3.UP)
	plane.global_rotation = Vector3(0.0, plane.global_rotation.y, 0.0)
	plane.speed = 40.0
	# Let it register being airborne after the teleport, then set the dive.
	await get_tree().physics_frame
	await get_tree().physics_frame
	plane.global_position = start
	plane.pitch = -atan2(26.0, 140.0)
	var damage := func() -> float:
		var total := 0.0
		for piece in target.datacenter.find_children("*", "Destructible", true, false):
			var part := piece as Destructible
			total += part.max_health if part.is_destroyed else part.max_health - maxf(part.health, 0.0)
		return total
	var before: float = damage.call()
	plane.call("_on_exit_pressed")
	check(player.aircraft == null and player.parachuting, "bailing out pops a parachute")
	await seconds(0.5)
	check(player.parachuting and not player.is_on_floor() and player.velocity.y >= -3.6,
		"the canopy stays open on the way down (%.1f m/s)" % player.velocity.y)
	for i in 80:
		if plane.is_wrecked:
			break
		await seconds(0.1)
	check(plane.is_wrecked, "the empty plane flew on and crashed")
	await seconds(0.5)
	check(damage.call() > before + 300.0, "into the datacenter: big damage (%d)" % roundi(damage.call() - before))
	for i in 60:
		if not player.parachuting:
			break
		await seconds(0.25)
	check(not player.parachuting, "the pilot lands safely")


## [H] orders: send an ally to a cooling unit and they wreck it; everyone
## follows again on [3].
func _test_orders() -> void:
	var orders := level.get_node("AllyOrders") as AllyOrders
	var allies: Array[Canuck] = []
	for i in 2:
		var ally := Canuck.new()
		ally.setup(false)
		ally.position = player.global_position + Vector3(2.0 + i, 0.2, 0.0)
		level.add_child(ally)
		ally.join()
		allies.append(ally)
	await seconds(0.3)
	check(orders.squad().size() == 2, "the orders menu counts your allies (%d)" % orders.squad().size())
	var unit: Destructible = null
	for node in get_tree().get_nodes_in_group("cooling_units"):
		if (node as Destructible).site_id == &"forprofit":
			unit = node
			break
	player.global_position = unit.global_position + Vector3(0.0, 0.2, 30.0)
	for ally in allies:
		ally.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	var before := unit.health
	check(orders.issue(0, unit.global_position) == 1, "[1] sends one ally")
	check(allies.filter(func(a: Canuck) -> bool: return a.order_point != Vector3.INF).size() == 1, "only one ally left to do it")
	for i in 120:
		if unit.health < before:
			break
		await seconds(0.25)
	check(unit.health < before or unit.is_destroyed, "the ally went and hit the cooling unit (%d -> %d)" % [roundi(before), roundi(unit.health)])
	orders.issue(2, Vector3.ZERO)
	check(allies.all(func(a: Canuck) -> bool: return a.order_point == Vector3.INF), "[3] everyone follows again")
	for ally in allies:
		ally.queue_free()
	await seconds(0.2)


## A Failurecab roams its street; hacked, it drives itself into the nearest
## datacenter and blows up against it. Smashed Grock cameras slow the police.
func _test_failurecab() -> void:
	var cabs := get_tree().get_nodes_in_group("failurecabs")
	check(cabs.size() == 3, "Failurecabs roam the cross streets (%d)" % cabs.size())
	# Any of them rolling (one may be easing past a parked car).
	var starts := cabs.map(func(c: Node) -> Vector3: return (c as Node3D).global_position)
	var moved := func() -> bool:
		for k in cabs.size():
			if (cabs[k] as Node3D).global_position.distance_to(starts[k]) > 4.0:
				return true
		return false
	for i in 20:
		await seconds(0.5)
		if moved.call():
			break
	check(moved.call(), "Failurecabs drive their loops")
	var cab := level.get_node("Failurecab1") as Failurecab
	check(cab.is_alive(), "and nobody wrecks them")
	check(not cab.is_in_group("hostiles") and not cab.is_in_group("allies"), "roaming cabs are neutral traffic")
	var damage := func() -> float:
		var total := 0.0
		for node in get_tree().get_nodes_in_group("datacenter_sites"):
			for piece in (node as DatacenterSite).datacenter.find_children("*", "Destructible", true, false):
				total += (piece as Destructible).max_health - maxf((piece as Destructible).health, 0.0) if not (piece as Destructible).is_destroyed else (piece as Destructible).max_health
		return total
	var before: float = damage.call()
	# Hack it at the west end of the street, so it goes for Scgrewgle (the
	# later tests need Felsa standing).
	cab.global_position = Vector3(-100.0, 0.2, 29.5)
	cab.global_rotation.y = PI * 0.5
	await seconds(0.1)
	player.global_position = cab.global_position + Vector3(0.0, 0.2, 3.0)
	await seconds(0.05)
	check(cab.in_reach(player) and player.nearest_interactable() is Failurecab, "[E] reaches the Failurecab")
	cab.interact(player)
	check(cab.is_hacked and cab.faction == Enemy.Faction.ALLY and cab.is_in_group("allies"), "hacked: it's on your side")
	player.global_position = Vector3(-84, 0.2, 60)
	for i in 160:
		if not is_instance_valid(cab) or not cab.is_alive():
			break
		await seconds(0.25)
	check(not is_instance_valid(cab) or not cab.is_alive(), "the hacked cab reached a datacenter and blew up")
	await seconds(0.5)
	check(damage.call() > before + 100.0, "it wrecked part of the datacenter (%d damage)" % roundi(damage.call() - before))

	# Grock cameras: each one down adds to the police response time.
	var delay: float = level.call("police_delay")
	var camera := get_tree().get_first_node_in_group("grock_cameras") as Destructible
	if camera == null:
		for node in level.get_children():
			if node is GrockCamera:
				camera = node
				break
	camera.apply_damage(9999.0, camera.global_position + Vector3(0, 0, 2), &"melee")
	await seconds(0.2)
	check(is_equal_approx(level.call("police_delay"), delay + level.get("camera_police_delay")),
		"a smashed Grock camera slows the police (%ds -> %ds)" % [int(delay), int(level.call("police_delay"))])


func _test_gun_show() -> void:
	var tables := get_tree().get_nodes_in_group("gun_store")
	check(tables.size() >= 6, "Trey's Guns & Ammo lays out its stock (%d tables)" % tables.size())
	var mg: WeaponPickup = null
	for node in tables:
		if (node as WeaponPickup).gun_name == "Machine gun":
			mg = node
	check(not player.weapon_named("Machine gun").owned, "machine gun starts locked")
	player.select_weapon(player.weapons.find(player.weapon_named("Machine gun")))
	check(player.current_weapon().display_name != "Machine gun", "locked weapons are skipped")
	player.global_position = mg.global_position + Vector3(0.0, 0.2, 1.2)
	await seconds(0.1)
	check(player.nearest_interactable() == mg, "the machine gun table is in reach")
	Game.cash = 0
	mg.interact(player)
	check(player.weapon_named("Machine gun").owned and player.weapon_named("Machine gun").ammo == 150,
		"took the machine gun with no cash: it's free, fully loaded")
	check(Game.cash == 0, "nothing was charged")
	for node in tables:
		var pickup := node as WeaponPickup
		if pickup.gun_name == "Grenades":
			pickup.interact(player)
	check(player.weapon_named("Grenades").owned and player.weapon_named("Grenades").ammo == 3, "grenades too (3)")
	player.weapon_named("Machine gun").ammo = 10
	for node in tables:
		var pickup := node as WeaponPickup
		if pickup.kind == &"ammo":
			pickup.interact(player)
	check(player.weapon_named("Machine gun").ammo == 150, "the ammo crate tops everything up")


func _test_machine_gun() -> void:
	player.global_position = Vector3(-40, 0.2, 100)
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(0, 0, -12)) as SecurityGuard
	await seconds(0.1)
	player.select_weapon(player.weapons.find(player.weapon_named("Machine gun")))
	check(player.current_weapon().display_name == "Machine gun", "machine gun selected")
	for i in 16:  # spread is random: leave headroom for misses
		if not guard.is_alive():
			break
		player.aim_at(guard.aim_point())
		player.fire()
		await seconds(0.1)
	check(not guard.is_alive(), "machine gun cuts down a guard in under two seconds")


func _test_grenade() -> void:
	var center := Vector3(-30, 0.2, 100)
	var guards: Array[Enemy] = []
	for offset in [Vector3(0, 0, 0), Vector3(1.5, 0, 0), Vector3(0, 0, 1.5)]:
		guards.append(_dummy(SecurityGuard.new(), center + offset))
	var grenade := Throwable.new()
	grenade.kind = &"grenade"
	grenade.damage = 130.0
	level.add_child(grenade)
	grenade.global_position = center + Vector3(0.5, 0.5, 0.5)
	await seconds(0.5)
	check(guards.all(func(g: Enemy) -> bool: return g.is_alive()), "grenade waits for its fuse")
	await seconds(2.2)
	var dead := guards.filter(func(g: Enemy) -> bool: return not g.is_alive()).size()
	check(dead >= 2, "grenade clears a cluster (%d/3 down)" % dead)


func _test_rockets() -> void:
	var cache := level.get_node("SecurityCache") as SecurityCache
	player.global_position = cache.global_position + Vector3(1.0, 0.2, 0.0)
	await seconds(0.2)
	check(not cache.is_looted and player.nearest_interactable() == cache, "security cache waits for [E]")
	cache.interact(player)
	check(cache.is_looted and player.weapon_named("Rocket launcher").owned, "security cache gives the rocket launcher")
	check(player.weapon_named("Rocket launcher").ammo == 4, "with 4 rockets")

	# Fire at the Felsa datacenter's front wall (z = -33), beside the doorway.
	var datacenter := (level.get_node("FelsaSite") as DatacenterSite).datacenter
	var walls_before: int = datacenter.get("_structure").filter(func(p: Variant) -> bool: return is_instance_valid(p)).size()
	player.global_position = Vector3(6, 0.2, -23)
	await seconds(0.1)
	player.select_weapon(player.weapons.find(player.weapon_named("Rocket launcher")))
	player.aim_at(Vector3(7, 4.0, -33))
	player.fire()
	await seconds(1.0)
	var walls_after: int = datacenter.get("_structure").filter(func(p: Variant) -> bool:
		return is_instance_valid(p) and not (p as Destructible).is_destroyed).size()
	check(walls_after < walls_before, "a rocket blows out a datacenter wall segment (%d -> %d)" % [walls_before, walls_after])
	check(player.weapon_named("Rocket launcher").ammo == 3, "rocket spent")


func _test_bulldozer() -> void:
	var dozer := level.get_node("Bulldozer") as Car
	Game.district.trust = 0.2
	player.global_position = dozer.global_position + Vector3(2.5, 0, 0)
	await seconds(0.1)
	check(not dozer.enter(player), "bulldozer locked at low trust")
	Game.district.trust = 0.5
	check(dozer.enter(player), "the foreman hands over the keys at 50% trust")
	await seconds(0.2)
	dozer.exit()
	await seconds(0.2)

	# Ram the Felsa datacenter's front wall from inside the fence.
	var datacenter := (level.get_node("FelsaSite") as DatacenterSite).datacenter
	var intact := func() -> int:
		return datacenter.get("_structure").filter(func(p: Variant) -> bool:
			return is_instance_valid(p) and not (p as Destructible).is_destroyed).size()
	var before: int = intact.call()
	dozer.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-8, 0.5, -26))
	dozer.brake = 0.0  # exit() parks it with the brake on
	dozer.linear_velocity = Vector3(0, 0, -8)
	# It lands and scrubs speed before the wall: 6 m/s sometimes arrived at ~3.4 m/s,
	# right at the wall's damage threshold, so give it a real run-up.
	for i in 16:
		await seconds(0.25)
		if intact.call() < before:
			break
	check(intact.call() < before, "bulldozer smashes through a datacenter wall (%d -> %d)" % [before, intact.call()])


## The fire truck (keys for the hydrant), the garbage truck (keys for the
## litter), and the road roller (trust).
func _test_heavy_equipment() -> void:
	var fire := level.get_node("FireTruck") as FireTruck
	var garbage := level.get_node("GarbageTruck") as Car
	var roller := level.get_node("RoadRoller") as RoadRoller
	check(not fire.can_enter() and "hydrant" in fire.lock_text(), "the fire truck is locked until the hydrant is capped")
	check(not garbage.can_enter() and "litter" in garbage.lock_text(), "the garbage truck is locked until the litter is gone")
	(level.get_node("WaterMain") as WaterMain).fixed.emit(level.get_node("WaterMain"))
	check(fire.can_enter(), "capping the hydrant hands over the fire truck")
	for piece in get_tree().get_nodes_in_group("litter"):
		player.global_position = (piece as Node3D).global_position + Vector3.UP * 0.2
		await seconds(0.05)
	await seconds(0.1)
	check(garbage.can_enter(), "clearing the litter hands over the garbage truck")

	# The roof cannon knocks a guard flat and puts out a fire, 12 m ahead.
	fire.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-84, 0.8, 70))
	fire.linear_velocity = Vector3.ZERO
	await seconds(0.8)
	var ahead := fire.global_position + fire.global_basis.z * 12.0
	var guard := SecurityGuard.new()
	guard.position = Vector3(ahead.x, 0.1, ahead.z)
	level.add_child(guard)
	var blaze := FireZone.new()
	level.add_child(blaze)
	blaze.global_position = Vector3(ahead.x + 2.0, 0.0, ahead.z + 2.0)
	await seconds(0.3)
	var start := guard.global_position
	for i in 15:
		fire.fire_cannon()
		await seconds(0.1)
	check(guard.global_position.distance_to(start) > 1.5 and guard.soaked_left > 0.0,
		"the fire truck's cannon blasts a guard back (%.1f m)" % guard.global_position.distance_to(start))
	check(not is_instance_valid(blaze), "the cannon puts out a fire")
	guard.queue_free()

	# The roller flattens a guard at walking pace.
	Game.district.trust = maxf(Game.district.trust, roller.required_trust)
	check(roller.can_enter(), "the road roller opens up with enough trust")
	roller.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-84, 0.8, 40))
	roller.linear_velocity = Vector3.ZERO
	await seconds(0.6)
	player.global_position = roller.global_position + Vector3(2.5, 0.2, 0.0)
	await seconds(0.1)
	roller.enter(player)
	var victim := SecurityGuard.new()
	victim.position = roller.global_position + roller.global_basis.z * 5.0 + Vector3(0, -0.7, 0)
	level.add_child(victim)
	victim.set_physics_process(false)
	Input.action_press("move_forward")
	for i in 60:
		await seconds(0.1)
		if not victim.is_alive():
			break
	Input.action_release("move_forward")
	check(not victim.is_alive(), "the road roller flattens a guard at walking pace (%.1f m/s)" % roller.linear_velocity.length())
	roller.exit()

