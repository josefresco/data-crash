class_name Barricade
extends Structure
## Concrete jersey barrier. Blocks paths (the navmesh rebakes around it) and soaks fire.


func _init() -> void:
	size = Vector3(4.0, 1.6, 0.6)
	color = Color(0.92, 0.9, 0.86)
	surface_kind = &"concrete"
	max_health = 350.0
	chunks = Vector3i(4, 2, 1)
	cost = 50
	label = "Barricade"
