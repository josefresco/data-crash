class_name Ragdoll
extends Node3D
## Physics death for a CharacterModel. Godot's PhysicalBone3D can't be used
## here: the Kenney skeleton node is scaled ~48x (FBX centimeters) and physics
## bodies don't support scale. Instead this builds unscaled rigid capsules in
## world space (pelvis, torso, head, upper and lower limbs) joined by cone
## twist joints, and each physics frame writes their transforms back onto the
## bones, so gear on bone anchors (hats, weapons) tumbles along.
##
## Bodies live on the debris layer and only collide with the world and
## destructible props (not units or cars, not each other). After `lifetime`
## they freeze, the body sinks into the ground, and `finished` fires.

signal finished

## At most this many simulate at once; callers fall back to a canned death.
const MAX_ACTIVE := 12
## [bone, end bone (sets the capsule length), radius, mass, parent part].
## Parents come before children (bones are written in this order).
const PARTS := [
	["Hips", "Spine", 0.13, 12.0, -1],
	["Spine", "Neck", 0.15, 16.0, 0],
	["Head", "Head_end", 0.14, 5.0, 1],
	["LeftArm", "LeftForeArm", 0.055, 2.5, 1],
	["LeftForeArm", "LeftHand", 0.05, 2.0, 3],
	["RightArm", "RightForeArm", 0.055, 2.5, 1],
	["RightForeArm", "RightHand", 0.05, 2.0, 5],
	["LeftUpLeg", "LeftLeg", 0.08, 6.0, 0],
	["LeftLeg", "LeftFoot", 0.065, 4.0, 7],
	["RightUpLeg", "RightLeg", 0.08, 6.0, 0],
	["RightLeg", "RightFoot", 0.065, 4.0, 9],
]
## Swing / twist limits (degrees) per part's joint to its parent.
const LIMITS := {"Spine": [30.0, 20.0], "Head": [45.0, 30.0], "LeftArm": [80.0, 40.0],
	"RightArm": [80.0, 40.0], "LeftForeArm": [70.0, 10.0], "RightForeArm": [70.0, 10.0],
	"LeftUpLeg": [55.0, 20.0], "RightUpLeg": [55.0, 20.0], "LeftLeg": [65.0, 5.0], "RightLeg": [65.0, 5.0]}
const LAYER_DEBRIS := 64  # Game.LAYER_BODIES: cars pass over bodies
const MASK := 1 | 16  # world + destructibles

static var active := 0

@export var lifetime := 5.0
@export var sink_seconds := 1.6

var _skeleton: Skeleton3D
var _bones: Array[int] = []
var _bodies: Array[RigidBody3D] = []
var _offsets: Array[Transform3D] = []
var _age := 0.0
var _sink := 0.0
var _done := false


## Starts a ragdoll for `model` (already posed by its last animation frame),
## pushed by `impulse` (N*s) applied near world point `at`. Returns null when
## too many are active: the caller should use its canned death instead.
static func start(model: CharacterModel, parent: Node, impulse: Vector3, at: Vector3,
		carry_velocity := Vector3.ZERO) -> Ragdoll:
	if active >= MAX_ACTIVE or model == null or model.skeleton() == null:
		return null
	var ragdoll := Ragdoll.new()
	parent.add_child(ragdoll)
	ragdoll._build(model, impulse, at, carry_velocity)
	return ragdoll


func _build(model: CharacterModel, impulse: Vector3, at: Vector3, carry: Vector3) -> void:
	active += 1
	model.set_animation_active(false)
	_skeleton = model.skeleton()
	var skel_xform := _skeleton.global_transform
	var total_mass := 0.0
	for part: Array in PARTS:
		total_mass += float(part[3])
	var hit_body: RigidBody3D = null
	var hit_distance := INF
	for part: Array in PARTS:
		var bone := _skeleton.find_bone(part[0])
		var end := _skeleton.find_bone(part[1])
		var start_xform := skel_xform * _skeleton.get_bone_global_pose(bone)
		var a := start_xform.origin
		var b := (skel_xform * _skeleton.get_bone_global_pose(end)).origin
		var axis := b - a
		var length := maxf(axis.length(), 0.05)
		var up := axis / length
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up)).orthonormalized()
		var body := RigidBody3D.new()
		body.collision_layer = LAYER_DEBRIS
		body.collision_mask = MASK
		body.mass = part[3]
		body.linear_damp = 0.4
		body.angular_damp = 1.5
		body.continuous_cd = true
		var shape := CapsuleShape3D.new()
		shape.radius = part[2]
		shape.height = length + float(part[2]) * 2.0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		body.global_transform = Transform3D(basis, a + axis * 0.5)
		body.linear_velocity = carry + impulse / total_mass
		_bodies.append(body)
		_bones.append(bone)
		_offsets.append(body.global_transform.affine_inverse() * start_xform)
		var distance := body.global_position.distance_to(at)
		if distance < hit_distance:
			hit_distance = distance
			hit_body = body
		var parent_index: int = part[4]
		if parent_index >= 0:
			_join(_bodies[parent_index], body, a, part[0])
	if hit_body:
		# The hit part takes an extra shove so the body twists away from it.
		hit_body.apply_impulse(impulse * 0.35, at - hit_body.global_position)


func _join(parent: RigidBody3D, child: RigidBody3D, at: Vector3, bone_name: String) -> void:
	var joint := ConeTwistJoint3D.new()
	add_child(joint)
	joint.global_position = at
	# Joint X axis along the child limb.
	var along := child.global_basis.y
	var side := along.cross(Vector3.UP if absf(along.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	joint.global_basis = Basis(along, side, along.cross(side)).orthonormalized()
	var limits: Array = LIMITS.get(bone_name, [45.0, 20.0])
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(limits[0]))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(limits[1]))
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)


func _physics_process(delta: float) -> void:
	if _done or not is_instance_valid(_skeleton):
		return
	_age += delta
	if _age >= lifetime:
		for body in _bodies:
			body.freeze = true
		_sink = minf(_sink + delta / sink_seconds * 0.7, 0.7)
		if _age >= lifetime + sink_seconds:
			_done = true
			finished.emit()
	_write_bones()


func _write_bones() -> void:
	var to_skeleton := _skeleton.global_transform.affine_inverse()
	for i in _bodies.size():
		var world := _bodies[i].global_transform * _offsets[i]
		world.origin.y -= _sink
		_skeleton.set_bone_global_pose(_bones[i], to_skeleton * world)


func _exit_tree() -> void:
	if not _done or _bodies.size() > 0:
		active = maxi(active - 1, 0)
		_bodies.clear()
