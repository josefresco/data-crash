class_name Police
extends Enemy
## Local Police: riot shield blocks most frontal bullet damage; taser slows.
## Counters: flank them, use explosives, or stun them (EMP drops the shield).

@export var taser_damage := 5.0
@export var taser_slow := 0.25
@export var taser_slow_duration := 1.5
## Share of frontal non-explosive damage that gets through the shield.
@export var shield_leak := 0.35
## Seconds the shield stays down after a stun.
@export var shield_recovery := 5.0

var _shield: MeshInstance3D
var _shield_down_left := 0.0


func _init() -> void:
	max_health = 90.0
	move_speed = 3.5
	sight_range = 22.0
	attack_range = 6.0
	attack_interval = 1.2
	bounty = 20
	body_color = Color(0.12, 0.2, 0.45)


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


func _decorate(visual_root: Node3D) -> void:
	var shield_mat := StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.7, 0.8, 0.9, 0.55)
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield = _add_box(visual_root, Vector3(0.9, 1.3, 0.08), Vector3(-0.1, 0.9, -0.5), shield_mat)
	var navy := _solid(Color(0.05, 0.08, 0.2))
	_add_box(visual_root, Vector3(0.34, 0.1, 0.36), Vector3(0.0, body_height * 0.97, 0.0), navy)  # cap
	_add_box(visual_root, Vector3(0.36, 0.03, 0.18), Vector3(0.0, body_height * 0.945, -0.2), navy)  # brim
	_add_box(visual_root, Vector3(0.1, 0.06, 0.06), Vector3(0.1, body_height * 0.72, -0.14), _solid(Color(0.9, 0.8, 0.2)))  # badge


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	var from := global_position + Vector3.UP * 1.2
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", taser_damage, from, &"taser")
	if victim.has_method("apply_slow"):
		victim.call(&"apply_slow", taser_slow, taser_slow_duration)
	Fx.tracer(get_parent(), from, _aim_point_of(victim), Color(0.5, 0.8, 1.0), 0.02, 0.15)
