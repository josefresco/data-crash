class_name Structure
extends Destructible
## Player-built defense piece. Hostiles target it; the player's bullets ignore it.

@export var cost := 50


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		add_to_group("structures")


func _add_box(box_size: Vector3, at: Vector3, box_color: Color, parent: Node3D = null,
		kind: StringName = &"rough") -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = box_size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = Models.mat(box_color, kind)
	mesh.position = at
	(parent if parent else self).add_child(mesh)
	return mesh
