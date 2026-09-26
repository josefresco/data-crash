class_name OldLady
extends Enemy
## A grandma waiting at the curb, eyeing the self-driving trucks. [E] offers
## your arm: she follows you (slowly) and the deed counts when she reaches
## `destination` across the street. Traffic doesn't stop for her.

signal crossed(lady: OldLady)

enum State { WAITING, FOLLOWING, CROSSED }

const WAITING_LINES := [
	"Could someone help me across? Those robot trucks...",
	"In my day, cars had drivers.",
	"Is it safe to cross, dear?",
]
const WALKING_LINES := [
	"Not so fast, dear!",
	"My hip isn't what it used to be.",
	"Such a nice young person.",
	"Did you eat? You look thin.",
]

@export var destination := Vector3.ZERO
@export var reach := 2.8

var state := State.WAITING

var _player: Player
var _line_left := 2.0
var _marker: MeshInstance3D


func _init() -> void:
	outfit = "old_lady"
	faction = Faction.ALLY
	max_health = 60.0
	move_speed = 1.8
	sight_range = 0.0
	attack_range = 0.0
	bounty = 0
	body_height = 1.55


func _ready() -> void:
	super()
	add_to_group("interactables")
	# A soft ring where she wants to go, shown while you walk her over.
	var ring := TorusMesh.new()
	ring.inner_radius = 1.1
	ring.outer_radius = 1.3
	_marker = MeshInstance3D.new()
	_marker.mesh = ring
	_marker.material_override = Models.glow(Color(0.5, 1.0, 0.6), 1.5)
	_marker.visible = false
	get_parent().add_child.call_deferred(_marker)
	_marker.position = destination + Vector3.UP * 0.05


func _faction_group() -> String:
	return "neighbors"


func _pick_target() -> Node3D:
	return null


func in_reach(player: Node3D) -> bool:
	return state == State.WAITING and is_alive() and player.global_position.distance_to(global_position) <= reach


func offer_text(_player_node: Player) -> String:
	return "[E] Help her across the street"


func interact(player: Player) -> void:
	if state != State.WAITING:
		return
	state = State.FOLLOWING
	_player = player
	_marker.visible = true
	speak("Oh, thank you, dear!")
	Game.tip("old_ladies", "Walk her to the green ring across the street. She's slow, so don't sprint off, and watch for traffic.")


func _process(delta: float) -> void:
	super(delta)
	if _is_dead or state == State.CROSSED:
		return
	_line_left -= delta
	if _line_left > 0.0:
		return
	_line_left = randf_range(6.0, 9.0)
	var near := _player != null and global_position.distance_to(_player.global_position) < 12.0
	if state == State.WAITING:
		speak(WAITING_LINES.pick_random())
	elif near:
		speak(WALKING_LINES.pick_random())
	else:
		speak("Wait for me, dear!")


func _idle() -> void:
	match state:
		State.WAITING:
			_nav.target_position = home
		State.FOLLOWING:
			if global_position.distance_to(destination) < 1.8:
				_arrive()
			elif _player and global_position.distance_to(_player.global_position) > 1.8:
				_nav.target_position = _player.global_position
			else:
				_nav.target_position = global_position
		State.CROSSED:
			_nav.target_position = destination + (destination - home).normalized() * 6.0


func _arrive() -> void:
	state = State.CROSSED
	_marker.visible = false
	speak("Bless you, dear! Here's a little something.")
	crossed.emit(self)
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.6)
	tween.tween_callback(_cleanup)


func _cleanup() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	queue_free()


func _on_death() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	if state != State.CROSSED and Game.district:
		Game.district.trust -= 0.05
		Game.notify("A grandma was hit crossing the street. The neighbors are furious.", 5.0)


func _decorate(_visual_root: Node3D) -> void:
	# Cane in one hand, handbag in the other.
	var cane := _add_box(_anchor(&"hand_l"), Vector3(0.04, 0.9, 0.04), Vector3(0.0, -0.4, -0.05), _solid(Color(0.35, 0.22, 0.12)))
	cane.rotation.x = 0.1
	_add_box(_anchor(&"hand_r"), Vector3(0.22, 0.18, 0.08), Vector3(0.0, -0.15, 0.0), _solid(Color(0.55, 0.15, 0.2)))
