class_name AimModifier
extends SkeletonModifier3D
## Raises a Kenney character's arms to aim, layered on top of the idle/run
## animation. The right arm straightens along `aim_direction`; with
## `two_handed`, the left arm reaches for `grip_point` (a foregrip). Blend in
## and out with the built-in `influence`. Directions and points are world space.

var aim_direction := Vector3.FORWARD
var two_handed := false
var grip_point := Vector3.ZERO

var _right: PackedInt32Array = []
var _left: PackedInt32Array = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	# Upper arm, forearm, hand: aligning the first two straightens the arm.
	for bone in ["RightArm", "RightForeArm", "RightHand"]:
		_right.append(skeleton.find_bone(bone))
	for bone in ["LeftArm", "LeftForeArm", "LeftHand"]:
		_left.append(skeleton.find_bone(bone))


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _right.has(-1) or _left.has(-1):
		return
	var to_local := skeleton.global_transform.affine_inverse()
	var direction := (to_local.basis * aim_direction).normalized()
	_point_chain(skeleton, _right, direction)
	if two_handed:
		var shoulder := skeleton.get_bone_global_pose(_left[0]).origin
		var reach := (to_local * grip_point - shoulder).normalized()
		_point_chain(skeleton, _left, reach)


## Rotates each segment of `chain` (upper arm, forearm) so it points along
## `direction` (skeleton space), keeping each bone's origin.
func _point_chain(skeleton: Skeleton3D, chain: PackedInt32Array, direction: Vector3) -> void:
	for i in 2:
		var pose := skeleton.get_bone_global_pose(chain[i])
		var child := skeleton.get_bone_global_pose(chain[i + 1]).origin
		var current := (child - pose.origin).normalized()
		if current.is_zero_approx() or direction.is_zero_approx() or current.dot(direction) > 0.9999:
			continue
		var turn := Quaternion(current, direction)
		pose.basis = Basis(turn) * pose.basis
		skeleton.set_bone_global_pose(chain[i], pose)
