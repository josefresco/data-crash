extends Node3D
## Vertical-slice test level.
## Phase 1 (ACTIVISM): optional good deeds for cash and trust; breaching the fence ends it.
## Phase 2 (ASSAULT): ram the fence, blow the cooling units, watch the sky clear.
## Boss (BOSS): Elmo Mushbrains arrives in his Cyberdouche, then fights on foot
## (and on Twatter: his Twats summon Reply Guys).
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
## Grock surveillance cameras on the block (position, yaw). Smash them for cash and trust.
@export var grock_camera_spots: Array[Vector4] = [
	Vector4(6.2, 0, 8, PI), Vector4(-6.2, 0, 56, 0), Vector4(6.2, 0, 88, PI), Vector4(-46, 0, 24.6, -PI * 0.5),
	Vector4(18, 0, 35.4, PI * 0.5), Vector4(50, 0, 24.6, -PI * 0.5), Vector4(-30, 0, 75.4, PI * 0.5),
]
## Datacenter security posted at the start. Passive until the site alarm.
@export var site_security_nodes: Array[String] = ["Guard1", "Guard2", "Guard3", "Dog1", "Dog2", "PatrolFelsa", "SentryNE", "SentryNW"]
## Fence lines corporate crews cut through at the start of waves 2+.
@export var breach_fences: Array[String] = ["FenceLeft", "FenceRight", "FenceBack"]
## Panels cut per breach.
@export var breach_width := 2
## First wave that opens a new lane. Announced (with a flare) a build phase ahead.
@export var breach_from_wave := 3

var phase := Phase.ACTIVISM
var core: GreenCore

var _fence_breached := false
var _auto_wave_left := -1.0
var _planned_breach: Array[Destructible] = []
var _breach_side := ""
var _breach_flare: Node3D
var _boss_bar_shown := false
var _deeds := {"water": false, "van": false, "dogs": false, "scout": false}
var _dogs_tamed := 0
var _cameras_total := 0
var _end_screen: EndScreen
var _waves_cleared := 0
var _cameras_smashed := 0

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
	_datacenter.turbine_destroyed.connect(func(remaining: int) -> void:
		if phase == Phase.ACTIVISM or phase == Phase.ASSAULT:
			Game.set_objective(("Gas turbine down: less smog, less noise. (+$%d)  %d left; take them all out to cut power to the defenses."
				% [_datacenter.turbine_cash, remaining]) if remaining > 0 else "All gas turbines down."))
	_datacenter.power_cut.connect(func() -> void:
		Game.set_objective("Power cut! Crapya's sentries, vents, and crushers are dead. Her control room still shields the cooling units."))
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
	_spawn_grock_cameras()
	_arm_site_security()
	var tips := TipDirector.new()
	tips.level = self
	add_child(tips)
	add_child(PauseMenu.new())
	_end_screen = EndScreen.new()
	add_child(_end_screen)
	($CrapyaControlRoom as CrapyaControlRoom).defenses_offline.connect(func() -> void:
		Game.set_objective("Crapya's control room is down: defenses offline, cooling units exposed. (+$300)"))
	_update_deeds()

	Game.set_objective("Help the neighborhood first (optional), or ram the fence with the car [E]. Crapya's control room shields the cooling units.")


func _process(delta: float) -> void:
	if phase != Phase.WON and phase != Phase.LOST:
		Game.count("time", delta)
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
	_update_deeds()
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

	_spawn_solar_field()
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
	_update_deeds()
	Sfx.ui(&"jingle_boss", -2.0, "Music")
	var truck := ElmoTruck.new()
	truck.position = ($WaveSpawner/SouthRoad as Node3D).global_position
	truck.objective = get_tree().get_first_node_in_group("player") as Node3D
	truck.wrecked.connect(_on_truck_wrecked)
	add_child(truck)
	truck.rotation.y = PI  # face north, up the road
	Game.set_objective("ELMO MUSHBRAINS rolls in with his Cyberdouche. Wreck it! (EMP won't hack this one.)")
	Game.tip("elmo_truck", "Elmo's Cyberdouche rams and charges a blue 'Beta Feature' shockwave. When the ring grows, get clear, then hit it while it's parked. Rockets, C4, and the rifle work best.")


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
	var room := get_node_or_null("CrapyaControlRoom") as Destructible
	if room and not room.is_destroyed:
		Game.set_objective("Fence down. Take out Crapya's glass control room (rifle or explosives), then C4 [G] the cooling units.")
	else:
		Game.set_objective("Fence down. Plant C4 [G] on the %d cooling units, then get clear."
			% _datacenter.cooling_remaining)


func _on_cooling_unit_destroyed(remaining: int) -> void:
	if remaining > 0:
		Game.set_objective("Cooling unit destroyed. %d left." % remaining)
	else:
		Game.set_objective("Cooling offline. The building is coming down!")


