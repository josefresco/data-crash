class_name ReplyGuy
extends Enemy
## Elmo's Twatter faithful: very pale, very large men who answer every Twat he
## posts. Slow and soft, they waddle at whoever is bothering Elmo and slap at
## close range while "well, actually"-ing. They log off when Elmo goes down.

const LINES := [
	"Well, actually...",
	"Source?",
	"He's literally Iron Man.",
	"Ratio.",
	"Do your own research.",
	"Concerning.",
	"Elmo, notice me!",
	"I'm something of an engineer myself.",
	"Touch grass? Never heard of her.",
	"This is a free speech zone!",
]

const MAX_ALIVE := 8

@export var slap_damage := 7.0

var _line_left := 0.0
var _logging_off := false


func _init() -> void:
	voice_pitch = 0.8
	outfit = "reply_guy"
	max_health = 80.0
	move_speed = 2.8
	sight_range = 35.0
	attack_range = 1.8
	attack_interval = 1.1
	bounty = 8
	body_radius = 0.5
	body_height = 1.75


func _ready() -> void:
	super()
	add_to_group("reply_guys")
	_line_left = randf_range(0.0, 2.0)


func _process(delta: float) -> void:
	super(delta)
	if _is_dead or _logging_off:
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = randf_range(3.5, 6.0)
		speak(LINES.pick_random() if randf() < 0.7 else "")


## Elmo went down: they wander off to post about it. Not a kill, no bounty.
func log_off() -> void:
	if _is_dead or _logging_off:
		return
	_logging_off = true
	speak("...brb, logging off")
	_emit_defeated()
	for group in FACTION_GROUPS:
		remove_from_group(group)
	collision_layer = 0
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(_visual, "scale", Vector3(1.0, 0.0, 1.0), 0.6)
	tween.tween_callback(queue_free)


func _build_visual() -> Node3D:
	var model := CharacterModel.create(outfit, body_height)
	model.scale = Vector3(1.55, 1.0, 1.5)  # a lot of guy
	return model


func _decorate(_visual_root: Node3D) -> void:
	# Gut straining the fan tee, and a phone (they are always online too).
	var tee := _solid(Color(0.16, 0.16, 0.18))
	Models.ball(_anchor(&"chest"), 0.27, Vector3(0.0, -0.2, -0.1), tee).scale = Vector3(1.0, 0.85, 0.75)
	Models.box(_anchor(&"hand_l"), Vector3(0.09, 0.16, 0.025), Vector3(0.0, 0.06, -0.08), Models.glow(Color(0.55, 0.75, 1.0), 1.5))


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", slap_damage, global_position, &"melee")
	Sfx.play(&"hit_soft", victim.global_position, -4.0)


## Spawns up to `count` reply guys in a ring 6-9 m around `host`, keeping at
## most MAX_ALIVE on the map. Returns how many showed up.
static func summon(host: Node3D, count: int) -> int:
	var tree := host.get_tree()
	var room := MAX_ALIVE - tree.get_nodes_in_group("reply_guys").size()
	var spawned := 0
	var nav_map := host.get_world_3d().navigation_map
	for i in mini(count, room):
		var angle := randf() * TAU
		var spot := host.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(6.0, 9.0)
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			spot = NavigationServer3D.map_get_closest_point(nav_map, spot)
		var guy := ReplyGuy.new()
		guy.position = (host.get_parent() as Node3D).to_local(spot + Vector3.UP * 0.1)
		host.get_parent().add_child(guy)
		Vfx.dust(host.get_parent(), spot, 1.0)
		spawned += 1
	return spawned
