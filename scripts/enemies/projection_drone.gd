class_name ProjectionDrone
extends Drone
## Sham Crapman's AI projection drone: wraps every hostile near it (Sham
## included) in a force field that blocks most damage. Shoot the drones first.

@export var field_radius := 7.0


func _init() -> void:
	max_health = 30.0
	body_color = Color(0.92, 0.95, 1.0)
	orbit_radius = 3.5
	orbit_height = 3.2


func _drone_tick() -> void:
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and unit != self and not unit is Drone \
				and unit.global_position.distance_to(global_position) <= field_radius + orbit_height:
			unit.shield_field(0.35)


func _decorate(visual_root: Node3D) -> void:
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.4, 0.9, 1.0)
	lens.emission_enabled = true
	lens.emission = Color(0.4, 0.9, 1.0)
	lens.emission_energy_multiplier = 2.0
	Models.cone(visual_root, 0.25, 0.3, Vector3(0.0, 0.0, 0.0), lens).rotation.x = PI
