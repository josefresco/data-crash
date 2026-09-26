class_name GrockCamera
extends Destructible
## Grock AI surveillance camera on a pole: Elmo's chatbot watching the block
## and "summarizing" the neighbors. Any weapon breaks it. Each one smashed pays
## `reward` and earns the neighborhood's goodwill.

signal smashed(camera: GrockCamera)

@export var reward := 40
@export var trust_reward := 0.02
@export var pan_degrees := 50.0

var _head: Node3D
var _clock := randf() * TAU


func _init() -> void:
	size = Vector3(0.22, 4.2, 0.22)
	color = Color(0.3, 0.32, 0.35)
	surface_kind = &"metal"
	max_health = 30.0
	damage_threshold = 0.0
	chunks = Vector3i(1, 3, 1)
	debris_lifetime = 6.0
	label = "Grock camera"


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	add_to_group("grock_cameras")
	var body := Models.mat(Color(0.1, 0.1, 0.12), &"paint")
	var white := Models.mat(Color(0.9, 0.9, 0.92), &"paint")
	Models.box(self, Vector3(0.9, 0.08, 0.08), Vector3(0.35, size.y - 0.1, 0.0), body)  # arm
	_head = Node3D.new()
	_head.position = Vector3(0.75, size.y - 0.3, 0.0)
	add_child(_head)
	Models.box(_head, Vector3(0.3, 0.3, 0.55), Vector3.ZERO, white)
	Models.box(_head, Vector3(0.36, 0.05, 0.62), Vector3(0.0, 0.18, -0.03), body)  # sun hood
	Models.cylinder(_head, 0.1, 0.06, Vector3(0.0, 0.0, -0.3), body, 12).rotation.x = PI * 0.5
	Models.ball(_head, 0.06, Vector3(0.0, 0.0, -0.33), Models.glow(Color(1.0, 0.1, 0.05), 5.0))  # the AI eye
	var tag := Label3D.new()
	tag.text = "GROCK"
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.outline_size = 0
	tag.modulate = Color(0.1, 0.1, 0.12)
	tag.position = Vector3(0.155, 0.0, 0.0)
	tag.rotation.y = PI * 0.5
	_head.add_child(tag)
	destroyed.connect(_on_smashed)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or is_destroyed or _head == null:
		return
	_clock += delta * 0.6
	_head.rotation.y = deg_to_rad(sin(_clock) * pan_degrees)
	_head.rotation.x = deg_to_rad(-18.0)


func _on_smashed(_self: Destructible) -> void:
	Game.add_cash(reward)
	if Game.district:
		Game.district.trust += trust_reward
	Game.count("cameras")
	Sfx.play(&"glitch", global_position + Vector3.UP * size.y, 0.0)
	smashed.emit(self)
