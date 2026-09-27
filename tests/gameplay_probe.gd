extends TestCase
## Gameplay report (no pass/fail on the numbers; it only checks it ran):
## 1. Time to kill: shots and seconds per weapon against each enemy type,
##    enemy frozen and facing the player (so riot shields count).
## 2. Threat: damage per second each enemy type deals to a player standing
##    in the open, and how long a 100 hp player would last.
## 3. Allies: recruited Canadians and tamed dogs against a guard squad.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/gameplay_probe.tscn [-- only=ttk,threat,allies]

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")
const TRIALS := 3
const MAX_SHOTS := 80
const STAND := Vector3(-84, 0.2, 40)

var level: Node
var player: Player
var only: PackedStringArray = []


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=").split(",")
	level = MAIN_SCENE.instantiate()
	level.set("boss_enabled", false)
	add_child(level)
	player = level.get_node("Player") as Player
	var baker := level.get_node("NavBaker") as NavBaker
	if baker.bake_count == 0:
		await baker.navmesh_ready
	await seconds(1.0)
	if _want("ttk"):
		await _time_to_kill()
	if _want("threat"):
		await _threat()
	if _want("allies"):
		await _allies()
	check(true, "gameplay probe ran")


func _want(section: String) -> bool:
	return only.is_empty() or section in only


func _spawn(kind: GDScript, at: Vector3, face: Vector3) -> Enemy:
	var unit := kind.new() as Enemy
	unit.position = at
	level.add_child(unit)
	var visual := unit.get("_visual") as Node3D
	if visual:
		visual.look_at(Vector3(face.x, visual.global_position.y, face.z), Vector3.UP)
	return unit


func _clear() -> void:
	for group in ["hostiles", "allies"]:
		for node in get_tree().get_nodes_in_group(group):
			var unit := node as Enemy
			if unit and not unit.is_dormant() and unit.global_position.distance_to(STAND) < 80.0:
				unit.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()


func _weapon_index(weapon_name: String) -> int:
	for i in player.weapons.size():
		if player.weapons[i].display_name == weapon_name:
			return i
	return -1


# --- 1. Time to kill ----------------------------------------------------------

func _time_to_kill() -> void:
	player.arm_all()
	player.global_position = STAND
	player.set_physics_process(false)
	var enemies: Array[GDScript] = [SecurityGuard, Police, Dog, Frost, ReplyGuy, OrangeHat, FelsaCar]
	var guns := ["Fists", "Shovel", "Pistol", "Shotgun", "Hunting rifle", "Machine gun"]
	print("\nTIME TO KILL (enemy at 12 m, melee at 1.6 m; mean shots / seconds over %d trials)" % TRIALS)
	var header := "%-14s %5s" % ["enemy", "hp"]
	for gun: String in guns:
		header += " | %-15s" % gun
	print(header)
	for kind in enemies:
		var probe := kind.new() as Enemy
		var row := "%-14s %5d" % [kind.get_global_name(), int(probe.max_health)]
		probe.free()
		for gun: String in guns:
			var weapon := player.weapons[_weapon_index(gun)]
			var melee := weapon.kind == Weapon.Kind.MELEE
			if melee and kind == FelsaCar:
				row += " | %-15s" % "n/a"
				continue
			var shots_total := 0
			var kills := 0
			for trial in TRIALS:
				var target := _spawn(kind, STAND + Vector3(0.0, -0.1, -(1.6 if melee else 12.0)), STAND)
				target.set_physics_process(false)
				await seconds(0.1)
				player.select_weapon(_weapon_index(gun))
				weapon.refill()
				var shots := 0
				while target.is_alive() and shots < MAX_SHOTS:
					player.aim_at(target.aim_point())
					player.call("_physics_process", 0.0)  # keep the camera and body in sync
					player.fire()
					shots += 1
					weapon.refill()
					await seconds(weapon.cooldown + 0.02)
				if not target.is_alive():
					kills += 1
				shots_total += shots
				if is_instance_valid(target):
					target.queue_free()
				_clear()
				await seconds(0.1)
			var mean := float(shots_total) / TRIALS
			var cell := ("%.1f / %.1fs" % [mean, mean * weapon.cooldown]) if kills == TRIALS else (">%d" % MAX_SHOTS if kills == 0 else "%.0f (%d/%d)" % [mean, kills, TRIALS])
			row += " | %-15s" % cell
		print(row)
	player.set_physics_process(true)


