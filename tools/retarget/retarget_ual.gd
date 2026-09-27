extends Node
## Bakes Quaternius Universal Animation Library clips (CC0, Unreal-style
## mannequin rig) onto the Kenney character rig and saves one
## AnimationLibrary: res://assets/quaternius/ual_kenney.res.
##
##   Godot_console.exe --headless --path . res://tools/retarget/retarget_ual.tscn
##
## Sources: assets/quaternius/source/UAL{1,2}_Standard.glb (in-place
## versions; the folder has a .gdignore, so they're read with GLTFDocument).
## Retargeting is done in each rig's model space. For a mapped bone with source
## model rotation A, source rest S, and dest rest D, the dest model rotation is
## (A * S^-1) * Q * D, where Q turns the dest rest bone direction onto the
## source one (so poses match in shape, not just in delta). Unmapped dest bones
## keep their rest pose relative to their parent. The hips also get the
## pelvis translation, scaled by the ratio of hip heights.

const SOURCES := {
	"UAL1": "res://assets/quaternius/source/UAL1_Standard.glb",
	"UAL2": "res://assets/quaternius/source/UAL2_Standard.glb",
}
const KENNEY := "res://assets/kenney/characters/characterMedium.fbx"
const OUT := "res://assets/quaternius/ual_kenney.res"
const TRACK_PREFIX := "Root/Skeleton3D:"
const FPS := 30.0

## Source bone -> Kenney bone.
const MAP := {
	"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
	"neck_01": "Neck", "Head": "Head",
	"clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm", "hand_l": "LeftHand",
	"index_01_l": "LeftHandIndex1", "index_02_l": "LeftHandIndex2", "index_03_l": "LeftHandIndex3",
	"thumb_01_l": "LeftHandThumb1", "thumb_02_l": "LeftHandThumb2",
	"clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm", "hand_r": "RightHand",
	"index_01_r": "RightHandIndex1", "index_02_r": "RightHandIndex2", "index_03_r": "RightHandIndex3",
	"thumb_01_r": "RightHandThumb1", "thumb_02_r": "RightHandThumb2",
	"thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToes",
	"thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToes",
}
## Bone -> child that sets its pointing direction (for the rest alignment Q).
const AIM_CHILD := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "Head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
	"thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
	"index_01_l": "index_02_l", "index_02_l": "index_03_l", "index_01_r": "index_02_r", "index_02_r": "index_03_r",
	"thumb_01_l": "thumb_02_l", "thumb_01_r": "thumb_02_r",
}
## Kenney bone -> child used for its direction (same bones as AIM_CHILD, dest side).
const DEST_AIM_CHILD := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandIndex1",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandIndex1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToes",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToes",
	"LeftHandIndex1": "LeftHandIndex2", "LeftHandIndex2": "LeftHandIndex3",
	"RightHandIndex1": "RightHandIndex2", "RightHandIndex2": "RightHandIndex3",
	"LeftHandThumb1": "LeftHandThumb2", "RightHandThumb1": "RightHandThumb2",
}
## Our clip name -> [source, source clip, loops].
const CLIPS := {
	&"idle": ["UAL1", "Idle_Loop", true],
	&"walk": ["UAL1", "Walk_Loop", true],
	&"jog": ["UAL1", "Jog_Fwd_Loop", true],
	&"sprint": ["UAL1", "Sprint_Loop", true],
	&"jump": ["UAL1", "Jump_Start", false],
	&"jump_loop": ["UAL1", "Jump_Loop", true],
	&"jump_land": ["UAL1", "Jump_Land", false],
	&"pistol_idle": ["UAL1", "Pistol_Idle_Loop", true],
	&"pistol_aim": ["UAL1", "Pistol_Aim_Neutral", true],
	&"pistol_shoot": ["UAL1", "Pistol_Shoot", false],
	&"pistol_reload": ["UAL1", "Pistol_Reload", false],
	&"punch_jab": ["UAL1", "Punch_Jab", false],
	&"punch_cross": ["UAL1", "Punch_Cross", false],
	&"swing": ["UAL1", "Sword_Attack", false],
	&"hit_chest": ["UAL1", "Hit_Chest", false],
	&"hit_head": ["UAL1", "Hit_Head", false],
	&"interact": ["UAL1", "Interact", false],
	&"pickup": ["UAL1", "PickUp_Table", false],
	&"fix": ["UAL1", "Fixing_Kneeling", true],
	&"talk": ["UAL1", "Idle_Talking_Loop", true],
	&"dance": ["UAL1", "Dance_Loop", true],
	&"drive": ["UAL1", "Driving_Loop", true],
	&"crouch_idle": ["UAL1", "Crouch_Idle_Loop", true],
	&"crouch_walk": ["UAL1", "Crouch_Fwd_Loop", true],
	&"phone": ["UAL2", "Idle_TalkingPhone_Loop", true],
	&"fold_arms": ["UAL2", "Idle_FoldArms_Loop", true],
	&"shield_idle": ["UAL2", "Idle_Shield_Loop", true],
	&"shield_bash": ["UAL2", "Shield_OneShot", false],
	&"zombie_idle": ["UAL2", "Zombie_Idle_Loop", true],
	&"zombie_walk": ["UAL2", "Zombie_Walk_Fwd_Loop", true],
	&"zombie_scratch": ["UAL2", "Zombie_Scratch", false],
	&"throw": ["UAL2", "OverhandThrow", false],
	&"watering": ["UAL2", "Farm_Watering", true],
	&"carry_walk": ["UAL2", "Walk_Carry_Loop", true],
	&"hook": ["UAL2", "Melee_Hook", false],
	&"heavy_swing": ["UAL2", "Sword_Regular_A", false],
	&"knockback": ["UAL2", "Hit_Knockback", false],
	&"consume": ["UAL2", "Consume", false],
	&"no": ["UAL2", "Idle_No_Loop", true],
	&"yes": ["UAL2", "Yes", false],
}

