extends TestCase
## District 2 (the riverside town): the level loads with its river and three
## sites, every boss waits in its suite, and each boss's mechanic works:
## Pete Bottleneck (hose-proof, pressure washer, heals off his river pumps),
## Chad Hodler (HODL bros, the rug pull: bros log off, cold wallet, token
## bombs), Brad Hypewell (hype shield from his chatbot kiosks, hallucinated
## copies). Fresh copies of the bosses are staged in the open strip, tied
## to their real sites (pumps and kiosks are per site).
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/district2_test.tscn

const D2 := preload("res://scenes/levels/district_2.tscn")
const STRIP := Vector3(-84, 0.1, 40)

var level: Level
var player: Player


func _run() -> void:
	level = D2.instantiate() as Level
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(2.0)
	var hood := level.get_node("Neighborhood") as NeighborhoodBuilder
	check(hood.has_river and hood.river() != null, "District 2 has its river")
	check(level.sites.size() == 3, "three datacenters (%d)" % level.sites.size())
	check(level.defense_site_name() == "PureDrain Bottling", "the defense goes up on the PureDrain lot")
	for site_node in level.sites:
		var boss := site_node.boss_unit
		check(boss != null and boss.global_position.y - site_node.global_position.y > ExecutiveSuite.FLOOR - 0.5,
			"%s waits upstairs at %s" % [site_node.boss_label(), site_node.display_name])
	check(get_tree().get_nodes_in_group("river_pumps").size() == 3, "PureDrain has three river pumps")
	check(get_tree().get_nodes_in_group("chatbot_kiosks").size() == 3, "SynergAI has three chatbot kiosks")
	await _test_pete()
	await _test_chad()
	await _test_brad()


func _stage(unit: Enemy, site_id: StringName, at: Vector3) -> Enemy:
	# The real boss upstairs would wake with the alarm and muddy the test.
	var real := level.site(site_id).boss_unit
	if is_instance_valid(real):
		real.queue_free()
	level.raise_alarm(site_id, "test")
	unit.site = site_id
	unit.position = at
	level.add_child(unit)
	return unit


func _test_pete() -> void:
	player.global_position = STRIP + Vector3(0, 0.1, 9)
	player.heal(9999.0)
	var pete := _stage(PeteBottleneck.new(), &"puredrain", STRIP) as PeteBottleneck
	await seconds(0.3)
	var hp := pete.health
	pete.apply_damage(60.0, player.global_position, &"water")
	check(pete.health == hp, "hoses don't hurt Pete (%.0f -> %.0f)" % [hp, pete.health])
	pete.apply_damage(300.0, player.global_position, &"bullet")
	var hurt := pete.health
	await seconds(2.0)
	check(pete.health > hurt + 10.0, "Pete heals while his river pumps run (%.0f -> %.0f)" % [hurt, pete.health])
	check(player.health < player.max_health, "his pressure washer stings")
	var water := Game.district.water_table
	for node in get_tree().get_nodes_in_group("river_pumps"):
		(node as Destructible).apply_damage(9999.0, player.global_position, &"explosive")
	await seconds(0.5)
	check(pete.pumps_running() == 0, "the river pumps are wrecked")
	check(Game.district.water_table > water + 0.15, "wrecking the pumps gives the river water back (%.2f -> %.2f)" % [water, Game.district.water_table])
	hurt = pete.health
	await seconds(2.0)
	check(pete.health <= hurt + 0.5, "no pumps, no healing")
	pete.apply_damage(9999.0, player.global_position, &"explosive")
	await seconds(0.5)


func _test_chad() -> void:
	player.global_position = STRIP + Vector3(0, 0.1, 14)
	player.heal(9999.0)
	var chad := _stage(ChadHodler.new(), &"moonmine", STRIP) as ChadHodler
	await seconds(0.3)
	chad.set("_summon_left", 0.1)
	await seconds(1.0)
	var bros := get_tree().get_nodes_in_group("hodl_bros").size()
	check(bros >= 1, "Chad pumps his community: HODL bros show up (%d)" % bros)
	player.heal(9999.0)
	var blasts := [0]
	var on_hurt := func(_from: Vector3, _amount: float) -> void: blasts[0] += 1
	player.hurt_from.connect(on_hurt)
	chad.apply_damage(chad.max_health * 0.55, player.global_position, &"bullet")
	await seconds(0.2)
	check(chad.rugged and chad.is_field_shielded(), "below half health he pulls the rug into a cold wallet")
	await seconds(3.0)
	player.hurt_from.disconnect(on_hurt)
	check(get_tree().get_nodes_in_group("hodl_bros").is_empty(), "the rug pull logs his bros off")
	check(blasts[0] >= 1, "token bombs land around the player (%d hits)" % blasts[0])
	chad.apply_damage(9999.0, player.global_position, &"explosive")
	await seconds(0.5)


func _test_brad() -> void:
	player.global_position = STRIP + Vector3(0, 0.1, 14)
	player.heal(9999.0)
	var brad := _stage(BradHypewell.new(), &"synergai", STRIP) as BradHypewell
	await seconds(0.5)
	check(brad.is_hyped() and brad.is_field_shielded(), "his chatbot kiosks keep Brad's hype shield up")
	var hp := brad.health
	brad.apply_damage(100.0, player.global_position, &"bullet")
	check(hp - brad.health < 50.0, "the hype shield soaks most damage (%.0f)" % (hp - brad.health))
	brad.set("_hallucinate_left", 0.1)
	await seconds(0.5)
	var copies := get_tree().get_nodes_in_group("hostiles").filter(func(n: Node) -> bool: return n is Hallucination).size()
	check(copies >= 1, "the kiosks hallucinate copies of him (%d)" % copies)
	for node in get_tree().get_nodes_in_group("chatbot_kiosks"):
		(node as Destructible).apply_damage(9999.0, player.global_position, &"explosive")
	await seconds(1.0)
	check(not brad.is_hyped(), "smashing the kiosks ends the hype")
	hp = brad.health
	brad.apply_damage(100.0, player.global_position, &"bullet")
	check(hp - brad.health > 90.0, "then he takes full damage (%.0f)" % (hp - brad.health))
	brad.apply_damage(9999.0, player.global_position, &"explosive")
	await seconds(0.5)