# --- 2. Threat to the player -----------------------------------------------------

func _threat() -> void:
	var enemies: Array[GDScript] = [SecurityGuard, Police, Dog, Frost, ReplyGuy, FelsaCar]
	print("\nTHREAT (one enemy starting 15 m away, player standing still in the open, 15 s)")
	print("%-14s | %8s | %6s | %s" % ["enemy", "1st hit", "dps", "100 hp player lasts"])
	for kind in enemies:
		_clear()
		player.global_position = STAND
		player.velocity = Vector3.ZERO
		player.heal(9999.0)
		await seconds(0.5)
		var taken := [0.0]
		var first_hit := [-1.0]
		var clock := [0.0]
		var on_hurt := func(_from: Vector3, amount: float) -> void:
			taken[0] += amount
			if first_hit[0] < 0.0:
				first_hit[0] = clock[0]
		player.hurt_from.connect(on_hurt)
		var unit := _spawn(kind, STAND + Vector3(0.0, -0.1, -15.0), STAND)
		for i in 60:
			await seconds(0.25)
			clock[0] += 0.25
			player.heal(9999.0)  # never respawn mid-measurement
			player.global_position = Vector3(STAND.x, player.global_position.y, STAND.z)
		player.hurt_from.disconnect(on_hurt)
		var engaged := 15.0 - maxf(first_hit[0], 0.0)
		var dps: float = taken[0] / engaged if first_hit[0] >= 0.0 else 0.0
		print("%-14s | %8s | %6.1f | %s" % [kind.get_global_name(),
			("%.1fs" % first_hit[0]) if first_hit[0] >= 0.0 else "never", dps,
			("%.1fs" % (100.0 / dps)) if dps > 0.0 else "-"])
		if is_instance_valid(unit):
			unit.queue_free()
	_clear()


# --- 3. Allies against a guard squad ----------------------------------------------

func _allies() -> void:
	print("\nALLIES vs 3 security guards (40 s, player far away)")
	print("%-22s | %6s | %11s | %s" % ["squad", "won", "guards left", "allies left (mean over 3)"])
	for setup in [["2 Canadians", 2, 0], ["3 Canadians", 3, 0], ["2 tamed dogs", 0, 2], ["3 Canadians + 2 dogs", 3, 2]]:
		var wins := 0
		var guards_left := 0
		var allies_left := 0
		for trial in 3:
			_clear()
			player.global_position = STAND + Vector3(0.0, 0.0, 60.0)
			await seconds(0.3)
			var guards: Array[Enemy] = []
			for i in 3:
				guards.append(_spawn(SecurityGuard, STAND + Vector3(-3.0 + i * 3.0, -0.1, -14.0), STAND))
			var allies: Array[Enemy] = []
			for i in setup[1]:
				var tourist := Canuck.new()
				tourist.setup(false)
				tourist.position = STAND + Vector3(-2.0 + i * 2.0, -0.1, 0.0)
				level.add_child(tourist)
				tourist.join()
				allies.append(tourist)
			for i in setup[2]:
				var dog := Dog.new()
				dog.position = STAND + Vector3(-1.0 + i * 2.0, -0.1, 1.5)
				level.add_child(dog)
				dog.befriend()
				allies.append(dog)
			for i in 160:
				await seconds(0.25)
				player.heal(9999.0)
				var g := guards.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).is_alive()).size()
				var a := allies.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).is_alive()).size()
				if g == 0 or a == 0:
					break
			var g_left := guards.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).is_alive()).size()
			var a_left := allies.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).is_alive()).size()
			guards_left += g_left
			allies_left += a_left
			if g_left == 0:
				wins += 1
		print("%-22s | %4d/3 | %11.1f | %.1f" % [setup[0], wins, guards_left / 3.0, allies_left / 3.0])
	_clear()
