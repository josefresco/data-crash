extends TestCase
## Player arsenal: shotgun, rifle, ammo, molotov fire, rock lure, knockback.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/weapons_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(0.5)
	check(player.current_weapon().display_name == "Fists" and player.held_model() == null, "the player starts unarmed")
	check(player.weapons.filter(func(w: Weapon) -> bool: return w.owned).size() == 1, "only fists are owned at the start")
	player.arm_all()
	# The open field west of the neighborhood, away from houses and guards.
	player.global_position = Vector3(-84, 0.2, 70)
	await seconds(0.3)

	await _test_shotgun()
	await _test_rifle_and_ammo()
	await _test_molotov()
	await _test_rock_lure()
	await _test_knockback()
	await _test_shovel()
	await _test_held_models()


func _select(weapon_name: String) -> void:
	player.select_weapon(player.weapons.find(player.weapon_named(weapon_name)))


func _test_shovel() -> void:
	player.global_position = Vector3(-84, 0.2, 40)
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(0, 0, -1.6)) as SecurityGuard
	await seconds(0.1)
	_select("Shovel")
	player.aim_at(guard.aim_point())
	for i in 3:
		player.fire()
		await seconds(0.75)
	check(not guard.is_alive(), "three shovel swings drop a guard (%.0f hp)" % guard.health)


func _test_held_models() -> void:
	player.global_position = Vector3(-84, 0.2, 50)
	await seconds(0.2)
	for weapon_name in ["Pistol", "Machine gun", "Shovel", "Rocket launcher"]:
		_select(weapon_name)
		await seconds(0.1)
		check(player.held_model() != null, "%s is visible in the player's hands" % weapon_name)
	_select("Pistol")
	player.aim_at(player.global_position + Vector3(0, 1.5, -20))
	player.fire()
	await seconds(0.1)
	var muzzle := player.muzzle_point()
	check(muzzle.distance_to(player.global_position + Vector3.UP * 1.4) < 1.2 and muzzle != player.global_position + Vector3.UP * 1.4,
		"shots leave from the pistol's muzzle (%s)" % (muzzle - player.global_position))


func _dummy(unit: Enemy, at: Vector3, frozen := true) -> Enemy:
	unit.position = at
	level.add_child(unit)
	if frozen:
		unit.set_physics_process(false)
	return unit


func _test_shotgun() -> void:
	var dog := _dummy(Dog.new(), player.global_position + Vector3(0, 0, -6)) as Dog
	await seconds(0.1)
	_select("Shotgun")
	check(player.current_weapon().display_name == "Shotgun", "switched to shotgun")
	for blast in 3:  # pellet spread is random: one spare blast
		if not dog.is_alive():
			break
		player.aim_at(dog.aim_point())
		player.fire()
		await seconds(0.9)
	check(not dog.is_alive(), "shotgun drops a dog at 6m within three blasts (hp %.0f)" % dog.health)


func _test_rifle_and_ammo() -> void:
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(4, 0, -30)) as SecurityGuard
	await seconds(0.1)
	_select("Hunting rifle")
	var rifle := player.current_weapon()
	var ammo := rifle.ammo
	player.aim_at(guard.aim_point())
	player.fire()
	await seconds(0.1)
	check(not guard.is_alive(), "hunting rifle one-shots a guard at 30m")
	check(rifle.ammo == ammo - 1, "rifle used one round (%d left)" % rifle.ammo)
	rifle.ammo = 0
	var guard2 := _dummy(SecurityGuard.new(), player.global_position + Vector3(-4, 0, -20)) as SecurityGuard
	await seconds(0.1)
	player.aim_at(guard2.aim_point())
	player.fire()
	await seconds(0.1)
	check(is_equal_approx(guard2.health, guard2.max_health), "empty rifle doesn't fire")
	player.refill_ammo()
	check(rifle.ammo == rifle.max_ammo, "refill restores ammo")
	guard2.apply_damage(9999.0, Vector3.ZERO)


func _test_molotov() -> void:
	_select("Molotov")
	check(player.current_weapon().display_name == "Molotov", "switched to molotov")
	var ground := player.global_position + Vector3(0, 0, -8)
	player.aim_at(ground)
	player.fire()
	var landed := false
	for i in 20:
		await seconds(0.1)
		if not get_tree().get_nodes_in_group("fire_zones").is_empty():
			landed = true
			break
	check(landed, "thrown molotov starts a fire")

	# Fire hurts hostiles and scatters protesters without harming them.
	var fire := FireZone.new()
	level.add_child(fire)
	fire.global_position = player.global_position + Vector3(12, -0.2, -12)
	var guard := _dummy(SecurityGuard.new(), fire.global_position + Vector3(1, 0.2, 0)) as SecurityGuard
	var protester := _dummy(OrangeHat.new(), fire.global_position + Vector3(-1, 0.2, 0), false) as OrangeHat
	await seconds(1.5)
	check(guard.health < guard.max_health, "fire burns a guard (%.0f hp)" % guard.health)
	check(protester.persuaded and is_equal_approx(protester.health, protester.max_health),
		"fire scatters a protester unharmed")
	guard.apply_damage(9999.0, Vector3.ZERO)


func _test_rock_lure() -> void:
	var guard := _dummy(SecurityGuard.new(), Vector3(-45, 0.1, 10), false) as SecurityGuard
	await seconds(0.5)
	var start := guard.global_position
	var lure_point := start + Vector3(8, 0, 0)
	var rock := Throwable.new()
	rock.kind = &"rock"
	level.add_child(rock)
	rock.global_position = lure_point + Vector3.UP
	rock.call("_impact", null)
	await seconds(3.0)
	check(guard.global_position.distance_to(lure_point) < start.distance_to(lure_point) - 3.0,
		"rock lures a guard toward the noise")
	guard.apply_damage(9999.0, Vector3.ZERO)


func _test_knockback() -> void:
	var start := player.global_position
	player.apply_knockback(Vector3(15, 4, 0))
	await seconds(0.4)
	check(player.global_position.x > start.x + 2.0, "knockback shoves the player")
