class_name Police
extends Enemy
## Local Police: riot shield blocks most frontal bullet damage; taser slows.
## Two or more officers with shields up on the player advance as a shield
## wall: a line across the player's approach, shields toward the player,
## with anyone ahead of the line slowing so they arrive together.
## Counters: flank them, use explosives, or stun them (EMP drops the shield).

## Gap between officers in a shield line, and how far ahead of the line's
## average an officer may get before slowing down.
const LINE_SPACING := 1.3
const LINE_SLACK := 1.5

@export var taser_damage := 5.0
@export var taser_slow := 0.25
@export var taser_slow_duration := 1.5
## Share of frontal non-explosive damage that gets through the shield.
@export var shield_leak := 0.35
## Seconds the shield stays down after a stun.
@export var shield_recovery := 5.0

var _shield: MeshInstance3D
var _shield_down_left := 0.0
## In a shield wall right now (tests read it).
var in_line := false


func _init() -> void:
	outfit = "police"
	max_health = 90.0
	move_speed = 3.5
	sight_range = 22.0
	attack_range = 6.0
	attack_interval = 1.2
	bounty = 20
	body_color = Color(0.12, 0.2, 0.45)
	# Wide enough to include the riot shield: officers can't stand inside
	# each other's shields.
	body_radius = 0.5


func is_shield_up() -> bool:
	return _shield_down_left <= 0.0


func stun(duration: float) -> void:
	super(duration)
	_shield_down_left = maxf(_shield_down_left, shield_recovery)
	_shield.visible = false


func _physics_process(delta: float) -> void:
	if _shield_down_left > 0.0:
		_shield_down_left -= delta
		if _shield_down_left <= 0.0:
			_shield.visible = true
	super(delta)


func _distracted_line(by: Node3D) -> String:
	if by is KidRider:
		return ["Hey kid! Get off the road!", "Slow down, you little...!", "Is that a wheelie? Stop that!"].pick_random()
	return ["Ma'am, please step back.", "Ma'am, I'm just doing my job.", "Okay, okay, I hear you, ma'am.", "Ma'am, that sign is very... large."].pick_random()


func _think() -> void:
	super()
	_hold_the_line()


## Shield wall against the player on foot: slot into a line across the
## approach, facing the player, pacing to the line's slowest member.
func _hold_the_line() -> void:
	in_line = false
	speed_scale = 1.0
	var foe := target as Player
	if foe == null or not is_shield_up() or rushing or _distance_to(foe) <= attack_range:
		return
	var line: Array[Police] = []
	for node in get_tree().get_nodes_in_group("hostiles"):
		var cop := node as Police
		if cop and cop.is_alive() and cop.target == foe and cop.is_shield_up() \
				and cop.global_position.distance_to(global_position) < 20.0:
			line.append(cop)
	if line.size() < 2:
		return
	var center := Vector3.ZERO
	for cop in line:
		center += cop.global_position
	center /= line.size()
	var toward := foe.global_position - center
	toward.y = 0.0
	toward = toward.normalized()
	var side := toward.cross(Vector3.UP)
	# Order along the line by where each officer already stands.
	line.sort_custom(func(a: Police, b: Police) -> bool:
		return a.global_position.dot(side) < b.global_position.dot(side))
	var slot := line.find(self) - (line.size() - 1) * 0.5
	var stop := foe.global_position - toward * (attack_range - 1.0)
	_nav.target_position = stop + side * slot * LINE_SPACING
	# Hold back when ahead of the line.
	var ahead := (global_position - center).dot(toward)
	if ahead > LINE_SLACK:
		speed_scale = 0.35
	elif ahead > 0.5:
		speed_scale = 0.7
	in_line = true


func _look_while_moving() -> Variant:
	if in_line and _is_valid(target):
		return (target as Node3D).global_position
	return null


func _modify_damage(amount: float, from: Vector3, kind: StringName) -> float:
	if kind == &"explosive" or kind == &"fire" or not is_shield_up():
		return amount
	var to_attacker := from - global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.01:
		return amount
	var facing := -_visual.global_basis.z
	facing.y = 0.0
	if facing.normalized().dot(to_attacker.normalized()) > 0.3:
		return amount * shield_leak
	return amount


func _decorate(_visual_root: Node3D) -> void:
	var shield_mat := StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.7, 0.8, 0.9, 0.55)
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield = _add_box(_anchor(&"chest"), Vector3(0.8, 1.1, 0.06), Vector3(-0.1, -0.28, -0.5), shield_mat)
	var navy := _solid(Color(0.05, 0.08, 0.2))
	var top := _head_top()
	Models.hat(_anchor(&"head"), &"police", navy.albedo_color, top, body_height / 1.8)
	_hold_weapon(&"pistol", Color(1.0, 0.82, 0.1), 0.85)  # taser


func _upper_pose() -> StringName:
	return &"shield_idle" if is_shield_up() else &""


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	_act(&"punch_jab")
	var from := muzzle_point()
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", taser_damage, from, &"taser")
	if victim.has_method("apply_slow"):
		victim.call(&"apply_slow", taser_slow, taser_slow_duration)
	Fx.tracer(get_parent(), from, _aim_point_of(victim), Color(0.5, 0.8, 1.0), 0.02, 0.15)
	Sfx.play(&"zap", from, -6.0, 1.4)
