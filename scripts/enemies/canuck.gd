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
## The Mountie's revolver round.
@export var revolver_damage := 12.0
@export var patience := 150.0
## During the defense, with the player farther than this from the core,
## recruited Canadians hold the core instead of tagging along.
@export var post_leash := 30.0
## While holding the core they only take on hostiles this close to it, under
## the turrets' cover (chasing farther out got them picked off).
@export var post_radius := 14.0
## Holding a post, they fall back to the core below this share of health,
## fight only in self-defense, and recover `recover_rate` hp/s until
## `rejoin_share`, then go back out.
@export var fall_back_share := 0.35
@export var rejoin_share := 0.8
@export var recover_rate := 3.0

## Falling back from the post to recover (tests read it).
var falling_back := false

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
	hospital_share = 0.35


func setup(is_mountie: bool) -> void:
	mountie = is_mountie
	outfit = "mountie" if is_mountie else ["canuck_a", "canuck_b"].pick_random()
	if mountie:
		# The Mountie carries a service revolver: the group's ranged member.
		attack_range = 13.0
		attack_interval = 1.1


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
	speak(_join_line())
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
	if falling_back and not _is_valid(target):
		health = minf(health + recover_rate * delta, max_health)
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
	if health < max_health * fall_back_share and _defense_post() != null:
		if not falling_back:
			speak(["Sorry, I'm hurt! Falling back, eh!", "Need a Timbit break, sorry!"].pick_random())
			_speech_left = 2.5
		falling_back = true
	elif falling_back and (health >= max_health * rejoin_share or _defense_post() == null):
		falling_back = false
	return super()


func _candidates() -> Array[Node3D]:
	var list := super()
	var post: Variant = _defense_post()
	if post == null:
		return list
	var near: Array[Node3D] = []
	for node in list:
		if falling_back:
			if node.global_position.distance_to(global_position) <= 4.0:
				near.append(node)  # self-defense only
		elif node.global_position.distance_to(post as Vector3) <= post_radius:
			near.append(node)
	return near


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
		State.ALLY:
			var post: Variant = _defense_post()
			if post == null or order_point != Vector3.INF:
				super()
			elif _nav.target_position.distance_to(post as Vector3) > 7.0 \
					or (_nav.is_navigation_finished() and randf() < 0.05):
				# Take up a spot around the core; shift about now and then.
				var angle := randf() * TAU
				_nav.target_position = (post as Vector3) + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(4.0, 6.5)
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


## Where to stand guard when the defense is on and the player is away from
## the core: the level's ally post (a fence breach or the core), or the core
## itself while falling back.
func _defense_post() -> Variant:
	if order_point != Vector3.INF:
		return null  # under orders
	var level := get_tree().get_first_node_in_group("level")
	if level == null or not level.has_method("ally_post"):
		return null
	var post: Variant = level.call(&"ally_post")
	if post == null:
		return null
	if falling_back:
		var core := level.get("core") as Node3D
		if core and is_instance_valid(core):
			post = core.global_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.is_visible_in_tree() and player.global_position.distance_to(post as Vector3) <= post_leash:
		return null
	return post


## Tagging along with the player: patch up at the hospital. Holding a
## defense post: fall back to the core instead (the hospital is too far).
func _can_visit_hospital() -> bool:
	return super() and state == State.ALLY and _defense_post() == null


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	if mountie:
		_shoot(victim)
		return
	_act(&"swing")
	var damage := stick_damage
	if victim is Destructible and (victim as Destructible).damage_threshold < 1000.0:
		# Sabotage under orders: hard enough to get past a prop's threshold.
		damage = maxf(stick_damage, (victim as Destructible).damage_threshold + 5.0)
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", damage, global_position, &"melee")
	if victim.has_method("apply_knockback"):
		var push := victim.global_position - global_position
		push.y = 0.0
		victim.call(&"apply_knockback", push.normalized() * 3.0 + Vector3.UP * 1.0)
	Sfx.play(&"hit_wood", victim.global_position, -4.0)
	if randf() < 0.35:
		speak(_fight_line())
		_speech_left = 2.0


## Overrides: what they say joining up and mid-fight.
func _join_line() -> String:
	return THANKS


func _fight_line() -> String:
	return FIGHT_LINES.pick_random()


## The Mountie's revolver: one hitscan round, less accurate far off.
func _shoot(victim: Node3D) -> void:
	_act(&"pistol_shoot")
	var from := muzzle_point()
	var aim := _aim_point_of(victim)
	if randf() > lerpf(0.85, 0.5, clampf(_distance_to(victim) / attack_range, 0.0, 1.0)):
		aim += Vector3(randf_range(-1.2, 1.2), randf_range(-0.5, 0.8), randf_range(-1.2, 1.2))
	var query := PhysicsRayQueryParameters3D.create(from, from + (aim - from).normalized() * (attack_range + 4.0),
		SecurityGuard.SHOT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var to := from + (aim - from).normalized() * (attack_range + 4.0)
	Vfx.muzzle(get_parent(), from, Color(1.0, 0.8, 0.45), (aim - from).normalized(), 0.8)
	Sfx.play(&"guard_gun", from, -6.0, 0.9)
	if not hit.is_empty():
		to = hit["position"]
		var struck := hit["collider"] as Node
		if struck and struck.has_method("apply_damage") and not _is_friend(struck) and not struck is Player:
			struck.call(&"apply_damage", revolver_damage, from, &"bullet")
	Fx.tracer(get_parent(), from, to, Color(1.0, 0.85, 0.5))
	if randf() < 0.25:
		speak(["Stop in the name of the Crown, eh!", "Sorry, bud! Warning shot!", "Royal Canadian apology incoming!"].pick_random())
		_speech_left = 2.0


func _upper_pose() -> StringName:
	if mountie and state == State.ALLY:
		return &"pistol_aim" if _is_valid(target) and _has_los else &"pistol_idle"
	return &""


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
	if mountie:
		_hold_weapon(&"pistol", Color(0.25, 0.22, 0.2))
		return
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
