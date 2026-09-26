class_name SentryTurret
extends SecurityGuard
## Crapya's roof water cannon: a riot-control nozzle on a fixed mount. It
## soaks whoever it hits (light damage) and shoves them back, and it only opens
## up once the site alarm is raised (site_security). Dies when her control room
## goes down or the gas turbines stop powering it.

## Damage per attack tick (attack_interval 0.15 s, so about 17 per second).
@export var soak_damage := 2.5
## Horizontal shove speed, applied at most every push_interval seconds.
@export var push_speed := 5.5
@export var push_interval := 0.6

var _nozzle: Node3D
var _jet: GPUParticles3D
var _hiss: AudioStreamPlayer3D
var _spray_left := 0.0
var _push_left := 0.0


func _init() -> void:
	outfit = ""  # procedural turret, not a person
	max_health = 120.0
	move_speed = 0.0
	sight_range = 32.0
	attack_range = 26.0
	attack_interval = 0.15
	bounty = 40
	body_color = Color(0.82, 0.84, 0.86)
	body_height = 1.2


func _ready() -> void:
	super()
	add_to_group("crapya_defenses")


func dismantle() -> void:
	shut_down()


func shut_down() -> void:
	if is_alive():
		apply_damage(9999.0, global_position, &"emp")


func _process(delta: float) -> void:
	super(delta)
	_push_left = maxf(_push_left - delta, 0.0)
	if _spray_left > 0.0:
		_spray_left -= delta
		if _spray_left <= 0.0:
			_set_spraying(false)


func _attack(victim: Node3D) -> void:
	var from := _nozzle.global_position
	var aim := _aim_point_of(victim)
	# Lob a little high: the stream droops over distance.
	var lead := aim + Vector3.UP * from.distance_to(aim) * 0.04
	_nozzle.look_at(lead, Vector3.UP)
	_set_spraying(true)
	_spray_left = 0.6  # keep the stream continuous between ticks
	var query := PhysicsRayQueryParameters3D.create(from, aim + (aim - from).normalized(), SHOT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var struck := hit["collider"] as Node
	if struck == null or _is_friend(struck):
		return
	if struck.has_method("apply_damage"):
		struck.call(&"apply_damage", soak_damage, from, &"water")
	if _push_left <= 0.0 and struck.has_method("apply_knockback"):
		_push_left = push_interval
		var push := aim - from
		push.y = 0.0
		struck.call(&"apply_knockback", push.normalized() * push_speed + Vector3.UP * 1.5)


func _on_death() -> void:
	super()
	_set_spraying(false)


func _set_spraying(on: bool) -> void:
	if _jet == null or _jet.emitting == on:
		return
	_jet.emitting = on
	if on:
		if _hiss == null:
			_hiss = Sfx.loop(self, &"hiss_loop", -2.0)
		elif not _hiss.playing:
			_hiss.play()
	elif _hiss:
		_hiss.stop()


func _build_visual() -> Node3D:
	var rig := Node3D.new()
	var steel := Models.mat(Color(0.3, 0.32, 0.36), &"metal")
	var brass := Models.mat(Color(0.78, 0.6, 0.25), &"metal")
	Models.cylinder(rig, 0.45, 0.5, Vector3(0.0, 0.25, 0.0), steel, 12)
	Models.box(rig, Vector3(0.7, 0.5, 0.8), Vector3(0.0, 0.75, 0.1), _material)
	# Water tank on the back with a supply hose down into the roof.
	var tank := Models.cylinder(rig, 0.3, 0.9, Vector3(0.0, 0.8, 0.65), Models.mat(Color(0.15, 0.35, 0.7), &"paint"), 12)
	tank.rotation.z = PI * 0.5
	Models.cylinder(rig, 0.06, 0.7, Vector3(0.25, 0.35, 0.65), Models.mat(Color(0.1, 0.1, 0.1)), 6)
	# The cannon: a swivel with a brass nozzle that aims (-Z) at the target.
	_nozzle = Node3D.new()
	_nozzle.position = Vector3(0.0, 1.05, -0.2)
	rig.add_child(_nozzle)
	Models.ball(_nozzle, 0.18, Vector3.ZERO, steel)
	var barrel := Models.cylinder(_nozzle, 0.1, 0.9, Vector3(0.0, 0.0, -0.45), brass, 10)
	barrel.rotation.x = PI * 0.5
	var tip := Models.cylinder(_nozzle, 0.14, 0.12, Vector3(0.0, 0.0, -0.9), brass, 10)
	tip.rotation.x = PI * 0.5
	_jet = Vfx.water_jet(_nozzle, Vector3(0.0, 0.0, -0.98))
	# Status light: red while armed.
	Models.box(rig, Vector3(0.3, 0.06, 0.04), Vector3(0.0, 0.92, -0.31), Models.glow(Color(1.0, 0.2, 0.1), 3.0))
	return rig


func _decorate(_visual_root: Node3D) -> void:
	pass  # no helmet or rifle on a turret
