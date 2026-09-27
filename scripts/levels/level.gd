class_name Level
extends Node3D
## One district: a neighborhood, three corporate datacenters, and the
## defense. Everything map-specific is an export (group "District") or a
## node in the district's scene, so each district is a scene using this
## script. District 1 is scenes/levels/test_block.tscn (the defaults below).
## Phase 1 (ACTIVISM): optional good deeds for cash and trust; attacking any
## site (or breaching a fence) ends it.
## Phase 2 (ASSAULT): take down Felsa Cloud (north, Elmo inside, his
## Cyberdouche at the dock), Scgrewgle (west, Crapya's control room), and
## ForProfitSI (east, Sham Crapman), in any order. Each DatacenterSite is
## cleared when its building collapses and its boss is down.
## Phase 3 (BUILD / WAVE): the green datacenter goes up on the `defense_site` lot; defend it.
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
@export var paint_job_near := Vector3(46.0, 0.0, 24.0)
## Litter to clean up (walk over it).
@export var litter_spots: Array[Vector3] = [
	Vector3(-12, 0, 33.5), Vector3(8, 0, 24.5), Vector3(-26, 0, 24.8), Vector3(36, 0, 35.2),
	Vector3(-50, 0, 55), Vector3(-34, 0, 62), Vector3(-18, 0, 62.5), Vector3(5.5, 0, 52),
	Vector3(-5.5, 0, 64), Vector3(46, 0, 63), Vector3(18, 0, 75.5), Vector3(-44, 0, 75.4),
	Vector3(-5.8, 0, 118), Vector3(30, 0, 115.3), Vector3(-52, 0, 104.8), Vector3(5.8, 0, 140),
]
## Neighbors strolling the block at the start, and how many more come out
## once trust reaches 50%.
@export var resident_count := 24
@export var resident_bonus := 12
## Lost Canadian tourists: the first RV shows up this many seconds in, then
## one every `tourist_interval`, at most `tourist_groups` in all.
@export var tourist_first := 90.0
@export var tourist_interval := 240.0
@export var tourist_groups := 3
## Where the RVs pull over (main-road shoulder), in rotation.
## The player's house is the one nearest this point (they spawn and respawn
## on its front walk, facing the street).
@export var home_near := Vector3(-5.0, 0.0, 20.0)
## Seconds between a datacenter alarm and the police cruiser being sent.
@export var police_response_delay := 30.0
## Most recruited Canadians with you at once: a new RV (up to 3 aboard)
## only comes while that still fits.
@export var tourist_ally_cap := 5
@export var tourist_stops: Array[Vector3] = [Vector3(3.8, 0.2, 92.0), Vector3(-3.8, 0.2, 52.0), Vector3(3.8, 0.2, 122.0)]
## The farmer's market stalls in the park (where the gun show used to be).
@export var market_position := Vector3(-24.0, 0.0, 58.0)
## [kind, position] of the weapon pickups (WeaponPickup) around the block.
@export var pickup_spots: Array = [
	[&"shovel", Vector3(24.0, 0.0, 56.0)], [&"shovel", Vector3(-44.0, 0.0, 60.0)],
	[&"rocks", Vector3(-50.0, 0.0, 60.0)], [&"rocks", Vector3(40.0, 0.0, 61.0)],
	[&"rocks", Vector3(22.0, 0.0, 37.5)], [&"molotovs", Vector3(28.0, 0.0, 60.0)],
]
## Fence lines corporate crews cut through at the start of waves 2+.
@export var breach_fences: Array[String] = ["FelsaSite/FenceLeft", "FelsaSite/FenceRight", "FelsaSite/FenceBack"]
## Panels cut per breach.
@export var breach_width := 2
## First wave that opens a new lane. Announced (with a flare) a build phase ahead.
@export var breach_from_wave := 3

@export_group("District")
## The site whose lot the green datacenter goes up on in Phase 3.
@export var defense_site_id := &"felsa"
## The opening objective line.
@export_multiline var intro_objective := "Three datacenters are draining the block: Felsa Cloud (north), Scgrewgle (west), and ForProfitSI (east), each with a boss inside. Help the neighbors first (optional), then hit them."
## The patrol cruiser's loop, and the street (z) it starts on by the station.
@export var police_patrol: Array[Vector3] = [Vector3(2.5, 0.2, -2), Vector3(2.5, 0.2, 28), Vector3(62, 0.2, 28),
	Vector3(62, 0.2, 32), Vector3(-62, 0.2, 32), Vector3(-62, 0.2, 28), Vector3(-2.5, 0.2, 28)]
@export var police_street_z := 28.0
## road_route(): the cross street (z) cruisers take, the main road's lanes
## (x = +-route_main_x), and |x| beyond which a site is reached along the
## cross street instead of up the main road.
@export var route_street_z := 30.0
@export var route_main_x := 2.5
@export var route_far_x := 90.0
## Where the tourists' camper enters and leaves the map.
@export var tourist_entry := Vector3(2.5, 0.2, 165.0)
@export var tourist_exit := Vector3(2.5, 0.2, 170.0)
## Heavy equipment: [x, y, z, yaw] for the fire truck (keys for capping the
## hydrant), the garbage truck (keys for clearing the litter), and the road
## roller at the construction site (trust-locked like the dozer).
@export var fire_truck_spot := Vector4(12.0, 0.8, 73.0, -PI * 0.5)
@export var garbage_truck_spot := Vector4(-70.0, 0.8, 73.0, PI * 0.5)
@export var roller_spot := Vector4(33.0, 0.8, 57.0, PI)
@export var roller_trust := 0.25
## Park spots residents stroll to.
@export var park_spots: Array[Vector3] = [Vector3(-50, 0.2, 60), Vector3(-36, 0.2, 60), Vector3(-24, 0.2, 60)]
@export_group("")

