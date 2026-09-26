class_name GreenCore
extends Structure
## The community-owned, zero-water solar datacenter. Losing it loses the zone.


func _init() -> void:
	size = Vector3(6.0, 3.0, 6.0)
	color = Color(0.96, 0.97, 0.94)
	surface_kind = &"concrete"
	max_health = 1500.0
	chunks = Vector3i(3, 2, 3)
	cost = 0
	label = "Green datacenter"


func _ready() -> void:
	super()
	for x in 2:
		for z in 2:
			var panel := _add_box(Vector3(2.6, 0.08, 2.6),
				Vector3(-1.4 + x * 2.8, size.y + 0.3, -1.4 + z * 2.8), Color.WHITE, null, &"solar")
			panel.rotation.x = deg_to_rad(-15.0)
	_add_box(Vector3(6.2, 0.3, 0.2), Vector3(0.0, 0.8, size.z * 0.5), Color(0.3, 0.7, 0.35))
