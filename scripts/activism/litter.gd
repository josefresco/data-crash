class_name Litter
extends Node3D
## Trash on the lawns and sidewalks, mostly Felsa delivery packaging. Walk
## over it to pick it up ($2 each; clearing all of it is a good deed).

signal collected(piece: Litter)

@export var reach := 1.5

var _clock := randf() * TAU


func _ready() -> void:
	add_to_group("litter")
	rotation.y = randf() * TAU
	match randi() % 4:
		0:  # soda can
			Models.cylinder(self, 0.04, 0.13, Vector3(0.0, 0.04, 0.0), Models.mat(Color(0.8, 0.15, 0.12), &"metal"), 8).rotation.z = PI * 0.5
		1:  # delivery box with the Felsa stripe
			Models.box(self, Vector3(0.35, 0.22, 0.28), Vector3(0.0, 0.11, 0.0), Models.mat(Color(0.72, 0.58, 0.4), &"rough"))
			Models.box(self, Vector3(0.36, 0.05, 0.29), Vector3(0.0, 0.16, 0.0), Models.mat(Color(0.2, 0.35, 0.8)))
		2:  # trash bag
			Models.ball(self, 0.22, Vector3(0.0, 0.18, 0.0), Models.mat(Color(0.08, 0.08, 0.09), &"paint")).scale = Vector3(1.0, 0.8, 1.0)
		_:  # crumpled paper and a cup
			Models.ball(self, 0.07, Vector3(0.1, 0.06, 0.0), Models.mat(Color(0.95, 0.95, 0.92), &"cloth"))
			Models.cylinder(self, 0.05, 0.14, Vector3(-0.1, 0.05, 0.05), Models.mat(Color(0.9, 0.9, 0.88), &"paint"), 8).rotation.x = PI * 0.5


func _process(delta: float) -> void:
	_clock += delta
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.is_visible_in_tree() and player.global_position.distance_to(global_position) <= reach:
		collect()


func collect() -> void:
	if is_queued_for_deletion():
		return
	Game.add_cash(2)
	Sfx.play(&"hit_soft", global_position, -6.0)
	collected.emit(self)
	queue_free()
