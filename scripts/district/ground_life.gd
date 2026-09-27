class_name GroundLife
extends Node3D
## Nature coming back as the district heals: grass tufts and wildflowers
## scattered over the neighborhood's open ground (not roads, sidewalks, or
## buildings), revealed in random order as DistrictState.restoration() rises.
## Two MultiMeshes (one draw call each) with a wind-sway shader. Also cracks
## and oil stains decaled on the roads, which stay.

const DECALS := "res://assets/decals/"
const FLOWER_COLORS: Array[Color] = [Color(0.95, 0.25, 0.3), Color(1.0, 0.85, 0.25), Color(0.7, 0.4, 0.95),
	Color(1.0, 1.0, 0.95), Color(1.0, 0.55, 0.2)]

@export var tufts := 10000
@export var flowers := 1800
## Grass starts at this restoration and is fully grown by `full_at`.
@export var grass_from := 0.25
@export var full_at := 0.85

var _grass: MultiMeshInstance3D
var _blooms: MultiMeshInstance3D
var _update_left := 0.0
var _shown := -1.0
var _rng := RandomNumberGenerator.new()


## Scatters everything over `hood`'s open ground. Call once after it's built.
func setup(hood: NeighborhoodBuilder) -> void:
	_rng.seed = 4242
	var open := _open_spots(hood, tufts + flowers)
	_grass = _scatter(_tuft_mesh(), open.slice(0, tufts), false)
	_blooms = _scatter(_flower_mesh(), open.slice(tufts), true)
	_decal_roads(hood)
	_apply(0.0)


func grass_shown() -> int:
	return _grass.multimesh.visible_instance_count if _grass else 0


func _process(delta: float) -> void:
	_update_left -= delta
	if _update_left > 0.0 or Game.district == null:
		return
	_update_left = 0.5
	_apply(Game.district.restoration())


func _apply(restoration: float) -> void:
	var grown := clampf((restoration - grass_from) / (full_at - grass_from), 0.0, 1.0)
	if absf(grown - _shown) < 0.01:
		return
	_shown = grown
	if _grass:
		_grass.multimesh.visible_instance_count = int(tufts * grown)
	if _blooms:
		# Flowers follow the grass, a little later.
		_blooms.multimesh.visible_instance_count = int(flowers * clampf(grown * 1.4 - 0.4, 0.0, 1.0))


## Random points on open ground: inside the neighborhood, off the roads and
## sidewalks, outside building footprints.
func _open_spots(hood: NeighborhoodBuilder, count: int) -> Array[Vector3]:
	var rooms: Array = hood.footprints()
	var road_half := hood.road_width * 0.5 + 2.2
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < count and tries < count * 8:
		tries += 1
		var p := Vector3(_rng.randf_range(-hood.street_half_length - 14.0, hood.street_half_length + 14.0), 0.0,
			_rng.randf_range(-4.0, hood.main_road_end_z + 4.0))
		if absf(p.x) < road_half:
			continue
		if hood.street_z.any(func(z: float) -> bool: return absf(p.z - z) < road_half):
			continue
		var point := Vector2(p.x, p.z)
		if rooms.any(func(entry: Array) -> bool: return (entry[0] as Rect2).grow(1.2).has_point(point)):
			continue
		spots.append(hood.global_transform * p)
	return spots


func _scatter(mesh: Mesh, spots: Array[Vector3], colored: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colored
	multimesh.mesh = mesh
	multimesh.instance_count = spots.size()
	for i in spots.size():
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.35))
		multimesh.set_instance_transform(i, Transform3D(basis, to_local(spots[i])))
		if colored:
			multimesh.set_instance_color(i, FLOWER_COLORS[_rng.randi() % FLOWER_COLORS.size()])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.material_override = _sway_material(colored)
	add_child(node)
	return node


## A clump of five blades; UV.y runs 0 at the root to 1 at the tip.
func _tuft_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var angle := k * TAU / 5.0 + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := out.cross(Vector3.UP) * 0.035
		var base := out * 0.05
		var tip := out * 0.16 + Vector3.UP * _rng.randf_range(0.28, 0.42)
		for point in [[base - side, 0.0], [base + side, 0.0], [tip, 1.0]]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(0.5, point[1]))
			tool.add_vertex(point[0])
	return tool.commit()


## A stem and two crossed petal cards; the petals take the instance color.
func _flower_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := [[Vector3(-0.012, 0.0, 0.0), 0.0], [Vector3(0.012, 0.0, 0.0), 0.0], [Vector3(0.0, 0.3, 0.0), 0.5]]
	for point in stem:
		tool.set_normal(Vector3.FORWARD)
		tool.set_uv(Vector2(0.0, point[1]))
		tool.add_vertex(point[0])
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		var a: Vector3 = axis * 0.07
		var top := Vector3.UP * 0.3
		for tri in [[top - a, top + a, top + a + Vector3.UP * 0.1], [top - a, top + a + Vector3.UP * 0.1, top - a + Vector3.UP * 0.1]]:
			for point: Vector3 in tri:
				tool.set_normal(Vector3.UP)
				tool.set_uv(Vector2(1.0, 1.0))
				tool.add_vertex(point)
	return tool.commit()


func _sway_material(colored: bool) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 root_color : source_color = vec4(0.16, 0.32, 0.1, 1.0);
uniform vec4 tip_color : source_color = vec4(0.46, 0.72, 0.26, 1.0);
uniform bool petals = false;
varying vec4 tint;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = UV.y * UV.y;
	VERTEX.x += sin(TIME * 1.6 + world.x * 0.35 + world.z * 0.2) * 0.07 * bend;
	VERTEX.z += cos(TIME * 1.3 + world.z * 0.3) * 0.04 * bend;
	tint = COLOR;
}
void fragment() {
	vec3 grass = mix(root_color.rgb, tip_color.rgb, clamp(UV.y, 0.0, 1.0));
	ALBEDO = (petals && UV.x > 0.5) ? tint.rgb : grass;
	ROUGHNESS = 0.9;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"petals", colored)
	return material


## Cracks and oil stains on the roads (projected decals, permanent).
func _decal_roads(hood: NeighborhoodBuilder) -> void:
	var textures: Array[Texture2D] = []
	for name: String in ["crack_0", "crack_1", "crack_2", "oil_0", "oil_1"]:
		var path := DECALS + name + ".png"
		if ResourceLoader.exists(path):
			textures.append(load(path))
	if textures.is_empty():
		return
	for i in 70:
		var on_main := _rng.randf() < 0.45
		var p := Vector3.ZERO
		if on_main:
			p = Vector3(_rng.randf_range(-3.2, 3.2), 0.0, _rng.randf_range(-4.0, hood.main_road_end_z))
		else:
			p = Vector3(_rng.randf_range(-hood.street_half_length, hood.street_half_length), 0.0,
				hood.street_z[_rng.randi() % hood.street_z.size()] + _rng.randf_range(-3.2, 3.2))
		var decal := Decal.new()
		var oily := _rng.randf() < 0.35
		decal.texture_albedo = textures[(3 + _rng.randi() % 2) if oily else (_rng.randi() % 3)]
		var size := _rng.randf_range(1.6, 3.2) if not oily else _rng.randf_range(1.2, 2.2)
		decal.size = Vector3(size, 0.6, size)
		decal.cull_mask = 1
		decal.upper_fade = 0.2
		decal.lower_fade = 0.2
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 60.0
		decal.distance_fade_length = 15.0
		add_child(decal)
		decal.global_position = hood.global_transform * p
		decal.rotation.y = _rng.randf() * TAU
