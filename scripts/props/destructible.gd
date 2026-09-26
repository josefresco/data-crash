@tool
class_name Destructible
extends StaticBody3D
## Box-shaped prop that takes damage and shatters into physics debris.
## Builds its own mesh and collision from `size` (origin at bottom center), so
## scenes only set properties. Set `fractured_scene` to shatter into a
## pre-fractured Blender model instead of a grid of box chunks.

signal damaged(amount: float, health: float)
signal destroyed(destructible: Destructible)
signal repaired(amount: float, health: float)

const MAX_LIVE_DEBRIS := 400

@export var size := Vector3(2.0, 2.0, 0.2):
	set(value):
		size = value
		if is_node_ready():
			_build()

@export var color := Color(0.5, 0.5, 0.5):
	set(value):
		color = value
		if is_node_ready():
			_build()

@export var max_health := 100.0
## Hits weaker than this do nothing (e.g. bullets against concrete).
@export var damage_threshold := 0.0
## Number of box chunks along each local axis when shattering.
@export var chunks := Vector3i(3, 3, 1)
## kg per cubic meter. Kept low so debris flies in a satisfying way.
@export var density := 250.0
@export var debris_lifetime := 8.0
## Optional pre-fractured model: every MeshInstance3D inside becomes a debris piece.
@export var fractured_scene: PackedScene
## Below 1 renders see-through (chain-link fences, glass).
@export_range(0.05, 1.0) var opacity := 1.0
## Name shown in HUD prompts, e.g. "Cooling unit".
@export var label := ""

var health: float
var is_destroyed := false

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 16  # Game.LAYER_DESTRUCTIBLE (autoloads are unavailable in @tool scripts)
	collision_mask = 0
	health = max_health
	_build()


func apply_damage(amount: float, from: Vector3, _kind: StringName = &"generic") -> void:
	if Engine.is_editor_hint() or is_destroyed or amount < damage_threshold:
		return
	health -= amount
	damaged.emit(amount, health)
	_show_damage()
	if health <= 0.0:
		shatter(from, amount)


## Restores health up to max. Returns the amount actually restored.
func repair(amount: float) -> float:
	if is_destroyed or amount <= 0.0:
		return 0.0
	var restored := minf(amount, max_health - health)
	if restored <= 0.0:
		return 0.0
	health += restored
	_material.albedo_color = _damage_color()
	repaired.emit(restored, health)
	return restored


func needs_repair() -> bool:
	return not is_destroyed and health < max_health - 0.5


## Destroys the prop immediately regardless of health.
func shatter(from: Vector3, force: float) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	# Deferred: this is often called from physics callbacks (ram contacts), where
	# adding new bodies to the space is not allowed.
	_spawn_debris.call_deferred(from, force)


## Distance from a world point to this box's surface (0 if inside).
func distance_to_point(point: Vector3) -> float:
	var local := global_transform.affine_inverse() * point
	local.y -= size.y * 0.5
	var half := size * 0.5
	return local.distance_to(local.clamp(-half, half))


func _build() -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		add_child(_mesh)
		_shape = CollisionShape3D.new()
		add_child(_shape)

	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_mesh.position.y = size.y * 0.5

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(color, opacity)
	if opacity < 1.0:
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		Models.surface(_material, &"rough")
	_mesh.material_override = _material

	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape
	_shape.position.y = size.y * 0.5


func _show_damage() -> void:
	# Darken with damage, plus a brief bright flash on each hit.
	var damaged_color := _damage_color()
	_material.albedo_color = damaged_color.lightened(0.6)
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", damaged_color, 0.15)


func _damage_color() -> Color:
	return Color(color.darkened(0.45 * (1.0 - clampf(health / max_health, 0.0, 1.0))), opacity)


