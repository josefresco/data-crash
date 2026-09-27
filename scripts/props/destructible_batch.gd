class_name DestructibleBatch
extends MultiMeshInstance3D
## Draws many identical Destructible boxes (same parent, size, color, surface
## kind, and opacity) as one MultiMesh: one draw call instead of one per
## piece. Each piece keeps its own collider, health, and material (debris
## uses it); only its MeshInstance3D is hidden. Damage tints become
## per-instance colors, and a shattered piece's instance collapses to zero.
## Pieces opt in with `Destructible.batched` (datacenter walls, roof tiles,
## racks, fence panels).

var _pieces: Array[Destructible] = []
var _index := {}
## Instance indices collapsed so far (the renderer can't be read back headless).
var _gone := {}
var _rebuild_queued := false


## The batch `piece` draws with (made on first use, a child of its parent).
static func join(piece: Destructible, box: Mesh, source: StandardMaterial3D) -> DestructibleBatch:
	var parent := piece.get_parent()
	var key := "%s|%s|%s|%s" % [piece.size, piece.color.to_html(), piece.surface_kind, piece.opacity]
	var batches: Dictionary = parent.get_meta(&"destructible_batches", {})
	var batch := batches.get(key) as DestructibleBatch
	if batch == null or not is_instance_valid(batch):
		batch = DestructibleBatch.new()
		batch.name = "Batch_%s" % String(piece.surface_kind)
		var material := source.duplicate() as StandardMaterial3D
		# Instance colors carry the tint (and damage); the material stays white.
		material.albedo_color = Color(1.0, 1.0, 1.0, piece.opacity)
		material.vertex_color_use_as_albedo = true
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = box
		batch.multimesh = multimesh
		batch.material_override = material
		parent.add_child.call_deferred(batch)
		batches[key] = batch
		parent.set_meta(&"destructible_batches", batches)
	batch._add(piece)
	return batch


func _add(piece: Destructible) -> void:
	_index[piece.get_instance_id()] = _pieces.size()
	_pieces.append(piece)
	if not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


## Sets every instance from its piece (pieces join during their _ready, so
## this runs once after they have all arrived).
func _rebuild() -> void:
	_rebuild_queued = false
	multimesh.instance_count = _pieces.size()
	for i in _pieces.size():
		var piece := _pieces[i]
		if is_instance_valid(piece) and not piece.is_destroyed and not _gone.has(i):
			multimesh.set_instance_transform(i, _placement(piece))
			multimesh.set_instance_color(i, piece.tint())
		else:
			_gone[i] = true
			multimesh.set_instance_transform(i, _hidden())
			multimesh.set_instance_color(i, Color.WHITE)


## Recolors `piece`'s instance (damage darkening, hit flashes, repairs).
func tint(piece: Destructible, color: Color) -> void:
	var i: int = _index.get(piece.get_instance_id(), -1)
	if i >= 0 and i < multimesh.instance_count:
		multimesh.set_instance_color(i, color)


## Hides `piece`'s instance (it shattered).
func remove(piece: Destructible) -> void:
	var i: int = _index.get(piece.get_instance_id(), -1)
	if i >= 0:
		_gone[i] = true
		if i < multimesh.instance_count:
			multimesh.set_instance_transform(i, _hidden())


## Instances still drawn (tests read it).
func visible_count() -> int:
	return _pieces.size() - _gone.size()


func _placement(piece: Destructible) -> Transform3D:
	return piece.transform * Transform3D(Basis.IDENTITY, Vector3.UP * piece.size.y * 0.5)


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * 0.00001), Vector3(0.0, -1000.0, 0.0))
