class_name KidRider
extends Enemy
## A neighborhood kid on a bike, won over with candy (Resident kid, [E]).
## Pedals fast circles around the nearest awake police officer near the
## player, and any cop the bike whizzes past gets distracted
## (Enemy.distract: "Hey kid! Get off the road!"). With nothing to annoy,
## rides loops around the player. Nobody targets kids (group `kids`).

@export var watch_radius := 40.0
@export var orbit := 5.0
@export var distract_seconds := 3.0

var _angle := randf() * TAU


func _init() -> void:
	faction = Faction.ALLY
	max_health = 40.0
	move_speed = 6.5
	sight_range = 0.0
	attack_range = 0.0
	bounty = 0
	body_height = 1.3
	outfit = "kid"


func _faction_group() -> String:
	return "kids"


func _think() -> void:
	var cop := _nearest_cop()
	var center: Vector3
	if cop:
		center = cop.global_position
		for node in get_tree().get_nodes_in_group("hostiles"):
			var other := node as Police
			if other and other.is_alive() and not other.is_dormant() and other.global_position.distance_to(global_position) < 6.0:
				other.distract(self, distract_seconds)
	else:
		var anchor: Vector3 = order_point
		if anchor == Vector3.INF:
			var player := get_tree().get_first_node_in_group("player") as Node3D
			if player == null:
				return
			anchor = player.global_position
		center = anchor
	# Keep circling: step the angle along each think tick.
	_angle += 0.55
	_nav.target_position = center + Vector3(cos(_angle), 0.0, sin(_angle)) * (orbit if cop else orbit + 2.0)


func _nearest_cop() -> Enemy:
	var center: Vector3 = order_point
	if center == Vector3.INF:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return null
		center = player.global_position
	var best: Enemy = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		var cop := node as Police
		if cop == null or not cop.is_alive() or cop.is_dormant() or cop.global_position.distance_to(center) > watch_radius:
			continue
		if best == null or cop.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = cop
	return best


func _stance() -> StringName:
	return &"drive"  # seated on the bike


func _decorate(visual_root: Node3D) -> void:
	# The bike: two wheels, a frame, handlebars (under the seated kid).
	var bike := Node3D.new()
	visual_root.add_child(bike)
	var tire := _solid(Color(0.08, 0.08, 0.08))
	var frame := _solid([Color(0.9, 0.15, 0.2), Color(0.2, 0.5, 0.95), Color(0.2, 0.75, 0.3)].pick_random())
	for z: float in [-0.5, 0.5]:
		var wheel := Models.cylinder(bike, 0.28, 0.05, Vector3(0.0, 0.28, z), tire, 16)
		wheel.rotation.z = PI * 0.5  # the axle runs side to side
		wheel.name = "Wheel"
		var hub := Models.cylinder(wheel, 0.2, 0.052, Vector3.ZERO, _solid(Color(0.75, 0.76, 0.78)), 12)
		hub.name = "Rim"
	_add_box(bike, Vector3(0.05, 0.06, 1.0), Vector3(0.0, 0.5, 0.0), frame)
	_add_box(bike, Vector3(0.05, 0.45, 0.06), Vector3(0.0, 0.62, -0.45), frame)
	_add_box(bike, Vector3(0.5, 0.04, 0.04), Vector3(0.0, 0.85, -0.45), frame)
	Models.hat(_anchor(&"head"), &"helmet", Color(0.95, 0.8, 0.2), _head_top(), body_height / 1.8)
