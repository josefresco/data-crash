class_name SecurityCache
extends Node3D
## Private security weapons crate inside the datacenter fence. Walk up to it
## to take the rocket launcher (WEAPONS.md: "stolen from corporate security").

signal looted(cache: SecurityCache)

@export var reach := 2.2
@export var rockets := 4

var is_looted := false

var _lid: MeshInstance3D


func _ready() -> void:
	var olive := Models.mat(Color(0.3, 0.33, 0.22))
	Models.box(self, Vector3(1.6, 0.7, 0.9), Vector3(0.0, 0.35, 0.0), olive)
	_lid = Models.box(self, Vector3(1.65, 0.12, 0.95), Vector3(0.0, 0.76, 0.0), Models.mat(Color(0.25, 0.28, 0.18)))
	Models.box(self, Vector3(0.6, 0.2, 0.02), Vector3(0.0, 0.45, 0.46), Models.mat(Color(0.9, 0.85, 0.2)))
	var tag := Label3D.new()
	tag.text = "SECURITY CACHE"
	tag.pixel_size = 0.008
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 1.4
	add_child(tag)


func _physics_process(_delta: float) -> void:
	if is_looted:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.is_visible_in_tree() and player.global_position.distance_to(global_position) <= reach:
		loot(player)


func loot(player: Player) -> void:
	if is_looted:
		return
	is_looted = true
	player.unlock_weapon("Rocket launcher", rockets)
	_lid.rotation.x = -1.2
	_lid.position += Vector3(0.0, 0.3, -0.35)
	looted.emit(self)
