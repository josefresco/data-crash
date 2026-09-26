extends Node3D
## Vertical-slice test level: one suburb, three corporate datacenters.
## Phase 1 (ACTIVISM): optional good deeds for cash and trust; attacking any
## site (or breaching a fence) ends it.
## Phase 2 (ASSAULT): take down Felsa Cloud (north, Elmo inside, his
## Cyberdouche at the dock), Scgrewgle (west, Crapya's control room), and
## ForProfitSI (east, Sham Crapman), in any order. Each DatacenterSite is
## cleared when its building collapses and its boss is down.
## Phase 3 (BUILD / WAVE): the green datacenter goes up on the Felsa lot; defend it.
## (BOSS is unused, kept so saved references and tests keep their values.)

enum Phase { ACTIVISM, ASSAULT, BOSS, BUILD, WAVE, WON, LOST }

## Seconds between the collapse and the green core going up (lets debris settle).
@export var core_delay := 3.0
## Bosses inside the datacenters. Tests that skip to Phase 3 turn this off.
@export var boss_enabled := true
## Seconds of build time before the next wave starts on its own.
@export var auto_wave_delay := 45.0
## Neighbors who join the repair crew: base + trust * per_trust.
@export var townspeople_base := 2
@export var townspeople_per_trust := 4.0
## Grock surveillance cameras on the block (position, yaw). Smash them for cash and trust.
@export var grock_camera_spots: Array[Vector4] = [
	Vector4(7.6, 0, 8, PI), Vector4(-7.6, 0, 56, 0), Vector4(7.6, 0, 88, PI), Vector4(-46, 0, 24.6, -PI * 0.5),
	Vector4(18, 0, 35.4, PI * 0.5), Vector4(50, 0, 24.6, -PI * 0.5), Vector4(-30, 0, 75.4, PI * 0.5),
	Vector4(-30, 0, 115.4, PI * 0.5), Vector4(50, 0, 104.6, -PI * 0.5), Vector4(7.6, 0, 124, PI),
]
## Grandmas who need help across the street: [start, destination].
@export var old_lady_spots: Array = [
	[Vector3(-6.8, 0.1, 46.0), Vector3(6.8, 0.0, 46.0)],
	[Vector3(-20.0, 0.1, 64.8), Vector3(-20.0, 0.0, 75.2)],
]
## The house getting repainted: the builder door nearest this point.
@export var paint_job_near := Vector3(30.0, 0.0, 24.0)
## Litter to clean up (walk over it).
@export var litter_spots: Array[Vector3] = [
	Vector3(-12, 0, 33.5), Vector3(8, 0, 24.5), Vector3(-26, 0, 24.8), Vector3(36, 0, 35.2),
	Vector3(-50, 0, 55), Vector3(-34, 0, 62), Vector3(-18, 0, 58), Vector3(5.5, 0, 52),
	Vector3(-5.5, 0, 64), Vector3(46, 0, 63), Vector3(18, 0, 75.5), Vector3(-44, 0, 75.4),
	Vector3(-5.8, 0, 118), Vector3(30, 0, 115.3), Vector3(-52, 0, 104.8), Vector3(5.8, 0, 140),
]
## [kind, position] of the weapon pickups (WeaponPickup) around the block.
@export var pickup_spots: Array = [
	[&"shovel", Vector3(-8.5, 0.0, 22.5)], [&"shovel", Vector3(24.0, 0.0, 56.0)], [&"shovel", Vector3(-44.0, 0.0, 60.0)],
	[&"rocks", Vector3(-10.0, 0.0, 26.0)], [&"rocks", Vector3(-30.0, 0.0, 57.0)], [&"rocks", Vector3(40.0, 0.0, 61.0)],
	[&"rocks", Vector3(22.0, 0.0, 37.5)], [&"molotovs", Vector3(28.0, 0.0, 60.0)],
]
## Fence lines corporate crews cut through at the start of waves 2+.
@export var breach_fences: Array[String] = ["FelsaSite/FenceLeft", "FelsaSite/FenceRight", "FelsaSite/FenceBack"]
## Panels cut per breach.
@export var breach_width := 2
## First wave that opens a new lane. Announced (with a flare) a build phase ahead.
@export var breach_from_wave := 3

