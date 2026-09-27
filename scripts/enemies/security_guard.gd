class_name SecurityGuard
extends Enemy
## Private Security: rifle hitscan, accuracy drops with distance.
## Against the player on foot they fight from cover: duck behind something
## solid nearby, pop out sideways to shoot, duck back. When two or more
## guards are on the player, one of them circles around to flank.

enum Tactic { NONE, COVER, PEEK, FLANK }

const SHOT_MASK := 1 | 2 | 16 | 32  # world, player, destructibles, units
## What counts as cover: world geometry and destructible props.
const COVER_MASK := 1 | 16
## Closer than this, guards stand and fight in the open.
const CLOSE_QUARTERS := 5.0

@export var shot_damage := 8.0
@export var close_accuracy := 0.8
@export var far_accuracy := 0.3
@export var uses_cover := true
## How far a guard looks for cover.
@export var cover_search := 8.0

var tactic := Tactic.NONE
var _cover := Vector3.INF
var _peek := Vector3.INF
var _flank := Vector3.INF
var _tactic_left := 0.0
var _search_left := 0.0
## In COVER and at the spot: crouched down.
var _settled := false


func _init() -> void:
	outfit = "guard"
	max_health = 60.0
	move_speed = 3.8
	sight_range = 25.0
	attack_range = 16.0
	attack_interval = 0.7
	bounty = 20
	body_color = Color(0.16, 0.17, 0.22)


func _decorate(_visual_root: Node3D) -> void:
	var dark := _solid(Color(0.06, 0.06, 0.07))
	var top := _head_top()
	Models.hat(_anchor(&"head"), &"cap", Color(0.08, 0.08, 0.09), top, body_height / 1.8)
	_add_box(_anchor(&"chest"), Vector3(0.48, 0.42, 0.36), Vector3(0.0, -0.06, 0.0), dark)  # vest
	_hold_weapon(&"pistol")


func _candidates() -> Array[Node3D]:
	var list := super()
	# A player's recon drone overhead is fair game.
	if faction == Faction.HOSTILE:
		for node in get_tree().get_nodes_in_group("player_drones"):
			list.append(node as Node3D)
	return list


func _think() -> void:
	super()
	_run_tactics()


## Cover, peek, and flank against the player on foot. Runs after the base
## think tick, so it overrides where the guard walks and, while hiding or
## flanking, holds fire (`_has_los` off) until it's in position.
func _run_tactics() -> void:
	var step := THINK_INTERVAL * (2.0 if is_far() else 1.0)
	_tactic_left -= step
	_search_left -= step
	var foe := target as Player
	if not uses_cover or foe == null or rushing or _distance_to(foe) < CLOSE_QUARTERS:
		tactic = Tactic.NONE
		return
	var eye := foe.global_position + Vector3.UP * 1.4
	match tactic:
		Tactic.NONE:
			if _search_left > 0.0:
				return
			_search_left = 2.0
			if _should_flank(foe):
				_flank = _flank_point(foe)
				if _flank != Vector3.INF:
					tactic = Tactic.FLANK
					_tactic_left = 7.0
					return
			_cover = _find_cover(eye)
			if _cover != Vector3.INF:
				tactic = Tactic.COVER
				_tactic_left = randf_range(1.0, 1.8)
		Tactic.COVER:
			if not _blocks(eye, _cover):
				# The player moved around it: find something else.
				tactic = Tactic.NONE
				_search_left = 0.0
				return
			_nav.target_position = _cover
			_has_los = false
			# In place, or as close as the navmesh gets it.
			var settled := _flat(global_position).distance_to(_flat(_cover)) < 0.9 \
				or (_nav.is_navigation_finished() and _flat(global_position).distance_to(_flat(_cover)) < 2.0)
			if settled and not _settled:
				_tactic_left = maxf(_tactic_left, randf_range(1.0, 1.6))  # just got here: stay down a moment
			_settled = settled
			if settled and _tactic_left <= 0.0:
				tactic = Tactic.PEEK
				_tactic_left = randf_range(1.8, 2.8)
			elif not settled and _tactic_left < -6.0:
				tactic = Tactic.NONE  # couldn't get there
		Tactic.PEEK:
			_nav.target_position = _peek
			if not _has_los and _nav.is_navigation_finished():
				# The peek spot has no shot after all: step out toward them.
				_nav.target_position = foe.global_position
			if _tactic_left <= 0.0:
				tactic = Tactic.COVER
				_tactic_left = randf_range(1.2, 2.2)
		Tactic.FLANK:
			_nav.target_position = _flank
			var arrived := _flat(global_position).distance_to(_flat(_flank)) < 1.5
			if arrived or _tactic_left <= 0.0:
				tactic = Tactic.NONE
				_search_left = 3.0  # shoot from the new angle for a while
			else:
				_has_los = false


## A spot on the navmesh within `cover_search` where something solid stands
## between it and `eye`, with a clear peek spot a step to the side. Rays from
## `eye` past the guard find the obstacles; candidates sit just behind where
## they hit. Picks the nearest good one; INF when there's none.
func _find_cover(eye: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_score := INF
	var spin := randf() * TAU
	for i in 16:
		var angle := spin + TAU * i / 16.0
		for radius: float in [cover_search * 0.45, cover_search]:
			var probe := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius + Vector3.UP * 1.2
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, probe, COVER_MASK))
			if hit.is_empty():
				continue
			var behind := (hit["position"] as Vector3) + _flat(probe - eye).normalized() * 1.0
			var spot := NavigationServer3D.map_get_closest_point(map, behind)
			if _flat(spot).distance_to(_flat(behind)) > 1.0 or spot.distance_to(global_position) > cover_search + 1.5:
				continue
			var range_to := _flat(spot).distance_to(_flat(eye))
			if range_to < CLOSE_QUARTERS + 1.0 or range_to > attack_range + 2.0:
				continue
			if not _covered(eye, spot):
				continue
			var peek := _peek_from(spot, eye, map)
			if peek == Vector3.INF:
				continue
			var score := spot.distance_to(global_position)
			if score < best_score:
				best_score = score
				best = spot
				_peek = peek
	return best


