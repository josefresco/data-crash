class_name Resident
extends Enemy
## A neighbor out and about. Nobody targets them; hurting one costs trust.
## When awake hostiles get close they hurry off somewhere else. Cars shove
## them aside (see Car._bump). Each has a `role`:
## - walker: strolls between doors, shops, the market, and the park
## - jogger: loops the block at a run, never stops
## - dog_walker: a strolling walker with a pet dog at heel
## - kid: dashes around near home with a ball
## - gardener: stays in the front yard, watering the flowers
## - mail_carrier: goes door to door with a satchel
## - busker: plays guitar by the farmer's market

const ROLES: Array[StringName] = [&"walker", &"jogger", &"dog_walker", &"kid", &"gardener", &"mail_carrier", &"busker"]
const WALKER_OUTFITS: Array[String] = ["resident_a", "resident_b", "resident_c", "resident_d", "townsperson", "old_lady"]
const LINES := {
	&"walker": [
		"My water bill tripled this year.",
		"Nice day, if you ignore the smog.",
		"Is that a Cyberdouche? Stay back.",
		"They cut down the old oak for a turbine.",
		"The market has great honey this week.",
		"My kid's asthma is worse since they opened.",
		"Duece gives stuff away. Good man.",
		"Remember when you could see the stars?",
	],
	&"jogger": ["On your left!", "Can't stop, heart rate zone!", "Mile four! Smog lap!", "Breathe in... actually, don't."],
	&"dog_walker": ["Good boy, Biscuit!", "He only bites datacenters.", "Leave the Grock camera alone, Biscuit.", "Walkies! Around the smog."],
	&"kid": ["Tag, you're it!", "Mom says the cloud ate our water.", "Can I drive the bulldozer?", "Race you!"],
	&"gardener": ["The tomatoes need water. So does everyone.", "Nothing grows in this smog.", "Mind the petunias, dear.", "I used to win ribbons for these roses."],
	&"mail_carrier": ["Another Felsa Prime box. Sigh.", "Neither smog nor noise stays these couriers.", "Package for... the whole block?", "Special delivery!"],
	&"busker": ["♪ This land was your land... ♪", "Tips appreciated, songs guaranteed!", "♪ Oh, the servers are hummin'... ♪", "Requests? I know three chords."],
}

## Places to walk between (world space). Set by the level.
var destinations: Array[Vector3] = []
var role := &"walker"

var _pause_left := 0.0
var _line_left := 0.0
## Sprinkler toggle, twice a second.
var _spray_left := randf() * 0.5
var _route_index := 0
var _spray: GPUParticles3D
var _pet: Dog


func _init() -> void:
	faction = Faction.ALLY
	max_health = 50.0
	move_speed = randf_range(1.3, 2.2)
	sight_range = 0.0
	attack_range = 0.0
	bounty = 0
	body_height = randf_range(1.65, 1.85)
	outfit = WALKER_OUTFITS.pick_random()


## Sets the role (before the resident enters the tree): outfit, pace, size.
func set_role(value: StringName) -> void:
	role = value
	match role:
		&"jogger":
			outfit = "jogger"
			move_speed = randf_range(3.6, 4.6)
		&"kid":
			outfit = "kid"
			body_height = randf_range(1.15, 1.3)
			move_speed = 3.2
		&"gardener":
			outfit = "gardener"
		&"mail_carrier":
			outfit = "mail_carrier"
			move_speed = 2.0
		&"busker":
			outfit = "busker"
		_:
			pass


func _ready() -> void:
	super()
	_line_left = randf_range(4.0, 20.0)
	if role == &"dog_walker":
		_pet = Dog.new()
		_pet.stray = true
		_pet.pet_owner = self
		_pet.body_color = [Color(0.85, 0.7, 0.45), Color(0.2, 0.18, 0.16), Color(0.95, 0.92, 0.88)].pick_random()
		_pet.position = position + Vector3(1.0, 0.0, 0.0)
		get_parent().add_child.call_deferred(_pet)
	if role == &"gardener":
		_spray = Vfx.water_spray(self, Vector3(0.0, 0.9, -0.6))
		_spray.amount_ratio = 0.35
		_spray.emitting = false


func _faction_group() -> String:
	return "residents"


func _pick_target() -> Node3D:
	return null


func _process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_spray_left -= delta
	if _spray and _spray_left <= 0.0:
		_spray_left = 0.5
		_spray.emitting = not is_far() and _nav.is_navigation_finished() and randf() < 0.6
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = randf_range(14.0, 30.0) if role != &"busker" else randf_range(6.0, 10.0)
		var lines: Array = LINES.get(role, LINES[&"walker"])
		speak(lines.pick_random())
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(self) and not _is_dead:
				speak(""))


