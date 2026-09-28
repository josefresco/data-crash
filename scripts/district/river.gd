class_name River
extends Node3D
## A district's river running along X (NeighborhoodBuilder builds the bed,
## banks, bridges, and dressing; this node owns the water). The water widens
## and rises with the district's water table: a trickle down the middle of
## the mud at 10%, nearly bank-full at 100%. The surface is
## shaders/river_water.gdshader (ripples, bank foam, a brown murk that
## clears with the smog); the bed (`bed_material`, shaders/riverbed) goes
## from dry cracked clay to wet mud as the water comes back. Bridges leave
## gaps in the water (`gaps`, x ranges) so the surface never covers a deck.

const WATER_SHADER := preload("res://shaders/river_water.gdshader")

## Riverbed width (z) and length (x), set before add_child.
var width := 18.0
var length := 400.0
## X ranges [from, to] under bridges: no water surface there.
var gaps: Array[Vector2] = []
## The bed's ShaderMaterial (its `wet` follows the water level).
var bed_material: ShaderMaterial

var _segments: Array[MeshInstance3D] = []
var _material: ShaderMaterial
var _level := -1.0
var _tick := 0.0


func _ready() -> void:
	add_to_group("rivers")
	_material = ShaderMaterial.new()
	_material.shader = WATER_SHADER
	_material.set_shader_parameter(&"ripple_a", _ripples(3))
	_material.set_shader_parameter(&"ripple_b", _ripples(17))
	var cuts: Array[Vector2] = gaps.duplicate()
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var start := -length * 0.5
	for cut in cuts + [Vector2(length * 0.5, length * 0.5)]:
		if cut.x > start + 0.5:
			_add_segment(start, cut.x)
		start = maxf(start, cut.y)
	set_level(Game.district.water_table if Game.district else 0.1)
	_update_murk()


## A seamless ripple normal map from noise.
static func _ripples(seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.as_normal_map = true
	texture.bump_strength = 6.0
	texture.noise = noise
	return texture


func _add_segment(from_x: float, to_x: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(to_x - from_x, 1.0)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = _material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position.x = (from_x + to_x) * 0.5
	add_child(water)
	_segments.append(water)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var target := Game.district.water_table if Game.district else 0.1
	if not is_equal_approx(_level, target):
		set_level(move_toward(_level, target, 0.25 * 0.08))
	_update_murk()


## Brown and polluted under heavy smog, clearing as the air does.
func _update_murk() -> void:
	var smog := Game.district.smog if Game.district else 1.0
	_material.set_shader_parameter(&"murk", clampf((smog - 0.2) / 0.8, 0.0, 1.0) * 0.75)


## Water level 0..1 (the district's water table).
func set_level(value: float) -> void:
	_level = clampf(value, 0.0, 1.0)
	for water in _segments:
		water.scale.z = water_width()
		water.position.y = lerpf(0.02, 0.1, _level)
	if bed_material:
		bed_material.set_shader_parameter(&"wet", wetness())


## Width of the water surface right now (tests read it).
func water_width() -> float:
	return width * lerpf(0.2, 0.92, _level)


## How wet the bed looks (0 dry cracked clay, 1 soaked mud).
func wetness() -> float:
	return smoothstep(0.15, 0.7, _level)
