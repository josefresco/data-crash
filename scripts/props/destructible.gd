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
## Settled rubble kept in the world (oldest pieces go first).
const MAX_RUBBLE := 350
## Random shard shapes per shattered prop (chunks pick among them).
const SHARD_VARIANTS := 4

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
## Surface look (Models.surface kind): rough, concrete, corrugated, plates,
## solar, chainlink, ... PBR kinds use real textures tinted by `color`.
@export var surface_kind: StringName = &"rough"
## Below 1 renders see-through (glass).
@export_range(0.05, 1.0) var opacity := 1.0
## Datacenter site this prop belongs to (fence, walls, turbines, cooling,
## racks). Any hit, even one below the damage threshold, raises that site's
## alarm (group "site_alarm"). &"" = not site property.
@export var site_id := &""
## Name shown in HUD prompts, e.g. "Cooling unit".
@export var label := ""
## Share of the debris that settles into permanent rubble instead of
## shrinking away (big structures: datacenter walls and roofs).
@export_range(0.0, 1.0) var rubble_share := 0.0
## Electronics: hits throw sparks, and the wreck keeps sparking for a while.
@export var sparks := false
## Draw through a shared DestructibleBatch (one MultiMesh per identical set
## under the same parent) instead of an own mesh. Only for plain boxes that
## never move (datacenter walls, roof tiles, racks, fence panels). Runtime only.
@export var batched := false

var health: float
var is_destroyed := false

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _material: StandardMaterial3D
var _batch: DestructibleBatch


func _ready() -> void:
	collision_layer = 16  # Game.LAYER_DESTRUCTIBLE (autoloads are unavailable in @tool scripts)
	collision_mask = 0
	health = max_health
	_build()


func apply_damage(amount: float, from: Vector3, _kind: StringName = &"generic") -> void:
	if Engine.is_editor_hint() or is_destroyed:
		return
	if site_id != &"" and amount > 0.0:
		get_tree().call_group(&"site_alarm", &"raise_alarm", site_id, label)
	if amount < damage_threshold:
		return
	health -= amount
	damaged.emit(amount, health)
	_show_damage()
	if sparks and amount > 1.0:
		_spark_at(from)
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
	_set_tint(_damage_color())
	repaired.emit(restored, health)
	return restored


func needs_repair() -> bool:
	return not is_destroyed and health < max_health - 0.5


## Destroys the prop immediately regardless of health.
func shatter(from: Vector3, force: float) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if _batch and is_instance_valid(_batch):
		_batch.remove(self)
	if not Engine.is_editor_hint():
		var cue := &"break_rock"
		if opacity < 0.99:
			cue = &"glass_break"
		elif surface_kind in [&"plates", &"corrugated", &"metal", &"solar", &"chainlink"]:
			cue = &"break_heavy"
		Sfx.play(cue, global_position + Vector3.UP * minf(size.y * 0.5, 2.0), 0.0 if size.length() > 4.0 else -6.0)
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

	var custom := _visual_mesh()
	if custom:
		_mesh.mesh = custom
		_mesh.position.y = 0.0
	else:
		_mesh.mesh = Models.box_mesh(size)
		_mesh.position.y = size.y * 0.5

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(color, opacity)
	if opacity < 1.0:
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		Models.surface(_material, surface_kind)
	_mesh.material_override = _material
	if batched and custom == null and _batch == null and not Engine.is_editor_hint() and get_parent():
		_mesh.visible = false
		_batch = DestructibleBatch.join(self, _mesh.mesh, _material)
		tree_exiting.connect(func() -> void:
			if is_instance_valid(_batch):
				_batch.remove(self))

	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape
	_shape.position.y = size.y * 0.5


## Override: a mesh (origin at bottom center) to show instead of the plain
## box. The collider and debris still use `size`; damage tints still apply.
func _visual_mesh() -> Mesh:
	return null


func _show_damage() -> void:
	# Darken with damage, plus a brief bright flash on each hit.
	var damaged_color := _damage_color()
	var tween := create_tween()
	tween.tween_method(_set_tint, damaged_color.lightened(0.6), damaged_color, 0.15)


## Current color (the batch reads it for this piece's instance).
func tint() -> Color:
	return _material.albedo_color if _material else Color(color, opacity)


func _set_tint(value: Color) -> void:
	_material.albedo_color = value
	if _batch and is_instance_valid(_batch):
		_batch.tint(self, value)


func _damage_color() -> Color:
	return Color(color.darkened(0.45 * (1.0 - clampf(health / max_health, 0.0, 1.0))), opacity)


## A shower of sparks on the face toward `from` (electronics being hit).
func _spark_at(from: Vector3) -> void:
	var local := global_transform.affine_inverse() * from
	local.y -= size.y * 0.5
	var half := size * 0.5
	var surface := global_transform * (local.clamp(-half, half) + Vector3.UP * size.y * 0.5)
	var normal := (from - surface).normalized() if from.distance_to(surface) > 0.01 else Vector3.UP
	Vfx.impact(get_parent(), surface, normal, &"metal", 1.4)
	if randf() < 0.4:
		Sfx.play(&"ricochet", surface, -8.0, 1.6)


