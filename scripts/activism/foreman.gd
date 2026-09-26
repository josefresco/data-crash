class_name Foreman
extends Node3D
## Sympathetic construction foreman. Hands over the bulldozer once the
## neighborhood trusts you enough (the vehicle itself enforces the lock).

@export var vehicle_path: NodePath

var _label: Label3D
var _refresh_left := 0.0


func _ready() -> void:
	var rig := CharacterModel.create("foreman")
	add_child(rig)
	Models.hat(rig.anchor(&"head"), &"hardhat", Color(0.95, 0.95, 0.9), 0.54)  # white hard hat
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