var phase := Phase.ACTIVISM:
	set(value):
		if value != phase:
			phase = value
			_announce_phase()
var core: GreenCore

var _fence_breached := false
## The three DatacenterSites; the green core goes up on the Felsa lot.
var sites: Array[DatacenterSite] = []
var _defense_site: DatacenterSite
var _auto_wave_left := -1.0
var _planned_breach: Array[Destructible] = []
## Where this wave's fence breach was cut (Vector3.INF = none): allies hold it.
var _breach_hold := Vector3.INF
var _breach_side := ""
var _breach_flare: Node3D
var _boss_bar_shown := false
var _deeds := {"water": false, "van": false, "dogs": false, "scout": false, "ladies": false, "paint": false, "litter": false}
var _dogs_tamed := 0
var _cameras_total := 0
var _residents_bonus_spawned := false
var _tourist_left := 0.0
var _tourists_sent := 0
var _ladies_total := 0
var _ladies_helped := 0
var _litter_total := 0
var _litter_left := 0
var _end_screen: EndScreen
var _waves_cleared := 0
## Continue: the Felsa lot's position once the sites are removed.
var _lot_override := Vector3.INF
## Stats at the start of the current wave (for the summary card).
var _wave_start := {}
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
	add_to_group("level")
	if Game.pending_intro:
		Game.pending_intro = false
		add_child(IntroOverlay.new())
	if not Game.pending_save.is_empty():
		var save := Game.pending_save
		Game.pending_save = {}
		_resume.call_deferred(save)
	var life := GroundLife.new()
	life.name = "GroundLife"
	add_child(life)
	life.setup($Neighborhood as NeighborhoodBuilder)
	($Player as Player).respawned.connect(_on_player_respawned)
	Sfx.music(&"calm")
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		var site := node as DatacenterSite
		sites.append(site)
		if site.site_id == defense_site_id:
			_defense_site = site
		_connect_site(site)
	_spawner.wave_started.connect(_on_wave_started)
	_spawner.wave_cleared.connect(_on_wave_cleared)
	_spawner.all_waves_cleared.connect(_on_all_waves_cleared)

	var water_main := get_node_or_null("WaterMain") as WaterMain
	if water_main:
		water_main.fixed.connect(func(_m: WaterMain) -> void:
			_complete_deed("water", 100, 0.1, "Hydrant capped. The Hendersons have water pressure again. (+$100)")
			_give_fire_hose())
	else:
		_deeds.erase("water")
	_place_scout_points()
	if get_tree().get_nodes_in_group("scout_points").is_empty():
		_deeds.erase("scout")
	var van := get_node_or_null("SupplyVan") as Enemy
	if van:
		van.died.connect(func(_v: Enemy) -> void:
			_complete_deed("van", 0, 0.05, "Supply van intercepted. Cargo seized. (+$150)"))
	else:
		_deeds.erase("van")
	var strays := 0
	for dog_name in ["StrayDog1", "StrayDog2"]:
		var dog := get_node_or_null(dog_name) as Dog
		if dog:
			dog.defeated.connect(_on_stray_dog_defeated)
			strays += 1
	if strays < 2:
		_deeds.erase("dogs")
	($BribeMenu as BribeMenu).bribe_bought.connect(_on_bribe_bought)
	_spawn_grock_cameras()
	_spawn_pickups()
	_spawn_hardware_store()
	_spawn_police()
	_spawn_heavy_equipment()
	var market := FarmersMarket.new()
	market.name = "FarmersMarket"
	market.position = market_position
	add_child(market)
	_spawn_residents(resident_count)
	_tourist_left = tourist_first
	_spawn_neighborly_deeds()
	var tips := TipDirector.new()
	tips.level = self
	add_child(tips)
	add_child(PauseMenu.new())
	_end_screen = EndScreen.new()
	add_child(_end_screen)
	_update_deeds()
	_update_sites()

	if old_lady_spots.is_empty():
		_deeds.erase("ladies")
	if litter_spots.is_empty():
		_deeds.erase("litter")
	Game.set_objective(intro_objective)


func _process(delta: float) -> void:
	_tick_police_calls(delta)
	if phase != Phase.WON and phase != Phase.LOST:
		Game.count("time", delta)
	if phase in [Phase.ACTIVISM, Phase.ASSAULT, Phase.BUILD] and _tourists_sent < tourist_groups:
		_tourist_left -= delta
		if _tourist_left <= 0.0:
			_tourist_left = tourist_interval
			if canadian_allies() + 3 <= tourist_ally_cap:
				spawn_tourists()
	if not _residents_bonus_spawned and Game.district and Game.district.trust >= 0.5:
		_residents_bonus_spawned = true
		_spawn_residents(resident_bonus)
		Game.notify("Trust is up: more neighbors are coming outside again.", 4.0)
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
	var lot := _defense_lot()
	_clear_rubble_near(lot, 60.0)
	# Whatever is left of the executive suite on this lot goes too, with the
	# guards and dog posted in it.
	if _defense_site and is_instance_valid(_defense_site):
		if is_instance_valid(_defense_site.suite):
			_defense_site.suite.queue_free()
		for child in _defense_site.get_children():
			if child is Enemy and (child as Enemy).stay_put and (child as Enemy).boss_name.is_empty():
				child.queue_free()
	core = GreenCore.new()
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
	save_checkpoint()


