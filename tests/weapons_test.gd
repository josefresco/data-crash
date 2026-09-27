extends TestCase
## Player arsenal: shotgun, rifle, ammo, molotov fire, rock lure, knockback,
## hoses (push, stun, scatter, put out fires), and the recon drone (flight,
## spotting, FPV dive, recall).
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
	await _test_hit_feedback()
	await _test_wounds()
	await _test_hoses()
	await _test_drone()
	await _test_drone_recon()


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


func _test_wounds() -> void:
	player.heal(9999.0)
	var model := player.get("_rig") as CharacterModel
	check(model.wound_count() == 0, "a healthy player shows no wounds")
	player.apply_damage(40.0, player.global_position + Vector3(4, 1, 0), &"bullet")
	await seconds(0.1)
	var hurt := model.wound_count()
	check(hurt >= 2, "getting shot leaves wounds on the model (%d)" % hurt)
	player.heal(25.0)
	check(model.wound_count() < hurt, "healing closes wounds (%d -> %d)" % [hurt, model.wound_count()])
	player.heal(9999.0)
	check(model.wound_count() == 0, "full health, no wounds")
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(0, 0, -5)) as SecurityGuard
	await seconds(0.1)
	guard.apply_damage(20.0, player.global_position, &"bullet")
	check((guard.get("_rig") as CharacterModel).wound_count() == 1, "a shot guard shows the wound")
	guard.queue_free()


## Sprays the current hose at `point` for `ticks` spray ticks (0.1 s each).
func _spray_at(point: Vector3, ticks: int) -> void:
	for i in ticks:
		player.aim_at(point)
		player.fire()
		await seconds(0.1)


func _test_hoses() -> void:
	player.global_position = Vector3(-84, 0.2, 60)
	player.heal(9999.0)
	await seconds(0.2)
	_select("Garden hose")
	await seconds(0.1)
	check(player.held_model() != null, "the garden hose nozzle is in hand")
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(0, 0, -6), false) as SecurityGuard
	guard.uses_cover = false
	await seconds(0.3)
	var before := guard.global_position.distance_to(player.global_position)
	await _spray_at(guard.aim_point(), 15)
	var jet := player.get("_jet") as GPUParticles3D
	check(jet != null and jet.emitting, "water streams from the nozzle while spraying")
	var pushed := guard.global_position.distance_to(player.global_position) - before
	check(pushed > 2.0, "the garden hose pushes a guard back (%.1f m)" % pushed)
	check(guard.health < guard.max_health and guard.health > guard.max_health * 0.8,
		"garden hose water barely hurts (%.0f of %.0f)" % [guard.health, guard.max_health])
	check(guard.soaked_left > 0.0, "a hosed guard is soaked (slowed)")
	await seconds(0.4)
	check(not jet.emitting, "the water stops when you let go")

	_select("Fire hose")
	player.heal(9999.0)
	guard.global_position = player.global_position + Vector3(0, 0, -5)
	await seconds(0.2)
	await _spray_at(guard.aim_point(), 2)
	check(guard.get("_stun_timer") as float > 0.0, "the fire hose knocks a guard off his feet up close")
	guard.apply_damage(9999.0, Vector3.ZERO)

	var hat := _dummy(OrangeHat.new(), player.global_position + Vector3(2, 0, -6), false) as OrangeHat
	await seconds(0.2)
	await _spray_at(hat.aim_point(), 3)
	check(hat.persuaded and hat.health == hat.max_health, "a hosed protester scatters, unharmed")
	hat.queue_free()

	var fire := FireZone.new()
	level.add_child(fire)
	fire.global_position = player.global_position + Vector3(0, 0, -7)
	await seconds(0.2)
	await _spray_at(fire.global_position, 10)
	check(not is_instance_valid(fire), "the fire hose puts out a molotov fire")

	var car := level.get_node("Car") as Car
	car.global_transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(4, 0.6, -7))
	car.linear_velocity = Vector3.ZERO
	await seconds(0.5)
	car.apply_damage(car.max_health * 0.9, car.global_position, &"bullet")
	check(car.is_burning(), "a badly shot-up car catches fire")
	await _spray_at(car.global_position + Vector3.UP, 5)
	check(not car.is_burning() and not car.wrecked, "the fire hose puts out a burning car before it blows")


