class_name WaterMain
extends Node3D
## A sabotaged fire hydrant on the sidewalk: its bonnet knocked off, water
## gushing into the street while the neighbors' taps run dry. Hold [F] next
## to it to cap it (the bonnet goes back on and the puddle dries up).
## (Named for its old role: the level and tests know it as the water main.)

signal fixed(main: WaterMain)

@export var fix_time := 2.5
@export var reach := 3.0

var progress := 0.0
var is_fixed := false

var _spray: GPUParticles3D
var _gush: GPUParticles3D
var _hiss: AudioStreamPlayer3D
var _bonnet: Node3D
var _loose_bonnet: Node3D
var _puddle: MeshInstance3D


func _ready() -> void:
	add_to_group("fixables")
	var red := Models.mat(Color(0.78, 0.12, 0.1), &"paint")
	var brass := Models.mat(Color(0.72, 0.6, 0.3), &"metal")
	# Barrel on a flanged base, with two hose outlets and a big pumper nozzle.
	Models.cylinder(self, 0.24, 0.08, Vector3(0.0, 0.04, 0.0), red, 14)
	Models.cylinder(self, 0.17, 0.62, Vector3(0.0, 0.39, 0.0), red, 14)
	Models.cylinder(self, 0.2, 0.06, Vector3(0.0, 0.7, 0.0), red, 14)
	for side in [-1.0, 1.0]:
		var outlet := Models.cylinder(self, 0.06, 0.16, Vector3(side * 0.22, 0.5, 0.0), red, 10)
		outlet.rotation.z = PI * 0.5
		var cap := Models.cylinder(outlet, 0.07, 0.04, Vector3(0.0, side * 0.09, 0.0), brass, 8)
		cap.rotation.z = 0.0
	var pumper := Models.cylinder(self, 0.09, 0.14, Vector3(0.0, 0.45, 0.2), red, 12)
	pumper.rotation.x = PI * 0.5
	Models.cylinder(pumper, 0.1, 0.04, Vector3(0.0, 0.08, 0.0), brass, 8)
	Models.collider(self, Vector3(0.5, 0.8, 0.5), Vector3(0.0, 0.4, 0.0))
	# The bonnet (dome and operating nut): on the pavement while it's broken.
	_bonnet = _make_bonnet(red, brass)
	_bonnet.position.y = 0.73
	_bonnet.visible = false
	add_child(_bonnet)
	_loose_bonnet = _make_bonnet(red, brass)
	_loose_bonnet.position = Vector3(0.55, 0.1, 0.35)
	_loose_bonnet.rotation = Vector3(1.2, 0.4, 0.3)
	add_child(_loose_bonnet)
	# A puddle spreading into the street.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.3, 0.42, 0.55, 0.6)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic = 0.2
	_puddle = Models.cylinder(self, 1.8, 0.01, Vector3(0.0, 0.03, 0.9), water, 24)
	_puddle.scale = Vector3(1.0, 1.0, 1.4)
	# A tall gush straight up, plus spray off the top.
	_gush = Vfx.water_spray(self, Vector3.UP * 0.7)
	_gush.amount_ratio = 1.0
	(_gush.process_material as ParticleProcessMaterial).initial_velocity_min = 7.0
	(_gush.process_material as ParticleProcessMaterial).initial_velocity_max = 9.5
	(_gush.process_material as ParticleProcessMaterial).spread = 6.0
	_spray = Vfx.water_spray(self, Vector3.UP * 0.75)
	_spray.emitting = true
	_gush.emitting = true
	_hiss = Sfx.loop(self, &"hiss_loop", -8.0)


func _make_bonnet(red: Material, brass: Material) -> Node3D:
	var bonnet := Node3D.new()
	var dome := Models.ball(bonnet, 0.18, Vector3(0.0, 0.06, 0.0), red)
	dome.scale = Vector3(1.0, 0.65, 1.0)
	Models.cylinder(bonnet, 0.05, 0.08, Vector3(0.0, 0.2, 0.0), brass, 5)
	return bonnet


func label() -> String:
	return "fire hydrant"


## Called every frame the player holds [F] nearby. Returns true when done.
func work(delta: float) -> bool:
	if is_fixed:
		return true
	progress = minf(progress + delta / fix_time, 1.0)
	if progress >= 1.0:
		is_fixed = true
		_spray.emitting = false
		_gush.emitting = false
		_bonnet.visible = true
		_loose_bonnet.visible = false
		var dry := create_tween()
		dry.tween_property(_puddle, "scale", Vector3(0.01, 1.0, 0.01), 6.0)
		dry.tween_callback(_puddle.hide)
		if _hiss:
			_hiss.stop()
		Sfx.play(&"hit_metal", global_position, 0.0, 0.7)
		fixed.emit(self)
	return is_fixed