## Where the player should head next (world space), or null. Drives the
## yellow objective marker on the minimap: grab a weapon at DUECE Hardware,
## then the nearest good deed, then the nearest standing datacenter (or its
## loose boss), then the green core.
## Where recruited allies hold when the player is off elsewhere during the
## defense: just inside the fence breach (announced or cut this wave), else
## the green core. Null outside BUILD/WAVE, or with no core.
func ally_post() -> Variant:
	if phase != Phase.BUILD and phase != Phase.WAVE:
		return null
	if core == null or not is_instance_valid(core) or core.is_destroyed:
		return null
	var gap := _breach_hold
	if phase == Phase.BUILD and has_planned_breach():
		gap = next_breach_point()
	if gap != Vector3.INF:
		var inward := core.global_position - gap
		inward.y = 0.0
		return gap + inward.normalized() * minf(4.0, inward.length())
	return core.global_position


func guidance_point() -> Variant:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	var here := player.global_position
	match phase:
		Phase.WAVE:
			# The last few hostiles: point at the nearest so the wave can end.
			if _spawner.remaining <= 3 and _spawner.queue_empty():
				var last: Variant = _spawner.nearest_remaining(here)
				if last != null:
					return last
			return core.global_position if is_instance_valid(core) else null
		Phase.BUILD:
			return core.global_position if is_instance_valid(core) else null
		Phase.WON, Phase.LOST:
			return null
	if phase == Phase.ACTIVISM:
		var armed := player.weapons.any(func(w: Weapon) -> bool: return w.owned and w.display_name != "Fists")
		if not armed and Game.has_meta(&"hardware_door"):
			return Game.get_meta(&"hardware_door")
		var targets: Array[Vector3] = []
		var main := get_node_or_null("WaterMain") as WaterMain
		if main and not main.is_fixed:
			targets.append(main.global_position)
		for node in get_tree().get_nodes_in_group("neighbors"):
			if node is OldLady and (node as OldLady).state == OldLady.State.WAITING:
				targets.append((node as Node3D).global_position)
		var job := get_node_or_null("PaintJob") as PaintJob
		if job and not job.is_fixed:
			targets.append(job.global_position)
		for node in get_tree().get_nodes_in_group("strays"):
			targets.append((node as Node3D).global_position)
		for node in get_tree().get_nodes_in_group("tourists"):
			if node is Canuck and (node as Canuck).state == Canuck.State.LOST:
				targets.append((node as Node3D).global_position)
		if not targets.is_empty():
			targets.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(here) < b.distance_to(here))
			return targets[0]
	var best: Variant = null
	for site_node in sites:
		if site_node.is_cleared:
			continue
		var point := site_node.at(Vector3(0.0, 0.0, site_node.compound.y * 0.5))
		if site_node.is_neutralized:
			for boss_node: Variant in [site_node.elmo, site_node.sham]:
				if is_instance_valid(boss_node):
					point = (boss_node as Node3D).global_position
		if best == null or point.distance_to(here) < (best as Vector3).distance_to(here):
			best = point
	return best


## Recruited Canadians still fighting with you.
func canadian_allies() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group("canadians"):
		if (node as Canuck).state == Canuck.State.ALLY and (node as Canuck).is_alive():
			total += 1
	return total


## Canadians help through one defense wave, then head home.
func _send_canadians_home() -> void:
	var leaving := 0
	for node in get_tree().get_nodes_in_group("canadians"):
		var tourist := node as Canuck
		if tourist.state == Canuck.State.ALLY:
			tourist.go_home(Vector3(2.5, 0.2, 165.0))
			leaving += 1
	if leaving > 0:
		Game.notify("The Canadians head home after the wave. \"Sorry we can't stay, eh!\"", 5.0)


## One vantage point per datacenter, just outside its front-left fence
## corner: any ScoutPoint placed in the scene (District 1: Felsa's tree),
## else a tree, or a rooftop for sites with `scout_rooftop`. All of them
## scouted completes the deed; each pays on its own.
func _place_scout_points() -> void:
	var points: Array[ScoutPoint] = []
	var covered := {}
	for child in get_children():
		if child is ScoutPoint:
			points.append(child as ScoutPoint)
			covered[(child as ScoutPoint).site_id] = true
	for site_node in sites:
		if covered.has(site_node.site_id):
			continue
		var point := ScoutPoint.new()
		point.name = "ScoutPoint_%s" % site_node.site_id
		point.site_id = site_node.site_id
		point.style = ScoutPoint.Style.ROOFTOP if site_node.scout_rooftop else ScoutPoint.Style.TREE
		var half := site_node.compound * 0.5
		add_child(point)
		point.global_position = site_node.at(Vector3(-(half.x - 4.0), 0.0, half.y + 4.0))
		point.global_rotation.y = site_node.global_rotation.y
		points.append(point)
	for point in points:
		point.scouted.connect(func(scouted_point: ScoutPoint) -> void:
			var done := get_tree().get_nodes_in_group("scout_points").filter(func(n: Node) -> bool:
				return (n as ScoutPoint).is_scouted).size()
			var total := get_tree().get_nodes_in_group("scout_points").size()
			Game.add_cash(50)
			if done >= total:
				_complete_deed("scout", 50, 0.05, "Every datacenter scouted: all cooling units marked. (+$100)")
			else:
				Game.notify("%s scouted: its cooling units are marked. (+$50, %d/%d)" % [
					scouted_point.call("_site_name"), done, total], 4.0)
			_update_deeds())