func _idle() -> void:
	if role != &"busker" and role != &"gardener" and _danger_nearby():
		# Hurry off to somewhere else.
		move_speed = maxf(move_speed, 4.0)
		if _nav.is_navigation_finished() and not destinations.is_empty():
			_nav.target_position = destinations.pick_random()
		return
	match role:
		&"busker", &"gardener":
			_nav.target_position = home
		&"kid":
			if _nav.is_navigation_finished():
				var angle := randf() * TAU
				_nav.target_position = home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(3.0, 8.0)
		&"jogger":
			if _nav.is_navigation_finished() and not destinations.is_empty():
				_route_index = (_route_index + 1 + randi() % 3) % destinations.size()
				_nav.target_position = destinations[_route_index]
		&"mail_carrier":
			if not _nav.is_navigation_finished() or destinations.is_empty():
				return
			_pause_left -= THINK_INTERVAL
			if _pause_left > 0.0:
				return
			_pause_left = 2.0
			_route_index = (_route_index + 1) % destinations.size()
			_nav.target_position = destinations[_route_index]
		_:
			_stroll()


func _stroll() -> void:
	if destinations.is_empty():
		_wander()
		return
	move_speed = minf(move_speed, 2.2)
	if not _nav.is_navigation_finished():
		return
	_pause_left -= THINK_INTERVAL
	if _pause_left > 0.0:
		return
	_pause_left = randf_range(3.0, 9.0)
	_nav.target_position = destinations.pick_random() + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))


## Acoustic guitar across the chest: a figure-eight body (two bouts), a sound
## hole, a neck angled up to the left, and a headstock.
func _guitar(chest: Node3D, s: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, -0.18, -0.2) * s
	root.rotation = Vector3(0.0, 0.0, deg_to_rad(-60.0))
	root.scale = Vector3.ONE * s
	chest.add_child(root)
	var wood := Models.mat(Color(0.72, 0.45, 0.2), &"paint")
	var dark := Models.mat(Color(0.18, 0.12, 0.08), &"paint")
	for bout in [[0.2, Vector3(0.0, -0.1, 0.0)], [0.15, Vector3(0.0, 0.14, 0.0)]]:
		var disc := Models.cylinder(root, bout[0], 0.1, bout[1], wood, 16)
		disc.rotation.x = PI * 0.5
	var hole := Models.cylinder(root, 0.055, 0.02, Vector3(0.0, 0.03, -0.05), dark, 12)
	hole.rotation.x = PI * 0.5
	Models.box(root, Vector3(0.06, 0.5, 0.04), Vector3(0.0, 0.5, -0.02), dark)
	Models.box(root, Vector3(0.09, 0.14, 0.03), Vector3(0.0, 0.8, -0.02), wood)
	Models.box(root, Vector3(0.1, 0.03, 0.02), Vector3(0.0, -0.2, -0.06), dark)  # bridge


func _danger_nearby() -> bool:
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and not unit.is_dormant() and unit.global_position.distance_to(global_position) < 12.0:
			return true
	return false


func _decorate(_visual_root: Node3D) -> void:
	var s := body_height / 1.8
	match role:
		&"jogger":
			Models.hat(_anchor(&"head"), &"headband", Color(0.95, 0.4, 0.1), _head_top(), s)
		&"kid":
			Models.ball(_anchor(&"hand_r"), 0.14, Vector3(0.0, -0.05, -0.1), Models.mat(Color(0.9, 0.2, 0.2), &"paint"))
			Models.hat(_anchor(&"head"), &"cap", Color(0.3, 0.55, 0.95), _head_top(), s)
		&"gardener":
			Models.hat(_anchor(&"head"), &"campaign", Color(0.85, 0.75, 0.45), _head_top(), s * 0.9)
			var can := Models.cylinder(_anchor(&"hand_r"), 0.1, 0.22, Vector3(0.0, -0.12, -0.05), Models.mat(Color(0.3, 0.6, 0.35), &"metal"), 10)
			Models.cylinder(can, 0.02, 0.25, Vector3(0.0, 0.05, -0.15), Models.mat(Color(0.3, 0.6, 0.35), &"metal"), 6).rotation.x = 1.0
		&"mail_carrier":
			Models.hat(_anchor(&"head"), &"police", Color(0.3, 0.4, 0.62), _head_top(), s)
			_add_box(_anchor(&"hips"), Vector3(0.35, 0.3, 0.12), Vector3(0.22, 0.0, 0.0), _solid(Color(0.45, 0.32, 0.18)))
		&"busker":
			_guitar(_anchor(&"chest"), s)
			# An upturned hat for tips, on the ground in front.
			var tips := Models.cylinder(_visual, 0.17, 0.1, Vector3(0.0, 0.05, -0.75), Models.mat(Color(0.25, 0.2, 0.15), &"cloth"), 12)
			Models.cylinder(tips, 0.26, 0.015, Vector3(0.0, 0.05, 0.0), Models.mat(Color(0.25, 0.2, 0.15), &"cloth"), 12)
			Models.ball(tips, 0.04, Vector3(0.05, 0.04, 0.02), Models.mat(Color(0.85, 0.75, 0.3), &"metal"))
		_:
			pass


func _on_death() -> void:
	if Game.district:
		Game.district.trust -= 0.03
		Game.notify("A neighbor was hurt. Trust falls.", 3.0)