var _dest: Skeleton3D
var _dest_model: Transform3D  # skeleton space -> model space (includes the FBX 100x scale)
var _dest_rest: Array[Quaternion] = []  # model-space rest rotation per dest bone
var _dest_rest_pos: Array[Vector3] = []  # model-space rest position per dest bone


func _ready() -> void:
	var library := AnimationLibrary.new()
	var kenney := (load(KENNEY) as PackedScene).instantiate()
	_dest = kenney.find_child("Skeleton3D", true, false) as Skeleton3D
	_dest_model = _chain(kenney, _dest)
	for i in _dest.get_bone_count():
		var rest := _dest_model * _dest.get_bone_global_rest(i)
		_dest_rest.append(Quaternion(rest.basis.orthonormalized()))
		_dest_rest_pos.append(rest.origin)
	var made := 0
	for tag: String in SOURCES:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(ProjectSettings.globalize_path(SOURCES[tag]), state)
		if err != OK:
			push_error("retarget: can't read %s (%d)" % [SOURCES[tag], err])
			continue
		var scene := doc.generate_scene(state)
		var source := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var align := _alignment(scene, source)
		for clip: StringName in CLIPS:
			var spec: Array = CLIPS[clip]
			if spec[0] != tag:
				continue
			if not player.has_animation(spec[1]):
				push_error("retarget: %s has no clip %s" % [tag, spec[1]])
				continue
			var animation := _bake(scene, source, player.get_animation(spec[1]), align, spec[2])
			library.add_animation(clip, animation)
			made += 1
		scene.free()
	kenney.free()
	var err := ResourceSaver.save(library, OUT)
	print("retarget: baked %d clips -> %s (err %d)" % [made, OUT, err])
	get_tree().quit(0 if err == OK and made == CLIPS.size() else 1)


## Transform from `node`'s space up to `root`'s space (root excluded).
func _chain(root: Node, node: Node3D) -> Transform3D:
	var xform := Transform3D()
	var current: Node = node
	while current != root and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## Per mapped source bone: Q that turns the dest rest direction onto the source's.
func _alignment(scene: Node, source: Skeleton3D) -> Dictionary:
	var source_model := _chain(scene, source)
	var align := {}
	for src_name: String in MAP:
		var q := Quaternion()
		var dst_name: String = MAP[src_name]
		if AIM_CHILD.has(src_name) and DEST_AIM_CHILD.has(dst_name):
			var s := source.find_bone(src_name)
			var sc := source.find_bone(AIM_CHILD[src_name])
			var d := _dest.find_bone(dst_name)
			var dc := _dest.find_bone(DEST_AIM_CHILD[dst_name])
			if s >= 0 and sc >= 0 and d >= 0 and dc >= 0:
				var src_dir := (source_model * source.get_bone_global_rest(sc)).origin \
					- (source_model * source.get_bone_global_rest(s)).origin
				var dst_dir := _dest_rest_pos[dc] - _dest_rest_pos[d]
				if src_dir.length() > 0.0001 and dst_dir.length() > 0.0001:
					q = Quaternion(dst_dir.normalized(), src_dir.normalized())
		align[src_name] = q
	return align