const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")


## The fire truck, the garbage truck, and the road roller (see the spots).
func _spawn_heavy_equipment() -> void:
	var fire := FireTruck.new_from_scene()
	fire.name = "FireTruck"
	fire.locked_hint = "cap the burst hydrant and the fire crew lends you their truck"
	_place_vehicle(fire, fire_truck_spot)
	var garbage := CAR_SCENE.instantiate() as Car
	garbage.name = "GarbageTruck"
	garbage.model_path = "res://assets/kenney/cars/garbage-truck.glb"
	garbage.model_scale = 1.7
	garbage.fit_to_model = true
	garbage.mass = 4500.0
	garbage.max_engine_force = 9000.0
	garbage.max_brake = 90.0
	garbage.max_speed = 12.0
	garbage.ram_min_speed = 2.5
	garbage.ram_damage_per_mps = 24.0
	garbage.max_health = 2000.0
	garbage.lower_center_of_mass = 0.3
	garbage.turbo_seconds = 0.0
	garbage.engine_cue = &"dozer_loop"
	garbage.locked_hint = "pick up all the litter and the sanitation crew lends you their truck"
	_place_vehicle(garbage, garbage_truck_spot)
	var roller := RoadRoller.new_from_scene()
	roller.name = "RoadRoller"
	roller.required_trust = roller_trust
	_place_vehicle(roller, roller_spot)
	# Deeds hand over the keys.
	var main := get_node_or_null("WaterMain") as WaterMain
	if main:
		main.fixed.connect(func(_m: WaterMain) -> void:
			fire.unlock()
			Game.notify("The fire crew tossed you the keys to their truck: [E] to drive, click to use the roof cannon.", 5.0))
	else:
		fire.unlock()
	if litter_spots.is_empty():
		garbage.unlock()


func _place_vehicle(vehicle: Car, spot: Vector4) -> void:
	vehicle.position = Vector3(spot.x, spot.y, spot.z)
	vehicle.rotation.y = spot.w
	add_child(vehicle)


## The fire department's thank-you for capping the hydrant.
func _give_fire_hose() -> void:
	var player := get_node_or_null("Player") as Player
	if player == null:
		return
	player.unlock_weapon("Fire hose")
	Game.notify("The fire crew left you their spare fire hose. [Q] to pick it: it knocks people flat and puts out fires.", 5.0)


## Spawn at home: the player's front walk, facing the street, with a HOME
## sign on the lawn (Game meta "home", minimap icon).
func _move_in() -> void:
	var spot := ($Neighborhood as NeighborhoodBuilder).home_spot(home_near)
	if spot.is_empty():
		return
	var door: Vector3 = spot[0]
	var facing: Vector3 = spot[1]
	facing.y = 0.0
	facing = facing.normalized()
	var player := $Player as Player
	var stand := door + facing * 1.5 + Vector3.UP * 0.1
	player.set_spawn(Transform3D(Basis.looking_at(facing, Vector3.UP), stand))
	Game.set_meta(&"home", stand)
	# A garden hose on a reel by the front walk.
	var hose := WeaponPickup.new()
	hose.name = "GardenHose"
	hose.kind = &"weapon"
	hose.gun_name = "Garden hose"
	hose.note = "Grabbed the garden hose. Good for fires, and for cooling people off."
	hose.respawn = 20.0
	add_child(hose)
	hose.global_position = door + facing * 1.2 - facing.cross(Vector3.UP) * 2.4
	var sign_root := Node3D.new()
	sign_root.name = "HomeSign"
	add_child(sign_root)
	sign_root.global_position = door + facing * 3.5 + facing.cross(Vector3.UP) * 2.2
	sign_root.global_basis = Basis.looking_at(-facing, Vector3.UP)
	var wood := Models.mat(Color(0.45, 0.32, 0.2))
	Models.box(sign_root, Vector3(0.1, 1.2, 0.1), Vector3(0.0, 0.6, 0.0), wood)
	var board := Models.box(sign_root, Vector3(1.4, 0.6, 0.06), Vector3(0.0, 1.25, 0.0), Models.mat(Color(0.95, 0.9, 0.7), &"paint"))
	var text := Label3D.new()
	text.text = "HOME\n(not for sale)"
	text.font_size = 56
	text.pixel_size = 0.007
	text.outline_size = 0
	text.modulate = Color(0.25, 0.4, 0.2)
	text.position = Vector3(0.0, 0.0, -0.04)
	text.rotation.y = PI
	Models.fit_label(text, Vector2(1.4, 0.6))
	board.add_child(text)


func scouted_count() -> int:
	return get_tree().get_nodes_in_group("scout_points").filter(func(n: Node) -> bool: return (n as ScoutPoint).is_scouted).size()


## An irrigation part broke or shut off: refresh the deeds line.
func on_irrigation_changed() -> void:
	_update_deeds()


