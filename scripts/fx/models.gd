@tool
class_name Models
extends RefCounted
## Low-poly procedural models (people, dogs, houses, trees, props) built from
## primitive meshes. Rigs expose named pivot nodes so code can animate them.
## Static only; never instantiated.

static var _materials := {}

const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.8, 0.69), Color(0.87, 0.67, 0.52), Color(0.72, 0.52, 0.38),
	Color(0.55, 0.37, 0.26), Color(0.4, 0.27, 0.19),
]


static func random_skin() -> Color:
	return SKIN_TONES.pick_random()


## Shared opaque material per color (cheap: meshes batch well).
static func mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_materials[key] = material
	return _materials[key]


static func glass(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.3
	material.roughness = 0.1
	return material


static func box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material,
		segments := 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


static func ball(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


static func cone(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


## Person facing -Z, feet at y = 0. `shirt` is used as-is (pass a unique
## material if you want to tint or flash it). Pivots: hip_l/hip_r,
## shoulder_l/shoulder_r, head.
static func humanoid(shirt: Material, pants: Color, skin: Color, height := 1.8, bulk := 1.0) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Rig"
	var leg_len := height * 0.47
	var torso_h := height * 0.33
	var head_r := height * 0.075
	var torso_w := 0.42 * bulk
	var pants_mat := mat(pants)
	var skin_mat := mat(skin)

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "hip_l" if side < 0.0 else "hip_r"
		hip.position = Vector3(side * torso_w * 0.25, leg_len, 0.0)
		rig.add_child(hip)
		box(hip, Vector3(0.17 * bulk, leg_len, 0.2 * bulk), Vector3(0.0, -leg_len * 0.5, 0.0), pants_mat)
		box(hip, Vector3(0.18 * bulk, 0.1, 0.28), Vector3(0.0, -leg_len + 0.05, -0.04), mat(pants.darkened(0.5)))

	box(rig, Vector3(torso_w, torso_h, 0.25 * bulk), Vector3(0.0, leg_len + torso_h * 0.5, 0.0), shirt)

	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.name = "shoulder_l" if side < 0.0 else "shoulder_r"
		shoulder.position = Vector3(side * (torso_w * 0.5 + 0.07 * bulk), leg_len + torso_h - 0.04, 0.0)
		rig.add_child(shoulder)
		box(shoulder, Vector3(0.12 * bulk, torso_h * 0.95, 0.14 * bulk), Vector3(0.0, -torso_h * 0.45, 0.0), shirt)
		box(shoulder, Vector3(0.11, 0.1, 0.12), Vector3(0.0, -torso_h * 0.95, 0.0), skin_mat)

	var head := Node3D.new()
	head.name = "head"
	head.position = Vector3(0.0, leg_len + torso_h + head_r + 0.03, 0.0)
	rig.add_child(head)
	ball(head, head_r, Vector3.ZERO, skin_mat)
	box(head, Vector3(head_r * 0.35, head_r * 0.35, head_r * 0.5), Vector3(0.0, 0.0, -head_r), skin_mat)  # nose: shows facing
	return rig


## Four-legged dog facing -Z. Pivots: leg_fl/fr/bl/br, tail.
static func dog(fur: Material, height := 0.8) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Rig"
	var leg_len := height * 0.45
	var body_y := leg_len + 0.12
	box(rig, Vector3(0.34, 0.3, 0.78), Vector3(0.0, body_y, 0.0), fur)
	var head := Node3D.new()
	head.name = "head"
	head.position = Vector3(0.0, body_y + 0.18, -0.42)
	rig.add_child(head)
	box(head, Vector3(0.26, 0.24, 0.28), Vector3.ZERO, fur)
	box(head, Vector3(0.16, 0.13, 0.18), Vector3(0.0, -0.04, -0.2), fur)
	box(head, Vector3(0.07, 0.07, 0.04), Vector3(0.0, -0.01, -0.3), mat(Color(0.05, 0.05, 0.05)))
	for side in [-1.0, 1.0]:
		box(head, Vector3(0.07, 0.14, 0.05), Vector3(side * 0.1, 0.16, 0.06), fur)
	for corner in [["leg_fl", -1.0, -1.0], ["leg_fr", 1.0, -1.0], ["leg_bl", -1.0, 1.0], ["leg_br", 1.0, 1.0]]:
		var hip := Node3D.new()
		hip.name = corner[0]
		hip.position = Vector3(corner[1] * 0.12, leg_len + 0.02, corner[2] * 0.3)
		rig.add_child(hip)
		box(hip, Vector3(0.09, leg_len, 0.09), Vector3(0.0, -leg_len * 0.5, 0.0), fur)
	var tail := Node3D.new()
	tail.name = "tail"
	tail.position = Vector3(0.0, body_y + 0.1, 0.38)
	rig.add_child(tail)
	box(tail, Vector3(0.06, 0.06, 0.3), Vector3(0.0, 0.08, 0.13), fur).rotation.x = -0.6
	return rig


## Swings a rig's limbs. `phase` advances with distance walked; `amount` 0..1.
static func animate_walk(rig: Node3D, phase: float, amount: float) -> void:
	if rig == null:
		return
	var swing := sin(phase) * 0.7 * amount
	for pair in [["hip_l", 1.0], ["hip_r", -1.0], ["shoulder_l", -0.8], ["shoulder_r", 0.8],
			["leg_fl", 1.0], ["leg_br", 1.0], ["leg_fr", -1.0], ["leg_bl", -1.0]]:
		var limb := rig.get_node_or_null(NodePath(pair[0])) as Node3D
		if limb:
			limb.rotation.x = swing * pair[1]
	var tail := rig.get_node_or_null(^"tail") as Node3D
	if tail:
		tail.rotation.y = sin(phase * 2.0) * 0.5


## Suburban house facing +Z (door side), origin at ground center. Returns the
## visual root; the caller adds collision (see NeighborhoodBuilder).
static func house(size: Vector3, wall: Color, roof: Color, trim: Color) -> Node3D:
	var root := Node3D.new()
	box(root, size, Vector3(0.0, size.y * 0.5, 0.0), mat(wall))
	# Gable roof: a prism over the long axis, plus eaves.
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x + 0.8, size.y * 0.45, size.z + 0.8)
	var roof_node := MeshInstance3D.new()
	roof_node.mesh = prism
	roof_node.material_override = mat(roof)
	roof_node.position = Vector3(0.0, size.y + size.y * 0.225, 0.0)
	root.add_child(roof_node)
	box(root, Vector3(0.7, 1.4, 0.7), Vector3(size.x * 0.28, size.y + size.y * 0.35, -size.z * 0.15), mat(roof.darkened(0.3)))  # chimney
	# Door, step, and windows on the front (+Z).
	var front := size.z * 0.5 + 0.03
	box(root, Vector3(1.0, 2.1, 0.08), Vector3(0.0, 1.05, front), mat(trim.darkened(0.35)))
	box(root, Vector3(1.8, 0.2, 1.0), Vector3(0.0, 0.1, front + 0.5), mat(Color(0.6, 0.6, 0.58)))
	var pane := mat(Color(0.25, 0.35, 0.45))
	for x in [-size.x * 0.3, size.x * 0.3]:
		box(root, Vector3(1.3, 1.1, 0.08), Vector3(x, size.y * 0.55, front), pane)
		box(root, Vector3(1.5, 0.12, 0.12), Vector3(x, size.y * 0.55 - 0.62, front + 0.04), mat(trim))
	# Side windows.
	for side in [-1.0, 1.0]:
		box(root, Vector3(0.08, 1.0, 1.2), Vector3(side * (size.x * 0.5 + 0.03), size.y * 0.55, 0.0), pane)
	return root


static func tree(height := 5.0, leaves := Color(0.25, 0.45, 0.2)) -> Node3D:
	var root := Node3D.new()
	cylinder(root, 0.18, height * 0.45, Vector3(0.0, height * 0.225, 0.0), mat(Color(0.35, 0.25, 0.15)), 6)
	cone(root, height * 0.3, height * 0.45, Vector3(0.0, height * 0.55, 0.0), mat(leaves))
	cone(root, height * 0.22, height * 0.38, Vector3(0.0, height * 0.8, 0.0), mat(leaves.lightened(0.08)))
	return root


static func streetlight(height := 5.0) -> Node3D:
	var root := Node3D.new()
	var metal := mat(Color(0.3, 0.32, 0.35))
	cylinder(root, 0.08, height, Vector3(0.0, height * 0.5, 0.0), metal, 6)
	box(root, Vector3(0.12, 0.12, 1.2), Vector3(0.0, height, -0.55), metal)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.95, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.7)
	lamp.emission_energy_multiplier = 1.5
	box(root, Vector3(0.35, 0.12, 0.5), Vector3(0.0, height - 0.08, -1.05), lamp)
	return root


## Parked car shell (visual only), facing -Z.
static func parked_car(paint: Color) -> Node3D:
	var root := Node3D.new()
	box(root, Vector3(1.8, 0.7, 4.0), Vector3(0.0, 0.7, 0.0), mat(paint))
	box(root, Vector3(1.6, 0.55, 2.0), Vector3(0.0, 1.32, 0.2), mat(Color(0.15, 0.18, 0.22)))
	for x in [-0.9, 0.9]:
		for z in [-1.3, 1.3]:
			var wheel := cylinder(root, 0.36, 0.25, Vector3(x, 0.36, z), mat(Color(0.06, 0.06, 0.06)), 10)
			wheel.rotation.z = PI * 0.5
	return root