func _spawn_debris(from: Vector3, force: float) -> void:
	var parent := get_tree().current_scene
	if sparks:
		_leave_sparking_wreck(parent)
	var budget := MAX_LIVE_DEBRIS - get_tree().get_nodes_in_group("debris").size()
	if budget > 0:
		if fractured_scene:
			_spawn_fractured(parent, from, force, budget)
		else:
			_spawn_box_chunks(parent, from, force, budget)
	Vfx.dust(parent, global_position + Vector3.UP * size.y * 0.5, maxf(size.x, maxf(size.y, size.z)) * 0.6)
	destroyed.emit(self)
	get_tree().call_group(&"nav_baker", &"request_rebake", global_position)
	queue_free()


## Electronics keep fizzing for a while after they're wrecked.
func _leave_sparking_wreck(parent: Node) -> void:
	var spot := Node3D.new()
	parent.add_child(spot)
	spot.global_position = global_position + Vector3.UP * minf(size.y * 0.6, 2.0)
	var fizz := func() -> void:
		if is_instance_valid(spot):
			var jitter := Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.4), randf_range(-0.6, 0.6))
			Vfx.impact(spot.get_parent(), spot.global_position + jitter, Vector3.UP, &"metal", 0.9)
	var tween := spot.create_tween()
	for i in 14:
		tween.tween_interval(randf_range(0.3, 1.1))
		tween.tween_callback(fizz)
	tween.tween_callback(spot.queue_free)
	Vfx.fire_puff(parent, spot.global_position, 0.6, Vector3.UP)


## Irregular shard shapes for chunks of `chunk_size`: jittered hexahedra
## (a box with its eight corners pushed around), mesh plus convex collider.
func _shard_variants(chunk_size: Vector3) -> Array:
	var variants := []
	var h := chunk_size * 0.49
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for v in SHARD_VARIANTS:
		var corners := PackedVector3Array()
		for i in 8:
			var corner := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
			corner += Vector3(randf_range(-0.3, 0.3) * h.x, randf_range(-0.3, 0.3) * h.y, randf_range(-0.3, 0.3) * h.z)
			corners.append(corner)
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face: Array in faces:
			var a := corners[face[0]]
			var b := corners[face[1]]
			var c := corners[face[2]]
			var d := corners[face[3]]
			var normal := (b - a).cross(c - a).normalized()
			if normal.dot((a + b + c + d) * 0.25) < 0.0:
				normal = -normal
				var swap := b
				b = d
				d = swap
			for tri in [[a, b, c], [a, c, d]]:
				for point: Vector3 in tri:
					tool.set_normal(normal)
					tool.set_uv(Vector2(point.x + point.z, point.y) * 0.5)
					tool.add_vertex(point)
		var shape := ConvexPolygonShape3D.new()
		shape.points = corners
		variants.append([tool.commit(), shape])
	return variants


func _spawn_box_chunks(parent: Node, from: Vector3, force: float, budget: int) -> void:
	var counts := Vector3(maxi(chunks.x, 1), maxi(chunks.y, 1), maxi(chunks.z, 1))
	var chunk_size := size / counts
	var variants := _shard_variants(chunk_size)
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
				var pick: Array = variants[randi() % variants.size()]
				var body := _make_debris_body(pick[0], pick[1], Vector3.ONE, mass)
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

	# Shrink away and free after the lifetime, or (a `rubble_share` of big
	# structures' debris) settle for good as static rubble. The tween belongs
	# to the body, so it survives this Destructible being freed.
	var tween := body.create_tween()
	tween.tween_interval(debris_lifetime + randf() * 2.0)
	if randf() < rubble_share:
		tween.tween_callback(Destructible._settle_rubble.bind(body))
	else:
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.6)
		tween.tween_callback(body.queue_free)
	return body


## Debris that stays: frozen static (cheap), out of the live-debris budget,
## in group "rubble" (capped at MAX_RUBBLE, oldest removed first).
static func _settle_rubble(body: Variant) -> void:
	if not is_instance_valid(body):
		return
	var piece := body as RigidBody3D
	piece.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	piece.freeze = true
	piece.remove_from_group("debris")
	piece.add_to_group("rubble")
	for child in piece.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var rubble := piece.get_tree().get_nodes_in_group("rubble")
	if rubble.size() > MAX_RUBBLE:
		rubble[0].queue_free()


func _launch(body: RigidBody3D, from: Vector3, force: float) -> void:
	var direction := body.global_position - from
	direction = Vector3.UP if direction.length_squared() < 0.001 else direction.normalized()
	var speed := clampf(force * 0.04, 1.0, 14.0)
	var scatter := Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.5), randf_range(-0.3, 0.3))
	body.linear_velocity = (direction + scatter) * speed
	body.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