var phase := Phase.ACTIVISM
var core: GreenCore

var _fence_breached := false
## The three DatacenterSites; the green core goes up on the Felsa lot.
var sites: Array[DatacenterSite] = []
var _felsa: DatacenterSite
var _auto_wave_left := -1.0
var _planned_breach: Array[Destructible] = []
var _breach_side := ""
var _breach_flare: Node3D
var _boss_bar_shown := false
var _deeds := {"water": false, "van": false, "dogs": false, "scout": false, "ladies": false, "paint": false, "litter": false}
var _dogs_tamed := 0
var _cameras_total := 0
var _ladies_total := 0
var _ladies_helped := 0
var _litter_total := 0
var _litter_left := 0
var _end_screen: EndScreen
var _waves_cleared := 0
var _cameras_smashed := 0

@onready var _env_driver: EnvironmentDriver = $EnvironmentDriver
@onready var _spawner: WaveSpawner = $WaveSpawner
@onready var _build: BuildController = $BuildController


func _ready() -> void:
	Game.reset()

	_env_driver.world_environment = $WorldEnvironment
	_env_driver.sun = $Sun
	_env_driver.ground = $Ground/Mesh

	add_to_group("site_alarm")
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		var site := node as DatacenterSite
		sites.append(site)
		if site.site_id == &"felsa":
			_felsa = site
		_connect_site(site)
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
	_spawn_pickups()
	_spawn_neighborly_deeds()
	var tips := TipDirector.new()
	tips.level = self
	add_child(tips)
	add_child(PauseMenu.new())
	_end_screen = EndScreen.new()
	add_child(_end_screen)
	_update_deeds()
	_update_sites()

	Game.set_objective("Three datacenters are draining the block: Felsa Cloud (north), Scgrewgle (west), and ForProfitSI (east), each with a boss inside. Help the neighbors first (optional), then hit them.")


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
	var lot := _felsa.datacenter.global_position if _felsa else Vector3.ZERO
	core.position = Vector3(lot.x, 0.0, lot.z)
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


## Debug and tests: sets off the Felsa alarm (Elmo runs for his truck).
func start_boss() -> void:
	raise_alarm(&"felsa", "test")


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


func site(id: StringName) -> DatacenterSite:
	for candidate in sites:
		if candidate.site_id == id:
			return candidate
	return null


func _connect_site(site_node: DatacenterSite) -> void:
	var building := site_node.datacenter
	site_node.fence_breached.connect(func(_s: DatacenterSite) -> void: _on_fence_breached(site_node))
	building.cooling_unit_destroyed.connect(func(remaining: int) -> void:
		if remaining > 0:
			Game.set_objective("%s: cooling unit destroyed. %d left." % [site_node.display_name, remaining])
		else:
			Game.set_objective("%s: cooling offline. The building is coming down!" % site_node.display_name))
	building.turbine_destroyed.connect(func(remaining: int) -> void:
		if phase == Phase.ACTIVISM or phase == Phase.ASSAULT:
			Game.set_objective(("%s: gas turbine down, less smog and noise. (+$%d)  %d left." % [site_node.display_name,
				building.turbine_cash, remaining]) if remaining > 0 else "%s: all gas turbines down." % site_node.display_name))
	if site_node.boss == DatacenterSite.Boss.CRAPYA:
		building.power_cut.connect(func() -> void:
			Game.set_objective("Scgrewgle's power is cut! Crapya's water cannons, vents, and crushers are dead. Her control room still shields the cooling units."))
	if site_node.crapya_room:
		site_node.crapya_room.defenses_offline.connect(func() -> void:
			Game.set_objective("Crapya's control room is down: Scgrewgle's defenses are offline and its cooling units exposed. (+$300)"))
	if site_node.elmo_truck:
		site_node.elmo_truck.wrecked.connect(_on_truck_wrecked)
	if site_node.elmo:
		site_node.elmo.died.connect(_on_boss_defeated)
	if site_node.sham:
		site_node.sham.died.connect(func(_e: Enemy) -> void:
			Game.set_objective("Sham Crapman is down: \"This is just a pivot.\" (+$400)"))
	site_node.neutralized.connect(func(_s: DatacenterSite) -> void:
		Game.set_objective("%s is down. The air is clearing. (+$%d)%s" % [site_node.display_name, site_node.cash_reward,
			"" if site_node.boss_defeated else "  %s is still loose!" % site_node.boss_label()])
		_update_sites())
	site_node.cleared.connect(_on_site_cleared)


