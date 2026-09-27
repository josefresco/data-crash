class_name FlinchModifier
extends SkeletonModifier3D
## Hit reaction layered on the animation: the spine and head snap away from
## the blow and ease back over `recover` seconds. Call `hit(push, strength)`
## with the world-space push direction (attacker -> victim) and 0..1 strength.

@export var max_angle := 0.45
@export var recover := 0.3

var _spine := -1
var _head := -1
var _axis := Vector3.RIGHT
var _amount := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton:
		_spine = skeleton.find_bone("Spine")
		_head = skeleton.find_bone("Head")


func hit(push: Vector3, strength: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _spine < 0:
		return
	var local := (skeleton.global_transform.basis.inverse() * push)
	local.y = 0.0
	if local.length_squared() < 0.0001:
		return
	# Leaning the top of the spine along the push: rotate about up x push.
	_axis = Vector3.UP.cross(local.normalized()).normalized()
	_amount = clampf(maxf(_amount, strength), 0.0, 1.0)


func _process_modification_with_delta(delta: float) -> void:
	if _amount <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null or _spine < 0:
		return
	var angle := _amount * max_angle
	for bone in [_spine, _head]:
		if bone < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var turn := Basis(_axis, angle * (1.0 if bone == _spine else 0.6))
		skeleton.set_bone_global_pose(bone, Transform3D(turn * pose.basis, pose.origin))
	_amount = maxf(_amount - delta / recover, 0.0)
