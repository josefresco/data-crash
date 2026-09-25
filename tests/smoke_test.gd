extends TestCase
## Headless end-to-end check of the vertical slice:
## car rams fence -> C4 on every cooling unit -> building collapses -> district heals.
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

	# The Phase 1 supply van drives the same road the ram test uses.
	(level.get_node("SupplyVan") as Enemy).apply_damage(9999.0, Vector3.ZERO)
	# Crapya's control room shields the cooling units until it falls.
	var room := level.get_node("CrapyaControlRoom") as CrapyaControlRoom
	room.shatter(room.global_position, 100.0)
	await seconds(0.5)
	var datacenter := level.get_node("Datacenter") as Datacenter
	var car := level.get_node("Car") as Car
	var fence := level.get_node("FenceFront") as FenceLine
	var breached := [false]
	fence.breached.connect(func() -> void: breached[0] = true)
	var neutralized := [false]
	datacenter.neutralized.connect(func() -> void: neutralized[0] = true)

	check(datacenter.cooling_remaining == 3, "datacenter spawned 3 cooling units")
	check(game.district.smog > 0.9, "district starts polluted")

	# 1. Ram the fence: aim the car at it from a few meters out at speed.
	car.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.8, -6.0))
	car.linear_velocity = Vector3(0.0, 0.0, -14.0)
	await seconds(1.5)
	check(breached[0], "car ram breached the front fence")

	# 2. Pistol shots must not hurt cooling units (below damage threshold).
	var units := get_tree().get_nodes_in_group("cooling_units")
	var first := units[0] as Destructible
	first.apply_damage(15.0, first.global_position, &"bullet")
	check(is_equal_approx(first.health, first.max_health), "bullets ignored by cooling units")

	# 3. Plant a short-fuse charge on each cooling unit.
	for node in units:
		var unit := node as Destructible
		var c4 := Explosive.new()
		c4.fuse_time = 0.2
		level.add_child(c4)
		c4.global_position = unit.global_position + Vector3(-1.6, 1.5, 0.0)
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
	check(game.district.smog < 0.3, "smog cleared (smog=%.2f)" % game.district.smog)
	check(game.cash >= datacenter.cash_reward, "cash reward paid ($%d incl. bounties)" % game.cash)
	var debris := get_tree().get_nodes_in_group("debris").size()
	check(debris <= Destructible.MAX_LIVE_DEBRIS, "debris under cap (%d)" % debris)

