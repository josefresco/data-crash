class_name EmpTrap
extends Node3D
## Floor pad that stuns every hostile within `radius` when one steps close,
## then recharges. Not solid and not targetable, so it never blocks paths.

@export var radius := 3.5
@export var stun_duration := 3.0
@export var recharge := 6.0
@export var cost := 75

var _charge_left := 0.0
var _scan_timer := 0.0
var _core_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("traps")
	var pad := BoxMesh.new()
	pad.size = Vector3(1.5, 0.1, 1.5)
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.2, 0.22, 0.25)
	var pad_mesh := MeshInstance3D.new()
	pad_mesh.mesh = pad
	pad_mesh.material_override = pad_mat
	pad_mesh.position.y = 0.05
	add_child(pad_mesh)

	var core := BoxMesh.new()
	core.size = Vector3(0.6, 0.12, 0.6)
	_core_mat = StandardMaterial3D.new()
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(0.3, 0.6, 1.0)
	var core_mesh := MeshInstance3D.new()
	core_mesh.mesh = core
	core_mesh.material_override = _core_mat
	core_mesh.position.y = 0.12
	add_child(core_mesh)
	# A copper coil ring and four emitter prongs.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.58
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.position.y = 0.14
	ring.material_override = Models.mat(Color(0.8, 0.45, 0.2), &"metal")
	add_child(ring)
	for i in 4:
		var angle := PI * 0.25 + i * PI * 0.5
		var prong := Models.cylinder(self, 0.03, 0.35, Vector3(cos(angle) * 0.62, 0.27, sin(angle) * 0.62),
			Models.mat(Color(0.25, 0.27, 0.3), &"metal"), 6)
		Models.ball(prong, 0.05, Vector3(0.0, 0.2, 0.0), _core_mat)


func _physics_process(delta: float) -> void:
	_charge_left = maxf(_charge_left - delta, 0.0)
	_core_mat.emission_energy_multiplier = 2.0 if _charge_left <= 0.0 else 0.1
	_scan_timer -= delta
	if _charge_left > 0.0 or _scan_timer > 0.0:
		return
	_scan_timer = 0.15

	var victims: Array[Enemy] = []
	var triggered := false
	for node in get_tree().get_nodes_in_group("hostiles"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive() or enemy.is_dormant():
			continue
		var distance := enemy.global_position.distance_to(global_position)
		if distance <= radius:
			victims.append(enemy)
			triggered = triggered or distance <= 1.5
	if not triggered:
		return
	Sfx.play(&"emp", global_position, -2.0)

	for enemy in victims:
		enemy.stun(stun_duration)
	_charge_left = recharge
	Explosive.spawn_flash(get_parent(), global_position + Vector3.UP * 0.5, radius * 0.8, Color(0.4, 0.7, 1.0))