## [off, total] irrigation parts across all sites.
func irrigation_status() -> Array:
	var total := 0
	var off := 0
	for site_node in sites:
		for part in site_node.irrigation:
			total += 1
			if not is_instance_valid(part) or not part.running or part.is_destroyed:
				off += 1
	return [off, total]


## Datacenter alarms waiting for a cruiser: site id -> seconds until dispatch.
var _police_calls := {}


func _tick_police_calls(delta: float) -> void:
	for id: StringName in _police_calls.keys():
		_police_calls[id] -= delta
		if _police_calls[id] > 0.0:
			continue
		_police_calls.erase(id)
		var site_node := site(id)
		if site_node and Game.is_alarmed(id):
			_dispatch_police(site_node)


## Seconds until the police arrive for `id` (-1 if none is pending). Tests.
func police_eta(id: StringName) -> float:
	return _police_calls.get(id, -1.0)


## Knocked out: like losing your wanted level. Alarms clear, security and
## police stop pursuing and go back to their posts, dispatched cruisers go
## back on patrol. Damage stays. Sites whose building is already down (boss
## loose) stay hot, and the defense waves don't stop.
func _on_player_respawned() -> void:
	Game.show_banner("KNOCKED OUT", "The heat's off. The damage stays.")
	if phase not in [Phase.ACTIVISM, Phase.ASSAULT]:
		return
	var cooled: Array[StringName] = []
	for id: StringName in Game.alarms.keys():
		var site_node := site(id)
		if site_node and site_node.is_neutralized:
			continue
		cooled.append(id)
	for id in cooled:
		Game.alarms.erase(id)
		_police_calls.erase(id)
	if cooled.is_empty():
		return
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit == null:
			continue
		if unit is PoliceCruiser and (unit as PoliceCruiser).respond_site in cooled:
			(unit as PoliceCruiser).recall()
		if unit.site in cooled:
			unit.stand_down()
	Game.notify("Security and police lost track of you. Lie low, or hit them again.", 6.0)
	_update_sites()


