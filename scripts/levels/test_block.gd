extends Node3D
## Vertical-slice test level.
## Phase 1 (ACTIVISM): optional good deeds for cash and trust; breaching the fence ends it.
## Phase 2 (ASSAULT): ram the fence, blow the cooling units, watch the sky clear.
## Boss (BOSS): Elmo Mushbrains arrives in his Felsa Truck, then fights on foot.
## Phase 3 (BUILD / WAVE): defend the new green datacenter against waves.

enum Phase { ACTIVISM, ASSAULT, BOSS, BUILD, WAVE, WON, LOST }

## Seconds between the collapse and the green core going up (lets debris settle).
@export var core_delay := 3.0
## Elmo shows up after the collapse. Tests that skip to Phase 3 turn this off.
@export var boss_enabled := true
## Seconds after the collapse before the boss truck rolls in.
@export var boss_delay := 4.0
## Seconds of build time before the next wave starts on its own.
@export var auto_wave_delay := 45.0
## Neighbors who join the repair crew: base + trust * per_trust.
@export var townspeople_base := 2
@export var townspeople_per_trust := 4.0
## Fence lines corporate crews cut through at the start of waves 2+.
@export var breach_fences: Array[String] = ["FenceLeft", "FenceRight", "FenceBack"]
## Panels cut per breach.
@export var breach_width := 2
## First wave that opens a new lane. Announced (with a flare) a build phase ahead.
@export var breach_from_wave := 3
## Where neighbors walk out from (front doors).
@export var house_doors: Array[Vector3] = [Vector3(-12, 0.2, 21), Vector3(13, 0.2, 25)]

var phase := Phase.ACTIVISM
var core: GreenCore

var _fence_breached := false
var _auto_wave_left := -1.0
var _planned_breach: Array[Destructible] = []
var _breach_side := ""
var _breach_flare: Node3D
var _boss: Enemy
var _boss_name := "ELMO MUSHBRAINS"
var _deeds := {"water": false, "van": false, "dogs": false, "scout": false}
var _dogs_tamed := 0

@onready var _datacenter: Datacenter = $Datacenter
@onready var _env_driver: EnvironmentDriver = $EnvironmentDriver
@onready var _spawner: WaveSpawner = $WaveSpawner
@onready var _build: BuildController = $BuildController


func _ready() -> void:
	Game.reset()

	_env_driver.world_environment = $WorldEnvironment
	_env_driver.sun = $Sun
	_env_driver.ground = $Ground/Mesh

	for child in get_children():
		if child is FenceLine:
			(child as FenceLine).breached.connect(_on_fence_breached)
	_datacenter.cooling_unit_destroyed.connect(_on_cooling_unit_destroyed)
	_datacenter.neutralized.connect(_on_neutralized)
	_spawner.wave_started.connect(_on_wave_started)
	_spawner.wave_cleared.connect(_on_wave_cleared)
	_spawner.all_waves_cleared.connect(_on_all_waves_cleared)

	($WaterMain as WaterMain).fixed.connect(func(_m: WaterMain) -> void:
		_complete_deed("water", 100, 0.1, "Water main fixed. The Hendersons have water again. (+$100)"))
	($ScoutPoint as ScoutPoint).scouted.connect(func(_p: ScoutPoint) -> void:
		_complete_deed("scout", 50, 0.05, "Datacenter scouted: cooling units marked. (+$50)"))
	($SupplyVan as Enemy).died.connect(func(_v: Enemy) -> void:
		_complete_deed("van", 0, 0.05, "Supply van intercepted. Cargo seized. (+$150)"))
	for dog_name in ["StrayDog1", "StrayDog2"]:
		var dog := get_node(dog_name) as Dog
		dog.defeated.connect(_on_stray_dog_defeated)
	($BribeMenu as BribeMenu).bribe_bought.connect(_on_bribe_bought)
	_update_deeds()

	Game.set_objective("Help the neighborhood first (optional), or get in the car [E] and ram the fence.")


