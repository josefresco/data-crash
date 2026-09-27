class_name BradHypewell
extends Enemy
## Boss (SynergAI Campus, District 2): Brad Hypewell, AI keynote showman.
## While any of his chatbot kiosks stands he's behind a "hype shield" (the
## force-field bubble: 35% damage), and every few seconds each kiosk hallucinates a copy of him
## (a flimsy decoy that shoots weakly). Counter: smash the kiosks, then him.

const LINES := [
	"It's not a bug, it's emergent behavior.",
	"Our model drinks one lake per prompt. Worth it.",
	"This demo is live. Mostly.",
	"AGI by Q4. Water by never.",
	"Disrupting hydration, one river at a time.",
	"The kiosks are sentient. Legally, no.",
]

@export var demo_damage := 16.0
@export var hallucinate_interval := 9.0
@export var max_hallucinations := 6
@export var line_interval := 7.0

var _line_left := 3.0
var _hallucinate_left := 5.0
var _hallucinations: Array = []


func _init() -> void:
	voice_pitch = 1.05
	outfit = "brad"
	max_health = 800.0
	move_speed = 3.2
	sight_range = 30.0
	attack_range = 20.0
	structure_engage_range = 16.0
	attack_interval = 1.6
	bounty = 400
	body_color = Color(0.05, 0.05, 0.06)
	boss_name = "BRAD HYPEWELL"


## His site's chatbot kiosks still standing.
func kiosks() -> Array[Destructible]:
	var standing: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group("chatbot_kiosks"):
		var kiosk := node as Destructible
		if kiosk and not kiosk.is_destroyed and kiosk.site_id == site:
			standing.append(kiosk)
	return standing


func is_hyped() -> bool:
	return not kiosks().is_empty()


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead or is_dormant():
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = line_interval
		speak(LINES.pick_random())
	var standing := kiosks()
	if not standing.is_empty():
		shield_field(0.5)  # the hype bubble, kept up while kiosks stand
	_hallucinate_left -= delta
	if _hallucinate_left <= 0.0 and not standing.is_empty():
		_hallucinate_left = hallucinate_interval
		_hallucinate(standing)


## Each standing kiosk spits out a copy of him (up to max_hallucinations).
func _hallucinate(standing: Array[Destructible]) -> void:
	_hallucinations = _hallucinations.filter(func(h: Variant) -> bool: return is_instance_valid(h) and (h as Enemy).is_alive())
	for kiosk in standing:
		if _hallucinations.size() >= max_hallucinations:
			break
		var copy := Hallucination.new()
		copy.site = site
		var spot := kiosk.global_position + Vector3(randf_range(-1.5, 1.5), 0.1, 1.5)
		copy.position = (get_parent() as Node3D).to_local(spot)
		get_parent().add_child(copy)
		_hallucinations.append(copy)
	speak("Our model has some... creative outputs.")


## A "live demo": a hitscan beam of product.
func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	var from := global_position + Vector3.UP * 1.4
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", demo_damage, from, &"energy")
	Fx.tracer(get_parent(), from, _aim_point_of(victim), Color(0.2, 0.95, 0.85), 0.1, 0.15)


func _on_death() -> void:
	speak("Let's take this offline...")
	for copy in _hallucinations:
		if is_instance_valid(copy) and (copy as Enemy).is_alive():
			(copy as Enemy).apply_damage(9999.0, global_position, &"emp")