func _on_fence_breached(site_node: DatacenterSite) -> void:
	raise_alarm(site_node.site_id, "fence")
	if _fence_breached or (phase != Phase.ACTIVISM and phase != Phase.ASSAULT):
		return
	_fence_breached = true
	_start_assault()
	if site_node.crapya_room and not site_node.crapya_room.is_destroyed:
		Game.set_objective("Fence down. Crapya's glass control room inside Scgrewgle shields the cooling units: rifle or explosives, then C4 [G] the units.")
	else:
		Game.set_objective("Fence down at %s. Plant C4 [G] on its %d cooling units, then get clear."
			% [site_node.display_name, site_node.datacenter.cooling_remaining])


func _start_assault() -> void:
	if phase == Phase.ACTIVISM:
		phase = Phase.ASSAULT
		_update_deeds()


## A site is done when its building is down and its boss is out. All three
## done: the neighbors build the green datacenter on the Felsa lot.
func _on_site_cleared(site_node: DatacenterSite) -> void:
	_update_sites()
	var left := sites.filter(func(s: DatacenterSite) -> bool: return not s.is_cleared)
	if left.is_empty():
		Game.set_objective("All three datacenters are down! The neighbors are coming to build.")
		get_tree().create_timer(core_delay).timeout.connect(start_defense)
	else:
		Game.set_objective("%s is finished. Still standing: %s." % [site_node.display_name,
			", ".join(left.map(func(s: DatacenterSite) -> String: return s.display_name))])


func _update_sites() -> void:
	if phase != Phase.ACTIVISM and phase != Phase.ASSAULT:
		Game.set_info("sites", "")
		return
	var parts: Array[String] = []
	for site_node in sites:
		var status := "quiet"
		if site_node.is_cleared:
			status = "DOWN"
		elif site_node.is_neutralized:
			status = "boss loose"
		elif site_node.is_alarmed():
			status = "ALARM"
		parts.append("%s: %s" % [site_node.display_name, status])
	Game.set_info("sites", "Datacenters   " + "   ".join(parts))


func _on_truck_wrecked(truck: ElmoTruck) -> void:
	var wreck := truck.global_position
	var felsa := site(&"felsa")
	# Wrecked before he got in: the Elmo inside is the on-foot fight.
	if felsa and is_instance_valid(felsa.elmo) and felsa.elmo.is_alive():
		felsa.elmo.ride = null
		Game.set_objective("His Cyberdouche is scrap. Elmo's on foot, flamethrower in one hand, phone in the other. Hit him while he Twats!")
		return
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
	Game.set_objective("Elmo is out, logged off for good.")
	var felsa := site(&"felsa")
	if felsa:
		felsa.mark_boss_defeated()


## Shows the first live member of group "bosses" (any node with boss_name,
## health, max_health). Clears the line once none are left.
func _update_boss_bar() -> void:
	var boss: Node = null
	for node in get_tree().get_nodes_in_group("bosses"):
		var alive: bool = (node as Enemy).is_alive() if node is Enemy else not (node as Destructible).is_destroyed
		# Bosses waiting inside a quiet datacenter don't get a bar yet.
		var waiting: bool = (node as Enemy).is_dormant() or (node is ElmoTruck and (node as ElmoTruck).parked) if node is Enemy \
			else (node as Destructible).site_id != &"" and not Game.is_alarmed((node as Destructible).site_id)
		if alive and not waiting:
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


