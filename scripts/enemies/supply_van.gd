class_name SupplyVan
extends FelsaCar
## Corporate supply van on a loop between `route` points. Doesn't hunt anyone
## (it will still flatten whatever it hits). Destroy it to intercept the cargo.

@export var route: Array[Vector3] = [Vector3(0, 0.2, 40), Vector3(0, 0.2, -6)]

var _leg := 0


func _init() -> void:
	max_health = 120.0
	top_speed = 7.0
	wobble = 0.0
	bounty = 150
	body_size = Vector3(2.0, 1.8, 4.6)
	body_color = Color(0.9, 0.9, 0.92)
	model_path = "res://assets/kenney/cars/delivery.glb"
	model_scale = 1.45
	explosion_damage = 50.0


func _candidates() -> Array[Node3D]:
	return []


func _goal_point() -> Vector3:
	if route.is_empty():
		return global_position
	var goal := route[_leg]
	var offset := goal - global_position
	if Vector2(offset.x, offset.z).length() < 4.0:
		_leg = (_leg + 1) % route.size()
		goal = route[_leg]
	return goal


func _decorate(visual_root: Node3D) -> void:
	if not model_path.is_empty():
		return  # the Kenney delivery truck already has its cargo box
	# Corporate cargo box with a logo stripe.
	_add_box(visual_root, Vector3(body_size.x * 0.95, 1.2, body_size.z * 0.55),
		Vector3(0.0, body_size.y + 0.8, body_size.z * 0.18), _solid(Color(0.8, 0.8, 0.82)))
	_add_box(visual_root, Vector3(body_size.x + 0.02, 0.25, body_size.z * 0.5),
		Vector3(0.0, body_size.y + 0.9, body_size.z * 0.18), _solid(Color(0.15, 0.3, 0.7)))
