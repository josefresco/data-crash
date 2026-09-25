class_name Enemy
extends CharacterBody3D
## Base for NPC combatants. Builds its own body, walks the navmesh, picks targets
## by faction, and calls _attack() when a target is in range and visible.
## Subclasses set stats in _init() and override _attack() / _decorate().

## Emitted when this unit dies.
signal died(enemy: Enemy)
## Emitted once when this unit stops counting as a hostile (death or conversion).
signal defeated(enemy: Enemy)

enum Faction { HOSTILE, ALLY }

## Line-of-sight blockers: world, player, destructibles, other units.
const LOS_MASK := 1 | 2 | 16 | 32
const THINK_INTERVAL := 0.25
const ALLY_TINT := Color(0.3, 0.85, 0.4)
## Every group a unit can belong to via _faction_group().
const FACTION_GROUPS: Array[String] = ["hostiles", "allies", "protesters", "townspeople"]

@export var faction := Faction.HOSTILE
@export var max_health := 60.0
@export var move_speed := 4.0
@export var sight_range := 25.0
@export var attack_range := 16.0
@export var attack_interval := 0.7
@export var bounty := 25
## Max range for attacking structures. Shorter than attack_range so ranged
## units push into turret coverage instead of sniping from outside it.
@export var structure_engage_range := 9.0

## Hostiles with nothing to fight walk here (the green core in wave defense).
var objective: Node3D
## Idle units wander around this point. Defaults to the spawn position.
var home: Vector3
var health: float
var target: Node3D

## Set by the wave spawner when a wave drags on: charge the objective, ignore the rest.
var rushing := false

var body_color := Color(0.2, 0.2, 0.25)
var skin_color := Models.random_skin()
var body_bulk := 1.0
var body_radius := 0.35
var body_height := 1.8

var _nav: NavigationAgent3D
var _visual: Node3D
var _material: StandardMaterial3D
var _attack_timer := 0.0
var _think_timer := 0.0
var _stun_timer := 0.0
var _wander_timer := 0.0
var _has_los := false
var _is_dead := false
var _defeated_emitted := false
var _rig: Node3D
var _walk_phase := randf() * TAU
var _stuck_time := 0.0
var _investigate_left := 0.0
var _sidestep_left := 0.0
var _sidestep := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	collision_layer = Game.LAYER_ENEMIES
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_VEHICLES \
		| Game.LAYER_DESTRUCTIBLE | Game.LAYER_ENEMIES
	health = max_health
	home = global_position
	_build_body()

	_nav = NavigationAgent3D.new()
	_nav.radius = body_radius + 0.1
	_nav.path_desired_distance = 0.8
	_nav.target_desired_distance = 1.0
	add_child(_nav)
	_nav.target_position = global_position

	set_faction(faction)
	_think_timer = randf() * THINK_INTERVAL  # spread thinking across frames


func set_faction(value: Faction) -> void:
	faction = value
	for group in FACTION_GROUPS:
		remove_from_group(group)
	var group := _faction_group()
	if not group.is_empty():
		add_to_group(group)
	if _material:
		_material.albedo_color = _base_color()


## Point other units aim at.
func aim_point() -> Vector3:
	return global_position + Vector3.UP * body_height * 0.6


func is_alive() -> bool:
	return not _is_dead


func apply_damage(amount: float, from: Vector3, kind: StringName = &"generic") -> void:
	if _is_dead:
		return
	amount = _modify_damage(amount, from, kind)
	if amount <= 0.0:
		return
	health -= amount
	_flash(Color(1.0, 0.3, 0.3))
	if health <= 0.0:
		_die()
	elif not _is_valid(target) and _nav:
		# Getting hit reveals roughly where the attacker is: go look.
		_nav.target_position = from


## Walk over to check out a noise (thrown rocks). Ignored while fighting.
func investigate(point: Vector3) -> void:
	if _is_dead or _is_valid(target) or faction != Faction.HOSTILE:
		return
	_investigate_left = 5.0
	_nav.target_position = point


