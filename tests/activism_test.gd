extends TestCase
## Phase 1 good deeds, noise-scaled trust, the town (walk-in shops, the
## hospital's bill, storefronts and their regulars), the fence breach into
## Phase 2, all three bribes, and free care once the green datacenter is up.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/activism_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(0.5)
	check(level.phase == level.Phase.ACTIVISM, "level starts in Phase 1")

	await _test_town()
	await _test_deeds()
	await _test_breach_ends_activism()
	await _test_bribes()
	await _test_free_hospital()


func _test_deeds() -> void:
	var van_start := (level.get_node("SupplyVan") as SupplyVan).global_position
	await seconds(2.0)
	check((level.get_node("SupplyVan") as SupplyVan).global_position.distance_to(van_start) > 5.0, "supply van drives its route")
	var cash := Game.cash
	var trust := Game.district.trust

	# Water main: hold [F] next to it.
	var main := level.get_node("WaterMain") as WaterMain
	player.global_position = main.global_position + Vector3(1.5, 0.2, 0)
	await seconds(0.1)
	check(player.fixable_target() == main, "water main is in reach")
	for i in 30:
		player.call("_repair", 0.1)
	check(main.is_fixed, "holding F fixes the water main")
	check(Game.cash == cash + 100, "water main pays $100")
	# Trust is scaled down by the datacenter's noise (1.0 at the start = half).
	check(is_equal_approx(Game.district.trust, trust + 0.1 * 0.5),
		"noise halves the trust reward (%.3f)" % (Game.district.trust - trust))

	# Scout: climb each perch ([E] at the ladder), raise the binoculars, hold
	# the reticle on each cooling unit to spot it, climb down.
	var perches := get_tree().get_nodes_in_group("scout_points")
	check(perches.size() == 3, "one scout perch per datacenter (%d)" % perches.size())
	for node in perches:
		var perch := node as ScoutPoint
		player.global_position = perch.base_spot() + Vector3(0, 0.2, 0)
		await seconds(0.2)
		check(perch.in_reach(player), "the %s ladder is in reach" % perch.site_id)
		perch.interact(player)
		await seconds(0.2)
		check(perch.on_perch(player), "[E] climbs up onto the %s perch" % perch.site_id)
		await seconds(1.0)
		check(not perch.is_scouted, "just standing up there doesn't scout %s" % perch.site_id)
		player.binoculars_up = true
		await seconds(0.4)
		check(player.optic == &"binoculars", "[Z] raises the binoculars (first person)")
		for unit in get_tree().get_nodes_in_group("cooling_units"):
			if StringName(unit.get_meta(&"scout_site", &"")) != perch.site_id:
				continue
			for i in 12:
				if Spotting.is_spotted(unit):
					break
				player.aim_at(Spotting.aim_point(unit as Node3D) + Vector3.UP * 0.4 * (i % 3))
				await seconds(0.25)
			check(Spotting.is_spotted(unit), "spotted %s at %s" % [unit.name, perch.site_id])
		player.binoculars_up = false
		await seconds(0.2)
		perch.interact(player)
		await seconds(0.2)
	var scouted := perches.filter(func(n: Node) -> bool: return (n as ScoutPoint).is_scouted).size()
	check(scouted == 3, "spotting every cooling unit scouts each datacenter (%d/3)" % scouted)
	check(get_tree().get_nodes_in_group("spotted_targets").size() >= 9, "spotted pieces are map targets")
	check(not (perches[0] as ScoutPoint).on_perch(player), "[E] climbs back down")
	var marked := 0
	for unit in get_tree().get_nodes_in_group("cooling_units"):
		for child in unit.get_children():
			if child is Label3D:
				marked += 1
	check(marked == 9, "scouting marks every cooling unit at all three sites (%d)" % marked)

	# Strays: treats. Approach each from the side away from the other one:
	# they wander, and a treat goes to the nearest dog.
	var strays: Array[Dog] = [level.get_node("StrayDog1") as Dog, level.get_node("StrayDog2") as Dog]
	for i in 2:
		var dog := strays[i]
		var away := dog.global_position - strays[1 - i].global_position
		away.y = 0.0
		player.global_position = dog.global_position + away.normalized() * 1.5 + Vector3.UP * 0.2
		await seconds(0.1)
		check(player.give_treat() and dog.faction == Enemy.Faction.ALLY, "treat for %s" % dog.name)

	# Grandmas: offer an arm, walk to the ring, she follows.
	for lady: OldLady in get_tree().get_nodes_in_group("neighbors").duplicate():
		player.global_position = lady.global_position + Vector3(1.0, 0.2, 0)
		await seconds(0.1)
		check(player.nearest_interactable() == lady, "[E] reaches the grandma")
		lady.interact(player)
		player.global_position = lady.destination + (lady.destination - lady.home).normalized() * 1.0 + Vector3.UP * 0.2
		for i in 60:
			if lady.state == OldLady.State.CROSSED:
				break
			await seconds(0.25)
		check(lady.state == OldLady.State.CROSSED, "grandma made it across")

	# Paint job: hold F in the ring.
	var job := level.get_node("PaintJob") as PaintJob
	player.global_position = job.global_position + Vector3(0, 0.2, 0)
	await seconds(0.1)
	check(player.fixable_target() == job, "paint job is in reach")
	for i in 70:
		player.call("_repair", 0.1)
	check(job.is_fixed, "holding F repaints the house")

	# Litter: walk over every piece.
	var pieces := get_tree().get_nodes_in_group("litter")
	check(pieces.size() >= 10, "litter around the block (%d)" % pieces.size())
	for piece: Litter in pieces:
		player.global_position = piece.global_position + Vector3.UP * 0.2
		await seconds(0.05)
	await seconds(0.1)
	check(get_tree().get_nodes_in_group("litter").is_empty(), "walking over litter picks it all up")

	# Potholes: hold F at each; a car over an open one takes a jolt first.
	var holes := get_tree().get_nodes_in_group("potholes")
	check(holes.size() == 8, "potholes on the roads (%d)" % holes.size())
	for hole: Pothole in holes:
		player.global_position = hole.global_position + Vector3(1.2, 0.2, 0.0)
		await seconds(0.05)
		check(player.fixable_target() == hole, "a pothole is in reach")
		for i in 25:
			player.call("_repair", 0.1)
	check(holes.all(func(h: Node) -> bool: return (h as Pothole).is_fixed), "holding F fills every pothole")

	# Library: buy boxes of books until the shelves are full.
	var drive := level.get_node("BookDrive") as BookDrive
	Game.cash += 500
	player.global_position = drive.global_transform * drive.desk + Vector3(0.0, 0.2, 0.0)
	await seconds(0.05)
	check(player.nearest_interactable() == drive, "[E] reaches the library's book drive")
	var books_shown := func() -> int:
		return drive.get_children().filter(func(n: Node) -> bool: return n is MultiMeshInstance3D and (n as Node3D).visible).size()
	check(books_shown.call() == 0, "the library shelves start bare")
	for i in drive.boxes_needed:
		drive.interact(player)
	check(drive.is_done() and books_shown.call() == drive.boxes_needed, "each box of books fills more shelves")

	# Soup kitchen: put on an apron, serve six neighbors.
	var kitchen := level.get_node("SoupKitchen") as SoupKitchen
	player.global_position = kitchen.global_transform * kitchen.server_spot + Vector3(0.0, 0.2, 0.0)
	await seconds(0.05)
	check(player.nearest_interactable() == kitchen, "[E] reaches the soup kitchen counter")
	kitchen.interact(player)
	check(kitchen.on_shift, "the shift starts")
	for i in 200:
		if kitchen.is_done:
			break
		if kitchen.waiting_diner():
			kitchen.interact(player)
		await seconds(0.25)
	check(kitchen.is_done and kitchen.bowls == 6, "six bowls served (%d)" % kitchen.bowls)

	# Supply van: take it out.
	var van := level.get_node_or_null("SupplyVan") as SupplyVan
	if van == null or not van.is_alive():
		# Traffic or a stray round got it first (rare): the deed still counts.
		check((level.get("_deeds") as Dictionary).get("van", false), "the supply van was already stopped (deed done)")
	else:
		cash = Game.cash
		player.global_position = Vector3(-40, 0.2, 45)
		van.apply_damage(9999.0, van.global_position + Vector3.UP, &"explosive")
		await seconds(0.5)
		# $150 bounty + $100 all-deeds bonus.
		check(Game.cash == cash + 150 + 100, "van bounty and the all-deeds bonus ($%d)" % (Game.cash - cash))
	check(level.get("_deeds").values().all(func(done: bool) -> bool: return done), "all ten deeds done")