func _bake(scene: Node, source: Skeleton3D, clip: Animation, align: Dictionary, loops: bool) -> Animation:
	var source_model := _chain(scene, source)
	var src_count := source.get_bone_count()
	var src_rest: Array[Quaternion] = []
	for i in src_count:
		src_rest.append(Quaternion((source_model * source.get_bone_global_rest(i)).basis.orthonormalized()))
	# Track lookup by bone name.
	var skeleton_path := String(scene.get_path_to(source))
	var rot_tracks := {}
	var pos_tracks := {}
	for t in clip.get_track_count():
		var path := String(clip.track_get_path(t))
		if not path.begins_with(skeleton_path + ":"):
			continue
		var bone := path.get_slice(":", 1)
		match clip.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot_tracks[bone] = t
			Animation.TYPE_POSITION_3D:
				pos_tracks[bone] = t
	var pelvis := source.find_bone("pelvis")
	var src_hip_height := (source_model * source.get_bone_global_rest(pelvis)).origin.y
	var hips := _dest.find_bone("Hips")
	var hip_scale := _dest_rest_pos[hips].y / maxf(src_hip_height, 0.001)
	var hips_parent_model := _dest_model * _dest.get_bone_global_rest(_dest.get_bone_parent(hips))

	var out := Animation.new()
	out.length = clip.length
	out.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	var dst_tracks := {}
	for src_name: String in MAP:
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, TRACK_PREFIX + String(MAP[src_name]))
		dst_tracks[src_name] = t
	var hip_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hip_track, TRACK_PREFIX + "Hips")

	var frames := maxi(int(ceil(clip.length * FPS)), 1)
	var src_global: Array[Transform3D] = []
	src_global.resize(src_count)
	var dst_model: Array[Quaternion] = []
	dst_model.resize(_dest.get_bone_count())
	var dst_index := {}
	for src_name: String in MAP:
		dst_index[_dest.find_bone(MAP[src_name])] = src_name
	for f in frames + 1:
		var time := minf(f / FPS, clip.length)
		# Source pose in model space (parents come before children).
		for i in src_count:
			var name := source.get_bone_name(i)
			var rest := source.get_bone_rest(i)
			var local := Transform3D(rest.basis, rest.origin)
			if rot_tracks.has(name):
				local.basis = Basis(clip.rotation_track_interpolate(rot_tracks[name], time))
			if pos_tracks.has(name):
				local.origin = clip.position_track_interpolate(pos_tracks[name], time)
			var parent := source.get_bone_parent(i)
			src_global[i] = (src_global[parent] if parent >= 0 else source_model) * local
		# Dest pose, parents first.
		for d in _dest.get_bone_count():
			var parent := _dest.get_bone_parent(d)
			var parent_model := dst_model[parent] if parent >= 0 else Quaternion(_dest_model.basis.orthonormalized())
			var model_rot: Quaternion
			if dst_index.has(d):
				var src_name: String = dst_index[d]
				var s := source.find_bone(src_name)
				var anim_rot := Quaternion(src_global[s].basis.orthonormalized())
				model_rot = (anim_rot * src_rest[s].inverse()) * (align[src_name] as Quaternion) * _dest_rest[d]
				var local_rot := (parent_model.inverse() * model_rot).normalized()
				out.rotation_track_insert_key(dst_tracks[src_name], time, local_rot)
			else:
				model_rot = parent_model * Quaternion(_dest.get_bone_rest(d).basis.orthonormalized())
			dst_model[d] = model_rot
		# Hips translation: the pelvis offset from rest, scaled to the Kenney rig.
		var pelvis_pos := src_global[pelvis].origin
		var rest_pos := (source_model * source.get_bone_global_rest(pelvis)).origin
		var target := _dest_rest_pos[hips] + (pelvis_pos - rest_pos) * hip_scale
		out.position_track_insert_key(hip_track, time, hips_parent_model.affine_inverse() * target)
	return out