func _on_neutralized() -> void:
	Game.set_objective("Datacenter down. The air is clearing. (+$%d)" % _datacenter.cash_reward)
	# The collapse takes Crapya's control room (and her defenses) down with it.
	var room := get_node_or_null("CrapyaControlRoom") as Destructible
	if room and not room.is_destroyed:
		room.shatter(room.global_position + Vector3.UP * 2.0, 120.0)
	if boss_enabled:
		get_tree().create_timer(boss_delay).timeout.connect(start_boss)
	else:
		get_tree().create_timer(core_delay).timeout.connect(start_defense)


func _on_truck_wrecked(truck: ElmoTruck) -> void:
	var wreck := truck.global_position
	Game.set_objective("The Cyberdouche is scrap. Elmo climbs out, flamethrower in one hand, phone in the other. Hit him while he Twats!")
	# Give the wreck's explosion a moment before he climbs out beside it.
	await get_tree().create_timer(1.2).timeout
	var elmo := ElmoOnFoot.new()
	elmo.position = wreck + Vector3(3.5, 0.2, 0.0)
	elmo.objective = get_tree().get_first_node_in_group("player") as Node3D
	elmo.died.connect(_on_boss_defeated)
	add_child(elmo)


func _on_boss_defeated(_elmo: Enemy) -> void:
	get_tree().call_group(&"reply_guys", &"log_off")
	Game.district.trust += 0.15
	Game.set_objective("Elmo is out, logged off for good. The neighbors are coming to build.")
	get_tree().create_timer(core_delay).timeout.connect(start_defense)


## Shows the first live member of group "bosses" (any node with boss_name,
## health, max_health). Clears the line once none are left.
func _update_boss_bar() -> void:
	var boss: Node = null
	for node in get_tree().get_nodes_in_group("bosses"):
		var alive: bool = (node as Enemy).is_alive() if node is Enemy else not (node as Destructible).is_destroyed
		if alive:
			boss = node
			break
	if boss == null:
		if _boss_bar_shown:
			_boss_bar_shown = false
			Game.set_info("boss", "")
		return
	_boss_bar_shown = true
	var ratio := clampf(float(boss.get("health")) / float(boss.get("max_health")), 0.0, 1.0)
	var filled := roundi(ratio * 30.0)
	var bar := "#".repeat(filled) + "-".repeat(30 - filled)
	var extra := ""
	if boss is ElmoOnFoot and (boss as ElmoOnFoot).is_posting:
		extra = "   TWATTING: x2.5 damage!"
	elif boss is ShamCrapman and (boss as ShamCrapman).is_field_shielded():
		extra = "   FORCE FIELD: shoot the drones!"
	elif boss is FarkPod and (boss as FarkPod).is_tracking():
		extra = "   TRACKED: shoot the surveillance drones!"
	elif boss is HarryPerckerson and not (boss as HarryPerckerson).is_exposed():
		extra = "   BEHIND GLASS: heavy explosives only!"
	elif boss is CrapyaControlRoom:
		extra = "   bullets bounce: rifle, explosives, or the dozer"
	Game.set_info("boss", "%s  [%s]%s" % [boss.get("boss_name"), bar, extra])


## Phase 1 rewards. Trust gains shrink while the datacenter's noise saps morale.
func _complete_deed(key: String, cash: int, trust: float, text: String) -> void:
	if _deeds.get(key, true):
		return
	_deeds[key] = true
	Game.count("deeds")
	Sfx.ui(&"jingle_deed", -6.0, "Music")
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


## Security stands down until the player attacks the site: hurting a guard,
## dog, truck, or sentry, or hitting the fence, walls, turbines, cooling
## units, or Crapya's control room raises the alarm.
func _arm_site_security() -> void:
	add_to_group("site_alarm")
	for unit_name in site_security_nodes:
		var unit := get_node_or_null(unit_name) as Enemy
		if unit:
			unit.site_security = true
	var property: Array[Node] = [_datacenter, get_node_or_null("CrapyaControlRoom")]
	for child in get_children():
		if child is FenceLine:
			property.append(child)
	for root in property:
		if root == null:
			continue
		if root is Destructible:
			(root as Destructible).site_property = true
		for node in root.find_children("*", "", true, false):
			if node is Destructible:
				(node as Destructible).site_property = true


## Everyone on the site's payroll engages. Idempotent. Public for tests.
func raise_alarm(reason := "") -> void:
	if Game.alarm:
		return
	Game.alarm = true
	Game.notify("ALARM! You hit the %s. Felsa security is engaging: guards, dogs, the Cyberdouche, and the roof water cannons."
		% (reason.to_lower() if not reason.is_empty() else "site"), 7.0)
	Sfx.play(&"alarm", _datacenter.global_position + Vector3.UP * 9.0, 8.0, 1.0, 0.0)
	Game.tip("alarm", "The alarm is up. Roof water cannons soak and shove you: take out the gas turbines to cut their power, or break Crapya's control room.")


