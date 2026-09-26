class_name CharacterModel
extends Node3D
## Animated Kenney humanoid (CC0, assets/kenney/characters) wearing a faction
## outfit skin from tools/generate_skins.py. Feet at y = 0, facing -Z, scaled
## to `height`. Gear attaches to bones via anchor() so it follows animations.
##
## Usage:
##   var model := CharacterModel.create("police", 1.8)
##   model.set_motion(speed / run_speed)   # idle <-> run blend
##   Models.box(model.anchor(&"head"), ...)  # hat that bobs with the head

const BASE_SCENE := preload("res://assets/kenney/characters/characterMedium.fbx")
const SKIN_DIR := "res://assets/kenney/characters/skins/"
const ANIMATIONS := {
	&"idle": ["res://assets/kenney/characters/animations/idle.fbx", "Root|Idle", true],
	&"run": ["res://assets/kenney/characters/animations/run.fbx", "Root|Run", true],
	&"jump": ["res://assets/kenney/characters/animations/jump.fbx", "Root|Jump", false],
}
## Rest-pose height of the Kenney mesh in its own units.
const NATIVE_HEIGHT := 3.76
const TONES := 5
## Anchor name -> skeleton bone.
const BONES := {&"head": "Head", &"chest": "UpperChest", &"hips": "Hips",
	&"hand_r": "RightHand", &"hand_l": "LeftHand", &"forearm_l": "LeftForeArm"}

static var _library: AnimationLibrary

## Unique per character: tint and flash it freely (albedo multiplies the skin).
var material: StandardMaterial3D
var outfit := ""

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _anchors := {}
var _scale := 1.0
var _current := &""


## `tone` < 0 picks a random skin tone.
static func create(outfit_name: String, height := 1.8, tone := -1) -> CharacterModel:
	var character := CharacterModel.new()
	character.outfit = outfit_name
	character._build(height, tone if tone >= 0 else randi() % TONES)
	return character


func set_motion(speed_ratio: float) -> void:
	if _player == null:
		return
	if speed_ratio > 0.15:
		_play(&"run")
		_player.speed_scale = clampf(speed_ratio, 0.55, 1.4)
	else:
		_play(&"idle")
		_player.speed_scale = 1.0


func play_jump() -> void:
	_play(&"jump")


## A node that follows `name`'s bone (see BONES), in meters and unscaled.
## Children are placed relative to the bone's origin.
func anchor(anchor_name: StringName) -> Node3D:
	if _anchors.has(anchor_name):
		return _anchors[anchor_name]
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = BONES.get(anchor_name, "Hips")
	_skeleton.add_child(attachment)
	# Undo everything between this node and the bone (FBX unit scale, model
	# scale and turn, bone rest rotation) so the holder is in meters with +Y
	# up and -Z forward in the rest pose.
	var holder := Node3D.new()
	var bone := _skeleton.find_bone(attachment.bone_name)
	var chain := Transform3D()
	var node: Node = _skeleton
	while node != self and node is Node3D:
		chain = (node as Node3D).transform * chain
		node = node.get_parent()
	var bone_in_self := chain * _skeleton.get_bone_global_rest(bone)
	holder.transform = Transform3D(bone_in_self.basis.inverse(), Vector3.ZERO)
	attachment.add_child(holder)
	_anchors[anchor_name] = holder
	return holder


func _build(height: float, tone: int) -> void:
	_model = BASE_SCENE.instantiate() as Node3D
	_scale = height / NATIVE_HEIGHT
	_model.scale = Vector3.ONE * _scale
	_model.rotation.y = PI  # Kenney characters face +Z; ours face -Z
	add_child(_model)
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D

	material = StandardMaterial3D.new()
	var skin_path := "%s%s_%d.png" % [SKIN_DIR, outfit, tone]
	if not ResourceLoader.exists(skin_path):
		skin_path = "%splayer_%d.png" % [SKIN_DIR, tone]
	material.albedo_texture = load(skin_path)
	material.roughness = 0.85
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

	_player = AnimationPlayer.new()
	_model.add_child(_player)  # root_node ".." = the model, matching the clips' track paths
	_player.add_animation_library(&"", _shared_library())
	_play(&"idle")


func _play(clip: StringName) -> void:
	if _current == clip and _player.is_playing():
		return
	_current = clip
	_player.play(clip, 0.2)


## Clips from the three Kenney animation files, loaded once and shared.
static func _shared_library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for clip: StringName in ANIMATIONS:
		var spec: Array = ANIMATIONS[clip]
		var source := (load(spec[0]) as PackedScene).instantiate()
		for player: AnimationPlayer in source.find_children("*", "AnimationPlayer", true, false):
			var library := player.get_animation_library(&"")
			if library and library.has_animation(spec[1]):
				var animation := library.get_animation(spec[1]).duplicate() as Animation
				animation.loop_mode = Animation.LOOP_LINEAR if spec[2] else Animation.LOOP_NONE
				_library.add_animation(clip, animation)
		source.free()
	return _library
