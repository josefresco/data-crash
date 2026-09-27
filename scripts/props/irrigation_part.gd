class_name IrrigationPart
extends Destructible
## Corporate landscaping irrigation around a datacenter: sprinkler heads,
## the controller boxes that run them, and decorative fountains. Lush lawns
## watered around the clock while the neighborhood's taps run dry.
##
## Smashing one saves water (`water_gain` onto the district's water table)
## and pays `cash`. A controller also shuts off its `controlled` sprinklers
## (each still gives back half its water). Not site property: wrecking the
## landscaping doesn't trip the alarm (like the Grock cameras). Group
## "irrigation"; the level counts them on the deeds checklist.

enum Kind { SPRINKLER, CONTROLLER, FOUNTAIN }

@export var kind := Kind.SPRINKLER
@export var water_gain := 0.004
@export var cash := 15

## Sprinklers a controller runs.
var controlled: Array[IrrigationPart] = []
var running := true

var _sprays: Array[GPUParticles3D] = []
var _sweep: Node3D
var _sweep_angle := randf() * TAU
var _visible_left := randf() * 0.5


func _init() -> void:
	surface_kind = &"metal"
	chunks = Vector3i(1, 1, 1)
	damage_threshold = 0.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	add_to_group("irrigation")
	destroyed.connect(_on_destroyed)
	match kind:
		Kind.SPRINKLER:
			label = "Lawn sprinkler"
			# A rotating head: the spray is tilted and swept around.
			_sweep = Node3D.new()
			_sweep.position.y = size.y
			add_child(_sweep)
			var spray := Vfx.water_spray(_sweep)
			spray.rotation.x = deg_to_rad(-55.0)
			spray.amount_ratio = 0.55
			spray.emitting = true
			_sprays.append(spray)
		Kind.FOUNTAIN:
			label = "Decorative fountain"
			for offset in [Vector3.ZERO, Vector3(0.7, 0.0, 0.0), Vector3(-0.7, 0.0, 0.0)]:
				var jet := Vfx.water_spray(self, offset + Vector3.UP * size.y)
				jet.emitting = true
				_sprays.append(jet)
		Kind.CONTROLLER:
			label = "Irrigation controller"


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not running or is_destroyed:
		return
	if _sweep:
		_sweep_angle += delta * 1.6
		_sweep.rotation.y = sin(_sweep_angle) * 1.4
	# Only spray near the camera (cheap crowds of sprinklers).
	_visible_left -= delta
	if _visible_left <= 0.0:
		_visible_left = 0.5
		var camera := get_viewport().get_camera_3d()
		var near := camera == null or camera.global_position.distance_to(global_position) < 90.0
		for spray in _sprays:
			spray.emitting = near


## The controller feeding this sprinkler died: the water stops.
func shut_off() -> void:
	if not running or is_destroyed:
		return
	running = false
	for spray in _sprays:
		spray.emitting = false
	if Game.district:
		Game.district.water_table += water_gain * 0.5
	get_tree().call_group(&"level", &"on_irrigation_changed")


func _on_destroyed(_self: Destructible) -> void:
	var was_running := running
	running = false
	for spray in _sprays:
		spray.emitting = false
	if Game.district and was_running:
		Game.district.water_table += water_gain
	Game.add_cash(cash)
	Game.count("irrigation")
	var shut := 0
	for part in controlled:
		if is_instance_valid(part) and part.running and not part.is_destroyed:
			part.shut_off()
			shut += 1
	match kind:
		Kind.CONTROLLER:
			Game.notify("Irrigation controller smashed: %d sprinklers shut off. The aquifer thanks you. (+$%d)" % [shut, cash], 4.0)
		Kind.FOUNTAIN:
			Game.notify("Decorative fountain wrecked. That was a lot of water for a logo. (+$%d, water up)" % cash, 4.0)
		_:
			if randf() < 0.35:
				Game.notify("Sprinkler busted. The lawn can wait. (+$%d)" % cash, 2.5)
	get_tree().call_group(&"level", &"on_irrigation_changed")
