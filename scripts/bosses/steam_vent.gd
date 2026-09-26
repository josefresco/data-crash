class_name SteamVent
extends Node3D
## Crapya's superheated steam vent (or, with `crusher = true`, a server-rack
## crusher that slams down). Cycles idle, then a telegraph, then an active
## blast; anything allied standing on it during the blast gets hurt. Shuts
## down with Crapya's control room.

@export var crusher := false
@export var radius := 2.2
@export var idle_time := 3.0
@export var warn_time := 1.0
@export var active_time := 1.5
## Steam: damage per second while active. Crusher: damage per slam.
@export var damage := 30.0
@export var phase_offset := 0.0

enum State { IDLE, WARN, ACTIVE, OFF }

var state := State.IDLE

var _left := 0.0
var _puff_left := 0.0
var _rack: MeshInstance3D
var _grate_mat: StandardMaterial3D
var _hit_this_slam := {}
var _jet: GPUParticles3D


func _ready() -> void:
	add_to_group("crapya_defenses")
	_left = idle_time + phase_offset
	_grate_mat = StandardMaterial3D.new()
	_grate_mat.albedo_color = Color(0.2, 0.2, 0.22)
	Models.box(self, Vector3(radius * 1.4, 0.08, radius * 1.4), Vector3(0.0, 0.04, 0.0), _grate_mat)
	if not crusher:
		_jet = Vfx.steam_jet(self, Vector3.UP * 0.2, 4.0)
	if crusher:
		_rack = Models.box(self, Vector3(1.2, 2.2, 0.9), Vector3(0.0, 4.5, 0.0), Models.mat(Color(0.15, 0.16, 0.2)))
		for i in 5:
			var led := StandardMaterial3D.new()
			led.albedo_color = Color(0.2, 1.0, 0.4)
			led.emission_enabled = true
			led.emission = Color(0.2, 1.0, 0.4)
			Models.box(_rack, Vector3(0.9, 0.05, 0.02), Vector3(0.0, -0.9 + i * 0.4, -0.46), led)


## Cleared away with the rest of the site after the datacenter falls.
func dismantle() -> void:
	Vfx.dust(get_parent(), global_position + Vector3.UP, 2.0)
	queue_free()


func shut_down() -> void:
	state = State.OFF
	if _jet:
		_jet.emitting = false
	_grate_mat.albedo_color = Color(0.2, 0.2, 0.22)
	if _rack:
		_rack.position.y = 1.1  # dropped, harmless


func _physics_process(delta: float) -> void:
	if state == State.OFF:
		return
	_left -= delta
	match state:
		State.IDLE:
			if _left <= 0.0:
				state = State.WARN
				_left = warn_time
				_grate_mat.albedo_color = Color(0.9, 0.5, 0.1)
		State.WARN:
			_set_jet(0.3)
			if _left <= 0.0:
				state = State.ACTIVE
				_left = active_time
				_hit_this_slam.clear()
		State.ACTIVE:
			if crusher:
				_rack.position.y = move_toward(_rack.position.y, 1.1, delta * 30.0)
			else:
				_set_jet(1.0)
			_hurt(delta)
			if _left <= 0.0:
				state = State.IDLE
				_left = idle_time
				_grate_mat.albedo_color = Color(0.2, 0.2, 0.22)
				_set_jet(0.0)
		_:
			pass
	if crusher and state == State.IDLE:
		_rack.position.y = move_toward(_rack.position.y, 4.5, delta * 2.0)


func _hurt(delta: float) -> void:
	var victims: Array[Node] = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("allies")
	for node in victims:
		var victim := node as Node3D
		if victim == null or not victim.is_visible_in_tree() or not victim.has_method("apply_damage"):
			continue
		var offset := victim.global_position - global_position
		if Vector2(offset.x, offset.z).length() > radius or absf(offset.y) > 2.5:
			continue
		if crusher:
			if _hit_this_slam.has(victim):
				continue
			_hit_this_slam[victim] = true
			victim.call(&"apply_damage", damage, global_position + Vector3.UP * 4.0, &"crush")
		else:
			victim.call(&"apply_damage", damage * delta, global_position, &"steam")


func _set_jet(intensity: float) -> void:
	if _jet == null:
		return
	_jet.emitting = intensity > 0.0
	_jet.amount_ratio = maxf(intensity, 0.01)
