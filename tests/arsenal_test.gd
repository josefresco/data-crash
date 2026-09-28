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

