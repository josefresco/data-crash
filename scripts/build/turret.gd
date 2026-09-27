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
	color = Color(0.78, 0.9, 0.8)
	surface_kind = &"paint"
	max_health = 200.0
	chunks = Vector3i(2, 2, 2)
	cost = 175
	label = "Turret"


## Octagonal pedestal (tapered), not the collider box.
func _visual_mesh() -> Mesh:
	var pedestal := CylinderMesh.new()
	pedestal.top_radius = 0.42
	pedestal.bottom_radius = 0.62
	pedestal.height = size.y
	pedestal.radial_segments = 8
	pedestal.rings = 1
	var tool := SurfaceTool.new()
	tool.append_from(pedestal, 0, Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)))
	return tool.commit()


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	var dark := Color(0.16, 0.18, 0.17)
	# Foot ring, a hazard collar, and a solar fin feeding it.
	_add_box(Vector3(1.3, 0.12, 1.3), Vector3(0.0, 0.06, 0.0), dark, null, &"plates")
	_add_box(Vector3(0.9, 0.08, 0.9), Vector3(0.0, size.y - 0.04, 0.0), Color(0.95, 0.75, 0.1), null, &"paint")
	var fin := _add_box(Vector3(0.9, 0.04, 0.5), Vector3(0.0, size.y * 0.55, 0.6), Color.WHITE, null, &"solar")
	fin.rotation.x = deg_to_rad(35.0)
	_head = Node3D.new()
	_head.position.y = size.y + 0.32
	add_child(_head)
	# Armored head: a rounded drum with a sloped front plate.
	var drum := MeshInstance3D.new()
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.38
	drum_mesh.bottom_radius = 0.38
	drum_mesh.height = 0.62
	drum_mesh.radial_segments = 12
	drum.mesh = drum_mesh
	drum.rotation.z = PI * 0.5
	drum.material_override = Models.mat(Color(0.72, 0.9, 0.76), &"paint")
	_head.add_child(drum)
	var plate := _add_box(Vector3(0.66, 0.46, 0.08), Vector3(0.0, 0.0, -0.36), Color(0.55, 0.75, 0.6), _head, &"paint")
	plate.rotation.x = deg_to_rad(-18.0)
	for side in [-0.12, 0.12]:
		var barrel := Models.cylinder(_head, 0.045, 0.9, Vector3(side, 0.02, -0.75), Models.mat(Color(0.1, 0.1, 0.1), &"metal"), 8)
		barrel.rotation.x = PI * 0.5
		var shroud := Models.cylinder(_head, 0.075, 0.3, Vector3(side, 0.02, -0.5), Models.mat(dark, &"metal"), 8)
		shroud.rotation.x = PI * 0.5
	Models.ball(_head, 0.07, Vector3(0.24, 0.2, -0.36), Models.glow(Color(0.3, 1.0, 0.5), 3.0))
	_add_box(Vector3(0.2, 0.26, 0.34), Vector3(0.4, -0.05, 0.05), Color(0.3, 0.35, 0.25), _head, &"metal")  # ammo box


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
		if not _is_target_valid(enemy) or enemy.is_dormant():
			continue  # quiet site security and neighborhood police aren't fights
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
	var dir := (to - from).normalized()
	Vfx.muzzle(get_parent(), from + dir * 0.7, Color(0.6, 1.0, 0.7), dir, 0.7)
	if not hit.is_empty() and not hit["collider"] is Enemy:
		Vfx.impact(get_parent(), to, hit["normal"], Player.surface_of(hit["collider"], hit["normal"]), 0.6)
	Fx.tracer(get_parent(), from, to, Color(0.5, 1.0, 0.6))
	Sfx.play(&"laser", from, -8.0)


## `enemy` is untyped: the cached target may have been freed since the last scan.
func _is_target_valid(enemy: Variant) -> bool:
	return enemy != null and is_instance_valid(enemy) and (enemy as Enemy).is_alive() \
		and (enemy as Enemy).faction == Enemy.Faction.HOSTILE