## Walk-in shops, the hospital's bill, and a storefront's regulars.
func _test_town() -> void:
	var hood := level.get_node("Neighborhood") as NeighborhoodBuilder
	for kind in WalkIn.KINDS:
		check(hood.walk_in(kind) != null, "the %s is a walk-in building" % kind)
	# Walk in through the hardware store's door: the navmesh reaches inside.
	var hardware := hood.global_transform * (hood.walk_in("hardware") as Transform3D)
	var inside := NavigationServer3D.map_get_closest_point(player.get_world_3d().navigation_map, hardware * Vector3(0.0, 0.0, 1.0))
	check(inside.distance_to(hardware * Vector3(0.0, 0.0, 1.0)) < 1.0, "the navmesh runs inside the hardware store")
	var tools := get_tree().get_nodes_in_group("hardware_store").map(func(n: Node) -> String: return (n as WeaponPickup).gun_name)
	check("Pickaxe" in tools and "Sledgehammer" in tools and not "Pistol" in tools, "DUECE Hardware stocks tools, not guns (%s)" % [tools])
	var guns := get_tree().get_nodes_in_group("gun_store")
	var gun_store := hood.global_transform * (hood.walk_in("gunstore") as Transform3D)
	check(guns.size() == 6 and guns.all(func(n: Node) -> bool: return (n as Node3D).global_position.distance_to(gun_store.origin) < 6.0),
		"the guns are inside Trey's Guns & Ammo (%d)" % guns.size())

	# Hospital: billed while the datacenters run the town.
	var hospital := level.get_node("Hospital") as Hospital
	player.global_position = hospital.global_position + Vector3(0.0, 0.2, 0.0)
	player.health = 40.0
	Game.cash = 100
	await seconds(0.05)
	check(player.nearest_interactable() == hospital, "[E] reaches the hospital's front desk")
	var bill := hospital.bill_for(player)
	check(bill == ceili(60.0 * hospital.price_per_hp), "care is billed per health point ($%d)" % bill)
	hospital.interact(player)
	check(is_equal_approx(player.health, player.max_health) and Game.cash == 100 - bill, "patched up and charged")
	# A hurt Canadian ally walks over and recovers on the ward.
	var ally := Canuck.new()
	ally.setup(false)
	ally.position = hospital.global_position + Vector3(0.0, 0.2, 4.0)
	level.add_child(ally)
	ally.join()
	ally.health = 10.0
	for i in 60:
		if not ally.in_hospital and ally.health > 70.0:
			break
		await seconds(0.25)
	check(ally.health >= ally.max_health * 0.9, "a hurt ally heads to the hospital and recovers (%d hp)" % roundi(ally.health))
	ally.queue_free()

	# Storefronts: spending builds goodwill; every third purchase, a regular joins.
	var diner: Storefront = null
	for node in get_tree().get_nodes_in_group("storefronts"):
		if (node as Storefront).kind == "diner":
			diner = node
	check(diner != null and get_tree().get_nodes_in_group("storefronts").size() >= 4, "local businesses are open for trade")
	Game.cash = 200
	var trust := Game.district.trust
	for i in 3:
		check(diner.buy(0, player), "bought a coffee")
	check(Game.cash == 200 - 15 and Game.district.trust > trust, "purchases cost cash and raise trust")
	var regulars := get_tree().get_nodes_in_group("regulars")
	check(regulars.size() == 1 and (regulars[0] as Enemy).faction == Enemy.Faction.ALLY, "three purchases: a regular joins you")
	for node in regulars:
		node.queue_free()
	await seconds(0.1)