func _process(delta: float) -> void:
	if phase == Phase.BOSS:
		_update_boss_bar()
	if phase != Phase.BUILD or _auto_wave_left < 0.0:
		return
	_auto_wave_left -= delta
	var line := "Wave %d/%d arrives in %ds  ([N] to start now)" \
		% [_spawner.current_wave + 1, _spawner.total_waves(), ceili(_auto_wave_left)]
	if has_planned_breach():
		line += "\nIntel: crews will cut the %s fence (red flare)" % _breach_side
	Game.set_info("wave", line)
	if _auto_wave_left <= 0.0:
		start_next_wave()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.BUILD and event.is_action_pressed("start_wave"):
		start_next_wave()
	elif phase == Phase.LOST and event.is_action_pressed("retry"):
		get_tree().reload_current_scene()


## Skips straight to Phase 3. Used by tests and handy for debugging.
func start_defense() -> void:
	if phase not in [Phase.ACTIVISM, Phase.ASSAULT, Phase.BOSS]:
		return
	phase = Phase.BUILD
	core = GreenCore.new()
	core.position = Vector3(_datacenter.global_position.x, 0.0, _datacenter.global_position.z)
	add_child(core)
	core.damaged.connect(_on_core_damaged)
	core.repaired.connect(_on_core_damaged)
	core.destroyed.connect(_on_core_destroyed)
	_on_core_damaged(0.0, core.health)

	_spawner.objective = core
	_build.center = core.global_position
	_build.enabled = true
	_build.set_active(false)
	get_tree().call_group(&"nav_baker", &"request_rebake")

	_spawn_townspeople(townspeople_base + int(Game.district.trust * townspeople_per_trust))
	_refill_player()
	_update_deeds()
	if Game.consume_bribe("zoning_permit"):
		_place_permit_walls()
	_auto_wave_left = auto_wave_delay
	Game.set_objective("Defend the green datacenter. Build defenses, then hold off %d waves."
		% _spawner.total_waves())


## Rolls Elmo's truck in from the south road. Public for tests.
func start_boss() -> void:
	if phase != Phase.ACTIVISM and phase != Phase.ASSAULT:
		return
	phase = Phase.BOSS
	var truck := ElmoTruck.new()
	truck.position = ($WaveSpawner/SouthRoad as Node3D).global_position
	truck.objective = get_tree().get_first_node_in_group("player") as Node3D
	truck.wrecked.connect(_on_truck_wrecked)
	add_child(truck)
	truck.rotation.y = PI  # face north, up the road
	_boss = truck
	Game.set_objective("ELMO MUSHBRAINS rolls in with his Felsa Truck. Wreck it! (EMP won't hack this one.)")


func has_planned_breach() -> bool:
	return not _planned_breach.is_empty()


## World position of the next announced breach (for AI builders and markers).
func next_breach_point() -> Vector3:
	var sum := Vector3.ZERO
	for panel in _planned_breach:
		sum += panel.global_position
	return sum / maxi(_planned_breach.size(), 1)


func start_next_wave() -> void:
	if phase == Phase.BUILD:
		_spawner.start_next_wave()


func _on_fence_breached() -> void:
	if _fence_breached or (phase != Phase.ACTIVISM and phase != Phase.ASSAULT):
		return
	_fence_breached = true
	phase = Phase.ASSAULT
	_update_deeds()
	Game.set_objective("Fence down. Plant C4 [G] on the %d cooling units, then get clear."
		% _datacenter.cooling_remaining)


func _on_cooling_unit_destroyed(remaining: int) -> void:
	if remaining > 0:
		Game.set_objective("Cooling unit destroyed. %d left." % remaining)
	else:
		Game.set_objective("Cooling offline. The building is coming down!")


func _on_neutralized() -> void:
	Game.set_objective("Datacenter down. The air is clearing. (+$%d)" % _datacenter.cash_reward)
	if boss_enabled:
		get_tree().create_timer(boss_delay).timeout.connect(start_boss)
	else:
		get_tree().create_timer(core_delay).timeout.connect(start_defense)