func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)
	_flash(Color(0.4, 0.7, 1.0))


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	var move_dir := Vector3.ZERO
	if _stun_timer > 0.0:
		_stun_timer -= delta
	else:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer = THINK_INTERVAL
			_think()

		if _is_valid(target) and _has_los and _distance_to(target) <= _engage_range(target):
			_face(target.global_position, delta)
			if _attack_timer <= 0.0:
				_attack_timer = attack_interval
				_attack(target)
		else:
			move_dir = _unstick(_nav_direction(), delta)

	var weight := 1.0 - exp(-10.0 * delta)
	velocity.x = lerpf(velocity.x, move_dir.x * move_speed, weight)
	velocity.z = lerpf(velocity.z, move_dir.z * move_speed, weight)
	if move_dir != Vector3.ZERO:
		_face(global_position + move_dir, delta)
	move_and_slide()
	_animate(delta)

	if global_position.y < -30.0:
		_die()


## Override: group this unit joins. Turrets and allied dogs only shoot "hostiles".
func _faction_group() -> String:
	return "hostiles" if faction == Faction.HOSTILE else "allies"


## Override: armor, shields. `from` is the attacker's position.
func _modify_damage(amount: float, _from: Vector3, _kind: StringName) -> float:
	return amount


## Override: extra consequences of dying (trust penalties, dropping captives).
func _on_death() -> void:
	pass


## Marks this unit as no longer part of the fight (wave bookkeeping). Idempotent.
func _emit_defeated() -> void:
	if not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit(self)


## Override: deal damage to `victim`.
func _attack(_victim: Node3D) -> void:
	pass


## Override: add extra meshes (helmets, snouts) under `visual`.
func _decorate(_visual_root: Node3D) -> void:
	pass


func _think() -> void:
	target = _pick_target()
	if _is_valid(target):
		_has_los = _can_see(target)
		_nav.target_position = target.global_position
		return
	_has_los = false
	if _investigate_left > 0.0:
		_investigate_left -= THINK_INTERVAL
		return
	_idle()


## Override: what to do with no target. Allies tag along with the player,
## hostiles march on their objective, everyone else wanders near home.
func _idle() -> void:
	if faction == Faction.ALLY:
		_follow_player()
	elif _is_valid(objective):
		_nav.target_position = objective.global_position
	else:
		_wander()


func _animate(delta: float) -> void:
	if _rig == null:
		return
	var real := get_real_velocity()
	var speed := Vector2(real.x, real.z).length()
	_walk_phase += speed * delta * 3.2
	Models.animate_walk(_rig, _walk_phase, clampf(speed / maxf(move_speed, 0.1), 0.0, 1.0))


## Units blocked by things the navmesh can't see (parked cars, crowds) sidestep.
func _unstick(move_dir: Vector3, delta: float) -> Vector3:
	if move_dir == Vector3.ZERO:
		_stuck_time = 0.0
		return move_dir
	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		return (move_dir * 0.3 + _sidestep).normalized()
	var real := get_real_velocity()
	if Vector2(real.x, real.z).length() < move_speed * 0.2:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.0:
		_stuck_time = 0.0
		_sidestep_left = randf_range(0.6, 1.2)
		_sidestep = move_dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	return move_dir


func _engage_range(other: Node3D) -> float:
	if other is Destructible:
		return minf(attack_range, structure_engage_range)
	return attack_range