## Phase 3: the green datacenter is up, and the hospital is free again.
func _test_free_hospital() -> void:
	var hospital := level.get_node("Hospital") as Hospital
	player.health = 30.0
	var cash := Game.cash
	check(hospital.is_free() and hospital.bill_for(player) == 0, "care is free once the green datacenter is built")
	hospital.interact(player)
	check(is_equal_approx(player.health, player.max_health) and Game.cash == cash, "patched up at no charge")


func _test_breach_ends_activism() -> void:
	var panel := level.get_node("FelsaSite/FenceFront/Panel4") as Destructible
	panel.shatter(panel.global_position, 50.0)
	await seconds(0.5)
	check(level.phase == level.Phase.ASSAULT, "breaching the fence starts Phase 2")


func _test_bribes() -> void:
	var menu := level.get_node("BribeMenu") as BribeMenu
	Game.cash = 0
	check(not menu.buy(2), "can't buy a bribe without cash")
	Game.cash = 2000
	check(menu.buy(2), "bought a zoning permit")
	check(not menu.buy(2), "can't stack the same bribe")
	check(menu.buy(0) and menu.buy(1), "bought municipal delay and supply blockade")
	check(Game.cash == 2000 - 300 - 200 - 250, "bribes cost cash ($%d)" % Game.cash)

	# Zoning permit: Phase 3 opens with walls.
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(9999.0, Vector3.ZERO)
	for node in get_tree().get_nodes_in_group("cooling_units"):
		(node as Destructible).shatter((node as Node3D).global_position, 200.0)
	for i in 80:
		if level.phase == level.Phase.BUILD:
			break
		await seconds(0.25)
	var walls := 0
	for node in get_tree().get_nodes_in_group("structures"):
		if node is Barricade:
			walls += 1
	check(walls == 4, "zoning permit pre-builds 4 walls (%d)" % walls)
	check(not Game.has_bribe("zoning_permit"), "permit consumed")

	# Delay + blockade reshape wave 3.
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	spawner.current_wave = 2
	spawner.start_next_wave()
	var kinds := {}
	for kind in spawner.get("_queue"):
		kinds[(kind as GDScript).get_global_name()] = kinds.get((kind as GDScript).get_global_name(), 0) + 1
	check(not kinds.has("Police") and not kinds.has("Frost"), "municipal delay: no police or FROST (%s)" % kinds)
	var listed := int(spawner.waves[2]["guard"])
	var blockaded := maxi(roundi(floori(listed * 0.7) * Game.wave_size_scale()), 1)
	check(kinds.get("SecurityGuard", 0) == blockaded, "supply blockade: %d guards become %d (%d)" % [listed, blockaded, kinds.get("SecurityGuard", 0)])
	check(Game.bribes.is_empty(), "wave bribes consumed")

