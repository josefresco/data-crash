class_name FireZone
extends Node3D
## Burning puddle from a molotov. Hurts hostiles (and a careless player) inside,
## and scatters Orange Hat protesters without harming them.

@export var radius := 3.5
@export var duration := 6.0
@export var enemy_dps := 15.0
@export var player_dps := 5.0

const TICK := 0.25

var _time_left := 0.0
var _tick_left := 0.0
var _light: OmniLight3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("fire_zones")
	_time_left = duration
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.45, 0.05, 0.7)
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.05
	var mesh := MeshInstance3D.new()
	mesh.mesh = disc
	mesh.material_override = _mat
	mesh.position.y = 0.05
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.omni_range = radius * 2.5
	_light.position.y = 1.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	_time_left -= delta
	_light.light_energy = randf_range(2.0, 4.0) * clampf(_time_left, 0.0, 1.0)
	_mat.albedo_color.a = 0.7 * clampf(_time_left, 0.0, 1.0)
	if _time_left <= 0.0:
		queue_free()
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	Fx.flame_puff(get_parent(), global_position + Vector3(randf_range(-radius, radius) * 0.6, 0.2,
		randf_range(-radius, radius) * 0.6), 0.5)

	for node in get_tree().get_nodes_in_group("hostiles"):
		var enemy := node as Enemy
		if _inside(enemy):
			enemy.apply_damage(enemy_dps * TICK, global_position, &"fire")
	for node in get_tree().get_nodes_in_group("protesters"):
		var protester := node as OrangeHat
		if protester and _inside(protester):
			protester.scatter()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.is_visible_in_tree() and _inside(player):
		player.apply_damage(player_dps * TICK, global_position, &"fire")


func _inside(node: Node3D) -> bool:
	var offset := node.global_position - global_position
	return Vector2(offset.x, offset.z).length() <= radius and absf(offset.y) < 2.0
