@tool
class_name FenceLine
extends Node3D
## Row of destructible chain-link panels along local +X. Weak to ramming,
## immune to small arms (threshold above pistol damage).

## Emitted once, the first time any panel in this line is destroyed.
signal breached

@export var length := 20.0:
	set(value):
		length = maxf(value, 1.0)
		if is_node_ready():
			_rebuild()
@export var panel_width := 2.5
@export var height := 2.2
@export var panel_health := 60.0
@export var damage_threshold := 20.0
@export var color := Color(0.85, 0.87, 0.9)

var _breached := false


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta(&"generated"):
			remove_child(child)
			child.queue_free()

	var count := maxi(int(round(length / panel_width)), 1)
	var width := length / count
	for i in count:
		var panel := Destructible.new()
		panel.set_meta(&"generated", true)
		panel.name = "Panel%d" % i
		panel.size = Vector3(width - 0.08, height, 0.1)
		panel.color = color
		panel.max_health = panel_health
		panel.damage_threshold = damage_threshold
		panel.chunks = Vector3i(3, 2, 1)
		panel.label = "Fence"
		panel.surface_kind = &"chainlink"  # alpha-cutout wire mesh
		panel.position = Vector3((i + 0.5) * width, 0.0, 0.0)
		add_child(panel)
		# Posts stay standing when the mesh is torn out.
		var post := Models.cylinder(self, 0.06, height + 0.2, Vector3(i * width, (height + 0.2) * 0.5, 0.0),
			Models.mat(Color(0.4, 0.42, 0.45)), 6)
		post.set_meta(&"generated", true)
		if not Engine.is_editor_hint():
			panel.destroyed.connect(_on_panel_destroyed)


func _on_panel_destroyed(_panel: Destructible) -> void:
	if not _breached:
		_breached = true
		breached.emit()
