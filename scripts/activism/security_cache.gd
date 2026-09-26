class_name SecurityCache
extends Node3D
## Private security weapons locker inside the datacenter fence. [E] pries it
## open for the rocket launcher (WEAPONS.md: "stolen from corporate security").
## A pulsing beacon and label make it easy to spot from the fence.

signal looted(cache: SecurityCache)

@export var reach := 3.0
@export var rockets := 4

var is_looted := false

var _lid: MeshInstance3D
var _beacon: OmniLight3D
var _tag: Label3D
var _pulse := 0.0


func _ready() -> void:
	add_to_group("interactables")
	var olive := Models.mat(Color(0.3, 0.33, 0.22), &"plates")
	var dark := Models.mat(Color(0.18, 0.2, 0.14), &"plates")
	# Pallet, crate, lid, hazard stripe, and stenciled side panels.
	Models.box(self, Vector3(1.9, 0.14, 1.2), Vector3(0.0, 0.07, 0.0), Models.mat(Color(0.5, 0.38, 0.24)))
	Models.box(self, Vector3(1.6, 0.7, 0.9), Vector3(0.0, 0.5, 0.0), olive)
	_lid = Models.box(self, Vector3(1.65, 0.12, 0.95), Vector3(0.0, 0.91, 0.0), dark)
	Models.box(self, Vector3(0.6, 0.2, 0.02), Vector3(0.0, 0.6, 0.46), Models.mat(Color(0.9, 0.85, 0.2)))
	for x in [-0.72, 0.72]:
		Models.box(self, Vector3(0.1, 0.72, 0.94), Vector3(x, 0.5, 0.0), dark)
	# Keypad light: red while locked, green once opened.
	Models.box(self, Vector3(0.12, 0.12, 0.03), Vector3(0.5, 0.6, 0.46), Models.glow(Color(1.0, 0.15, 0.1), 3.0)).name = "Keypad"
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.75, 0.2)
	_beacon.omni_range = 5.0
	_beacon.position = Vector3(0.0, 1.6, 0.0)
	add_child(_beacon)
	_tag = Label3D.new()
	_tag.text = "SECURITY CACHE\n[E] pry it open"
	_tag.pixel_size = 0.008
	_tag.outline_size = 8
	_tag.modulate = Color(1.0, 0.85, 0.4)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position.y = 1.7
	add_child(_tag)


func _process(delta: float) -> void:
	if is_looted:
		return
	_pulse += delta
	_beacon.light_energy = 1.5 + sin(_pulse * 4.0) * 1.0


func in_reach(player: Node3D) -> bool:
	return not is_looted and player.global_position.distance_to(global_position) <= reach


func offer_text(_player: Player) -> String:
	return "[E] Pry open the security cache: rocket launcher x%d" % rockets


func interact(player: Player) -> void:
	loot(player)


func loot(player: Player) -> void:
	if is_looted:
		return
	is_looted = true
	var weapon := player.unlock_weapon("Rocket launcher", rockets)
	player.select_weapon(player.weapons.find(weapon))
	_lid.rotation.x = -1.2
	_lid.position += Vector3(0.0, 0.3, -0.35)
	(get_node("Keypad") as MeshInstance3D).material_override = Models.glow(Color(0.2, 1.0, 0.3), 3.0)
	_beacon.visible = false
	_tag.text = "SECURITY CACHE\n(empty)"
	_tag.modulate = Color(0.7, 0.7, 0.7)
	Sfx.play(&"unlock", global_position)
	Game.notify("Rocket launcher acquired (%d rockets). Selected it for you: LMB fires, Q switches back." % rockets)
	looted.emit(self)
