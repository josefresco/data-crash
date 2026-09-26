class_name DatacenterWorker
extends Enemy
## The one tech keeping a datacenter running. Potters between the racks until
## the site's alarm goes off, then flees out the front door ("I just work
## here!"). Not a target for anyone; hurting them costs trust.

const LINES := [
	"Have you tried turning the neighborhood off and on again?",
	"Ticket closed: works on my machine.",
	"I'm on call for 72 hours. Send help.",
	"The racks are fine. I am not.",
]

## Where to run when the alarm goes off (world space, outside the gate).
var escape_point := Vector3.ZERO
var fled := false

var _line_left := 3.0


func _init() -> void:
	outfit = "tech"
	faction = Faction.ALLY
	max_health = 40.0
	move_speed = 2.2
	sight_range = 0.0
	attack_range = 0.0
	bounty = 0


func _faction_group() -> String:
	return "workers"


func _pick_target() -> Node3D:
	return null


func _process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = randf_range(9.0, 14.0)
		speak("" if fled else LINES.pick_random())


func _idle() -> void:
	if site != &"" and Game.is_alarmed(site):
		if not fled:
			fled = true
			move_speed = 5.0
			speak("I just work here!")
		_nav.target_position = escape_point
		if global_position.distance_to(escape_point) < 2.5:
			_emit_defeated()
			queue_free()
		return
	_wander()


## Always "dormant": the worker never picks fights.
func is_dormant() -> bool:
	return false


func _on_death() -> void:
	if Game.district:
		Game.district.trust -= 0.03
		Game.notify("You hurt the datacenter tech. They just worked there.", 4.0)


func _decorate(_visual_root: Node3D) -> void:
	# Laptop under one arm, company cap on.
	_add_box(_anchor(&"hand_l"), Vector3(0.32, 0.03, 0.24), Vector3(0.0, -0.05, 0.0), _solid(Color(0.2, 0.2, 0.22)))
	Models.hat(_anchor(&"head"), &"cap", Color(0.22, 0.42, 0.72), _head_top(), body_height / 1.8)
