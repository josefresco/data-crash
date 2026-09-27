class_name CharacterModel
extends Node3D
## Animated Kenney humanoid (CC0, assets/kenney/characters) wearing a faction
## outfit skin from tools/generate_skins.py. Feet at y = 0, facing -Z, scaled
## to `height`. Gear attaches to bones via anchor() so it follows animations.
##
## Animation comes from the Quaternius Universal Animation Library (CC0),
## baked onto this rig by tools/retarget (assets/quaternius/ual_kenney.res),
## through an AnimationTree built in code:
## - legs: idle / walk / jog / sprint blended by speed (set_motion)
## - upper body: a held pose over the legs (set_upper: pistol aim, phone, ...)
## - one-shots: upper-body actions (play_action: shoot, punch, swing, throw)
##   and full-body ones (play_action(clip, true): jump, hit knockback)
##
## Usage:
##   var model := CharacterModel.create("police", 1.8)
##   model.set_motion(speed / Enemy.RUN_CLIP_SPEED)
##   model.set_upper(&"shield_idle")
##   model.play_action(&"swing")
##   Models.box(model.anchor(&"head"), ...)  # hat that bobs with the head

const BASE_SCENE := preload("res://assets/kenney/characters/characterMedium.fbx")
const SKIN_DIR := "res://assets/kenney/characters/skins/"
const LIBRARY_PATH := "res://assets/quaternius/ual_kenney.res"
## Locomotion blend points: clip -> speed ratio (speed / Enemy.RUN_CLIP_SPEED).
const LOCOMOTION := {&"idle": 0.0, &"walk": 0.35, &"jog": 0.9, &"sprint": 1.5}
const SKELETON_PATH := "Root/Skeleton3D:"
## Bones the upper-body layers (held poses, actions) drive; legs keep walking.
const UPPER_BONES := ["Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3",
	"LeftHandThumb1", "LeftHandThumb2",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandIndex1", "RightHandIndex2", "RightHandIndex3",
	"RightHandThumb1", "RightHandThumb2"]
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
var _tree: AnimationTree
var _upper_clip: AnimationNodeAnimation
var _action_clip: AnimationNodeAnimation
var _full_clip: AnimationNodeAnimation
var _upper_target := 0.0
var _upper_weight := 0.0
var _air_target := 0.0
var _air_weight := 0.0
## Animation LOD: advance the tree every `_step` frames (1 = every frame).
var _step := 1
var _step_count := 0
var _step_delta := 0.0
var _anchors := {}
var _scale := 1.0


## `tone` < 0 picks a random skin tone.
static func create(outfit_name: String, height := 1.8, tone := -1) -> CharacterModel:
	var character := CharacterModel.new()
	character.outfit = outfit_name
	character._build(height, tone if tone >= 0 else randi() % TONES)
	return character


func set_motion(speed_ratio: float) -> void:
	if _tree:
		_tree.set(&"parameters/loco/blend_position", clampf(speed_ratio, 0.0, 1.6))


## Holds `clip` on the upper body over the locomotion (&"" releases it).
func set_upper(clip: StringName, weight := 1.0) -> void:
	if _tree == null:
		return
	if clip == &"":
		_upper_target = 0.0
		return
	var full := &"ual/" + clip
	if _upper_clip.animation != full:
		_upper_clip.animation = full
	_upper_target = weight


func upper_clip() -> StringName:
	return String(_upper_clip.animation).trim_prefix("ual/") if _tree and _upper_target > 0.0 else &""


