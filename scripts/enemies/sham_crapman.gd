class_name ShamCrapman
extends Enemy
## Boss (wave 2): Sham Crapman, Synthetic Evangelist. Three projection drones
## wrap him and nearby hostiles in force fields. His energy blasts draw on
## two power pylons he plants on arrival: each standing pylon adds damage.
## Counter: shotgun the drones, then the pylons, then him.

const LINES := [
	"Alignment is when you agree with me.",
	"The model says your neighborhood is optional.",
	"I'm not a CEO. I'm a movement.",
	"AGI will fix the water. Eventually.",
	"Think of the shareholders' feelings.",
]

@export var drone_count := 3
@export var pylon_count := 2
@export var blast_damage := 22.0
## Extra blast damage per standing pylon (0.5 = +50%).
@export var pylon_bonus := 0.5
@export var line_interval := 7.0

var drones: Array[ProjectionDrone] = []
var pylons: Array[Destructible] = []

var _line_left := 0.0


func _init() -> void:
	voice_pitch = 1.0
	outfit = "sham"
	max_health = 750.0
	move_speed = 3.2
	sight_range = 30.0
	attack_range = 20.0
	structure_engage_range = 16.0
	attack_interval = 2.5
	bounty = 400
	body_color = Color(0.93, 0.93, 0.96)
	boss_name = "SHAM CRAPMAN"


func _ready() -> void:
	super()
	speak(LINES[0])
	_deploy.call_deferred()


func alive_pylons() -> int:
	return pylons.filter(func(p: Variant) -> bool:
		return is_instance_valid(p) and not (p as Destructible).is_destroyed).size()


func _deploy() -> void:
	for i in drone_count:
		var drone := ProjectionDrone.new()
		drone.owner_unit = self
		drone.position = global_position + Vector3(0.0, 3.0, 0.0)
		drone.set("_angle", TAU * i / drone_count)
		get_parent().add_child(drone)
		drones.append(drone)
	for i in pylon_count:
		var pylon := Destructible.new()
		pylon.size = Vector3(0.8, 4.0, 0.8)
		pylon.color = Color(0.2, 0.22, 0.28)
		pylon.max_health = 150.0
		pylon.chunks = Vector3i(1, 3, 1)
		pylon.label = "Power pylon"
		pylon.position = global_position + Vector3(-4.0 + i * 8.0, -global_position.y, 3.0)
		get_parent().add_child(pylon)
		pylon.add_to_group("pylons")
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.4, 0.9, 1.0)
		glow.emission_enabled = true
		glow.emission = Color(0.4, 0.9, 1.0)
		glow.emission_energy_multiplier = 3.0
		Models.ball(pylon, 0.45, Vector3(0.0, 4.3, 0.0), glow)
		pylons.append(pylon)


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = line_interval
		speak(LINES.pick_random())


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	var from := global_position + Vector3.UP * 1.5
	var damage := blast_damage * (1.0 + pylon_bonus * alive_pylons())
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", damage, from, &"energy")
	Fx.tracer(get_parent(), from, _aim_point_of(victim), Color(0.4, 0.9, 1.0), 0.12, 0.15)


func _on_death() -> void:
	speak("This is just a pivot.")
	for pylon in pylons:
		if is_instance_valid(pylon) and not pylon.is_destroyed:
			pylon.shatter(pylon.global_position + Vector3.UP * 2.0, 80.0)


func _decorate(_visual_root: Node3D) -> void:
	pass  # the white suit and glowing badge are on the skin