## The defense is built on the Felsa lot: haul away its settled rubble.
func _clear_rubble_near(center: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group("rubble"):
		if (node as Node3D).global_position.distance_to(center) < radius:
			node.queue_free()


## Where Phase 3 is built: the defense site's lot (remembered if the site is gone).
func _defense_lot() -> Vector3:
	if _lot_override != Vector3.INF:
		return _lot_override
	return _defense_site.datacenter.global_position if _defense_site and is_instance_valid(_defense_site) else Vector3.ZERO


## Name of the site the defense happens on (end screen, tips).
func defense_site_name() -> String:
	return _defense_site.display_name if _defense_site and is_instance_valid(_defense_site) else "the datacenter"


## The site whose boss is `boss` (Elmo's truck and the on-foot fight).
func _boss_site(boss: DatacenterSite.Boss) -> DatacenterSite:
	for site_node in sites:
		if is_instance_valid(site_node) and site_node.boss == boss:
			return site_node
	return null


## Player-built pieces (not the core or the auto solar field), for saving.
func _built_structures() -> Array:
	var built := []
	var kinds := [Barricade, Turret, SolarPanel, EmpTrap]
	for node in get_tree().get_nodes_in_group("structures") + get_tree().get_nodes_in_group("traps"):
		if node is GreenCore or node is SolarArray or not is_instance_valid(node):
			continue
		for index in kinds.size():
			if is_instance_of(node, kinds[index]) and not (index == 2 and node is SolarArray):
				var piece := node as Node3D
				var steps := posmod(roundi(piece.rotation.y / (PI * 0.5)), 4)
				var hp: float = node.get("health") if node.get("health") != null else 0.0
				built.append([index, piece.global_position.x, piece.global_position.y, piece.global_position.z, steps, hp])
				break
	return built


## Writes the defense checkpoint (see SaveGame).
func save_checkpoint() -> void:
	var district := Game.district
	SaveGame.write({
		"waves_cleared": _spawner.current_wave,
		"cash": Game.cash,
		"district": [district.smog, district.noise, district.water_table, district.trust],
		"bribes": Game.bribes.keys(),
		"stats": Game.stats,
		"core_health": core.health if is_instance_valid(core) else 0.0,
		"structures": _built_structures(),
		"difficulty": Game.difficulty,
	})


## Continue: skip straight to the defense on the (already fallen) Felsa lot
## and restore the checkpoint.
func _resume(save: Dictionary) -> void:
	_lot_override = _defense_lot()
	for site_node in sites:
		site_node.queue_free()
	sites.clear()
	_defense_site = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and unit.site != &"police":
			unit.queue_free()
	await get_tree().process_frame
	start_defense()
	Game.cash = int(save.get("cash", Game.cash))
	Game.cash_changed.emit(Game.cash)
	var values: Array = save.get("district", [])
	if values.size() == 4:
		Game.district.smog = values[0]
		Game.district.noise = values[1]
		Game.district.water_table = values[2]
		Game.district.trust = values[3]
	for key in save.get("bribes", []):
		Game.bribes[String(key)] = true
	var stats: Dictionary = save.get("stats", {})
	for key in stats:
		Game.stats[key] = stats[key]
	var cleared := int(save.get("waves_cleared", 0))
	_spawner.current_wave = cleared
	_waves_cleared = cleared
	if is_instance_valid(core):
		core.health = clampf(float(save.get("core_health", core.max_health)), 1.0, core.max_health)
		_on_core_damaged(0.0, core.health)
	for entry: Array in save.get("structures", []):
		var node := _build.place(int(entry[0]), Vector3(entry[1], entry[2], entry[3]), int(entry[4]), true)
		if node and float(entry[5]) > 0.0 and node.get("health") != null:
			node.set("health", minf(float(entry[5]), float(node.get("max_health"))))
	get_tree().call_group(&"nav_baker", &"request_rebake")
	Game.show_banner("CONTINUE", "Wave %d of %d is next" % [cleared + 1, _spawner.total_waves()])
	Game.set_objective("Continuing: repair and rebuild, then [N] for wave %d." % (cleared + 1))


## A card after each cleared wave: what it cost and what's coming.
func _show_wave_summary(number: int) -> void:
	var hud := get_node_or_null("Hud") as Hud
	if hud == null:
		return
	var before: Dictionary = _wave_start
	var lost_structures := maxi(int(before.get("structures", 0)) - _built_structures().size(), 0)
	var rows := [
		["Hostiles stopped", str(int(Game.stat("kills") - float(before.get("kills", 0.0))))],
		["Core damage taken", str(maxi(int(float(before.get("core", 0.0)) - (core.health if is_instance_valid(core) else 0.0)), 0))],
		["Cash earned", "$%d" % int(Game.stat("cash_earned") - float(before.get("cash", 0.0)))],
		["Structures lost", str(lost_structures)],
	]
	var next := _spawner.describe_wave(number + 1)
	if next != "":
		rows.append(["Next wave", next])
	hud.show_wave_summary("WAVE %d CLEARED" % number, rows)


## Title card on each phase change.
func _announce_phase() -> void:
	Sfx.music({Phase.ACTIVISM: &"calm", Phase.ASSAULT: &"assault", Phase.BUILD: &"build",
		Phase.WAVE: &"wave"}.get(phase, &""))
	# Checklists only belong to their phases.
	_update_sites()
	_update_deeds()
	match phase:
		Phase.ASSAULT:
			Game.show_banner("THE ASSAULT", "Wreck the cooling units to bring the datacenter down")
		Phase.BUILD:
			Game.show_banner("BUILD PHASE", "[B] build defenses around the Green Core")
		Phase.WON:
			Game.show_banner("DISTRICT SAVED", "The air is clearing")
		Phase.LOST:
			Game.show_banner("CORE LOST", "The datacenters win this round")


## Debug and tests: sets off Elmo's site alarm (he runs for his truck).
func start_boss() -> void:
	var home := _boss_site(DatacenterSite.Boss.ELMO)
	raise_alarm(home.site_id if home else defense_site_id, "test")


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
		Game.set_checklist("sites", "", [])
		return
	var rows: Array = []
	for site_node in sites:
		var row := [site_node.display_name + "   quiet", &"todo"]
		if site_node.is_cleared:
			row = [site_node.display_name + "   DOWN", &"done"]
		elif site_node.is_neutralized:
			row = [site_node.display_name + "   boss loose", &"alert"]
		elif site_node.is_alarmed():
			row = [site_node.display_name + "   ALARM", &"alert"]
		rows.append(row)
	Game.set_checklist("sites", "DATACENTERS", rows)


func _on_truck_wrecked(truck: ElmoTruck) -> void:
	var wreck := truck.global_position
	var home := _boss_site(DatacenterSite.Boss.ELMO)
	# Wrecked before he got in: the Elmo inside is the on-foot fight.
	if home and is_instance_valid(home.elmo) and home.elmo.is_alive():
		home.elmo.ride = null
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
	var home := _boss_site(DatacenterSite.Boss.ELMO)
	if home:
		home.mark_boss_defeated()


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
## `reason` names what the player hit; `seen_by` (stealth) names who spotted them.
func raise_alarm(site_id: StringName, reason := "", seen_by := "") -> void:
	if Game.is_alarmed(site_id):
		return
	Game.alarms[site_id] = true
	var site_node := site(site_id)
	var site_name := site_node.display_name if site_node else "the police"
	if not seen_by.is_empty():
		Game.notify("ALARM at %s! A %s spotted you. Its security is engaging." % [site_name, seen_by.to_lower()], 7.0)
	else:
		Game.notify("ALARM at %s! You hit the %s. Its security is engaging." % [site_name,
			reason.to_lower() if not reason.is_empty() else "site"], 7.0)
	if site_node:
		Sfx.play(&"alarm", site_node.datacenter.global_position + Vector3.UP * 11.0, 8.0, 1.0, 0.0)
		if site_node.boss == DatacenterSite.Boss.CRAPYA:
			Game.tip("alarm", "Scgrewgle's roof water cannons soak and shove you: take out its gas turbines to cut their power, or break Crapya's control room.")
		elif site_node.boss == DatacenterSite.Boss.ELMO:
			Game.tip("alarm_elmo", "Elmo's making a run for his Cyberdouche at the back dock. Catch him first, or wreck the truck.")
	if site_node:
		# Someone calls it in; the nearest cruiser rolls after a delay.
		_police_calls[site_id] = police_response_delay
		Game.notify("Someone called the cops. Police are on their way to %s (about %ds)." % [
			site_node.display_name, int(police_response_delay)], 5.0)
	elif site_id == &"police":
		Game.notify("You attacked the police! Every cop in town is after you now.", 6.0)
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
	if _litter_left <= 1:
		var garbage := get_node_or_null("GarbageTruck") as Car
		if garbage and not garbage.can_enter() and not garbage.locked_hint.is_empty():
			garbage.unlock()
			Game.notify("The block is spotless. The sanitation crew left you their garbage truck: [E] to drive it.", 5.0)
	_litter_left -= 1
	if _litter_left == _litter_total - 1:
		Game.tip("litter", "Walk over litter to pick it up. Clear all of it for a good deed.")
	if _litter_left <= 0:
		_complete_deed("litter", 40, 0.05, "The block is spotless. (+$40)")
	else:
		_update_deeds()


## DUECE Hardware, next to where the player starts: every gun, grenades,
## molotovs, shovels, rocks, and ammo on tables out front, all free.
func _spawn_hardware_store() -> void:
	var door := ($Neighborhood as NeighborhoodBuilder).store_door("DUECE HARDWARE")
	if door == Vector3.ZERO:
		return
	var stock := [
		[&"shovel", ""], [&"weapon", "Pistol"], [&"weapon", "Shotgun"], [&"weapon", "Hunting rifle"],
		[&"weapon", "Machine gun"], [&"weapon", "Grenades"], [&"weapon", "Recon drone"], [&"molotovs", ""],
		[&"rocks", ""], [&"ammo", ""],
	]
	for i in stock.size():
		var pickup := WeaponPickup.new()
		pickup.kind = stock[i][0]
		pickup.gun_name = stock[i][1]
		pickup.respawn = 20.0
		# One tidy row centered on the door, a pace apart.
		pickup.position = Vector3(door.x + (i - (stock.size() - 1) * 0.5) * 1.9, 0.0, door.z - 0.9)
		pickup.add_to_group("hardware_store")
		add_child(pickup)
	Game.set_meta(&"hardware_door", door)
	_move_in()
	var hall := ($Neighborhood as NeighborhoodBuilder).store_door("TOWN HALL")
	if hall != Vector3.ZERO:
		Game.set_meta(&"town_hall_door", hall)


## One patrol car loops the first street and the main road, and two officers
## stand outside the station. All of them are site &"police": passive unless
## the player attacks the police. A datacenter alarm dispatches a cruiser.
func _spawn_police() -> void:
	var door := ($Neighborhood as NeighborhoodBuilder).store_door("POLICE")
	if door == Vector3.ZERO:
		return
	var loop := police_patrol
	for i in 1:
		var cruiser := PoliceCruiser.new()
		cruiser.name = "PoliceCruiser%d" % (i + 1)
		cruiser.site = &"police"
		cruiser.route = loop.duplicate()
		cruiser.set("_leg", 1 + i * 3)
		cruiser.position = Vector3(door.x + 4.0 * i, 0.2, police_street_z)
		cruiser.rotation.y = -PI * 0.5
		add_child(cruiser)
	for side in [-1.0, 1.0]:
		var officer := Police.new()
		officer.site = &"police"
		officer.position = door + Vector3(side * 2.2, 0.1, 0.0)  # beside the door, not inside the station
		add_child(officer)


## Nearest free cruiser (or a fresh one from the station) drives the roads to
## the site's front gate and deploys two riot officers.
func _dispatch_police(site_node: DatacenterSite) -> void:
	var gate := site_node.at(Vector3(7.0, 0.2, site_node.compound.y * 0.5 + 7.0))
	var best: PoliceCruiser = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		var car := node as PoliceCruiser
		if car and not car.responding and car.is_alive() and (best == null
				or car.global_position.distance_to(gate) < best.global_position.distance_to(gate)):
			best = car
	if best == null:
		var door := ($Neighborhood as NeighborhoodBuilder).store_door("POLICE")
		best = PoliceCruiser.new()
		best.site = &"police"
		best.position = Vector3(door.x, 0.2, police_street_z)
		add_child(best)
	best.dispatch(road_route(best.global_position, gate), site_node.site_id)


## Waypoints along the roads from `from` to `to`: over to the first street,
## along it to the main road or the access road, then up to the destination.
func road_route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var street := route_street_z
	var lane := route_main_x
	var points: Array[Vector3] = []
	if absf(from.z - street) > 6.0:
		points.append(Vector3(lane if from.x >= 0.0 else -lane, 0.2, from.z))
	points.append(Vector3(points[-1].x if not points.is_empty() else from.x, 0.2, street - 2.0))
	if absf(to.x) > route_far_x:
		points.append(Vector3(signf(to.x) * (absf(to.x) - 4.0), 0.2, street - 2.0))
	else:
		points.append(Vector3(lane, 0.2, street - 2.0))
		points.append(Vector3(lane, 0.2, to.z + 4.0))
	points.append(to)
	return points


## A camper full of lost Canadians rolls up the main road from the south and
## pulls over. Public for tests.
func spawn_tourists() -> TouristRV:
	var rv := TouristRV.new()
	rv.name = "TouristRV%d" % (_tourists_sent + 1)
	rv.stop_point = tourist_stops[_tourists_sent % tourist_stops.size()]
	rv.exit_point = tourist_exit
	rv.with_mountie = _tourists_sent % 3 == 1
	rv.position = Vector3(absf(tourist_entry.x) * (1.0 if rv.stop_point.x > 0.0 else -1.0), tourist_entry.y, tourist_entry.z)
	rv.rotation.y = 0.0  # nose (-Z) up the main road
	_tourists_sent += 1
	add_child(rv)
	rv.arrived.connect(func(_r: TouristRV) -> void:
		Game.notify("A camper full of lost Canadian tourists pulled over. They look confused, eh.", 5.0)
		Game.tip("canadians", "Lost Canadian tourists! Walk up and press E to point them the right way. Grateful Canadians join your side, hockey sticks and all."))
	return rv


## Neighbors on the sidewalks, walking between front doors, shops, the
## market, and the park.
func _spawn_residents(count: int) -> void:
	var destinations: Array[Vector3] = ($Neighborhood as NeighborhoodBuilder).door_positions().duplicate()
	destinations.append(market_position + Vector3(0.0, 0.2, 3.5))
	for spot in park_spots:
		destinations.append(spot)
	var doors := ($Neighborhood as NeighborhoodBuilder).door_positions()
	# Mostly strollers, with joggers, dog walkers, kids, gardeners, and the mail.
	var roles: Array[StringName] = [&"walker", &"walker", &"walker", &"jogger", &"jogger", &"dog_walker", &"dog_walker",
		&"kid", &"kid", &"gardener", &"gardener", &"mail_carrier"]
	var busker := get_tree().get_nodes_in_group("residents").any(func(n: Node) -> bool: return (n as Resident).role == &"busker")
	for i in count:
		var person := Resident.new()
		var role: StringName = roles[i % roles.size()] if i < roles.size() else roles.pick_random()
		if not busker:
			role = &"busker"
			busker = true
		person.set_role(role)
		person.destinations = destinations if role != &"mail_carrier" else doors
		var start: Vector3 = destinations.pick_random()
		if role == &"busker":
			start = market_position + Vector3(12.5, 0.2, 2.5)
		elif role == &"gardener" or role == &"kid":
			start = doors.pick_random() + Vector3(0.0, 0.0, 0.0)
		person.position = start + (Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)) if role != &"busker" else Vector3.ZERO)
		add_child(person)


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
		Game.set_checklist("deeds", "", [])
		return
	var cams := &"done" if _cameras_smashed >= _cameras_total else &"info"
	var labels := {
		"water": "Cap the burst hydrant [F]",
		"van": "Stop the supply van",
		"dogs": "Tame strays %d/2 [T]" % mini(_dogs_tamed, 2),
		"scout": "Scout the datacenters %d/%d" % [scouted_count(), get_tree().get_nodes_in_group("scout_points").size()],
		"ladies": "Help grandmas %d/%d [E]" % [_ladies_helped, _ladies_total],
		"paint": "Paint a house [F]",
		"litter": "Litter %d/%d" % [_litter_total - _litter_left, _litter_total],
	}
	var rows := []
	for key: String in ["water", "van", "dogs", "scout", "ladies", "paint", "litter"]:
		if _deeds.has(key):
			rows.append([labels[key], &"done" if _deeds[key] else &"todo"])
	rows.append(["Grock cams %d/%d" % [_cameras_smashed, _cameras_total], cams])
	rows.append(["Irrigation off %d/%d" % irrigation_status(), &"done" if irrigation_status()[0] >= irrigation_status()[1] else &"info"])
	Game.set_checklist("deeds", "GOOD DEEDS", rows)


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
	_wave_start = {"kills": Game.stat("kills"), "cash": Game.stat("cash_earned"),
		"core": core.health if is_instance_valid(core) else 0.0, "structures": _built_structures().size()}
	var hud := get_node_or_null("Hud") as Hud
	if hud:
		hud.hide_wave_summary()
	Sfx.ui(&"jingle_wave", -4.0, "Music")
	_auto_wave_left = -1.0
	Game.set_info("wave", "Wave %d/%d" % [number, total])
	Game.show_banner("WAVE %d / %d" % [number, total], "Hold the line!")
	if has_planned_breach():
		Game.set_info("wave", "Wave %d/%d: they cut through the %s fence!" % [number, total, _breach_side])
		_execute_breach()
	Game.set_objective("Wave %d/%d incoming. Hold the line!" % [number, total])