func _test_drone() -> void:
	player.global_position = Vector3(-84, 0.2, 85)
	player.heal(9999.0)
	await seconds(0.2)
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(0, 0, -24)) as SecurityGuard
	_select("Recon drone")
	var kit := player.current_weapon()
	check(kit.display_name == "Recon drone" and kit.ammo == 2, "the drone kit comes with two FPV payloads")
	player.fire()
	await seconds(0.1)
	var drone := player.drone
	check(drone != null and get_viewport().get_camera_3d().get_parent().get_parent() == drone,
		"firing the kit launches the drone and switches to its camera")
	if drone == null:
		return
	drone.set_heading(0.0)  # facing -Z, toward the guard
	var start := drone.global_position
	Input.action_press("move_forward")
	await seconds(1.0)
	Input.action_release("move_forward")
	check(start.z - drone.global_position.z > 5.0, "WASD flies the drone (%.1f m)" % (start.z - drone.global_position.z))
	await seconds(0.5)
	check(guard.spotted_left > 0.0 and drone.spotted_count >= 1, "the drone spots a guard in view")
	var hud := level.get_node("Hud") as Hud
	await seconds(0.3)
	check(guard in hud.overlay().spotted_units(), "the HUD marks the spotted guard")
	check(player.velocity.length() < 0.5, "the player stands still while piloting")

	# FPV dive: point it at the guard and click.
	var to := guard.aim_point() - drone.global_position
	drone.set("_pitch", asin(clampf(to.normalized().y, -1.0, 1.0)))
	drone.set_heading(atan2(-to.x, -to.z))
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	for i in 40:
		if not is_instance_valid(drone):
			break
		await seconds(0.1)
	check(not is_instance_valid(drone), "the FPV dive ends the flight")
	check(not guard.is_alive() or guard.health < guard.max_health * 0.5,
		"the FPV dive blows up on the guard (%.0f hp left)" % maxf(guard.health, 0.0))
	check(kit.ammo == 1, "the dive used one payload (%d left)" % kit.ammo)
	check(player.drone == null and get_viewport().get_camera_3d() == player.get("_camera"), "the view returns to the player")
	check(player.drone_cooldown() > 0.0 and player.launch_drone() == null, "the next drone needs a moment")

	player.set("_drone_cooldown", 0.0)
	check(player.launch_drone() != null, "a new drone goes up after the cooldown")
	await seconds(0.3)
	player.apply_damage(5.0, player.global_position + Vector3(5, 0, 0), &"bullet")
	await seconds(0.1)
	check(player.drone == null, "getting hurt calls the drone back")
	player.set("_drone_cooldown", 0.0)
	var target_drone := player.launch_drone()
	await seconds(0.2)
	target_drone.apply_damage(100.0, Vector3.ZERO, &"bullet")
	await seconds(0.1)
	check(player.drone == null and player.drone_cooldown() > 15.0, "a drone shot down takes a while to replace")
	if is_instance_valid(guard):
		guard.queue_free()
	_select("Pistol")


## Drone over the quiet Felsa compound: first sightings of site security pay,
## and spotting most of it completes a recon that marks the cooling units.
func _test_drone_recon() -> void:
	player.global_position = Vector3(-6, 0.2, 2)
	player.heal(9999.0)
	player.set("_drone_cooldown", 0.0)
	await seconds(0.3)
	check(not Game.is_alarmed(&"felsa"), "Felsa is still quiet")
	var cash := Game.cash
	var drone := player.launch_drone()
	drone.global_position = Vector3(0, 38, -42)  # over the middle of the compound
	drone.set("_pitch", -1.2)
	for i in 16:
		drone.set_heading(TAU * i / 16.0)
		drone.battery_left = drone.battery
		await seconds(0.3)
		if ReconDrone.recon_done(&"felsa"):
			break
	check(Game.cash > cash, "spotting quiet site security pays (+$%d)" % (Game.cash - cash))
	check(ReconDrone.recon_done(&"felsa"), "circling over Felsa completes its recon")
	var marked := get_tree().get_nodes_in_group("cooling_units").filter(func(u: Node) -> bool:
		return (u as Destructible).site_id == &"felsa" and u.has_meta(&"marked")).size()
	check(marked >= 3, "the recon marks Felsa's cooling units (%d)" % marked)
	check(not Game.is_alarmed(&"felsa"), "the recon doesn't tip them off")
	if is_instance_valid(drone):
		drone.recall()
	await seconds(0.2)


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


## Landing a shot confirms the hit (the HUD's marker), and guns kick.
func _test_hit_feedback() -> void:
	player.global_position = Vector3(-84, 0.2, 30)
	var guard := _dummy(SecurityGuard.new(), player.global_position + Vector3(0, 0, -8)) as SecurityGuard
	await seconds(0.1)
	_select("Pistol")
	var hits := []
	player.hit_confirmed.connect(func(killed: bool) -> void: hits.append(killed))
	player.aim_at(guard.aim_point())
	var pitch: float = player.get("_pitch")
	player.fire()
	check(hits.size() == 1 and hits[0] == false, "a pistol hit confirms on the crosshair")
	check(float(player.get("_pitch")) > pitch, "the pistol kicks the aim up")
	guard.apply_damage(9999.0, Vector3.ZERO)
