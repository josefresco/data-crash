class_name ElmoOnFoot
extends Enemy
## Boss phase B: Elmo climbs out of the wreck with a flamethrower. Every so
## often he stops to post an update, standing still and taking extra damage.

const POSTS := [
	"Posting: 'Datacenters are actually green if you think about it'",
	"Posting: 'Engagement is up 400% on this situation'",
	"Posting: 'Just got attacked by a garden hose. Wild times'",
	"Posting: 'Concerning.'",
	"Posting: 'Should I buy this neighborhood?' (poll)",
]
const TAUNTS := [
	"Nobody reads the terms of service!",
	"I'll just build another one. Tonight.",
	"You're all on a list now.",
]

@export var flame_dps := 22.0
## Cone half-angle of the flamethrower.
@export var flame_cone_degrees := 35.0
@export var post_interval := 10.0
@export var post_duration := 3.0
@export var posting_damage_multiplier := 2.5

var is_posting := false

var _post_left := 6.0
var _posting_left := 0.0
var _speech: Label3D
var _phone: MeshInstance3D


func _init() -> void:
	max_health = 600.0
	move_speed = 4.8
	sight_range = 40.0
	attack_range = 6.5
	attack_interval = 0.2
	bounty = 500
	body_color = Color(0.13, 0.13, 0.15)
	body_height = 1.9


func _ready() -> void:
	super()
	_speech = Label3D.new()
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.font_size = 40
	_speech.pixel_size = 0.008
	_speech.outline_size = 10
	_speech.no_depth_test = true
	_speech.width = 900.0
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.position.y = body_height + 1.0
	add_child(_speech)
	_speech.text = TAUNTS[0]


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if is_posting:
		_posting_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		if _posting_left <= 0.0:
			is_posting = false
			_phone.visible = false
			_speech.text = TAUNTS.pick_random()
		return
	_post_left -= delta
	if _post_left <= 0.0:
		_post_left = post_interval
		_posting_left = post_duration
		is_posting = true
		_phone.visible = true
		_speech.text = POSTS.pick_random()
		return
	super(delta)


func _modify_damage(amount: float, _from: Vector3, _kind: StringName) -> float:
	return amount * posting_damage_multiplier if is_posting else amount


func _attack(victim: Node3D) -> void:
	var nozzle := global_position + Vector3.UP * 1.2
	var facing := (victim.global_position - global_position)
	facing.y = 0.0
	facing = facing.normalized()
	for i in 2:
		var reach := randf_range(1.0, attack_range)
		var side := facing.cross(Vector3.UP) * randf_range(-0.4, 0.4) * reach * 0.5
		Fx.flame_puff(get_parent(), nozzle + facing * reach + side, 0.4 + reach * 0.08, 0.3)

	var cone := cos(deg_to_rad(flame_cone_degrees))
	for node in _candidates():
		if not _is_valid(node) or _is_friend(node):
			continue
		var offset := node.global_position - global_position
		offset.y = 0.0
		if offset.length() > attack_range + 0.5 or offset.normalized().dot(facing) < cone:
			continue
		if node.has_method("apply_damage"):
			node.call(&"apply_damage", flame_dps * attack_interval, global_position, &"fire")


func _decorate(visual_root: Node3D) -> void:
	# Fuel tank on the back, nozzle forward (-Z), phone for posting.
	_add_box(visual_root, Vector3(0.36, 0.6, 0.24), Vector3(0.0, body_height * 0.62, 0.26), _solid(Color(0.6, 0.15, 0.1)))
	_add_box(visual_root, Vector3(0.08, 0.08, 0.8), Vector3(0.25, body_height * 0.52, -0.4), _solid(Color(0.2, 0.2, 0.2)))
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.6, 0.8, 1.0)
	screen.emission_enabled = true
	screen.emission = Color(0.5, 0.7, 1.0)
	_phone = _add_box(visual_root, Vector3(0.1, 0.18, 0.03), Vector3(-0.18, body_height * 0.72, -0.3), screen)
	_phone.visible = false
