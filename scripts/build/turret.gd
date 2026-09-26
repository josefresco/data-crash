class_name Turret
extends Structure
## Community-built auto turret. Targets the nearest visible hostile in range.
## Fires over barricades (its ray ignores destructibles).

const SHOT_MASK := 1 | 32  # world + units

@export var fire_range := 18.0
@export var shot_damage := 7.0
@export var fire_interval := 0.35

var _head: Node3D
var _target: Enemy
var _cooldown := 0.0
var _scan_timer := 0.0


func _init() -> void:
	size = Vector3(1.2, 1.0, 1.2)
	color = Color(0.85, 1.0, 0.88)
	surface_kind = &"plates"
	max_health = 200.0
	chunks = Vector3i(2, 2, 2)
	cost = 175
	label = "Turret"


func _ready() -> void:
	super()
	_head = Node3D.new()
	_head.position.y = size.y + 0.3
	add_child(_head)
	_add_box(Vector3(0.8, 0.5, 0.8), Vector3.ZERO, Color(0.75, 0.95, 0.8), _head, &"plates")
	_add_box(Vector3(0.15, 0.15, 1.1), Vector3(0.0, 0.05, -0.6), Color(0.1, 0.1, 0.1), _head)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_destroyed:
		return
	_cooldown -= delta
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.2
		_target = _find_target()
	if not _is_target_valid(_target):
		return
	var aim := _target.aim_point()
	if _head.global_position.distance_squared_to(aim) > 0.01:
		_head.look_at(aim, Vector3.UP)
	if _cooldown <= 0.0 and not is_picketed():
		_cooldown = fire_interval
		_shoot(aim)


## True while an Orange Hat protester pickets nearby: we don't fire on civilians.
func is_picketed() -> bool:
	for node in get_tree().get_nodes_in_group("protesters"):
		var protester := node as OrangeHat
		if protester and protester.blocks_turret_at(global_position):
			return true
	return false


func _find_target() -> Enemy:
	var best: Enemy = null
	var best_distance := fire_range
	for node in get_tree().get_nodes_in_group("hostiles"):
		var enemy := node as Enemy
		if not _is_target_valid(enemy):
			continue
		var distance := _head.global_position.distance_to(enemy.aim_point())
		if distance < best_distance and _can_see(enemy):
			best = enemy
			best_distance = distance
	return best


func _can_see(enemy: Enemy) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_head.global_position, enemy.aim_point(), SHOT_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == enemy


func _shoot(aim: Vector3) -> void:
	var from := _head.global_position
	var to := from + (aim - from).normalized() * (fire_range + 2.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, SHOT_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = hit["position"]
		var enemy := hit["collider"] as Enemy
		if enemy and enemy.faction == Enemy.Faction.HOSTILE:
			enemy.apply_damage(shot_damage, from, &"bullet")
	Vfx.muzzle(get_parent(), from + (to - from).normalized() * 0.7, Color(0.6, 1.0, 0.7))
	Fx.tracer(get_parent(), from, to, Color(0.5, 1.0, 0.6))


## `enemy` is untyped: the cached target may have been freed since the last scan.
func _is_target_valid(enemy: Variant) -> bool:
	return enemy != null and is_instance_valid(enemy) and (enemy as Enemy).is_alive() \
		and (enemy as Enemy).faction == Enemy.Faction.HOSTILE