func _pick_target() -> Node3D:
	if rushing and faction == Faction.HOSTILE and _is_valid(objective):
		return objective
	var best: Node3D = null
	var best_distance := sight_range
	for candidate in _candidates():
		if not _is_valid(candidate):
			continue
		var distance := _distance_to(candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _candidates() -> Array[Node3D]:
	var list: Array[Node3D] = []
	if faction == Faction.HOSTILE:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player:
			list.append(player.vehicle if player.vehicle else player)
		for node in get_tree().get_nodes_in_group("allies"):
			list.append(node as Node3D)
		for node in get_tree().get_nodes_in_group("structures"):
			list.append(node as Node3D)
	else:
		for node in get_tree().get_nodes_in_group("hostiles"):
			list.append(node as Node3D)
	return list


func _can_see(other: Node3D) -> bool:
	if other is VehicleBody3D:
		return true  # not on the LOS mask; bullets just bounce off anyway
	var from := global_position + Vector3.UP * body_height * 0.8
	var to := _aim_point_of(other)
	var query := PhysicsRayQueryParameters3D.create(from, to, LOS_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == other


func _follow_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.is_visible_in_tree() and global_position.distance_to(player.global_position) > 4.0:
		_nav.target_position = player.global_position
	else:
		_wander()


func _wander() -> void:
	_wander_timer -= THINK_INTERVAL
	if _wander_timer > 0.0 or not _nav.is_navigation_finished():
		return
	_wander_timer = randf_range(2.0, 5.0)
	var offset := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
	_nav.target_position = home + offset


func _nav_direction() -> Vector3:
	if _nav.is_navigation_finished():
		return Vector3.ZERO
	var step := _nav.get_next_path_position() - global_position
	step.y = 0.0
	return step.normalized() if step.length_squared() > 0.0025 else Vector3.ZERO


func _face(point: Vector3, delta: float) -> void:
	var direction := point - global_position
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	var yaw := atan2(-direction.x, -direction.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 1.0 - exp(-12.0 * delta))


## Horizontal distance, or distance to the surface for big box targets.
func _distance_to(other: Node3D) -> float:
	if other is Destructible:
		return (other as Destructible).distance_to_point(global_position + Vector3.UP * 0.5)
	var offset := other.global_position - global_position
	return Vector2(offset.x, offset.z).length()


func _aim_point_of(other: Node3D) -> Vector3:
	if other is Enemy:
		return (other as Enemy).aim_point()
	if other is Destructible:
		var box := other as Destructible
		return box.global_position + Vector3.UP * minf(box.size.y * 0.5, 1.5)
	return other.global_position + Vector3.UP * 1.0


func _is_friend(other: Object) -> bool:
	if other is Enemy:
		return (other as Enemy).faction == faction
	# Allies never hurt the player or player-built structures.
	return faction == Faction.ALLY and (other is Player or (other is Node and (other as Node).is_in_group("structures")))


## `node` is untyped: targets may be freed between think ticks.
func _is_valid(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node as Node).is_inside_tree():
		return false
	if node is Enemy:
		return (node as Enemy).is_alive()
	if node is Destructible:
		return not (node as Destructible).is_destroyed
	return true


func _base_color() -> Color:
	return body_color if faction == Faction.HOSTILE else body_color.lerp(ALLY_TINT, 0.6)


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = maxf(body_height, body_radius * 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)

	_visual = Node3D.new()
	add_child(_visual)
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color()
	_rig = _build_visual()
	if _rig:
		_visual.add_child(_rig)
	_decorate(_visual)


## Override: the model under _visual. `_material` is this unit's own shirt /
## fur material (tinted for allies, flashed on hits).
func _build_visual() -> Node3D:
	return Models.humanoid(_material, body_color.darkened(0.55), skin_color, body_height, body_bulk)


func _add_box(parent: Node3D, box_size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = box_size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
	return mesh


func _solid(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _flash(color: Color) -> void:
	if _material == null:
		return
	_material.albedo_color = color
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", _base_color(), 0.2)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if faction == Faction.HOSTILE and not _defeated_emitted:
		Game.add_cash(bounty)
	_emit_defeated()
	_on_death()
	for group in FACTION_GROUPS:
		remove_from_group(group)
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	died.emit(self)
	_play_death()


## Override: death animation. Must free the node when done.
func _play_death() -> void:
	var tween := create_tween()
	tween.tween_property(_visual, "rotation:x", -PI * 0.5, 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.4)
	tween.tween_callback(queue_free)
