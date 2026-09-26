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


func _dummy(unit: Enemy, at: Vector3) -> Enemy:
	unit.position = at
	level.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _test_gun_show() -> void:
	var stall := level.get_node("GunShow") as GunShow
	player.global_position = stall.global_position + Vector3(2.0, 0.2, 0.0)
	await seconds(0.1)
	check(player.nearest_interactable() == stall, "gun show in reach")
	check(not player.weapon_named("Machine gun").owned, "machine gun starts locked")
	player.select_weapon(player.weapons.find(player.weapon_named("Machine gun")))
	check(player.current_weapon().display_name != "Machine gun", "locked weapons are skipped")
	Game.cash = 100
	check(not stall.buy_item(3, player), "can't afford the machine gun with $100")
	Game.cash = 1000
	check(stall.buy_item(3, player), "bought the machine gun")
	check(player.weapon_named("Machine gun").owned, "machine gun unlocked")
	check(not stall.buy_item(3, player), "guns sell once")
	check(stall.buy_item(4, player) and player.weapon_named("Grenades").ammo == 3, "then grenade packs (3)")
	check(Game.cash == 1000 - 450 - 150, "gun show took $600 ($%d)" % Game.cash)
	stall.interact(player)
	check(stall.is_open, "[E] opens the gun show table")
	stall.interact(player)


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

	# Fire at the middle of the datacenter's front wall (z = -24).
	var datacenter := level.get_node("Datacenter") as Datacenter
	var walls_before: int = datacenter.get("_structure").filter(func(p: Variant) -> bool: return is_instance_valid(p)).size()
	player.global_position = Vector3(3, 0.2, -14)
	await seconds(0.1)
	player.select_weapon(player.weapons.find(player.weapon_named("Rocket launcher")))
	player.aim_at(Vector3(2, 4.0, -24))
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

	# Ram the datacenter's front wall from inside the fence.
	var datacenter := level.get_node("Datacenter") as Datacenter
	var intact := func() -> int:
		return datacenter.get("_structure").filter(func(p: Variant) -> bool:
			return is_instance_valid(p) and not (p as Destructible).is_destroyed).size()
	var before: int = intact.call()
	dozer.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-6, 0.9, -17))
	dozer.brake = 0.0  # exit() parks it with the brake on
	dozer.linear_velocity = Vector3(0, 0, -6)
	await seconds(1.5)
	check(intact.call() < before, "bulldozer smashes through a datacenter wall (%d -> %d)" % [before, intact.call()])