func _on_wave_cleared(number: int, total: int) -> void:
	_breach_hold = Vector3.INF
	if phase == Phase.LOST:
		return
	_waves_cleared = number
	if number >= total:
		return  # _on_all_waves_cleared handles the finale
	Sfx.ui(&"jingle_clear", -4.0, "Music")
	phase = Phase.BUILD
	_auto_wave_left = auto_wave_delay
	_send_canadians_home()
	Game.district.trust += 0.05
	_refill_player()
	if number + 1 >= breach_from_wave:
		_plan_breach()
	# High trust brings more neighbors out to help.
	if Game.district.trust >= 0.6 and get_tree().get_nodes_in_group("townspeople").size() < 8:
		_spawn_townspeople(1)
	Game.set_objective("Wave %d cleared. Repair, rebuild, then [N] for the next one." % number)
	_show_wave_summary(number)
	save_checkpoint()


func _on_all_waves_cleared() -> void:
	if phase == Phase.LOST:
		return
	SaveGame.clear()
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
	_breach_hold = next_breach_point()
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
	SaveGame.clear()
	phase = Phase.LOST
	_build.enabled = false
	_build.set_active(false)
	Game.district.smog += 0.6
	Game.set_info("core", "")
	Game.set_objective("The green datacenter fell. Press [Enter] to retry.")
	get_tree().create_timer(3.0).timeout.connect(_show_end.bind(false))
