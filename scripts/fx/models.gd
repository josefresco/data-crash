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
## Shared cached material per color and surface kind (see surface()).
static func mat(color: Color, kind: StringName = &"rough") -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), kind]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		surface(material, kind)
		_materials[key] = material
	return _materials[key]


static func glass(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.3
	material.roughness = 0.1
	return material


## Shared emissive material: lamps, signage, indicator lights.
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "glow/%s/%.2f" % [color.to_html(), energy]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return _materials[key]


## Side-profile extrusion: `profile` is a closed polygon of (z, y) points
## (y up, -Z forward), extruded `width` meters along X and centered on x = 0.
## Flat-shaded, for angular shapes like the Felsa Cyberdouche.
static func extrude(parent: Node3D, profile: PackedVector2Array, width: float, material: Material,
		at := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = extrude_mesh(profile, width)
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


## The mesh `extrude()` builds, without a node.
static func extrude_mesh(profile: PackedVector2Array, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width * 0.5
	var count := profile.size()
	# Signed area > 0: counter-clockwise with z right and y up.
	var area := 0.0
	for i in count:
		var a := profile[i]
		var b := profile[(i + 1) % count]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	var tris := Geometry2D.triangulate_polygon(profile)
	for side in [-half, half]:
		for i in range(0, tris.size(), 3):
			var face := PackedVector3Array()
			for k in 3:
				var p := profile[tris[i + k]]
				face.append(Vector3(side, p.y, p.x))
			_add_face(tool, face, Vector3(signf(side), 0.0, 0.0))
	for i in count:
		var a := profile[i]
		var b := profile[(i + 1) % count]
		var d := b - a
		var out := Vector3(0.0, -d.x, d.y) * (1.0 if ccw else -1.0)
		_add_face(tool, PackedVector3Array([Vector3(-half, a.y, a.x), Vector3(half, a.y, a.x), Vector3(half, b.y, b.x)]), out)
		_add_face(tool, PackedVector3Array([Vector3(-half, a.y, a.x), Vector3(half, b.y, b.x), Vector3(-half, b.y, b.x)]), out)
	return tool.commit()


## Low-poly headwear sized for the Kenney character head (about 0.6 m wide at
## body height 1.8). `top` is the top of the head relative to `parent` (the
## head anchor); `scale` follows the character's height. -Z is the face.
## Kinds: cap (baseball cap), police (peaked cap), hardhat, helmet (tactical,
## with a glowing visor in `accent`).
static func hat(parent: Node3D, kind: StringName, color: Color, top: float, scale := 1.0,
		accent := Color(0.4, 0.8, 1.0)) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.0, top, 0.02)
	root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var cloth := mat(color, &"cloth")
	var shell := mat(color, &"paint")
	match kind:
		&"cap":
			_dome(root, 0.33, 0.2, Vector3(0.0, -0.1, 0.0), cloth)
			var brim := _disc(root, 0.3, 0.025, Vector3(0.0, -0.1, -0.2), cloth)
			brim.scale = Vector3(0.95, 1.0, 0.75)
			brim.rotation.x = deg_to_rad(-8.0)
			cylinder(root, 0.035, 0.03, Vector3(0.0, 0.1, 0.0), cloth, 8)  # button
		&"police":
			var crown := CylinderMesh.new()
			crown.top_radius = 0.37
			crown.bottom_radius = 0.31
			crown.height = 0.2
			crown.radial_segments = 16
			var node := MeshInstance3D.new()
			node.mesh = crown
			node.material_override = cloth
			node.position = Vector3(0.0, 0.0, 0.0)
			node.scale = Vector3(1.0, 1.0, 1.05)
			root.add_child(node)
			cylinder(root, 0.318, 0.06, Vector3(0.0, -0.07, 0.0), mat(Color(0.05, 0.05, 0.06), &"cloth"), 16)  # band
			var peak := _disc(root, 0.26, 0.022, Vector3(0.0, -0.1, -0.24), mat(Color(0.04, 0.04, 0.05), &"paint"))
			peak.scale = Vector3(1.0, 1.0, 0.55)
			peak.rotation.x = deg_to_rad(-14.0)
			box(root, Vector3(0.1, 0.08, 0.02), Vector3(0.0, 0.0, -0.33), mat(Color(0.95, 0.8, 0.3), &"metal"))  # badge
		&"hardhat":
			_dome(root, 0.34, 0.24, Vector3(0.0, -0.1, 0.0), shell)
			_disc(root, 0.4, 0.025, Vector3(0.0, -0.1, -0.03), shell).scale = Vector3(1.0, 1.0, 1.1)
			var ridge := box(root, Vector3(0.08, 0.05, 0.56), Vector3(0.0, 0.12, 0.0), shell)
			ridge.scale = Vector3(1.0, 1.0, 1.0)
		&"helmet":
			var dome := _dome(root, 0.38, 0.3, Vector3(0.0, -0.14, 0.02), mat(color, &"paint"))
			dome.scale.z = 1.05
			# Ear guards down the sides and a visor strip across the eyes.
			for x in [-1.0, 1.0]:
				box(root, Vector3(0.06, 0.2, 0.4), Vector3(x * 0.34, -0.22, 0.04), shell)
			var visor := box(root, Vector3(0.6, 0.1, 0.04), Vector3(0.0, -0.22, -0.34), glow(accent, 2.5))
			visor.rotation.x = deg_to_rad(8.0)
		&"toque":
			# Knit winter hat: a rounded crown, a rolled cuff, and a pom-pom.
			_dome(root, 0.34, 0.3, Vector3(0.0, -0.12, 0.0), cloth)
			cylinder(root, 0.345, 0.12, Vector3(0.0, -0.1, 0.0), mat(accent, &"cloth"), 16)
			ball(root, 0.1, Vector3(0.0, 0.2, 0.0), mat(Color(0.95, 0.95, 0.92), &"cloth"))
		&"headband":
			cylinder(root, 0.33, 0.07, Vector3(0.0, -0.2, 0.0), cloth, 16)
		&"campaign":
			# Mountie's felt hat: a wide flat brim and a pinched crown.
			_disc(root, 0.55, 0.03, Vector3(0.0, -0.1, 0.0), cloth)
			var crown := cylinder(root, 0.28, 0.26, Vector3(0.0, 0.03, 0.0), cloth, 4)
			crown.rotation.y = PI * 0.25
			cylinder(root, 0.3, 0.05, Vector3(0.0, -0.07, 0.0), mat(Color(0.35, 0.2, 0.1), &"cloth"), 16)
	return root


## Flattened hemisphere (hat crowns): radius across, `height` tall, base at `at`.
static func _dome(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius
	mesh.is_hemisphere = true
	mesh.radial_segments = 16
	mesh.rings = 5
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.scale = Vector3(1.0, height / radius, 1.0)
	parent.add_child(node)
	return node


static func _disc(parent: Node3D, radius: float, thickness: float, at: Vector3, material: Material) -> MeshInstance3D:
	return cylinder(parent, radius, thickness, at, material, 18)


## Adds a flat triangle facing `outward` (Godot front faces wind clockwise).
static func _add_face(tool: SurfaceTool, face: PackedVector3Array, outward: Vector3) -> void:
	var cross := (face[1] - face[0]).cross(face[2] - face[0])
	if cross.dot(outward) > 0.0:
		face = PackedVector3Array([face[0], face[2], face[1]])
	var normal := outward.normalized()
	for v in face:
		tool.set_normal(normal)
		tool.set_uv(Vector2(v.z + v.x, v.y) * 0.5)
		tool.add_vertex(v)


## Glossy dark window pane: reflects the sky with screen-space reflections.
static func window() -> StandardMaterial3D:
	return mat(Color(0.32, 0.42, 0.52), &"window")


## Gives a flat-color material surface detail: procedural grain (albedo) and
## bumps (normal map), plus roughness/metallic per kind. Textures are grayscale
## so albedo_color still sets the color (and can be tinted at runtime).
## Kinds: rough (walls, props), asphalt, grass, metal, paint (cars), cloth
## (clothes, fur, gear), skin, window. Mapping is object-space triplanar, so
## grain never swims across moving units.
static func surface(material: StandardMaterial3D, kind: StringName) -> void:
	material.uv1_triplanar = true
	material.uv1_world_triplanar = false
	material.normal_enabled = true
	if PBR_KINDS.has(kind):
		_pbr(material, kind)
		return
	match kind:
		&"grass":
			material.albedo_texture = _grain(&"grass", 0.012, Color(0.68, 0.7, 0.62))
			material.normal_texture = _bumps(&"grass_n", 0.2, 2.0)
			material.uv1_scale = Vector3.ONE * 0.08
			material.roughness = 1.0
		&"metal":
			material.albedo_texture = _grain(&"grain", 0.03, Color(0.85, 0.85, 0.85))
			material.normal_texture = _bumps(&"grain_n", 0.06, 1.0)
			material.uv1_scale = Vector3.ONE * 0.5
			material.metallic = 0.6
			material.roughness = 0.45
		&"paint":
			material.normal_enabled = false
			material.metallic = 0.35
			material.roughness = 0.28
		&"cloth":
			material.albedo_texture = _grain(&"cloth", 0.08, Color(0.82, 0.82, 0.82))
			material.normal_texture = _bumps(&"cloth_n", 0.2, 1.5)
			material.uv1_scale = Vector3.ONE * 2.0
			material.roughness = 0.95
		&"skin":
			material.normal_enabled = false
			material.roughness = 0.65
		&"window":
			material.normal_enabled = false
			material.metallic = 0.25
			material.roughness = 0.08
			material.metallic_specular = 0.8
		_:  # rough
			material.albedo_texture = _grain(&"grain_soft", 0.02, Color(0.9, 0.9, 0.9))
			material.normal_texture = _bumps(&"grain_soft_n", 0.04, 0.7)
			material.uv1_scale = Vector3.ONE * 0.25
			material.roughness = 0.88


static var _scenes := {}
static var _retextured := {}


## Instances an imported model (glb/fbx) scaled by `scale`. Scenes are cached.
static func model(path: String, scale := 1.0) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var node := (_scenes[path] as PackedScene).instantiate() as Node3D
	node.scale = Vector3.ONE * scale
	return node


## Merged mesh bounds of `root` in `root`'s parent space (includes its scale).
static func model_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xform := root.transform
		var node: Node = mesh
		var chain := Transform3D()
		while node != root:
			chain = (node as Node3D).transform * chain
			node = node.get_parent()
		var bounds := (xform * chain) * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


## Swaps the albedo texture on every mesh (palette variants). Materials are
## cached per (source material, texture) so identical swaps share one.
static func retexture(root: Node, texture: Texture2D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for surface_index in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface_index) as StandardMaterial3D
			if source == null:
				continue
			var key := "%d/%s" % [source.get_instance_id(), texture.resource_path]
			if not _retextured.has(key):
				var copy := source.duplicate() as StandardMaterial3D
				copy.albedo_texture = texture
				_retextured[key] = copy
			mesh.set_surface_override_material(surface_index, _retextured[key])


const PBR_DIR := "res://assets/ambientcg/"
## Photo-scanned CC0 texture sets (tools/import_textures.py):
## kind -> [folder, meters covered by one texture tile, metallic].
const PBR_KINDS := {
	&"asphalt": ["Asphalt031", 4.0, 0.0],
	&"concrete": ["Concrete034", 3.0, 0.0],
	&"dirt": ["Ground054", 4.0, 0.0],
	&"corrugated": ["CorrugatedSteel005", 2.5, 0.5],
	&"plates": ["MetalPlates006", 2.0, 0.6],
	&"solar": ["SolarPanel003", 1.6, 0.3],
	&"chainlink": ["Fence006", 3.5, 0.6],
	&"brick": ["Bricks090", 2.2, 0.0],
	&"wood": ["Planks021", 2.0, 0.0],
	&"gravel": ["Gravel022", 2.5, 0.0],
	&"rust": ["Rust004", 2.0, 0.35],
}


## Real texture sets: albedo (tinted by albedo_color), normal, roughness.
static func _pbr(material: StandardMaterial3D, kind: StringName) -> void:
	var spec: Array = PBR_KINDS[kind]
	var folder := PBR_DIR + String(spec[0]) + "/"
	var color_path := folder + "color.png"
	if not ResourceLoader.exists(color_path):
		color_path = folder + "color.jpg"
	material.albedo_texture = load(color_path)
	material.normal_texture = load(folder + "normal.jpg")
	material.roughness_texture = load(folder + "roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness = 1.0
	material.metallic = spec[2]
	material.uv1_scale = Vector3.ONE / float(spec[1])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if kind == &"chainlink":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.3
		# Keeps thin wires visible at a distance instead of mipping away.
		material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Sets how a subtree takes part in global illumination. Moving things must be
## DYNAMIC (or DISABLED for short-lived FX) so SDFGI doesn't voxelize them.
static func set_gi_mode(node: Node, mode: GeometryInstance3D.GIMode) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).gi_mode = mode
	for child in node.get_children():
		set_gi_mode(child, mode)


static var _textures := {}


## Seamless grayscale grain: `dark` at the low end, white at the high end.
static func _grain(key: StringName, frequency: float, dark: Color) -> NoiseTexture2D:
	if not _textures.has(key):
		var ramp := Gradient.new()
		ramp.set_color(0, dark)
		ramp.set_color(1, Color.WHITE)
		var texture := _noise(frequency)
		texture.color_ramp = ramp
		_textures[key] = texture
	return _textures[key]


static func _bumps(key: StringName, frequency: float, strength: float) -> NoiseTexture2D:
	if not _textures.has(key):
		var texture := _noise(frequency)
		texture.as_normal_map = true
		texture.bump_strength = strength
		_textures[key] = texture
	return _textures[key]


static func _noise(frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture


## Draw-call budget: small detail parts stop drawing at a distance where
## they'd be a few pixels (the level has thousands of them).
const SMALL_PART := 0.6
const MEDIUM_PART := 2.0
const SMALL_RANGE := 60.0
const MEDIUM_RANGE := 130.0


static func cull_small(node: GeometryInstance3D, extent: float) -> void:
	if extent < SMALL_PART:
		node.visibility_range_end = SMALL_RANGE
	elif extent < MEDIUM_PART:
		node.visibility_range_end = MEDIUM_RANGE
	node.visibility_range_end_margin = 4.0


## Draw-call batching: bakes the static decoration meshes under `root` into
## one MeshInstance3D per shadow setting, with one surface per material
## (a rack run's 40 dividers and LEDs become 4 surfaces). Skips `keep` nodes
## and their subtrees (animated fans, blinking lights), scripted nodes, and
## `skip` meshes (a Destructible's own box). Emptied leaf nodes are freed.
## Returns how many meshes were merged. Call after decorating, at runtime.
static func merge_static(root: Node3D, keep: Array = [], skip: Array = []) -> int:
	var groups := {}  # [material, casts shadows] -> Array of [mesh, transform]
	var merged: Array[MeshInstance3D] = []
	for child in root.get_children():
		_collect_static(child as Node3D, Transform3D.IDENTITY, keep, skip, groups, merged)
	if merged.size() < 2:
		return 0
	for shadows in [true, false]:
		var mesh := ArrayMesh.new()
		for key: Array in groups:
			if key[1] != shadows:
				continue
			var tool := SurfaceTool.new()
			for entry: Array in groups[key]:
				tool.append_from(entry[0] as Mesh, entry[1], entry[2])
			tool.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, key[0])
		if mesh.get_surface_count() == 0:
			continue
		var node := MeshInstance3D.new()
		node.name = "MergedDetail"
		node.set_meta(&"generated", true)  # builders that rebuild clear it
		node.mesh = mesh
		if not shadows:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
	for part in merged:
		part.mesh = null
	for part in merged:
		if part.get_child_count() == 0:
			part.queue_free()
	return merged.size()


static func _collect_static(node: Node3D, parent_xform: Transform3D, keep: Array, skip: Array,
		groups: Dictionary, merged: Array[MeshInstance3D]) -> void:
	if node == null or node in keep or node.get_script() != null or not node.visible 			or node.is_in_group(&"smog_beams"):
		return  # light cones fade and hide with the smog on their own
	var xform := parent_xform * node.transform
	if node.get_class() == "Node3D":
		# Plain grouping nodes (imported model roots): look inside, keep the node.
		for child in node.get_children():
			_collect_static(child as Node3D, xform, keep, skip, groups, merged)
		return
	if not (node is MeshInstance3D):
		return  # lights, labels, bodies, particles stay as they are
	var part := node as MeshInstance3D
	if part.mesh and not part in skip and (part.mesh is PrimitiveMesh or part.mesh is ArrayMesh):
		var shadows := part.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in part.mesh.get_surface_count():
			var key := [part.get_active_material(s), shadows]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([part.mesh, s, xform])
		merged.append(part)
	for child in part.get_children():
		_collect_static(child as Node3D, xform, keep, skip, groups, merged)


## Makes a prop solid: an invisible static box (world layer, so people,
## cars, and bullets stop at it, and the navmesh bakes around it). `at` is
## the box center in `parent` space.
static func collider(parent: Node3D, size: Vector3, at: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # Game.LAYER_WORLD (this @tool script can't use the autoload)
	body.collision_mask = 0
	body.position = at
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	parent.add_child(body)
	return body


## Sizes a sign's Label3D so its text (all lines) fits inside `box` meters
## (width, height) with a margin, measured with the label's own font. Signs
## read from the front only.
static func fit_label(label: Label3D, box: Vector2, fill := 0.84) -> void:
	var font := label.font if label.font else ThemeDB.fallback_font
	var extent := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size)
	extent += Vector2.ONE * label.outline_size * 2.0
	if extent.x <= 0.0 or extent.y <= 0.0:
		return
	label.pixel_size = minf(box.x * fill / extent.x, box.y * fill / extent.y)
	label.double_sided = false


static func box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	cull_small(node, maxf(size.x, maxf(size.y, size.z)))
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
	cull_small(node, maxf(radius * 2.0, height))
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
	cull_small(node, radius * 2.0)
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
	var pants_mat := mat(pants, &"cloth")
	var skin_mat := mat(skin, &"skin")

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "hip_l" if side < 0.0 else "hip_r"
		hip.position = Vector3(side * torso_w * 0.25, leg_len, 0.0)
		rig.add_child(hip)
		box(hip, Vector3(0.17 * bulk, leg_len, 0.2 * bulk), Vector3(0.0, -leg_len * 0.5, 0.0), pants_mat)
		box(hip, Vector3(0.18 * bulk, 0.1, 0.28), Vector3(0.0, -leg_len + 0.05, -0.04), mat(pants.darkened(0.5), &"cloth"))

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
	var pane := window()
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


## A light that comes on in the smog (EnvironmentDriver scales group
## "smog_lights" by smog: full in thick smog, off in clean air). No shadows,
## a strong volumetric-fog share so it cuts a beam through the haze, and a
## distance fade. `spot_angle` > 0 makes a downward spotlight.
static func smog_light(parent: Node3D, at: Vector3, color: Color, energy: float, reach: float,
		spot_angle := 0.0, fog_energy := 3.0) -> Light3D:
	var light: Light3D
	if spot_angle > 0.0:
		var spot := SpotLight3D.new()
		spot.spot_range = reach
		spot.spot_angle = spot_angle
		spot.spot_attenuation = 0.8
		spot.rotation.x = -PI * 0.5  # straight down
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = reach
		light = omni
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.light_volumetric_fog_energy = fog_energy
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 20.0
	light.set_meta(&"base_energy", energy)
	light.add_to_group(&"smog_lights")
	parent.add_child(light)
	return light


static var _beam_materials := {}


## A soft light shaft (fake volumetric cone) from `at` along `direction`:
## translucent, brightest at the lamp and fading out toward the far end,
## softened where it meets surfaces. Group "smog_beams": EnvironmentDriver
## fades the shared materials with the smog, like the smog lights.
static func light_cone(parent: Node3D, at: Vector3, direction: Vector3, length: float, radius: float,
		color: Color, alpha := 0.16) -> MeshInstance3D:
	var key := "%s/%.2f" % [color.to_html(), alpha]
	if not _beam_materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.proximity_fade_enabled = true
		material.proximity_fade_distance = 1.5
		material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		material.distance_fade_min_distance = 110.0
		material.distance_fade_max_distance = 70.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color(color, 1.0))
		ramp.set_color(1, Color(color, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = ramp
		texture.fill_from = Vector2(0.0, 0.0)
		texture.fill_to = Vector2(0.0, 1.0)  # along the cylinder's V: top (lamp) to bottom
		texture.width = 4
		texture.height = 64
		material.albedo_texture = texture
		material.albedo_color = Color(1, 1, 1, alpha)
		material.set_meta(&"base_alpha", alpha)
		_beam_materials[key] = material
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.08
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _beam_materials[key]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(node)
	# Cylinder axis is +Y (top at +length/2): point -Y along the beam.
	var down := -direction.normalized()
	var side := down.cross(Vector3.RIGHT if absf(down.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
	node.basis = Basis(side, down, side.cross(down)).orthonormalized()
	node.position = at - down * length * 0.5
	node.add_to_group(&"smog_beams")
	return node


static func beam_materials() -> Array:
	return _beam_materials.values()


static func streetlight(height := 5.0) -> Node3D:
	var root := Node3D.new()
	var metal := mat(Color(0.3, 0.32, 0.35), &"metal")
	cylinder(root, 0.08, height, Vector3(0.0, height * 0.5, 0.0), metal, 6)
	collider(root, Vector3(0.3, height, 0.3), Vector3(0.0, height * 0.5, 0.0))
	box(root, Vector3(0.12, 0.12, 1.2), Vector3(0.0, height, -0.55), metal)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.95, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.7)
	lamp.emission_energy_multiplier = 1.5
	box(root, Vector3(0.35, 0.12, 0.5), Vector3(0.0, height - 0.08, -1.05), lamp)
	if not Engine.is_editor_hint():
		# Sodium-orange pool under the lamp, on while the smog is thick.
		smog_light(root, Vector3(0.0, height - 0.2, -1.05), Color(1.0, 0.72, 0.38), 5.0, 14.0, 55.0, 5.0)
		light_cone(root, Vector3(0.0, height - 0.15, -1.05), Vector3.DOWN, height - 0.2, 2.2, Color(1.0, 0.75, 0.45), 0.12)
	return root


## Parked car shell (visual only), facing -Z.
static func parked_car(paint: Color) -> Node3D:
	var root := Node3D.new()
	box(root, Vector3(1.8, 0.7, 4.0), Vector3(0.0, 0.7, 0.0), mat(paint, &"paint"))
	box(root, Vector3(1.6, 0.55, 2.0), Vector3(0.0, 1.32, 0.2), window())
	for x in [-0.9, 0.9]:
		for z in [-1.3, 1.3]:
			var wheel := cylinder(root, 0.36, 0.25, Vector3(x, 0.36, z), mat(Color(0.06, 0.06, 0.06)), 10)
			wheel.rotation.z = PI * 0.5
	return root
