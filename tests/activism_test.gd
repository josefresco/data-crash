extends TestCase
## Phase 1 good deeds, noise-scaled trust, the fence breach into Phase 2, and
## all three bribes.
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

	await _test_deeds()
	await _test_breach_ends_activism()
	await _test_bribes()


func _test_deeds() -> void:
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

	# Scout: stand in the ring.
	var scout := level.get_node("ScoutPoint") as ScoutPoint
	player.global_position = scout.global_position + Vector3(0, 0.2, 0)
	for i in 20:
		if scout.is_scouted:
			break
		await seconds(0.25)
	check(scout.is_scouted, "standing in the ring scouts the datacenter")
	var marked := 0
	for unit in get_tree().get_nodes_in_group("cooling_units"):
		for child in unit.get_children():
			if child is Label3D:
				marked += 1
	check(marked == 3, "scouting marks all cooling units (%d)" % marked)

	# Strays: treats.
	for dog_name in ["StrayDog1", "StrayDog2"]:
		var dog := level.get_node(dog_name) as Dog
		player.global_position = dog.global_position + Vector3(1.5, 0.2, 0)
		await seconds(0.1)
		check(player.give_treat(), "treat for %s" % dog_name)

	# Supply van: take it out.
	cash = Game.cash
	var van := level.get_node("SupplyVan") as SupplyVan
	var start := van.global_position
	await seconds(2.0)
	check(van.global_position.distance_to(start) > 5.0, "supply van drives its route")
	player.global_position = Vector3(-40, 0.2, 45)
	van.apply_damage(9999.0, van.global_position + Vector3.UP, &"explosive")
	await seconds(0.5)
	# $150 bounty + $100 all-deeds bonus.
	check(Game.cash == cash + 150 + 100, "van bounty and the all-deeds bonus ($%d)" % (Game.cash - cash))
	check(level.get("_deeds").values().all(func(done: bool) -> bool: return done), "all four deeds done")


func _test_breach_ends_activism() -> void:
	var panel := level.get_node("FenceFront/Panel4") as Destructible
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

	# Delay + blockade reshape wave 3 (guard 5, police 3, frost 1, orange 3, felsa 1).
	var spawner := level.get_node("WaveSpawner") as WaveSpawner
	spawner.current_wave = 2
	spawner.start_next_wave()
	var kinds := {}
	for kind in spawner.get("_queue"):
		kinds[(kind as GDScript).get_global_name()] = kinds.get((kind as GDScript).get_global_name(), 0) + 1
	check(not kinds.has("Police") and not kinds.has("Frost"), "municipal delay: no police or FROST (%s)" % kinds)
	check(kinds.get("SecurityGuard", 0) == 3, "supply blockade: 5 guards become 3 (%d)" % kinds.get("SecurityGuard", 0))
	check(Game.bribes.is_empty(), "wave bribes consumed")
