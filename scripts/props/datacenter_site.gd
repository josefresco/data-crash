class_name DatacenterSite
extends Node3D
## One corporate datacenter compound, built in code. Local +Z faces the
## neighborhood. Contents:
## - A chain-link fence with a flimsy SiteGate front and back, each posted with
##   two guards and a guard dog; a patrol guard in the courtyard.
## - The Datacenter building (racks, a worker, cooling units, turbines).
## - A CargoTruck loop through the back gate: Government Cheese in, money out.
## - This site's boss, inside: Elmo (with his Cyberdouche parked at the dock),
##   Crapya (her control room, roof water cannons, vents, crushers), or Sham.
## Everything is tagged with `site_id`: nothing engages until the player
## attacks this site (Game.alarms). The site is cleared when the building has
## collapsed and the boss is down.

signal fence_breached(site: DatacenterSite)
## The building collapsed (all cooling units destroyed).
signal neutralized(site: DatacenterSite)
## Building down and boss down: this site is done.
signal cleared(site: DatacenterSite)

enum Boss { NONE, ELMO, CRAPYA, SHAM }

@export var site_id := &"felsa"
@export var display_name := "Felsa Cloud"
@export var brand_name := "FELSA CLOUD"
@export var brand_tagline := "REGION US-SUBURB-1  //  99.99% UPTIME, 0% WATER LEFT"
@export var brand_color := Color(0.3, 0.85, 1.0)
@export var boss := Boss.NONE
## Fenced area: x = width, y = depth (local Z).
@export var compound := Vector2(68.0, 60.0)
@export var gate_width := 7.5
## Where the building sits (local), and its share of the district's damage.
@export var building_offset := Vector3(0.0, 0.0, -2.0)
@export var smog_share := 0.3
@export var noise_share := 0.3
@export var water_share := 0.2
@export var trust_share := 0.1
@export var cash_reward := 300
@export var patrol_cyberdouche := false

var datacenter: Datacenter
var worker: DatacenterWorker
var truck: CargoTruck
## Boss pieces (null when absent or bosses are off).
var elmo: ElmoOnFoot
var elmo_truck: ElmoTruck
var crapya_room: CrapyaControlRoom
var sham: ShamCrapman
var is_neutralized := false
var boss_defeated := false
var is_cleared := false


func _ready() -> void:
	add_to_group("datacenter_sites")
	_build_fences()
	_build_gates()
	datacenter = Datacenter.new()
	datacenter.name = "Datacenter"
	datacenter.position = building_offset
	datacenter.site_id = site_id
	datacenter.brand_name = brand_name
	datacenter.brand_tagline = brand_tagline
	datacenter.brand_color = brand_color
	datacenter.smog_contribution = smog_share
	datacenter.noise_contribution = noise_share
	datacenter.water_restored = water_share
	datacenter.trust_gain = trust_share
	datacenter.cash_reward = cash_reward
	datacenter.turbine_smog = 0.03
	datacenter.turbine_noise = 0.03
	datacenter.turbine_cash = 50
	if boss == Boss.CRAPYA:
		datacenter.defenses_group = &"crapya_defenses"
	add_child(datacenter)
	datacenter.neutralized.connect(_on_neutralized)
	_post_security()
	_spawn_worker()
	_spawn_truck()
	var level := get_parent()
	if level == null or level.get("boss_enabled") != false:
		_spawn_boss()
	else:
		boss_defeated = true


## World position of a point given in compound space.
func at(local: Vector3) -> Vector3:
	return to_global(local)


func is_alarmed() -> bool:
	return Game.is_alarmed(site_id)


func boss_label() -> String:
	match boss:
		Boss.ELMO:
			return "Elmo Mushbrains"
		Boss.CRAPYA:
			return "Crapya Butella"
		Boss.SHAM:
			return "Sham Crapman"
	return ""


## Called by the level when this site's boss goes down for good.
func mark_boss_defeated() -> void:
	if boss_defeated:
		return
	boss_defeated = true
	_check_cleared()


func _build_fences() -> void:
	var half := compound * 0.5
	# [name, position, yaw, length, has gate]
	var runs := [
		["FenceFront", Vector3(-half.x, 0.0, half.y), 0.0, compound.x, true],
		["FenceBack", Vector3(-half.x, 0.0, -half.y), 0.0, compound.x, true],
		["FenceLeft", Vector3(-half.x, 0.0, half.y), PI * 0.5, compound.y, false],
		["FenceRight", Vector3(half.x, 0.0, half.y), PI * 0.5, compound.y, false],
	]
	for run: Array in runs:
		var fence := FenceLine.new()
		fence.name = run[0]
		fence.position = run[1]
		fence.rotation.y = run[2]
		fence.length = run[3]
		if run[4]:
			fence.gap_center = compound.x * 0.5
			fence.gap_width = gate_width + 0.4
		add_child(fence)
		for panel in fence.get_children():
			if panel is Destructible:
				(panel as Destructible).site_id = site_id
		fence.breached.connect(func() -> void: fence_breached.emit(self))


func _build_gates() -> void:
	var half := compound * 0.5
	for spec in [["FrontGate", Vector3(0.0, 0.0, half.y - 0.3), 0.0, "PRIVATE PROPERTY  //  %s" % brand_name],
			["BackGate", Vector3(0.0, 0.0, -half.y + 0.3), PI, "DELIVERIES: CHEESE IN, CASH OUT"]]:
		var gate := SiteGate.new()
		gate.name = spec[0]
		gate.width = gate_width
		gate.site_id = site_id
		gate.sign_text = spec[3]
		gate.position = spec[1]
		gate.rotation.y = spec[2]
		add_child(gate)