func _on_truck_wrecked(truck: ElmoTruck) -> void:
	var wreck := truck.global_position
	Game.set_objective("The truck is scrap. Elmo climbs out with a flamethrower. Hit him while he posts!")
	# Give the wreck's explosion a moment before he climbs out beside it.
	await get_tree().create_timer(1.2).timeout
	var elmo := ElmoOnFoot.new()
	elmo.position = wreck + Vector3(3.5, 0.2, 0.0)
	elmo.objective = get_tree().get_first_node_in_group("player") as Node3D
	elmo.died.connect(_on_boss_defeated)
	add_child(elmo)
	_boss = elmo
	_boss_name = "ELMO MUSHBRAINS (on foot)"


func _on_boss_defeated(_elmo: Enemy) -> void:
	_boss = null
	Game.set_info("boss", "")
	Game.district.trust += 0.15
	Game.set_objective("Elmo is out, logged off for good. The neighbors are coming to build.")
	get_tree().create_timer(core_delay).timeout.connect(start_defense)


func _update_boss_bar() -> void:
	if not is_instance_valid(_boss) or not _boss.is_alive():
		return
	var ratio := clampf(_boss.health / _boss.max_health, 0.0, 1.0)
	var filled := roundi(ratio * 30.0)
	var bar := "#".repeat(filled) + "-".repeat(30 - filled)
	var extra := ""
	if _boss is ElmoOnFoot and (_boss as ElmoOnFoot).is_posting:
		extra = "   POSTING: x2.5 damage!"
	Game.set_info("boss", "%s  [%s]%s" % [_boss_name, bar, extra])


## Phase 1 rewards. Trust gains shrink while the datacenter's noise saps morale.
func _complete_deed(key: String, cash: int, trust: float, text: String) -> void:
	if _deeds.get(key, true):
		return
	_deeds[key] = true
	var morale := 1.0 - 0.5 * Game.district.noise
	Game.add_cash(cash)
	Game.district.trust += trust * morale
	if not _deeds.values().has(false):
		Game.add_cash(100)
		Game.district.trust += 0.05
		text += "  Every deed done: the neighborhood is organized! (+$100)"
	if phase == Phase.ACTIVISM:
		Game.set_objective(text)
	_update_deeds()


func _on_stray_dog_defeated(dog: Enemy) -> void:
	if dog.faction != Enemy.Faction.ALLY:
		return  # killed, not tamed
	_dogs_tamed += 1
	Game.district.trust += 0.03
	if _dogs_tamed >= 2:
		_complete_deed("dogs", 50, 0.05, "Both strays tamed. They'll guard the block now. (+$50)")
	else:
		_update_deeds()


func _update_deeds() -> void:
	if phase != Phase.ACTIVISM:
		Game.set_info("deeds", "")
		return
	var marks := {}
	for key: String in _deeds:
		marks[key] = "x" if _deeds[key] else " "
	Game.set_info("deeds", "Good deeds:  [%s] Fix the water main [F]   [%s] Intercept the supply van   [%s] Tame the strays %d/2 [T]   [%s] Scout the datacenter"
		% [marks["water"], marks["van"], marks["dogs"], mini(_dogs_tamed, 2), marks["scout"]])


func _on_bribe_bought(key: String) -> void:
	# A permit bought mid-defense goes up right away.
	if key == "zoning_permit" and phase in [Phase.BUILD, Phase.WAVE] and Game.consume_bribe(key):
		_place_permit_walls()


## Zoning permit: the town board lets the crew pour walls on all four sides.
func _place_permit_walls() -> void:
	if core == null:
		return
	var center := core.global_position
	for spot in [[Vector3(0, 0, 8), 0], [Vector3(0, 0, -8), 0], [Vector3(8, 0, 0), 1], [Vector3(-8, 0, 0), 1]]:
		for nudge in [0.0, 1.0, -1.0, 2.0]:
			var offset: Vector3 = spot[0] * (1.0 + nudge / 8.0)
			if _build.place(0, center + offset, spot[1], true) != null:
				break


func _refill_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.refill_ammo()


func _on_wave_started(number: int, total: int) -> void:
	phase = Phase.WAVE
	_auto_wave_left = -1.0
	Game.set_info("wave", "Wave %d/%d" % [number, total])
	if has_planned_breach():
		Game.set_info("wave", "Wave %d/%d: they cut through the %s fence!" % [number, total, _breach_side])
		_execute_breach()
	Game.set_objective("Wave %d/%d incoming. Hold the line!" % [number, total])


