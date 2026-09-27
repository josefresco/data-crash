class_name PeteBottleneck
extends Enemy
## Boss (PureDrain Bottling, District 2): Pete Bottleneck, bottled-water
## baron. A pressure washer that shoves you across the yard while it
## stings, and he shrugs off hoses ("That's MY water!"). While his river
## pumps run he keeps topping himself up. Counter: wreck the river pumps
## (each one gives the river some water back), then shoot him.

const LINES := [
	"Water is a product, not a right.",
	"Tap water? In THIS economy?",
	"Hydration is a subscription now.",
	"The river signed a waiver.",
	"Premium drought, premium prices.",
	"You're standing on my aquifer.",
]

## Pressure washer: damage per second and push per 0.1 s tick on the target.
@export var jet_damage := 12.0
@export var jet_push := 0.4
## Health per second while any of his site's river pumps runs.
@export var pump_regen := 12.0
@export var line_interval := 7.0

var _line_left := 3.0
var _jet: GPUParticles3D
var _jet_left := 0.0
var _scoff_left := 0.0


func _init() -> void:
	voice_pitch = 0.85
	outfit = "pete"
	max_health = 900.0
	move_speed = 3.0
	sight_range = 30.0
	attack_range = 13.0
	structure_engage_range = 12.0
	attack_interval = 0.1
	bounty = 400
	body_color = Color(0.55, 0.78, 0.92)
	boss_name = "PETE BOTTLENECK"


func _ready() -> void:
	super()
	var nozzle := _hold_weapon(&"firehose", Color(0.2, 0.45, 0.9))
	var muzzle := nozzle.get_node_or_null("Muzzle") as Node3D if nozzle else null
	if muzzle:
		_jet = Vfx.water_jet(muzzle)
		var jet_material := _jet.process_material as ParticleProcessMaterial
		jet_material.initial_velocity_min = attack_range * 1.3
		jet_material.initial_velocity_max = attack_range * 1.5


## His site's river pumps still running.
func pumps_running() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("river_pumps"):
		var pump := node as Destructible
		if pump and not pump.is_destroyed and pump.site_id == site:
			count += 1
	return count


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead or is_dormant():
		return
	_scoff_left = maxf(_scoff_left - delta, 0.0)
	_jet_left = maxf(_jet_left - delta, 0.0)
	if _jet and _jet.emitting and _jet_left <= 0.0:
		_jet.emitting = false
	if health < max_health and pumps_running() > 0:
		health = minf(health + pump_regen * delta, max_health)
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = line_interval
		speak(LINES.pick_random())


## One pressure-washer tick at `victim`: a sting and a hard shove.
func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	_jet_left = 0.25
	if _jet:
		_jet.emitting = true
	var push := victim.global_position - global_position
	push.y = 0.0
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", jet_damage * attack_interval, muzzle_point(), &"water")
	if victim.has_method("apply_knockback"):
		victim.call(&"apply_knockback", push.normalized() * jet_push + Vector3.UP * 0.1)
	if victim is Enemy:
		(victim as Enemy).soak(2.0)


func _modify_damage(amount: float, _from: Vector3, kind: StringName) -> float:
	if kind == &"water":
		if _scoff_left <= 0.0:
			_scoff_left = 4.0
			speak("That's MY water!")
		return 0.0
	return amount


func _upper_pose() -> StringName:
	return &"pistol_aim" if _is_valid(target) and _has_los else &"pistol_idle"


func _on_death() -> void:
	speak("You can't un-bottle a river...")
