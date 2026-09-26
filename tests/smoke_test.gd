extends TestCase
## Headless end-to-end check of the vertical slice at the Felsa site:
## car rams fence -> C4 on every cooling unit -> building collapses -> district
## heals. Plus Scgrewgle's gas turbines cutting power to Crapya's defenses.
## A scene (not a --script SceneTree) so the Game autoload is available.
##
## Run from the project root:
##   Godot_console.exe --headless --path . res://tests/smoke_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

func _run() -> void:
	var level := MAIN_SCENE.instantiate()
	add_child(level)
	await seconds(0.5)
	var game := Game

	check(get_tree().get_nodes_in_group("datacenter_sites").size() == 3, "three datacenter sites")
	# The Phase 1 supply van drives the same road the ram test uses.
	(level.get_node("SupplyVan") as Enemy).apply_damage(9999.0, Vector3.ZERO)
	var felsa := level.get_node("FelsaSite") as DatacenterSite
	var datacenter := felsa.datacenter
	var car := level.get_node("Car") as Car
	var fence := felsa.get_node("FenceFront") as FenceLine
	var breached := [false]
	fence.breached.connect(func() -> void: breached[0] = true)
	var neutralized := [false]
	datacenter.neutralized.connect(func() -> void: neutralized[0] = true)

	check(datacenter.cooling_remaining == 3, "datacenter spawned 3 cooling units")
	check(game.district.smog > 0.9, "district starts polluted")
	check(felsa.get_node_or_null("FrontGate") != null and felsa.get_node_or_null("BackGate") != null, "front and back gates")
	check(datacenter.get("_racks").size() >= 4, "server racks inside")
	check(felsa.worker != null and felsa.truck != null, "a worker inside and a cargo truck out back")

	# 1. Ram the fence beside the gate: aim the car at it from a few meters out at speed.
	car.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(12.0, 0.8, -6.0))
	car.linear_velocity = Vector3(0.0, 0.0, -14.0)
	await seconds(1.5)
	check(breached[0], "car ram breached the front fence")
	check(Game.is_alarmed(&"felsa") and not Game.is_alarmed(&"scgrewgle"), "only Felsa's alarm went off")

	# 1b. Scgrewgle's gas turbines: shrug off pistols, blow up under heavy fire, cut power.
	var scgrewgle := level.get_node("ScgrewgleSite") as DatacenterSite
	var turbines := scgrewgle.datacenter.get_children().filter(func(n: Node) -> bool: return n is GasTurbine)
	check(turbines.size() == 3, "each datacenter runs 3 gas turbines")
	var first_turbine := turbines[0] as GasTurbine
	first_turbine.apply_damage(15.0, first_turbine.global_position + Vector3(0, 1, 5), &"bullet")
	check(is_equal_approx(first_turbine.health, first_turbine.max_health), "pistol rounds bounce off a turbine")
	var smog_before := game.district.smog
	var cash_before := game.cash
	first_turbine.apply_damage(9999.0, first_turbine.global_position + Vector3(0, 1, 5), &"explosive")
	await seconds(0.5)
	check(game.district.smog < smog_before, "a downed turbine clears some smog")
	check(game.cash >= cash_before + 50, "turbine pays $50")
	var power := [false]
	scgrewgle.datacenter.power_cut.connect(func() -> void: power[0] = true)
	for turbine: Variant in turbines:  # fuel blasts may already have freed some
		if is_instance_valid(turbine) and not (turbine as GasTurbine).is_destroyed:
			(turbine as GasTurbine).apply_damage(9999.0, (turbine as GasTurbine).global_position, &"explosive")
	await seconds(0.8)
	check(power[0], "all turbines down cuts the power")
	var vent := scgrewgle.get_node("SteamVent1") as SteamVent
	check(vent.state == SteamVent.State.OFF, "powered defenses shut down")

	# 2. Pistol shots must not hurt cooling units (below damage threshold).
	var units := datacenter.get_children().filter(func(n: Node) -> bool: return n.is_in_group("cooling_units"))
	var first := units[0] as Destructible
	first.apply_damage(15.0, first.global_position, &"bullet")
	check(is_equal_approx(first.health, first.max_health), "bullets ignored by cooling units")

	# 3. Plant a short-fuse charge on each cooling unit.
	var smog_before_collapse := game.district.smog
	for node in units:
		var unit := node as Destructible
		var c4 := Explosive.new()
		c4.fuse_time = 0.2
		level.add_child(c4)
		c4.global_position = unit.global_position + (unit.global_basis * Vector3(1.6, 1.5, 0.0))
		c4.arm()
	await seconds(1.0)
	check(datacenter.cooling_remaining == 0, "all cooling units destroyed (remaining=%d)" % datacenter.cooling_remaining)
	check(get_tree().get_nodes_in_group("debris").size() > 0, "debris spawned")

	# 4. Collapse and district heal.
	for i in 40:
		if neutralized[0]:
			break
		await seconds(0.25)
	check(neutralized[0], "datacenter neutralized")
	check(game.district.smog < smog_before_collapse - 0.25, "smog clearing (smog=%.2f)" % game.district.smog)
	check(game.cash >= datacenter.cash_reward, "cash reward paid ($%d incl. bounties)" % game.cash)
	check(felsa.is_neutralized and not felsa.is_cleared, "Felsa's building is down but Elmo is still loose")
	var debris := get_tree().get_nodes_in_group("debris").size()
	check(debris <= Destructible.MAX_LIVE_DEBRIS, "debris under cap (%d)" % debris)