func _on_wave_cleared(number: int, total: int) -> void:
	if phase == Phase.LOST:
		return
	if number >= total:
		return  # _on_all_waves_cleared handles the finale
	phase = Phase.BUILD
	_auto_wave_left = auto_wave_delay
	Game.district.trust += 0.05
	_refill_player()
	if number + 1 >= breach_from_wave:
		_plan_breach()
	# High trust brings more neighbors out to help.
	if Game.district.trust >= 0.6 and get_tree().get_nodes_in_group("townspeople").size() < 8:
		_spawn_townspeople(1)
	Game.set_objective("Wave %d cleared. Repair, rebuild, then [N] for the next one." % number)


func _on_all_waves_cleared() -> void:
	if phase == Phase.LOST:
		return
	phase = Phase.WON
	Game.district.trust = 1.0
	Game.district.water_table = 1.0
	Game.set_info("wave", "")
	Game.set_objective("Zone held! Water is flowing and the neighborhood is yours.")


## Picks `breach_width` adjacent intact panels on a random fence and marks them
## with a flare. They get cut when the next wave starts.
func _plan_breach() -> void:
	_clear_breach_plan()
	var fences := breach_fences.duplicate()
	fences.shuffle()
	for fence_name: String in fences:
		var fence := get_node_or_null(fence_name) as FenceLine
		if fence == null:
			continue
		var panels: Array[Destructible] = []
		for child in fence.get_children():
			if child is Destructible and not (child as Destructible).is_destroyed:
				panels.append(child)
		if panels.size() < breach_width:
			continue
		var start := randi_range(0, panels.size() - breach_width)
		_planned_breach = panels.slice(start, start + breach_width)
		_breach_side = fence_name.trim_prefix("Fence").to_lower()
		_breach_flare = _make_flare()
		add_child(_breach_flare)
		_breach_flare.global_position = next_breach_point()
		return


func _execute_breach() -> void:
	for panel in _planned_breach:
		if is_instance_valid(panel) and not panel.is_destroyed:
			panel.shatter(panel.global_position + Vector3.UP, 80.0)
	_clear_breach_plan()


func _clear_breach_plan() -> void:
	_planned_breach.clear()
	if is_instance_valid(_breach_flare):
		_breach_flare.queue_free()
	_breach_flare = null


## Pulsing red road flare: tall enough to spot over the fence.
func _make_flare() -> Node3D:
	var flare := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.1)
	var beam := BoxMesh.new()
	beam.size = Vector3(0.15, 6.0, 0.15)
	var mesh := MeshInstance3D.new()
	mesh.mesh = beam
	mesh.material_override = mat
	mesh.position.y = 3.0
	flare.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.1)
	light.omni_range = 8.0
	light.position.y = 1.0
	flare.add_child(light)
	var tween := light.create_tween().set_loops()
	tween.tween_property(light, "light_energy", 4.0, 0.4)
	tween.tween_property(light, "light_energy", 0.5, 0.4)
	return flare


func _spawn_townspeople(count: int) -> void:
	for i in count:
		var person := Townsperson.new()
		person.objective = core
		person.position = house_doors[i % house_doors.size()] + Vector3(randf_range(-1.5, 1.5), 0.0, 0.0)
		person.abducted.connect(_on_townsperson_abducted)
		add_child(person)
		# Home is the core, so idle neighbors hang around the site.
		person.home = core.global_position + Vector3(randf_range(-6.0, 6.0), 0.0, 8.0)


func _on_townsperson_abducted(_person: Townsperson) -> void:
	Game.set_info("wave", "FROST took a neighbor! Trust falling.")


func _on_core_damaged(_amount: float, health: float) -> void:
	Game.set_info("core", "Green datacenter  %d / %d" % [maxi(ceili(health), 0), int(core.max_health)])


func _on_core_destroyed(_core: Destructible) -> void:
	phase = Phase.LOST
	_build.enabled = false
	_build.set_active(false)
	Game.district.smog += 0.6
	Game.set_info("core", "")
	Game.set_objective("The green datacenter fell. Press [Enter] to retry.")
