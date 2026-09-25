class_name Foreman
extends Node3D
## Sympathetic construction foreman. Hands over the bulldozer once the
## neighborhood trusts you enough (the vehicle itself enforces the lock).

@export var vehicle_path: NodePath

var _label: Label3D
var _refresh_left := 0.0


func _ready() -> void:
	var rig := Models.humanoid(Models.mat(Color(1.0, 0.6, 0.1)), Color(0.25, 0.3, 0.4), Models.random_skin())
	add_child(rig)
	Models.box(rig, Vector3(0.34, 0.12, 0.36), Vector3(0.0, 1.75, 0.0), Models.mat(Color(0.95, 0.95, 0.9)))
	_label = Label3D.new()
	_label.pixel_size = 0.01
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.4
	add_child(_label)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.5
	var dozer := get_node_or_null(vehicle_path) as Car
	if dozer == null:
		_label.text = ""
	elif dozer.can_enter():
		_label.text = "Foreman: \"Keys are in it. Knock 'em down.\""
	else:
		_label.text = "Foreman: \"Show me the block's behind you.\"\n(trust %d%% / %d%%)" % [
			roundi(Game.district.trust * 100.0), roundi(dozer.required_trust * 100.0)]
