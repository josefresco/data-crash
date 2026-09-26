class_name Resident
extends Enemy
## A neighbor out and about: strolls between front doors, the shops, and the
## park, stops to chat, and grumbles about the datacenters. Nobody targets
## them; hurting one costs trust. When hostiles get close they hurry off
## somewhere else. Cars shove them aside (see Car._bump).

const OUTFITS: Array[String] = ["resident_a", "resident_b", "resident_c", "resident_d", "townsperson", "old_lady"]
const LINES := [
	"My water bill tripled this year.",
	"Nice day, if you ignore the smog.",
	"Is that a Cyberdouche? Stay back.",
	"They cut down the old oak for a turbine.",
	"The market has great honey this week.",
	"My kid's asthma is worse since they opened.",
	"I heard the servers are thirstier than we are.",
	"Duece gives stuff away. Good man.",
	"Remember when you could see the stars?",
	"They say the cloud is weightless. My lungs disagree.",
]

## Places to walk between (world space). Set by the level.
var destinations: Array[Vector3] = []

var _pause_left := 0.0
var _line_left := 0.0


func _init() -> void:
	outfit = OUTFITS.pick_random()
	faction = Faction.ALLY
	max_health = 50.0
	move_speed = randf_range(1.3, 2.2)
	sight_range = 0.0
	attack_range = 0.0
	bounty = 0
	body_height = randf_range(1.65, 1.85)


func _ready() -> void:
	super()
	_line_left = randf_range(4.0, 20.0)


func _faction_group() -> String:
	return "residents"


func _pick_target() -> Node3D:
	return null


func _process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = randf_range(14.0, 30.0)
		speak(LINES.pick_random())
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(self) and not _is_dead:
				speak(""))


func _idle() -> void:
	if destinations.is_empty():
		_wander()
		return
	if _danger_nearby():
		# Hurry off to somewhere else.
		move_speed = 4.0
		if _nav.is_navigation_finished():
			_nav.target_position = destinations.pick_random()
		return
	move_speed = minf(move_speed, 2.2)
	if not _nav.is_navigation_finished():
		return
	_pause_left -= THINK_INTERVAL
	if _pause_left > 0.0:
		return
	_pause_left = randf_range(3.0, 9.0)
	_nav.target_position = destinations.pick_random() + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))


func _danger_nearby() -> bool:
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and not unit.is_dormant() and unit.global_position.distance_to(global_position) < 12.0:
			return true
	return false


func _on_death() -> void:
	if Game.district:
		Game.district.trust -= 0.03
		Game.notify("A neighbor was hurt. Trust falls.", 3.0)
