class_name GasTurbine
extends Destructible
## On-site gas turbine generator powering a corporate datacenter. Loud, and its
## exhaust stack pours smoke into the neighborhood. Small arms bounce off; the
## rifle, explosives, and the bulldozer get through. Blowing one up sets off a
## fuel explosion and leaves a burning wreck. The Datacenter tracks them.

@export var blast_radius := 7.0
@export var blast_damage := 120.0
@export var wreck_burn_time := 25.0

var is_running := true
## Taken apart after the datacenter falls: no fuel explosion, no wreck.
var dismantled := false

var _smoke: GPUParticles3D
var _glow: StandardMaterial3D
var _roar: AudioStreamPlayer3D


func _init() -> void:
	size = Vector3(6.0, 3.2, 2.8)
	color = Color(0.78, 0.8, 0.82)
	surface_kind = &"plates"
	max_health = 400.0
	damage_threshold = 30.0
	chunks = Vector3i(3, 2, 2)
	label = "Gas turbine"


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	add_to_group("gas_turbines")
	var steel := Models.mat(Color(0.62, 0.64, 0.66), &"plates")
	var dark := Models.mat(Color(0.35, 0.36, 0.38), &"plates")
	# Exhaust stack at one end, intake housing at the other, pipework between.
	Models.cylinder(self, 0.55, 9.0, Vector3(size.x * 0.36, size.y + 4.5, 0.0), steel, 12)
	Models.cylinder(self, 0.7, 0.4, Vector3(size.x * 0.36, size.y + 0.2, 0.0), dark, 12)
	Models.box(self, Vector3(1.4, 2.2, size.z + 0.4), Vector3(-size.x * 0.5 - 0.6, 1.1, 0.0), dark)
	for i in 3:
		Models.box(self, Vector3(1.0, 0.8, 0.06), Vector3(-1.8 + i * 1.3, size.y * 0.6, size.z * 0.5 + 0.03), dark)
	Models.cylinder(self, 0.18, size.x * 0.8, Vector3(0.0, size.y + 0.3, size.z * 0.3), steel, 8).rotation.z = PI * 0.5
	# Heat glow at the stack's mouth.
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.45, 0.15)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.4, 0.1)
	_glow.emission_energy_multiplier = 3.0
	Models.cylinder(self, 0.5, 0.2, Vector3(size.x * 0.36, size.y + 9.0, 0.0), _glow, 12)
	_smoke = Vfx.smoke_column(self, Vector3(size.x * 0.36, size.y + 9.4, 0.0), 2.2)
	_roar = Sfx.loop(self, &"turbine_loop", -3.0)
	destroyed.connect(_on_destroyed)


## Datacenter offline: the turbine spins down and stops smoking.
func shut_down() -> void:
	is_running = false
	if _roar:
		var fade := create_tween()
		fade.tween_property(_roar, "pitch_scale", 0.3, 2.5)
		fade.parallel().tween_property(_roar, "volume_db", -40.0, 2.5)
		fade.tween_callback(_roar.stop)
	if _smoke:
		_smoke.emitting = false
	if _glow:
		_glow.emission_energy_multiplier = 0.0


func _on_destroyed(_self: Destructible) -> void:
	if _roar:
		_roar.stop()
	if dismantled:
		return
	var at := global_position + Vector3.UP * size.y * 0.5
	var parent := get_tree().current_scene
	# Fuel explosion: hurts everything nearby, including other turbines.
	var blast := Explosive.new()
	blast.radius = blast_radius
	blast.damage = blast_damage
	parent.add_child(blast)
	blast.global_position = at
	blast.detonate.call_deferred()
	# Burning wreck left behind.
	var wreck := Node3D.new()
	parent.add_child(wreck)
	wreck.global_position = global_position
	Vfx.fire_patch(wreck, Vector3.UP * 0.3, 2.0)
	Sfx.loop(wreck, &"fire_loop", 0.0)
	var smoke := Vfx.smoke_column(wreck, Vector3.UP * 2.0, 2.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.position.y = 1.5
	wreck.add_child(light)
	var tween := wreck.create_tween()
	tween.tween_interval(wreck_burn_time)
	tween.tween_callback(func() -> void: smoke.emitting = false)
	tween.tween_property(light, "light_energy", 0.0, 3.0)
	tween.tween_callback(wreck.queue_free)