func _spawn_debris(from: Vector3, force: float) -> void:
	var parent := get_tree().current_scene
	var budget := MAX_LIVE_DEBRIS - get_tree().get_nodes_in_group("debris").size()
	if budget > 0:
		if fractured_scene:
			_spawn_fractured(parent, from, force, budget)
		else:
			_spawn_box_chunks(parent, from, force, budget)
	Vfx.dust(parent, global_position + Vector3.UP * size.y * 0.5, maxf(size.x, maxf(size.y, size.z)) * 0.6)
	destroyed.emit(self)
	get_tree().call_group(&"nav_baker", &"request_rebake")
	queue_free()


func _spawn_box_chunks(parent: Node, from: Vector3, force: float, budget: int) -> void:
	var counts := Vector3(maxi(chunks.x, 1), maxi(chunks.y, 1), maxi(chunks.z, 1))
	var chunk_size := size / counts
	var mesh := BoxMesh.new()
	mesh.size = chunk_size * 0.98
	var shape := BoxShape3D.new()
	shape.size = chunk_size * 0.98
	var mass := maxf(chunk_size.x * chunk_size.y * chunk_size.z * density, 1.0)

	for x in int(counts.x):
		for y in int(counts.y):
			for z in int(counts.z):
				if budget <= 0:
					return
				budget -= 1
				var local := Vector3(
					(x + 0.5) * chunk_size.x - size.x * 0.5,
					(y + 0.5) * chunk_size.y,
					(z + 0.5) * chunk_size.z - size.z * 0.5)
				var body := _make_debris_body(mesh, shape, Vector3.ONE, mass)
				parent.add_child(body)
				body.global_transform = global_transform * Transform3D(Basis(), local)
				_launch(body, from, force)


func _spawn_fractured(parent: Node, from: Vector3, force: float, budget: int) -> void:
	var model := fractured_scene.instantiate() as Node3D
	if model == null:
		push_warning("%s: fractured_scene root must be a Node3D" % name)
		_spawn_box_chunks(parent, from, force, budget)
		return
	# Add temporarily so the pieces have resolvable global transforms.
	parent.add_child(model)
	model.global_transform = global_transform

	for node in model.find_children("*", "MeshInstance3D", true, false):
		if budget <= 0:
			break
		var piece := node as MeshInstance3D
		if piece.mesh == null:
			continue
		budget -= 1
		var xform := piece.global_transform
		var piece_scale := xform.basis.get_scale()
		# Rigid bodies can't be scaled, so bake scale into the shape and mesh child.
		var shape := piece.mesh.create_convex_shape() as ConvexPolygonShape3D
		var points := shape.points
		for i in points.size():
			points[i] *= piece_scale
		shape.points = points
		var aabb_size := piece.mesh.get_aabb().size * piece_scale
		var mass := maxf(aabb_size.x * aabb_size.y * aabb_size.z * density * 0.5, 1.0)
		var body := _make_debris_body(piece.mesh, shape, piece_scale, mass)
		var visual := body.get_child(1) as MeshInstance3D
		visual.material_override = piece.material_override if piece.material_override else _material
		parent.add_child(body)
		body.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
		_launch(body, from, force)

	model.queue_free()


func _make_debris_body(mesh: Mesh, shape: Shape3D, mesh_scale: Vector3, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.add_to_group("debris")
	body.collision_layer = 8  # debris
	body.collision_mask = 1 | 4 | 8 | 16  # world, vehicles, debris, destructibles
	body.mass = mass

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = mesh_scale
	visual.material_override = _material
	visual.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC  # flying debris
	body.add_child(visual)

	# Shrink away and free after the lifetime. The tween belongs to the body,
	# so it survives this Destructible being freed.
	var tween := body.create_tween()
	tween.tween_interval(debris_lifetime + randf() * 2.0)
	tween.tween_property(visual, "scale", Vector3.ZERO, 0.6)
	tween.tween_callback(body.queue_free)
	return body


func _launch(body: RigidBody3D, from: Vector3, force: float) -> void:
	var direction := body.global_position - from
	direction = Vector3.UP if direction.length_squared() < 0.001 else direction.normalized()
	var speed := clampf(force * 0.04, 1.0, 14.0)
	var scatter := Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.5), randf_range(-0.3, 0.3))
	body.linear_velocity = (direction + scatter) * speed
	body.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
