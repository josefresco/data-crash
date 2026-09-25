extends Node
## Headless end-to-end check of the vertical slice:
## car rams fence -> C4 on every cooling unit -> building collapses -> district heals.
## A scene (not a --script SceneTree) so the Game autoload is available.
##
## Run from the project root:
##   Godot_console.exe --headless --path . res://tests/smoke_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	var level := MAIN_SCENE.instantiate()
	add_child(level)
	await _seconds(0.5)
	var game := Game

	var datacenter := level.get_node("Datacenter") as Datacenter
	var car := level.get_node("Car") as Car
	var fence := level.get_node("FenceFront") as FenceLine
	var breached := [false]
	fence.breached.connect(func() -> void: breached[0] = true)
	var neutralized := [false]
	datacenter.neutralized.connect(func() -> void: neutralized[0] = true)

	_check(datacenter.cooling_remaining == 3, "datacenter spawned 3 cooling units")
	_check(game.district.smog > 0.9, "district starts polluted")

	# 1. Ram the fence: aim the car at it from a few meters out at speed.
	car.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.8, -6.0))
	car.linear_velocity = Vector3(0.0, 0.0, -14.0)
	await _seconds(1.5)
	_check(breached[0], "car ram breached the front fence")

	# 2. Pistol shots must not hurt cooling units (below damage threshold).
	var units := get_tree().get_nodes_in_group("cooling_units")
	var first := units[0] as Destructible
	first.apply_damage(15.0, first.global_position, &"bullet")
	_check(is_equal_approx(first.health, first.max_health), "bullets ignored by cooling units")

	# 3. Plant a short-fuse charge on each cooling unit.
	for node in units:
		var unit := node as Destructible
		var c4 := Explosive.new()
		c4.fuse_time = 0.2
		level.add_child(c4)
		c4.global_position = unit.global_position + Vector3(-1.6, 1.5, 0.0)
		c4.arm()
	await _seconds(1.0)
	_check(datacenter.cooling_remaining == 0, "all cooling units destroyed (remaining=%d)" % datacenter.cooling_remaining)
	_check(get_tree().get_nodes_in_group("debris").size() > 0, "debris spawned")

	# 4. Collapse and district heal.
	for i in 40:
		if neutralized[0]:
			break
		await _seconds(0.25)
	_check(neutralized[0], "datacenter neutralized")
	_check(game.district.smog < 0.3, "smog cleared (smog=%.2f)" % game.district.smog)
	_check(game.cash == datacenter.cash_reward, "cash reward paid ($%d)" % game.cash)
	var debris := get_tree().get_nodes_in_group("debris").size()
	_check(debris <= Destructible.MAX_LIVE_DEBRIS, "debris under cap (%d)" % debris)
	_finish()


func _seconds(duration: float) -> Signal:
	return get_tree().create_timer(duration).timeout


func _check(condition: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)


func _finish() -> void:
	print("\n%d failure(s)" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
