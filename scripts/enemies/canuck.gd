class_name Canuck
extends Enemy
## A lost Canadian tourist. Mills around their RV apologizing until someone
## helps ([E] on any of the group): then the whole group joins you, follows
## you around, and fights hostiles with hockey sticks, apologizing the whole
## time. Left unhelped for `patience` seconds, they pile back in and leave.

signal helped(group_rv: Node)

enum State { LOST, ALLY, LEAVING, HOME }

const LOST_LINES := [
	"Sorry, is this the road to Lake Louise?",
	"We took a wrong turn at Buffalo, eh.",
	"Sorry to bother you, bud. Where's the Tim's?",
	"The GPS just says 'datacenter', eh.",
	"Is the smog always this thick? Sorry.",
]
const FIGHT_LINES := [
	"Sorry!", "Sorry, bud!", "That's a penalty, eh!", "Take off, eh!", "Apologies, eh!",
	"Two minutes for roughing!", "Sorry about your server, eh!",
]
const THANKS := "Thanks a bunch, eh! We'll help you out. Sorry in advance!"

@export var stick_damage := 14.0
@export var patience := 150.0

var state := State.LOST
var mountie := false
## The RV they came in (untyped: it may be gone).
var rv: Variant = null

var _line_left := 2.0
var _home_exit := Vector3.ZERO
var _home_left := 0.0
var _speech_left := 0.0


func _init() -> void:
	faction = Faction.ALLY
	max_health = 80.0
	move_speed = 3.8
	sight_range = 0.0
	attack_range = 1.9
	attack_interval = 0.9
	bounty = 0


func setup(is_mountie: bool) -> void:
	mountie = is_mountie
	outfit = "mountie" if is_mountie else ["canuck_a", "canuck_b"].pick_random()


func _ready() -> void:
	super()
	add_to_group("interactables")
	add_to_group("canadians")


func _faction_group() -> String:
	# Lost tourists aren't in the fight yet: nobody targets them.
	return "allies" if state == State.ALLY else "tourists"


func in_reach(player: Node3D) -> bool:
	return state == State.LOST and is_alive() and player.global_position.distance_to(global_position) <= 3.0


func offer_text(_player: Player) -> String:
	return "[E] Point the lost Canadians the right way"


func interact(_player: Player) -> void:
	if state != State.LOST:
		return
	helped.emit(rv)


## Joins the player's side (called for everyone in the group).
func join() -> void:
	if state != State.LOST or not is_alive():
		return
	state = State.ALLY
	sight_range = 22.0
	remove_from_group("tourists")
	set_faction(Faction.ALLY)
	speak(THANKS)
	_speech_left = 4.0


## After a defense wave: allies say goodbye and walk off south.
func go_home(exit: Vector3) -> void:
	if state != State.ALLY or not is_alive():
		return
	state = State.HOME
	_home_exit = exit
	_home_left = 45.0
	set_faction(Faction.ALLY)  # regroups as "tourists": out of the fight
	speak(["Thanks for the adventure, eh!", "Sorry we can't stay longer!", "Visit us in Moose Jaw, eh!"].pick_random())
	_speech_left = 4.0


## Unhelped: back to the RV.
func leave() -> void:
	if state == State.LOST:
		state = State.LEAVING


func _process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	if _speech_left > 0.0:
		_speech_left -= delta
		if _speech_left <= 0.0:
			speak("")
	_line_left -= delta
	if state == State.LOST and _line_left <= 0.0:
		_line_left = randf_range(6.0, 10.0)
		speak(LOST_LINES.pick_random())
		_speech_left = 3.5


func _pick_target() -> Node3D:
	if state != State.ALLY:
		return null
	return super()


func _idle() -> void:
	match state:
		State.LOST:
			if rv != null and is_instance_valid(rv):
				var spot := (rv as Node3D).global_position + Vector3(4.0, 0.0, 0.0)
				if _nav.is_navigation_finished():
					_nav.target_position = spot + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
			else:
				_wander()
		State.HOME:
			_nav.target_position = _home_exit
			_home_left -= THINK_INTERVAL
			if global_position.distance_to(_home_exit) < 5.0 or _home_left <= 0.0:
				_emit_defeated()
				queue_free()
		State.LEAVING:
			if rv != null and is_instance_valid(rv):
				_nav.target_position = (rv as Node3D).global_position
				if global_position.distance_to((rv as Node3D).global_position) < 3.5:
					_emit_defeated()
					queue_free()
			else:
				queue_free()
		_:
			super()


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", stick_damage, global_position, &"melee")
	if victim.has_method("apply_knockback"):
		var push := victim.global_position - global_position
		push.y = 0.0
		victim.call(&"apply_knockback", push.normalized() * 3.0 + Vector3.UP * 1.0)
	Sfx.play(&"hit_wood", victim.global_position, -4.0)
	if randf() < 0.35:
		speak(FIGHT_LINES.pick_random())
		_speech_left = 2.0


func _on_death() -> void:
	if Game.district and state == State.ALLY:
		Game.district.trust -= 0.02
	Game.notify("A Canadian tourist went down. Sorry, eh.", 3.0)


func _decorate(_visual_root: Node3D) -> void:
	var s := body_height / 1.8
	if mountie:
		# Tan felt Stetson with a brown band.
		Models.hat(_anchor(&"head"), &"campaign", Color(0.78, 0.63, 0.42), _head_top(), s)
	else:
		Models.hat(_anchor(&"head"), &"toque", [Color(0.8, 0.1, 0.1), Color(0.95, 0.95, 0.92)].pick_random(),
			_head_top(), s, Color(0.8, 0.1, 0.1))
	# Hockey stick held low: a wood shaft with a taped grip, down and forward
	# from the hand, ending in a flat blade that curves off to the side.
	var hand := _anchor(&"hand_r")
	var stick := Node3D.new()
	stick.rotation = Vector3(deg_to_rad(40.0), 0.0, deg_to_rad(-10.0))
	hand.add_child(stick)
	var wood := _solid(Color(0.78, 0.62, 0.4))
	var tape := _solid(Color(0.1, 0.1, 0.12))
	_add_box(stick, Vector3(0.045, 1.35, 0.03), Vector3(0.0, -0.55, 0.0), wood)
	_add_box(stick, Vector3(0.055, 0.14, 0.04), Vector3(0.0, 0.08, 0.0), tape)
	var blade := Node3D.new()
	blade.position = Vector3(0.0, -1.22, 0.0)
	blade.rotation.x = deg_to_rad(-40.0)
	stick.add_child(blade)
	_add_box(blade, Vector3(0.28, 0.08, 0.02), Vector3(0.14, 0.0, 0.0), wood)
	_add_box(blade, Vector3(0.12, 0.085, 0.025), Vector3(0.22, 0.0, 0.0), tape)
	var tip := _add_box(blade, Vector3(0.1, 0.08, 0.02), Vector3(0.31, 0.0, -0.02), wood)
	tip.rotation.y = deg_to_rad(25.0)