## `spot` and a step to either side of it are all hidden from `eye` (the
## navmesh rarely lands a guard exactly on the spot).
func _covered(eye: Vector3, spot: Vector3) -> bool:
	var side := _flat(eye - spot).normalized().cross(Vector3.UP) * 0.5
	return _blocks(eye, spot) and _blocks(eye, spot + side) and _blocks(eye, spot - side)


## Something solid right next to `spot` hides a standing guard from `eye`.
func _blocks(eye: Vector3, spot: Vector3) -> bool:
	var chest := spot + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(eye, chest, COVER_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit["position"] as Vector3).distance_to(chest) < 3.0


## A step to either side of the cover spot with a clear shot at `eye`.
func _peek_from(spot: Vector3, eye: Vector3, map: RID) -> Vector3:
	var toward := _flat(eye - spot).normalized()
	var side := toward.cross(Vector3.UP)
	var space := get_world_3d().direct_space_state
	for offset: float in [1.6, -1.6, 2.6, -2.6]:
		var peek := NavigationServer3D.map_get_closest_point(map, spot + side * offset)
		if _flat(peek).distance_to(_flat(spot + side * offset)) > 0.8:
			continue
		var query := PhysicsRayQueryParameters3D.create(peek + Vector3.UP * 1.4, eye, COVER_MASK)
		if space.intersect_ray(query).is_empty():
			return peek
	return Vector3.INF


## One flanker at a time, and only when someone else keeps the player busy.
func _should_flank(foe: Player) -> bool:
	var busy := 0
	for node in get_tree().get_nodes_in_group("hostiles"):
		var guard := node as SecurityGuard
		if guard == null or guard == self or not guard.uses_cover or guard.target != foe:
			continue
		if guard.tactic == Tactic.FLANK:
			return false
		busy += 1
	return busy >= 1 and randf() < 0.6


## A navmesh spot swung about 75 degrees around the player from where this
## guard stands, at fighting range.
func _flank_point(foe: Player) -> Vector3:
	var map := get_world_3d().navigation_map
	var from_foe := _flat(global_position - foe.global_position)
	var distance := clampf(from_foe.length(), 8.0, attack_range - 2.0)
	var sides: Array[float] = [1.3, -1.3]
	sides.shuffle()
	for turn in sides:
		var wanted := foe.global_position + from_foe.normalized().rotated(Vector3.UP, turn) * distance
		var spot := NavigationServer3D.map_get_closest_point(map, wanted)
		if _flat(spot).distance_to(_flat(wanted)) < 2.0:
			return spot
	return Vector3.INF


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _watches() -> bool:
	return uses_cover  # people, not the roof cannons or holo decoys


func _stance() -> StringName:
	var hiding := tactic == Tactic.COVER and _settled and velocity.length_squared() < 0.5
	return &"crouch_idle" if hiding else &""


func _upper_pose() -> StringName:
	if is_dormant():
		return &"fold_arms" if velocity.length_squared() < 0.25 else &""
	return &"pistol_aim" if _is_valid(target) and _has_los else &"pistol_idle"


func _attack(victim: Node3D) -> void:
	_act(&"pistol_shoot")
	var from := muzzle_point()
	var aim := _aim_point_of(victim)
	var accuracy := lerpf(close_accuracy, far_accuracy, clampf(_distance_to(victim) / sight_range, 0.0, 1.0))
	if randf() > accuracy:
		aim += Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 0.9), randf_range(-1.5, 1.5))

	var direction := (aim - from).normalized()
	var to := from + direction * (sight_range + 5.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, SHOT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	Vfx.muzzle(get_parent(), from + direction * 0.05, Color(1.0, 0.8, 0.45), direction, 0.9)
	Sfx.play(&"guard_gun", from, -6.0)
	if not hit.is_empty():
		to = hit["position"]
		var struck := hit["collider"] as Node
		if not struck is Enemy and not struck is Player:
			Vfx.impact(get_parent(), to, hit["normal"], Player.surface_of(struck, hit["normal"]), 0.8)
		if struck and struck.has_method("apply_damage") and not _is_friend(struck):
			struck.call(&"apply_damage", shot_damage, from, &"bullet")
	Fx.tracer(get_parent(), from, to, Color(1.0, 0.85, 0.5))
	_whiz_past_player(from, to, hit)


## A round that just misses the player cracks past their ear.
func _whiz_past_player(from: Vector3, to: Vector3, hit: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or not player.is_visible_in_tree() or (not hit.is_empty() and hit["collider"] == player):
		return
	var ear := player.global_position + Vector3.UP * 1.5
	var closest := Geometry3D.get_closest_point_to_segment(ear, from, to)
	if closest.distance_to(ear) < 2.5 and closest.distance_to(from) > 4.0:
		Sfx.play(&"whiz", closest, 2.0, 1.0, 0.12)

