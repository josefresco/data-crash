extends TestCase
## The four remaining bosses: Crapya Butella (inside Scgrewgle: control room,
## water cannons, vents), Sham Crapman (inside ForProfitSI; tested in the
## field here), Fark Suckerbush (wave 4), Harry Perckerson (wave 5).
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/bosses_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")
const FIELD := Vector3(-84, 0.2, 60)  # open strip west of the houses

var level: Node3D
var player: Player
var scgrewgle: DatacenterSite


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(0.5)
	var felsa := level.get_node("FelsaSite") as DatacenterSite
	check(felsa.elmo != null and felsa.elmo_truck != null and felsa.elmo_truck.parked,
		"Elmo waits inside Felsa with his Cyberdouche parked at the dock")
	# Clear the regular site security and traffic (keep bosses and the water cannons).
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if (unit is SecurityGuard and not unit is SentryTurret) or unit is Dog or (unit is FelsaCar and not unit is ElmoTruck):
			unit.apply_damage(9999.0, Vector3.ZERO)
	for name in ["StrayDog1", "StrayDog2"]:
		(level.get_node(name) as Enemy).apply_damage(9999.0, Vector3.ZERO)
	scgrewgle = level.get_node("ScgrewgleSite") as DatacenterSite
	await seconds(1.0)

	_test_init_order()
	await _test_crapya()
	await _test_sham()
	await _test_fark()
	await _test_harry()
	_test_boss_waves()


func _spawn(unit: Enemy, at: Vector3) -> Enemy:
	unit.position = at
	level.add_child(unit)
	return unit


func _test_init_order() -> void:
	var truck := ElmoTruck.new()
	check(is_equal_approx(truck.max_health, 1200.0) and is_equal_approx(truck.top_speed, 13.0),
		"subclass _init overrides parent defaults (truck %.0f hp)" % truck.max_health)
	truck.free()


func _test_crapya() -> void:
	var room := scgrewgle.crapya_room
	var units := scgrewgle.datacenter.get_children().filter(func(n: Node) -> bool: return n.is_in_group("cooling_units"))
	var unit := units[0] as Destructible
	check(room != null and scgrewgle.datacenter.is_ancestor_of(unit), "Crapya's control room is inside Scgrewgle")
	check(unit.damage_threshold > 1.0e6, "control room shields the cooling units")
	var felsa_unit := (level.get_node("FelsaSite") as DatacenterSite).datacenter.get_children().filter(
		func(n: Node) -> bool: return n.is_in_group("cooling_units"))[0] as Destructible
	check(felsa_unit.damage_threshold < 1.0e6, "but not Felsa's")
	unit.apply_damage(500.0, unit.global_position, &"explosive")
	check(is_equal_approx(unit.health, unit.max_health), "shielded cooling unit ignores C4-level damage")

	# Roof water cannons soak the yard once the alarm is up.
	level.call("raise_alarm", &"scgrewgle", "test")
	player.global_position = scgrewgle.to_global(Vector3(6.0, 0.2, 18.0))
	var hit := [false]
	var on_hit := func(_h: float, _m: float) -> void: hit[0] = true
	player.health_changed.connect(on_hit)
	for i in 24:
		if hit[0]:
			break
		await seconds(0.25)
	check(hit[0], "roof water cannons soak the player")
	for name in ["SentryNE", "SentryNW"]:
		(scgrewgle.get_node(name) as Enemy).apply_damage(9999.0, Vector3.ZERO)

	# Steam vent and rack crusher hurt whoever stands on them.
	for name in ["SteamVent1", "RackCrusher1"]:
		var trap := scgrewgle.get_node(name) as SteamVent
		player.global_position = trap.global_position + Vector3(0, 0.2, 0)
		hit[0] = false
		for i in 32:
			if hit[0]:
				break
			await seconds(0.25)
		check(hit[0], "%s hurts the player" % name)
	player.health_changed.disconnect(on_hit)
	player.global_position = FIELD

	var hp := room.health
	room.apply_damage(15.0, room.global_position + Vector3(0, 1, 5), &"bullet")
	check(is_equal_approx(room.health, hp), "pistol rounds bounce off the control room glass")
	room.apply_damage(70.0, room.global_position + Vector3(0, 1, 5), &"bullet")
	check(room.health < hp, "a rifle round cracks it")
	var cash := Game.cash
	room.apply_damage(9999.0, room.global_position + Vector3(0, 1, 5), &"explosive")
	await seconds(0.3)
	check(is_equal_approx(unit.damage_threshold, 50.0) and not unit.has_meta(CrapyaControlRoom.SHIELD_META),
		"control room down: cooling units exposed")
	check((scgrewgle.get_node("SteamVent1") as SteamVent).state == SteamVent.State.OFF, "steam vents shut down")
	check(scgrewgle.boss_defeated, "Scgrewgle's boss is down")
	check(Game.cash == cash + 300, "Crapya pays out $300")


