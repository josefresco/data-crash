class_name BuildController
extends Node3D
## Phase 3 grid placement. [B] toggles build mode, [1-4] picks an item,
## [R] rotates, left click places, right click exits.

signal structure_placed(structure: Node3D)

@export var grid_size := 1.0
## Max horizontal distance from `center` (the green core) to build.
@export var build_radius := 26.0

## Set by the level when Phase 3 starts.
var enabled := false
var active := false
var center := Vector3.ZERO
var selected := 0

var _items: Array[Dictionary] = []
var _rotation_steps := 0
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _placement := Vector3.ZERO
var _can_place := false
var _player: Player


func _ready() -> void:
	add_to_group("build_controller")
	_items = [
		{"name": "Barricade", "kind": Barricade, "cost": 50, "size": Vector3(4.0, 1.6, 0.6)},
		{"name": "Turret", "kind": Turret, "cost": 175, "size": Vector3(1.2, 1.6, 1.2)},
		{"name": "Solar panel", "kind": SolarPanel, "cost": 100, "size": Vector3(3.0, 0.9, 2.0)},
		{"name": "EMP trap", "kind": EmpTrap, "cost": 75, "size": Vector3(1.5, 0.2, 1.5)},
	]
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_find_player.call_deferred()


func item_count() -> int:
	return _items.size()


func item_cost(index: int) -> int:
	return _items[index]["cost"]


func set_active(value: bool) -> void:
	active = value and enabled
	if active:
		var bribes := get_tree().get_first_node_in_group("bribe_menu") as BribeMenu
		if bribes and bribes.is_open:
			bribes.set_open(false)
	_ghost.visible = active
	if _player:
		_player.build_mode = active
	_update_info()


## Places item `index` at `point` (snapped) if affordable and clear.
## Used by clicks and by tests. Returns the new node or null.
func place(index: int, point: Vector3, rotation_steps := 0, no_cost := false) -> Node3D:
	var item := _items[index]
	var at := _snap(point)
	if not _is_clear(item, at, rotation_steps, no_cost):
		return null
	var node: Node3D = (item["kind"] as GDScript).new()
	node.position = at
	node.rotation.y = rotation_steps * PI * 0.5
	get_parent().add_child(node)
	if not no_cost:
		Game.add_cash(-int(item["cost"]))
	if node is Structure:
		get_tree().call_group(&"nav_baker", &"request_rebake")
	structure_placed.emit(node)
	_update_info()
	return node


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("build_mode"):
		set_active(not active)
		return
	if not active:
		return
	for i in _items.size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			selected = i
			_update_info()
	if event.is_action_pressed("rotate"):
		_rotation_steps = (_rotation_steps + 1) % 4
	elif event.is_action_pressed("cancel"):
		set_active(false)
	elif event.is_action_pressed("fire") and _can_place:
		place(selected, _placement, _rotation_steps)


func _process(_delta: float) -> void:
	if not active or _player == null:
		return
	var item := _items[selected]
	var hit := _player.aim(60.0, Game.LAYER_WORLD)
	if hit.is_empty():
		_ghost.visible = false
		_can_place = false
		return
	_placement = _snap(hit["position"])
	var item_size: Vector3 = item["size"]
	(_ghost.mesh as BoxMesh).size = item_size
	_ghost.visible = true
	_ghost.global_position = _placement + Vector3.UP * item_size.y * 0.5
	_ghost.rotation.y = _rotation_steps * PI * 0.5
	_can_place = _is_clear(item, _placement, _rotation_steps)
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4) if _can_place else Color(1.0, 0.25, 0.2, 0.4)


func _is_clear(item: Dictionary, at: Vector3, rotation_steps: int, no_cost := false) -> bool:
	if not no_cost and Game.cash < int(item["cost"]):
		return false
	if Vector2(at.x - center.x, at.z - center.z).length() > build_radius:
		return false
	var item_size: Vector3 = item["size"]
	var shape := BoxShape3D.new()
	shape.size = Vector3(item_size.x * 0.95, maxf(item_size.y, 0.5), item_size.z * 0.95)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, rotation_steps * PI * 0.5),
		at + Vector3.UP * (shape.size.y * 0.5 + 0.05))
	query.collision_mask = Game.LAYER_PLAYER | Game.LAYER_VEHICLES | Game.LAYER_DESTRUCTIBLE | Game.LAYER_ENEMIES
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	# Traps are not physical, so check spacing against other traps by distance.
	for trap in get_tree().get_nodes_in_group("traps"):
		if (trap as Node3D).global_position.distance_to(at) < 1.5:
			return false
	return true


func _snap(point: Vector3) -> Vector3:
	return Vector3(snappedf(point.x, grid_size), maxf(point.y, 0.0), snappedf(point.z, grid_size))


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player


func _update_info() -> void:
	if not active:
		Game.set_info("build", "[B] Build mode" if enabled else "")
		return
	var parts: PackedStringArray = []
	for i in _items.size():
		var entry := "[%d] %s $%d" % [i + 1, _items[i]["name"], _items[i]["cost"]]
		parts.append("> %s <" % entry if i == selected else entry)
	Game.set_info("build", "BUILD  " + "   ".join(parts) + "   [R] rotate  [RMB] exit")