## Plays `clip` once: on the upper body, or the whole body with `full_body`.
func play_action(clip: StringName, full_body := false) -> void:
	if _tree == null:
		return
	var node := _full_clip if full_body else _action_clip
	node.animation = &"ual/" + clip
	var request := &"parameters/full/request" if full_body else &"parameters/action/request"
	_tree.set(request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Animation LOD: update the pose every `frames` frames (mid-distance crowds
## at 2-3 look the same and cost a fraction).
func set_update_step(frames: int) -> void:
	frames = maxi(frames, 1)
	if _tree == null or frames == _step:
		return
	_step = frames
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if frames == 1 		else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_step_delta = 0.0
	_step_count = 0


## Pause the animation (far-away crowds, ragdolls); the pose freezes.
func set_animation_active(active: bool) -> void:
	if _tree and _tree.active != active:
		_tree.active = active


func _process(delta: float) -> void:
	if _tree == null:
		return
	if _step > 1 and _tree.active:
		_step_delta += delta
		_step_count += 1
		if _step_count >= _step:
			_tree.advance(_step_delta)
			_step_delta = 0.0
			_step_count = 0
	if not is_equal_approx(_air_weight, _air_target):
		_air_weight = move_toward(_air_weight, _air_target, delta * 6.0)
		_tree.set(&"parameters/air/blend_amount", _air_weight)
	if is_equal_approx(_upper_weight, _upper_target):
		return
	_upper_weight = move_toward(_upper_weight, _upper_target, delta * 5.0)
	_tree.set(&"parameters/upper/blend_amount", _upper_weight)


func skeleton() -> Skeleton3D:
	return _skeleton


func play_jump() -> void:
	play_action(&"jump", true)


## Holds the mid-air pose (full body) while `on`; blends back when landing.
func set_airborne(on: bool) -> void:
	_air_target = 1.0 if on else 0.0


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
	_player.name = "AnimationPlayer"
	_model.add_child(_player)  # root_node ".." = the model, matching the clips' track paths
	_player.add_animation_library(&"ual", _shared_library())
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = _build_tree()
	_model.add_child(_tree)
	_tree.anim_player = NodePath("../AnimationPlayer")
	_tree.active = true


## loco (BlendSpace1D) -> upper (Blend2, upper-body filter) -> action
## (OneShot, upper-body filter) -> full (OneShot) -> air (Blend2 to the
## jump loop while airborne) -> output.
func _build_tree() -> AnimationNodeBlendTree:
	var root := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 1.6
	loco.sync = true
	for clip: StringName in LOCOMOTION:
		var node := AnimationNodeAnimation.new()
		node.animation = &"ual/" + clip
		loco.add_blend_point(node, LOCOMOTION[clip], -1, clip)
	root.add_node(&"loco", loco, Vector2(0, 0))
	_upper_clip = AnimationNodeAnimation.new()
	_upper_clip.animation = &"ual/pistol_idle"
	root.add_node(&"upper_clip", _upper_clip, Vector2(0, 200))
	var upper := AnimationNodeBlend2.new()
	_filter_upper(upper)
	root.add_node(&"upper", upper, Vector2(250, 0))
	_action_clip = AnimationNodeAnimation.new()
	_action_clip.animation = &"ual/punch_jab"
	root.add_node(&"action_clip", _action_clip, Vector2(250, 200))
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.08
	action.fadeout_time = 0.2
	_filter_upper(action)
	root.add_node(&"action", action, Vector2(500, 0))
	_full_clip = AnimationNodeAnimation.new()
	_full_clip.animation = &"ual/jump"
	root.add_node(&"full_clip", _full_clip, Vector2(500, 200))
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.1
	full.fadeout_time = 0.25
	root.add_node(&"full", full, Vector2(750, 0))
	root.connect_node(&"upper", 0, &"loco")
	root.connect_node(&"upper", 1, &"upper_clip")
	root.connect_node(&"action", 0, &"upper")
	root.connect_node(&"action", 1, &"action_clip")
	# Mid-air: a full-body blend to the jump loop while airborne.
	var air_clip := AnimationNodeAnimation.new()
	air_clip.animation = &"ual/jump_loop"
	root.add_node(&"air_clip", air_clip, Vector2(750, 200))
	root.add_node(&"air", AnimationNodeBlend2.new(), Vector2(1000, 0))
	root.connect_node(&"full", 0, &"action")
	root.connect_node(&"full", 1, &"full_clip")
	root.connect_node(&"air", 0, &"full")
	root.connect_node(&"air", 1, &"air_clip")
	root.connect_node(&"output", 0, &"air")
	return root


func _filter_upper(node: AnimationNode) -> void:
	node.filter_enabled = true
	for bone: String in UPPER_BONES:
		node.set_filter_path(NodePath(SKELETON_PATH + bone), true)


## The retargeted clip library, loaded once and shared.
static func _shared_library() -> AnimationLibrary:
	if _library == null:
		_library = load(LIBRARY_PATH) as AnimationLibrary
	return _library