func _spawn_grock_cameras() -> void:
	for spot in grock_camera_spots:
		var camera := GrockCamera.new()
		camera.position = Vector3(spot.x, spot.y, spot.z)
		camera.rotation.y = spot.w
		add_child(camera)
		camera.smashed.connect(_on_grock_camera_smashed)
	_cameras_total = grock_camera_spots.size()


func _on_grock_camera_smashed(camera: GrockCamera) -> void:
	_cameras_smashed += 1
	var left := _cameras_total - _cameras_smashed
	Game.notify("Grock camera smashed: +$%d, the neighbors approve. %s" % [camera.reward,
		("%d left on the block." % left) if left > 0 else "The block is Grock-free!"])
	_update_deeds()


func _update_deeds() -> void:
	if phase != Phase.ACTIVISM:
		Game.set_info("deeds", "")
		return
	var marks := {}
	for key: String in _deeds:
		marks[key] = "x" if _deeds[key] else " "
	Game.set_info("deeds", "Deeds:  [%s] Fix the water main [F]   [%s] Stop the supply van   [%s] Tame the strays %d/2 [T]   [%s] Scout the datacenter   Grock cams %d/%d"
		% [marks["water"], marks["van"], marks["dogs"], mini(_dogs_tamed, 2), marks["scout"], _cameras_smashed, _cameras_total])


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
	Sfx.ui(&"jingle_wave", -4.0, "Music")
	_auto_wave_left = -1.0
	Game.set_info("wave", "Wave %d/%d" % [number, total])
	if has_planned_breach():
		Game.set_info("wave", "Wave %d/%d: they cut through the %s fence!" % [number, total, _breach_side])
		_execute_breach()
	Game.set_objective("Wave %d/%d incoming. Hold the line!" % [number, total])


func _on_wave_cleared(number: int, total: int) -> void:
	if phase == Phase.LOST:
		return
	_waves_cleared = number
	if number >= total:
		return  # _on_all_waves_cleared handles the finale
	Sfx.ui(&"jingle_clear", -4.0, "Music")
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
	# Harry's hires: their contracts are void. Everyone left goes home.
	for node in get_tree().get_nodes_in_group("hostiles"):
		(node as Enemy).apply_damage(99999.0, (node as Node3D).global_position, &"explosive")
	Game.district.trust = 1.0
	Game.district.water_table = 1.0
	Game.set_info("wave", "")
	Game.set_objective("Zone held! Water is flowing and the neighborhood is yours.")
	_waves_cleared = _spawner.total_waves()
	get_tree().create_timer(3.0).timeout.connect(_show_end.bind(true))


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


## The green datacenter's solar field: rows of arrays behind the core, on the
## lot the turbines used to occupy.
func _spawn_solar_field() -> void:
	var center := core.global_position
	for dz in [-9.0, -12.5, -16.0]:
		for dx in [-12.0, -7.5, -3.0, 1.5, 6.0, 10.5]:
			var array := SolarArray.new()
			array.position = Vector3(center.x + dx, 0.0, center.z + dz)
			add_child(array)
	get_tree().call_group(&"nav_baker", &"request_rebake")


func _spawn_townspeople(count: int) -> void:
	for i in count:
		var person := Townsperson.new()
		person.objective = core
		person.position = _nearest_doors()[i % 4] + Vector3(randf_range(-1.0, 1.0), 0.0, 0.0)
		person.abducted.connect(_on_townsperson_abducted)
		add_child(person)
		# Home is the core, so idle neighbors hang around the site.
		person.home = core.global_position + Vector3(randf_range(-6.0, 6.0), 0.0, 8.0)


## The four front doors closest to the datacenter site (quickest to arrive).
func _nearest_doors() -> Array[Vector3]:
	var doors := ($Neighborhood as NeighborhoodBuilder).door_positions().duplicate()
	var site := _datacenter.global_position
	doors.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(site) < b.distance_to(site))
	return doors.slice(0, 4)


func _on_townsperson_abducted(_person: Townsperson) -> void:
	Game.set_info("wave", "FROST took a neighbor! Trust falling.")


func _show_end(won: bool) -> void:
	if is_inside_tree():
		_end_screen.show_result(won, _waves_cleared, _spawner.total_waves())


func _on_core_damaged(_amount: float, health: float) -> void:
	Game.set_info("core", "Green datacenter  %d / %d" % [maxi(ceili(health), 0), int(core.max_health)])


func _on_core_destroyed(_core: Destructible) -> void:
	phase = Phase.LOST
	_build.enabled = false
	_build.set_active(false)
	Game.district.smog += 0.6
	Game.set_info("core", "")
	Game.set_objective("The green datacenter fell. Press [Enter] to retry.")
	get_tree().create_timer(3.0).timeout.connect(_show_end.bind(false))
