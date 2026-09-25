class_name ElmoTruck
extends FelsaCar
## Boss phase A: Elmo Mushbrains in his armored Felsa Truck. Rams, and every
## few seconds stops to charge a "Beta Feature" shockwave (telegraphed with a
## growing ring). EMP only stalls it briefly. Wrecking it forces him out.

signal wrecked(truck: ElmoTruck)

const LINES := [
	"You can't stop progress. I own progress.",
	"This datacenter was carbon neutral. In beta.",
	"Full Self-Ramming is a feature, not a bug.",
	"Water is a legacy resource.",
	"I'm literally saving humanity right now.",
	"Your neighborhood is a rounding error.",
]

@export var shockwave_interval := 9.0
@export var shockwave_charge := 1.2
@export var shockwave_radius := 11.0
@export var shockwave_damage := 25.0
@export var line_interval := 6.0

var _shock_left := 5.0
var _charge_left := 0.0
var _line_left := 0.0
var _line_index := 0
var _speech: Label3D
var _ring: MeshInstance3D


func _init() -> void:
	max_health = 1200.0
	top_speed = 13.0
	acceleration = 5.0
	turn_rate = 1.6
	wobble = 0.1
	ram_damage_per_mps = 3.5
	body_size = Vector3(2.6, 2.0, 6.0)
	body_color = Color(0.62, 0.64, 0.68)
	explosion_radius = 7.0
	explosion_damage = 60.0
	bounty = 300


## Bosses shrug off hacks: a short stall and some damage, no battery fire.
func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, minf(duration, 1.0))
	apply_damage(60.0, global_position, &"emp")
	say("Who authorized that firmware update?!")


func say(text: String) -> void:
	if _speech:
		_speech.text = text


func _ready() -> void:
	super()
	_speech = Label3D.new()
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.font_size = 48
	_speech.pixel_size = 0.02  # readable from down the road
	_speech.outline_size = 12
	_speech.modulate = Color(1.0, 0.95, 0.8)
	_speech.position.y = body_size.y + 2.2
	_speech.no_depth_test = true
	add_child(_speech)
	say(LINES[0])

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.0
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.4, 0.8, 1.0)
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.material_override = ring_mat
	_ring.visible = false
	_ring.position.y = 0.3
	add_child(_ring)


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0 and _charge_left <= 0.0:
		_line_left = line_interval
		_line_index = (_line_index + 1) % LINES.size()
		say(LINES[_line_index])

	if _charge_left > 0.0:
		_charge_left -= delta
		var grown := 1.0 - _charge_left / shockwave_charge
		_ring.scale = Vector3.ONE * lerpf(1.0, shockwave_radius, grown)
		if _charge_left <= 0.0:
			_release_shockwave()
		return
	_shock_left -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _shock_left <= 0.0 and player and global_position.distance_to(player.global_position) < shockwave_radius + 4.0:
		_charge_left = shockwave_charge
		_stun_timer = shockwave_charge + 0.3  # parks while charging: a window to hit it
		_ring.visible = true
		say("BETA FEATURE!")


func _release_shockwave() -> void:
	_ring.visible = false
	_shock_left = shockwave_interval
	Explosive.spawn_flash(get_parent(), global_position + Vector3.UP, shockwave_radius * 0.5, Color(0.4, 0.8, 1.0))
	var victims: Array[Node] = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("allies") \
		+ get_tree().get_nodes_in_group("structures") + get_tree().get_nodes_in_group("townspeople")
	for node in victims:
		var victim := node as Node3D
		if victim == null or not victim.is_visible_in_tree():
			continue
		var offset := victim.global_position - global_position
		if offset.length() > shockwave_radius:
			continue
		if victim.has_method("apply_damage"):
			victim.call(&"apply_damage", shockwave_damage, global_position, &"shockwave")
		if victim.has_method("apply_knockback"):
			offset.y = 0.0
			victim.call(&"apply_knockback", offset.normalized() * 12.0 + Vector3.UP * 5.0)


func _on_death() -> void:
	super()
	wrecked.emit(self)
