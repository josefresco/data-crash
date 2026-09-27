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

const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")
const CAR_MODELS: Array[String] = ["sedan", "suv", "hatchback-sports", "taxi", "van", "suv-luxury"]

var datacenter: Datacenter
## Gallons shown on the water board by the gate (it keeps climbing).
var water_used := 48203117.0
var _water_board: Label3D
var _board_left := 0.0
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
## This site's sprinklers, controller, and fountain (see _build_grounds).
var irrigation: Array[IrrigationPart] = []


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
	_build_extras()
	_build_grounds()
	if not Engine.is_editor_hint():
		# Draw calls: bake the lot's static dressing (lines, beds, bushes,
		# poles, signs) into a few meshes; bodies and scripted props stay.
		Models.merge_static(self)
	_spawn_worker()
	_spawn_truck()
	var level := get_parent()
	if level == null or level.get("boss_enabled") != false:
		_spawn_boss()
	else:
		boss_defeated = true


## Share of this site's irrigation still running, 0..1.
func irrigation_running() -> float:
	if irrigation.is_empty():
		return 0.0
	var on := 0
	for part in irrigation:
		if is_instance_valid(part) and part.running and not part.is_destroyed:
			on += 1
	return on / float(irrigation.size())


## Outside the side fences: a visitor parking lot (+X) with lit, drivable
## cars, and a manicured corporate lawn (-X) with hedges, flower beds, trees,
## a logo fountain, and sprinklers run by an irrigation controller. All of it
## watered around the clock while the neighborhood's taps run dry.
func _build_grounds() -> void:
	var half := compound * 0.5
	var paint := Models.mat(Color(0.92, 0.92, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(site_id) + 7

	# --- Visitor parking, east side ------------------------------------------------------
	var lot := Vector3(half.x + 12.0, 0.0, 4.0)
	Models.box(self, Vector3(18.0, 0.04, 30.0), lot + Vector3.UP * 0.02, Models.mat(Color(0.7, 0.7, 0.7), &"asphalt"))
	for row in [-1.0, 1.0]:
		for k in 11:
			Models.box(self, Vector3(4.6, 0.05, 0.12), lot + Vector3(row * 6.4, 0.04, -15.0 + k * 3.0), paint)
		for k in 10:
			if rng.randf() < 0.45:
				continue
			var car := CAR_SCENE.instantiate() as Node3D
			car.set(&"model_path", "res://assets/kenney/cars/%s.glb" % CAR_MODELS[rng.randi() % CAR_MODELS.size()])
			car.set(&"model_scale", 1.45)
			car.set(&"model_offset", Vector3(0.0, 0.05, 0.0))
			car.set(&"fit_to_model", true)
			car.position = lot + Vector3(row * 6.4, 0.4, -13.5 + k * 3.0)
			car.rotation.y = PI * 0.5 * -row  # nose toward the aisle
			add_child(car)
	for z in [-9.0, 9.0]:
		var pole := Models.streetlight(6.0)
		pole.position = lot + Vector3(0.0, 0.0, z)
		add_child(pole)
	var island := Models.mat(Color(0.3, 0.55, 0.25), &"grass")
	for z in [-15.8, 15.8]:
		Models.box(self, Vector3(18.0, 0.18, 1.4), lot + Vector3(0.0, 0.09, z), island)
		for x in [-6.0, 0.0, 6.0]:
			var bush := Models.model("res://assets/kenney/nature/plant_bushLarge.glb", 2.6)
			bush.position = lot + Vector3(x, 0.15, z)
			add_child(bush)
	var sign_board := Models.box(self, Vector3(4.0, 1.0, 0.15), lot + Vector3(-9.5, 1.4, -14.0), Models.mat(brand_color.darkened(0.5), &"paint"))
	sign_board.rotation.y = PI * 0.5
	var sign_text := Label3D.new()
	sign_text.text = "VISITOR PARKING
EMPLOYEES OF THE MONTH ONLY"
	sign_text.font_size = 48
	sign_text.pixel_size = 0.008
	sign_text.outline_size = 0
	sign_text.position = Vector3(0.0, 0.0, 0.09)
	Models.fit_label(sign_text, Vector2(4.0, 1.0))
	sign_board.add_child(sign_text)

	# --- Corporate lawn, west side ----------------------------------------------------------
	var lawn := Vector3(-(half.x + 11.0), 0.0, 0.0)
	var lawn_length := compound.y - 4.0
	var green := Models.mat(Color(0.28, 0.62, 0.22), &"grass")
	Models.box(self, Vector3(18.0, 0.06, lawn_length), lawn + Vector3.UP * 0.03, green)
	# A clipped hedge along the fence, then flower beds in front of it.
	var hedge_mat := Models.mat(Color(0.15, 0.38, 0.14), &"grass")
	Models.box(self, Vector3(1.0, 1.1, lawn_length - 2.0), Vector3(-(half.x + 2.6), 0.55, 0.0), hedge_mat)
	Models.collider(self, Vector3(1.0, 1.1, lawn_length - 2.0), Vector3(-(half.x + 2.6), 0.55, 0.0))
	var bloom: Array[Color] = [Color(0.9, 0.2, 0.3), Color(0.95, 0.8, 0.2), Color(0.6, 0.3, 0.85), Color(1.0, 0.55, 0.2)]
	for k in 6:
		var bed := Models.box(self, Vector3(1.6, 0.3, 4.0), Vector3(-(half.x + 4.5), 0.15, -22.5 + k * 9.0),
			Models.mat(Color(0.32, 0.2, 0.12), &"dirt"))
		for f in 5:
			Models.ball(bed, 0.18, Vector3(rng.randf_range(-0.5, 0.5), 0.25, -1.6 + f * 0.8), Models.mat(bloom[(k + f) % bloom.size()], &"paint"))
	for z in [-22.0, -8.0, 8.0, 22.0]:
		var tree := Models.model("res://assets/kenney/nature/%s.glb" % ["tree_oak", "tree_default", "tree_fat"][rng.randi() % 3], 4.5)
		tree.position = lawn + Vector3(5.5, 0.0, z)
		add_child(tree)
		Models.collider(self, Vector3(0.6, 3.0, 0.6), lawn + Vector3(5.5, 1.5, z))
	# The logo fountain: a basin, three jets, and a plaque about stewardship.
	var fountain := IrrigationPart.new()
	fountain.kind = IrrigationPart.Kind.FOUNTAIN
	fountain.name = "Fountain"
	fountain.size = Vector3(3.4, 0.7, 3.4)
	fountain.color = Color(0.9, 0.9, 0.88)
	fountain.surface_kind = &"concrete"
	fountain.max_health = 140.0
	fountain.water_gain = 0.03
	fountain.cash = 80
	fountain.position = lawn + Vector3(1.0, 0.0, 0.0)
	add_child(fountain)
	Models.box(fountain, Vector3(3.0, 0.05, 3.0), Vector3(0.0, 0.66, 0.0), Models.mat(Color(0.35, 0.6, 0.85), &"paint"))
	var plaque := Label3D.new()
	plaque.text = "%s\nWATER STEWARDSHIP GARDEN" % brand_name
	plaque.font_size = 40
	plaque.pixel_size = 0.007
	plaque.outline_size = 6
	plaque.outline_size = 0
	plaque.position = Vector3(1.72, 0.38, 0.0)
	plaque.rotation.y = PI * 0.5
	Models.fit_label(plaque, Vector2(3.2, 0.6))
	fountain.add_child(plaque)
	irrigation.append(fountain)
	# Sprinklers in a grid, all fed by one controller box on the lawn's corner.
	var controller := IrrigationPart.new()
	controller.kind = IrrigationPart.Kind.CONTROLLER
	controller.name = "IrrigationController"
	controller.size = Vector3(0.8, 1.2, 0.45)
	controller.color = Color(0.3, 0.45, 0.35)
	controller.surface_kind = &"metal"
	controller.max_health = 45.0
	controller.water_gain = 0.012
	controller.cash = 40
	controller.position = lawn + Vector3(7.5, 0.0, lawn_length * 0.5 - 2.0)
	add_child(controller)
	Models.box(controller, Vector3(0.5, 0.3, 0.02), Vector3(0.0, 0.85, 0.235), Models.glow(Color(0.3, 1.0, 0.45), 2.0))
	var pipe := Models.mat(Color(0.3, 0.3, 0.32), &"metal")
	Models.box(self, Vector3(0.12, 0.1, lawn_length - 4.0), lawn + Vector3(7.5, 0.1, 0.0), pipe)
	irrigation.append(controller)
	for col in [-5.0, 1.0, 6.0]:
		for row in 4:
			var head := IrrigationPart.new()
			head.kind = IrrigationPart.Kind.SPRINKLER
			head.size = Vector3(0.22, 0.32, 0.22)
			head.color = Color(0.2, 0.22, 0.2)
			head.max_health = 8.0
			head.water_gain = 0.004
			head.cash = 12
			head.position = lawn + Vector3(col, 0.0, -lawn_length * 0.5 + 5.0 + row * (lawn_length - 10.0) / 3.0)
			add_child(head)
			controller.controlled.append(head)
			irrigation.append(head)

## True when `point` (world) is inside the fenced compound, grown by `margin`.
func contains(point: Vector3, margin := 0.0) -> bool:
	var local := to_local(point)
	return absf(local.x) <= compound.x * 0.5 + margin and absf(local.z) <= compound.y * 0.5 + margin


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
		car.position = Vector3(-10.0, 0.2, half.y - 10.0)
		add_child(car)


func _process(delta: float) -> void:
	if _water_board and not is_neutralized:
		# About 5 million gallons a day; the lawns are a good share of it.
		water_used += delta * 57.0 * (0.7 + 0.3 * irrigation_running())
		_board_left -= delta
		if _board_left <= 0.0:
			_board_left = 0.5  # re-rendering the text every frame is costly
			_water_board.text = "WATER USED THIS MONTH\n%s GAL" % _thousands(int(water_used))
			if _water_board.double_sided:
				Models.fit_label(_water_board, Vector2(4.8, 2.0))


static func _thousands(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## Employee parking (drivable cars), an evaporative cooling tower and diesel
## tanks you can wreck, a power substation, flagpoles, floodlights, and the
## water board by the gate.
func _build_extras() -> void:
	var half := compound * 0.5
	var steel := Models.mat(Color(0.35, 0.37, 0.4), &"metal")
	var paint := Models.mat(Color(0.92, 0.92, 0.9))
	# Parking lot, front-east.
	var lot := Vector3(22.0, 0.0, half.y - 13.0)
	Models.box(self, Vector3(15.0, 0.04, 11.0), lot + Vector3.UP * 0.02, Models.mat(Color(0.7, 0.7, 0.7), &"asphalt"))
	for k in 5:
		Models.box(self, Vector3(0.12, 0.05, 4.5), lot + Vector3(-6.0 + k * 3.0, 0.04, -2.5), paint)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(site_id)
	for k in 3:
		var car := CAR_SCENE.instantiate() as Node3D
		car.set(&"model_path", "res://assets/kenney/cars/%s.glb" % CAR_MODELS[rng.randi() % CAR_MODELS.size()])
		car.set(&"model_scale", 1.45)
		car.set(&"model_offset", Vector3(0.0, 0.05, 0.0))
		car.set(&"fit_to_model", true)
		car.position = lot + Vector3(-4.5 + k * 3.0 + (1.5 if k == 2 else 0.0), 0.4, -2.5)
		car.rotation.y = PI
		add_child(car)
	# Evaporative cooling tower, front-west: wreck it and the aquifer recovers a bit.
	var tower := Destructible.new()
	tower.name = "CoolingTower"
	tower.size = Vector3(6.0, 7.0, 6.0)
	tower.color = Color(0.75, 0.78, 0.8)
	tower.surface_kind = &"plates"
	tower.max_health = 300.0
	tower.damage_threshold = 20.0
	tower.chunks = Vector3i(3, 3, 3)
	tower.label = "Evaporative cooling tower"
	tower.site_id = site_id
	tower.position = Vector3(-26.0, 0.0, half.y - 16.0)
	add_child(tower)
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		for k in 5:
			var louver_size := Vector3(5.6, 0.12, 0.08) if absf(side.z) > 0.0 else Vector3(0.08, 0.12, 5.6)
			Models.box(tower, louver_size, side * 3.03 + Vector3.UP * (0.8 + k * 0.45), steel)
	Models.cylinder(tower, 2.4, 1.4, Vector3(0.0, 7.7, 0.0), steel, 20)
	Vfx.steam_jet(tower, Vector3(0.0, 8.6, 0.0), 6.0).emitting = true
	var tower_sign := Label3D.new()
	tower_sign.text = "EVAPORATIVE COOLING\n5,000,000 GAL/DAY"
	tower_sign.font_size = 56
	tower_sign.pixel_size = 0.01
	tower_sign.outline_size = 8
	tower_sign.position = Vector3(0.0, 5.0, 3.1)
	Models.fit_label(tower_sign, Vector2(5.4, 1.6))
	tower.add_child(tower_sign)
	tower.destroyed.connect(func(_t: Destructible) -> void:
		if Game.district:
			Game.district.water_table += 0.08
		Game.add_cash(60)
		Game.notify("%s's cooling tower is down: the aquifer gets a break. (+$60, water up)" % display_name))
	# Diesel tanks, back-west: a big bang, and they take the neighbors with them.
	for k in 2:
		var tank := Destructible.new()
		tank.name = "DieselTank%d" % (k + 1)
		tank.size = Vector3(5.0, 2.4, 2.4)
		tank.color = Color(0.85, 0.82, 0.3)
		tank.surface_kind = &"paint"
		tank.max_health = 120.0
		tank.damage_threshold = 15.0
		tank.chunks = Vector3i(3, 1, 1)
		tank.label = "Diesel tank"
		tank.site_id = site_id
		tank.position = Vector3(-22.0, 0.0, -half.y + 7.0 + k * 3.4)
		add_child(tank)
		var tank_sign := Label3D.new()
		tank_sign.text = "DIESEL  //  BACKUP POWER"
		tank_sign.font_size = 48
		tank_sign.pixel_size = 0.008
		tank_sign.outline_size = 6
		tank_sign.position = Vector3(0.0, 1.3, 1.25)
		Models.fit_label(tank_sign, Vector2(4.6, 0.8))
		tank.add_child(tank_sign)
		tank.destroyed.connect(func(t: Destructible) -> void:
			var blast := Explosive.new()
			blast.radius = 7.0
			blast.damage = 110.0
			get_parent().add_child(blast)
			blast.global_position = t.global_position + Vector3.UP * 1.2
			blast.detonate.call_deferred())
	# Power substation, west side: transformers behind a little fence.
	var sub := Vector3(-27.0, 0.0, -4.0)
	for k in 3:
		var transformer := Models.box(self, Vector3(1.6, 2.0, 1.4), sub + Vector3(0.0, 1.0, -3.0 + k * 3.0), Models.mat(Color(0.45, 0.5, 0.45), &"plates"))
		Models.collider(self, Vector3(1.6, 2.0, 1.4), sub + Vector3(0.0, 1.0, -3.0 + k * 3.0))
		for x in [-0.4, 0.0, 0.4]:
			Models.cylinder(transformer, 0.08, 0.7, Vector3(x, 1.35, 0.0), Models.mat(Color(0.6, 0.4, 0.3), &"paint"), 8)
	for z in [-5.0, 5.0]:
		Models.box(self, Vector3(4.0, 1.8, 0.06), sub + Vector3(0.0, 0.9, z), Models.mat(Color(0.8, 0.82, 0.85), &"chainlink"))
		Models.collider(self, Vector3(4.0, 1.8, 0.2), sub + Vector3(0.0, 0.9, z))
	# Flagpoles by the front gate, floodlight masts at the corners.
	var flag := Models.mat(brand_color, &"cloth")
	for x in [-10.0, -12.5, 10.0, 12.5]:
		Models.cylinder(self, 0.07, 9.0, Vector3(x, 4.5, half.y - 2.5), steel, 8)
		Models.collider(self, Vector3(0.25, 9.0, 0.25), Vector3(x, 4.5, half.y - 2.5))
		var cloth := Models.box(self, Vector3(1.8, 1.1, 0.04), Vector3(x + 0.95, 8.3, half.y - 2.5), flag)
		cloth.rotation.y = 0.1
	for corner in [Vector3(-half.x + 1.5, 0, half.y - 1.5), Vector3(half.x - 1.5, 0, half.y - 1.5),
			Vector3(-half.x + 1.5, 0, -half.y + 1.5), Vector3(half.x - 1.5, 0, -half.y + 1.5)]:
		Models.cylinder(self, 0.15, 12.0, corner + Vector3.UP * 6.0, steel, 8)
		Models.collider(self, Vector3(0.4, 12.0, 0.4), corner + Vector3.UP * 6.0)
		var head := Models.box(self, Vector3(1.4, 0.5, 0.6), corner + Vector3(0.0, 12.1, 0.0), steel)
		Models.box(head, Vector3(1.2, 0.3, 0.05), Vector3(0.0, -0.1, 0.31), Models.glow(Color(0.85, 0.95, 1.0), 4.0))
		# Cold security floodlight angled into the lot: a hard beam in the smog.
		var beam := Models.smog_light(self, corner + Vector3(0.0, 11.8, 0.0), Color(0.72, 0.88, 1.0), 16.0, 38.0, 30.0, 9.0)
		beam.set_meta(&"aim", corner * 0.45)
		var shaft_from: Vector3 = corner + Vector3(0.0, 11.8, 0.0)
		var shaft_to: Vector3 = corner * 0.45
		Models.light_cone(self, shaft_from, shaft_to - shaft_from, shaft_from.distance_to(shaft_to), 5.5,
			Color(0.75, 0.9, 1.0), 0.1)
	# The water board by the gate.
	var board := Models.box(self, Vector3(5.0, 2.2, 0.3), Vector3(-9.0, 2.6, half.y + 1.5), Models.mat(Color(0.08, 0.08, 0.1), &"paint"))
	Models.collider(self, Vector3(5.0, 3.7, 0.4), Vector3(-9.0, 1.85, half.y + 1.5))
	for x in [-2.0, 2.0]:
		Models.box(self, Vector3(0.15, 1.5, 0.15), Vector3(-9.0 + x, 0.75, half.y + 1.5), steel)
	_water_board = Label3D.new()
	_water_board.font_size = 72
	_water_board.pixel_size = 0.008
	_water_board.outline_size = 0
	_water_board.modulate = Color(1.0, 0.45, 0.2)
	_water_board.position = Vector3(0.0, 0.0, 0.17)
	board.add_child(_water_board)


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