## Everyone on `site_id`'s payroll engages. Idempotent. Group "site_alarm"
## routes hits on site units and property here.
func raise_alarm(site_id: StringName, reason := "") -> void:
	if Game.is_alarmed(site_id):
		return
	Game.alarms[site_id] = true
	var site_node := site(site_id)
	var site_name := site_node.display_name if site_node else String(site_id)
	Game.notify("ALARM at %s! You hit the %s. Its security is engaging." % [site_name,
		reason.to_lower() if not reason.is_empty() else "site"], 7.0)
	if site_node:
		Sfx.play(&"alarm", site_node.datacenter.global_position + Vector3.UP * 11.0, 8.0, 1.0, 0.0)
		if site_node.boss == DatacenterSite.Boss.CRAPYA:
			Game.tip("alarm", "Scgrewgle's roof water cannons soak and shove you: take out its gas turbines to cut their power, or break Crapya's control room.")
		elif site_node.boss == DatacenterSite.Boss.ELMO:
			Game.tip("alarm_elmo", "Elmo's making a run for his Cyberdouche at the back dock. Catch him first, or wreck the truck.")
	_start_assault()
	_update_sites()


## Old ladies to walk across, a house to repaint, and litter to pick up.
func _spawn_neighborly_deeds() -> void:
	for spot: Array in old_lady_spots:
		var lady := OldLady.new()
		lady.position = spot[0]
		lady.destination = spot[1]
		lady.rotation.y = PI * 0.5
		add_child(lady)
		lady.crossed.connect(_on_lady_crossed)
	_ladies_total = old_lady_spots.size()

	var doors := ($Neighborhood as NeighborhoodBuilder).door_positions()
	if not doors.is_empty():
		var door := doors[0]
		for candidate in doors:
			if candidate.distance_to(paint_job_near) < door.distance_to(paint_job_near):
				door = candidate
		var job := PaintJob.new()
		job.name = "PaintJob"
		job.position = Vector3(door.x, 0.0, door.z)
		# -Z toward the house: doors north of a street face +Z (house behind them at -Z).
		var street := 0.0
		for z: float in ($Neighborhood as NeighborhoodBuilder).street_z:
			if absf(z - door.z) < absf(street - door.z) or street == 0.0:
				street = z
		job.rotation.y = 0.0 if door.z < street else PI
		add_child(job)
		job.fixed.connect(func(_j: PaintJob) -> void:
			_complete_deed("paint", 75, 0.06, "House repainted. The Parkers are thrilled. (+$75)"))

	for spot in litter_spots:
		var piece := Litter.new()
		piece.position = spot
		add_child(piece)
		piece.collected.connect(_on_litter_collected)
	_litter_total = litter_spots.size()
	_litter_left = _litter_total


func _on_lady_crossed(_lady: OldLady) -> void:
	_ladies_helped += 1
	Game.add_cash(25)
	Game.district.trust += 0.02
	if _ladies_helped >= _ladies_total:
		_complete_deed("ladies", 50, 0.05, "Every grandma made it across. (+$50)")
	else:
		Game.notify("Helped a grandma across the street. (+$25)")
		_update_deeds()


func _on_litter_collected(_piece: Litter) -> void:
	_litter_left -= 1
	if _litter_left == _litter_total - 1:
		Game.tip("litter", "Walk over litter to pick it up. Clear all of it for a good deed.")
	if _litter_left <= 0:
		_complete_deed("litter", 40, 0.05, "The block is spotless. (+$40)")
	else:
		_update_deeds()


## The player starts with bare hands: shovels, rock piles, and a crate of
## bottles and gas lie around the block. Guns come from the gun show.
func _spawn_pickups() -> void:
	for spot: Array in pickup_spots:
		var pickup := WeaponPickup.new()
		pickup.kind = spot[0]
		pickup.position = spot[1]
		add_child(pickup)


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
	Game.set_info("deeds", "Deeds:  [%s] Water main [F]   [%s] Supply van   [%s] Strays %d/2 [T]   [%s] Scout the datacenter   [%s] Grandmas %d/%d [E]   [%s] Paint a house [F]   [%s] Litter %d/%d   Grock cams %d/%d"
		% [marks["water"], marks["van"], marks["dogs"], mini(_dogs_tamed, 2), marks["scout"], marks["ladies"], _ladies_helped,
			_ladies_total, marks["paint"], marks["litter"], _litter_total - _litter_left, _litter_total, _cameras_smashed, _cameras_total])


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
		_breach_side = fence_name.get_file().trim_prefix("Fence").to_lower()
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
	var lot := core.global_position
	doors.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(lot) < b.distance_to(lot))
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
