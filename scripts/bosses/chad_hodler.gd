class_name ChadHodler
extends Enemy
## Boss (MoonMine, District 2): Chad Hodler, crypto-mining bro. Laser eyes
## at range, and every so often he pumps his community: HODL bros pile in.
## Below half health he pulls the rug: his bros log off, token bombs rain
## around the player (telegraphed), and he hides in a cold-wallet shield for
## a while. Counter: thin the bros, dodge the bombs, outlast the shield.

const LINES := [
	"Have fun staying poor.",
	"Diamond hands, dry river.",
	"Number go up, water go down.",
	"It's not a Ponzi, it's a community.",
	"Few understand this.",
	"Mining is basically recycling electricity.",
]

@export var laser_damage := 14.0
@export var summon_interval := 14.0
@export var bros_per_summon := 3
@export var line_interval := 7.5
## Cold-wallet shield after the rug pull (seconds).
@export var wallet_seconds := 10.0
@export var bomb_damage := 25.0

var rugged := false

var _line_left := 3.0
var _summon_left := 4.0


func _init() -> void:
	voice_pitch = 1.15
	outfit = "chad"
	max_health = 850.0
	move_speed = 3.4
	sight_range = 30.0
	attack_range = 22.0
	structure_engage_range = 16.0
	attack_interval = 1.2
	bounty = 400
	body_color = Color(0.08, 0.08, 0.09)
	boss_name = "CHAD HODLER"


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead or is_dormant():
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = line_interval
		speak(LINES.pick_random())
	if not rugged:
		_summon_left -= delta
		if _summon_left <= 0.0:
			_summon_left = summon_interval
			if HodlBro.summon_bros(self, bros_per_summon) > 0:
				speak("Pump it, frens!")
		if health < max_health * 0.5:
			rug_pull()


## Below half health: the bros log off, token bombs drop around the player,
## and he sits in a cold wallet for a while. Once per fight. Public for tests.
func rug_pull() -> void:
	if rugged:
		return
	rugged = true
	speak("RUG PULL! It was always a pump and dump.")
	get_tree().call_group(&"hodl_bros", &"log_off")
	shield_field(wallet_seconds)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		for i in 3:
			var angle := TAU * i / 3.0 + randf() * 0.5
			_drop_token_bomb(player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.0, 4.0), 1.2 + i * 0.4)


## A red ring on the ground, then a blast of worthless tokens.
func _drop_token_bomb(at: Vector3, delay: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.2
	torus.outer_radius = 3.5
	ring.mesh = torus
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.6, 0.1)
	ring.material_override = glow
	get_parent().add_child(ring)
	ring.global_position = at + Vector3.UP * 0.1
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * 0.2, delay).from(Vector3.ONE)
	tween.tween_callback(func() -> void:
		var blast := Explosive.new()
		blast.radius = 3.5
		blast.damage = bomb_damage
		ring.get_parent().add_child(blast)
		blast.global_position = at
		blast.detonate()
		ring.queue_free())


## Laser eyes: a hitscan beam from the head.
func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	var from := global_position + Vector3.UP * (body_height * 0.85)
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", laser_damage, from, &"energy")
	Fx.tracer(get_parent(), from, _aim_point_of(victim), Color(1.0, 0.15, 0.1), 0.1, 0.15)
	Sfx.play(&"zap", from, -6.0, 0.7)


func _on_death() -> void:
	speak("I was just holding it for a friend.")
	get_tree().call_group(&"hodl_bros", &"log_off")
