class_name SiteGate
extends Node3D
## Flimsy sliding chain-link gate in a datacenter fence, with a guard booth
## and a sign. It slides open (along local +X) while a cargo truck is close
## and shuts behind it. Any weapon breaks it; a broken gate stays open.

@export var width := 7.5
@export var height := 2.4
@export var site_id := &""
@export var sign_text := "AUTHORIZED VEHICLES ONLY"
## Trucks within this range get the gate open.
@export var sense_range := 14.0

var panel: Destructible
var open_amount := 0.0


func _ready() -> void:
	panel = Destructible.new()
	panel.name = "Gate"
	panel.size = Vector3(width, height, 0.12)
	panel.color = Color(0.75, 0.78, 0.8)
	panel.surface_kind = &"chainlink"
	panel.max_health = 40.0
	panel.damage_threshold = 4.0  # flimsy: anything but a thrown rock
	panel.chunks = Vector3i(3, 2, 1)
	panel.label = "Gate"
	panel.site_id = site_id
	add_child(panel)
	var frame := Models.mat(Color(0.3, 0.32, 0.35), &"metal")
	Models.box(panel, Vector3(width, 0.08, 0.14), Vector3(0.0, height, 0.0), frame)
	Models.box(panel, Vector3(width, 0.06, 0.14), Vector3(0.0, 0.12, 0.0), frame)
	Models.box(panel, Vector3(0.9, 0.35, 0.03), Vector3(0.0, 1.3, 0.08), Models.mat(Color(0.9, 0.15, 0.1), &"paint"))
	# Gate posts, a boom-style warning stripe, and the guard booth beside it.
	for x in [-width * 0.5 - 0.15, width * 0.5 + 0.15]:
		Models.box(self, Vector3(0.22, height + 0.4, 0.22), Vector3(x, (height + 0.4) * 0.5, 0.0), frame)
	var booth := Node3D.new()
	booth.position = Vector3(-width * 0.5 - 2.2, 0.0, -1.8)
	add_child(booth)
	Models.box(booth, Vector3(2.2, 2.6, 2.2), Vector3(0.0, 1.3, 0.0), Models.mat(Color(0.82, 0.83, 0.85), &"plates"))
	Models.box(booth, Vector3(1.8, 0.9, 0.05), Vector3(0.0, 1.6, 1.11), Models.window())
	Models.box(booth, Vector3(2.5, 0.15, 2.5), Vector3(0.0, 2.68, 0.0), frame)
	Models.ball(booth, 0.12, Vector3(0.0, 2.9, 0.0), Models.glow(Color(1.0, 0.6, 0.1), 3.0))
	var sign_label := Label3D.new()
	sign_label.text = sign_text
	sign_label.font_size = 40
	sign_label.pixel_size = 0.006
	sign_label.outline_size = 6
	sign_label.position = Vector3(0.0, 1.3, 0.12)
	panel.add_child(sign_label)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(panel) or panel.is_destroyed:
		return
	var wanted := 0.0
	for node in get_tree().get_nodes_in_group("cargo_trucks"):
		var truck := node as Node3D
		if truck and truck.is_visible_in_tree() and truck.global_position.distance_to(global_position) < sense_range:
			wanted = 1.0
			break
	open_amount = move_toward(open_amount, wanted, delta / 1.4)
	panel.position.x = open_amount * (width + 0.3)


## Lets anything through for good (the site has fallen).
func remove() -> void:
	if is_instance_valid(panel) and not panel.is_destroyed:
		panel.queue_free()
	get_tree().call_group(&"nav_baker", &"request_rebake")