func _post_security() -> void:
	var half := compound * 0.5
	var radius := maxf(half.x, half.y) + 4.0
	for side in [["Front", 1.0], ["Back", -1.0]]:
		var z: float = side[1] * (half.y - 4.0)
		for i in 2:
			var guard := SecurityGuard.new()
			guard.name = "%sGuard%d" % [side[0], i + 1]
			guard.site = site_id
			guard.position = Vector3(-5.5 + i * 11.0, 0.1, z)
			add_child(guard)
		var dog := Dog.new()
		dog.name = "%sDog" % side[0]
		dog.site = site_id
		dog.territory_radius = radius
		dog.position = Vector3(2.5 * side[1], 0.1, side[1] * (half.y - 6.5))
		add_child(dog)
		dog.territory_center = global_position
	var patrol := SecurityGuard.new()
	patrol.name = "PatrolGuard"
	patrol.site = site_id
	patrol.position = Vector3(12.0, 0.1, half.y - 14.0)
	add_child(patrol)
	if patrol_cyberdouche:
		var car := FelsaCar.new()
		car.name = "PatrolFelsa"
		car.site = site_id
		car.position = Vector3(-20.0, 0.2, half.y - 12.0)
		add_child(car)


func _spawn_worker() -> void:
	worker = DatacenterWorker.new()
	worker.name = "Worker"
	worker.site = site_id
	worker.position = building_offset + Vector3(-4.0, 0.1, 6.0)
	worker.escape_point = at(Vector3(0.0, 0.0, compound.y * 0.5 + 14.0))
	add_child(worker)


func _spawn_truck() -> void:
	truck = CargoTruck.new()
	truck.name = "CargoTruck"
	truck.site = site_id
	truck.spawn_point = at(Vector3(0.0, 0.2, -compound.y * 0.5 - 14.0))
	truck.dock_point = at(building_offset + datacenter.back_door() + Vector3(0.0, 0.2, -5.0))
	truck.position = Vector3(0.0, 0.2, -compound.y * 0.5 - 14.0)
	truck.rotation.y = PI  # nose (-Z) toward the back gate
	add_child(truck)


func _spawn_boss() -> void:
	var lobby := building_offset + Vector3(0.0, 0.1, datacenter.footprint.y * 0.5 - 4.5)
	match boss:
		Boss.ELMO:
			elmo_truck = ElmoTruck.new()
			elmo_truck.name = "ElmoTruck"
			elmo_truck.parked = true
			elmo_truck.site = site_id
			elmo_truck.position = building_offset + datacenter.back_door() + Vector3(-9.0, 0.3, -7.0)
			add_child(elmo_truck)
			elmo = ElmoOnFoot.new()
			elmo.name = "Elmo"
			elmo.site = site_id
			elmo.ride = elmo_truck
			elmo.position = lobby + Vector3(5.0, 0.0, 0.0)
			add_child(elmo)
		Boss.CRAPYA:
			crapya_room = CrapyaControlRoom.new()
			crapya_room.name = "CrapyaControlRoom"
			crapya_room.site_id = site_id
			crapya_room.position = lobby + Vector3(-9.0, -0.1, -0.5)
			add_child(crapya_room)
			crapya_room.destroyed.connect(func(_r: Destructible) -> void: mark_boss_defeated())
			# On the front edge of the roof, where they can see down into the yard.
			var roof := datacenter.height + 0.5
			var edge := datacenter.footprint.y * 0.5 - 0.6
			for spec in [["SentryNE", Vector3(10.0, roof, edge)], ["SentryNW", Vector3(-10.0, roof, edge)]]:
				var sentry := SentryTurret.new()
				sentry.name = spec[0]
				sentry.site = site_id
				sentry.position = building_offset + spec[1]
				add_child(sentry)
			# Steam vents between the cooling units, rack crushers beside them.
			var units: Array[Vector3] = []
			for node in datacenter.get_children():
				if node.is_in_group("cooling_units"):
					units.append((node as Node3D).position + building_offset)
			for i in mini(units.size() - 1, 2):
				var vent := SteamVent.new()
				vent.name = "SteamVent%d" % (i + 1)
				vent.position = (units[i] + units[i + 1]) * 0.5
				vent.phase_offset = i * 1.5
				add_child(vent)
				var crusher := SteamVent.new()
				crusher.name = "RackCrusher%d" % (i + 1)
				crusher.crusher = true
				crusher.radius = 1.3
				crusher.idle_time = 2.5
				crusher.warn_time = 0.8
				crusher.active_time = 0.6
				crusher.damage = 45.0
				crusher.phase_offset = i * 1.2
				crusher.position = units[i] + Vector3(3.5, 0.0, 0.0)
				add_child(crusher)
		Boss.SHAM:
			sham = ShamCrapman.new()
			sham.name = "Sham"
			sham.site = site_id
			sham.position = lobby + Vector3(5.0, 0.0, 0.0)
			add_child(sham)
			sham.died.connect(func(_s: Enemy) -> void: mark_boss_defeated())
		_:
			boss_defeated = true


func _on_neutralized() -> void:
	is_neutralized = true
	for gate_name in ["FrontGate", "BackGate"]:
		var gate := get_node_or_null(gate_name) as SiteGate
		if gate:
			gate.remove()
	if is_instance_valid(truck) and truck.is_alive():
		truck.queue_free()
	# The collapse takes Crapya's control room (and her defenses) down with it.
	if is_instance_valid(crapya_room) and not crapya_room.is_destroyed:
		crapya_room.shatter(crapya_room.global_position + Vector3.UP * 2.0, 120.0)
	neutralized.emit(self)
	_check_cleared()


func _check_cleared() -> void:
	if is_cleared or not is_neutralized or not boss_defeated:
		return
	is_cleared = true
	cleared.emit(self)