func _test_sham() -> void:
	var sham := _spawn(ShamCrapman.new(), FIELD + Vector3(0, 0, -20)) as ShamCrapman
	sham.set("sight_range", 0.0)  # keep him busy standing still
	await seconds(0.5)
	check(sham.drones.size() == 3 and sham.alive_pylons() == 2, "Sham deploys 3 drones and 2 pylons")
	var hp := sham.health
	sham.apply_damage(100.0, FIELD, &"bullet")
	check(hp - sham.health < 50.0, "force field blocks most damage (%.0f)" % (hp - sham.health))
	for drone in sham.drones:
		drone.apply_damage(9999.0, FIELD)
	await seconds(0.5)
	hp = sham.health
	sham.apply_damage(100.0, FIELD, &"bullet")
	check(is_equal_approx(hp - sham.health, 100.0), "drones down: full damage (%.1f, shielded=%s, drones alive=%d)" % [
		hp - sham.health, sham.is_field_shielded(), sham.drones.filter(func(d: Variant) -> bool:
			return is_instance_valid(d) and (d as Enemy).is_alive()).size()])

	player.health = player.max_health
	var before := player.health
	sham.call("_attack", player)
	var pylon_hit := before - player.health
	for pylon in sham.pylons:
		pylon.apply_damage(9999.0, pylon.global_position)
	await seconds(0.2)
	player.health = player.max_health
	before = player.health
	sham.call("_attack", player)
	check(pylon_hit > before - player.health, "pylons power his blasts (%.0f vs %.0f)" % [pylon_hit, before - player.health])
	player.health = player.max_health
	sham.apply_damage(99999.0, FIELD, &"explosive")
	await seconds(0.3)
	check(not sham.is_alive(), "Sham Crapman defeated")


func _test_fark() -> void:
	player.global_position = FIELD
	var fark := _spawn(FarkPod.new(), FIELD + Vector3(0, 0, -18)) as FarkPod
	fark.set("_clone_left", 0.5)
	for i in 12:
		if fark.is_tracking():
			break
		await seconds(0.25)
	check(fark.drones.size() == 2 and fark.is_tracking(), "surveillance drones track the player")
	await seconds(0.6)
	check(fark.clones.size() == 3, "Fark summons 3 holographic clones")
	check(is_equal_approx(fark.clones[0].max_health, 1.0), "clones pop in one hit")
	var hp := fark.health
	fark.apply_damage(100.0, FIELD, &"bullet")
	check(is_equal_approx(hp - fark.health, 50.0), "pod glass halves bullets")
	fark.set("_reeducate_left", 0.0)
	for i in 16:
		if player.controls_reversed():
			break
		await seconds(0.25)
	check(player.controls_reversed(), "Algorithm Re-education reverses the controls")
	fark.apply_damage(99999.0, FIELD, &"explosive")
	await seconds(0.5)
	check(fark.clones.all(func(c: Variant) -> bool: return not is_instance_valid(c) or not (c as Enemy).is_alive()),
		"his clones vanish with him")
	player.set("_reversed_left", 0.0)


func _test_harry() -> void:
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	spawner.call("_spawn", HarryPerckerson)
	await seconds(0.3)
	var harry: HarryPerckerson = null
	for node in get_tree().get_nodes_in_group("bosses"):
		if node is HarryPerckerson:
			harry = node
	check(harry != null, "Harry arrives")
	if harry == null:
		return
	var site := (spawner.get_node("BoardroomSite") as Node3D).global_position
	check(Vector2(harry.global_position.x - site.x, harry.global_position.z - site.z).length() < 0.5,
		"Harry sets up at the BoardroomSite marker")
	harry.apply_damage(500.0, site, &"bullet")
	check(is_equal_approx(harry.health, harry.max_health), "untouchable behind the glass")
	var glass := harry.boardroom
	glass.apply_damage(60.0, site + Vector3(0, 1, -6), &"bullet")
	check(is_equal_approx(glass.health, glass.max_health), "glass shrugs off small arms")
	for i in 4:
		glass.apply_damage(260.0, site + Vector3(0, 1, -6), &"explosive")
	await seconds(0.3)
	check(harry.is_exposed(), "four rockets shatter the boardroom glass")
	harry.set("_subsidy_left", 0.0)
	await seconds(0.3)
	check(harry.summoned.size() >= 2, "Capital Subsidies summon guards (%d)" % harry.summoned.size())
	harry.apply_damage(99999.0, site, &"explosive")
	await seconds(0.3)
	check(not harry.is_alive(), "Harry Perckerson defeated")


func _test_boss_waves() -> void:
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	check(not spawner.waves[1].has("sham") and spawner.waves[3].has("fark") and spawner.waves[4].has("harry"),
		"Fark and Harry lead waves 4 and 5; Sham lives in ForProfitSI now")
	var forprofit := level.get_node("ForProfitSite") as DatacenterSite
	check(forprofit.sham != null and forprofit.datacenter.global_position.distance_to(forprofit.sham.global_position) < 15.0,
		"Sham waits inside the ForProfitSI datacenter")

