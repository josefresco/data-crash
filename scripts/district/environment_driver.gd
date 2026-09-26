class_name EnvironmentDriver
extends Node
## Owns the level's look: sets up the Environment (AgX tonemapping, glow,
## SSAO/SSIL/SSR, SDFGI bounce light, volumetric fog, clouds) and blends it
## between "polluted" and "restored" from Game.district. Displayed values
## ease toward the real ones, so a destroyed datacenter clears the sky over
## several seconds. The smog itself is volumetric fog: thick, brown, lit by
## sun shafts, thinning to a light haze as the district heals.
##
## [F10] cycles graphics quality (Low / Medium / High), saved to
## user://settings.cfg.

enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_NAMES := ["Low", "Medium", "High"]
const SETTINGS_PATH := "user://settings.cfg"

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var ground: GeometryInstance3D
## Higher = faster visual transition.
@export var blend_speed: float = 0.35
@export var quality := Quality.HIGH

@export_group("Polluted")
@export var polluted_fog_color := Color(0.45, 0.36, 0.25)
@export var polluted_fog_density := 0.035
@export var polluted_volumetric_density := 0.028
@export var polluted_volumetric_albedo := Color(0.62, 0.5, 0.34)
@export var polluted_sky_top := Color(0.38, 0.32, 0.25)
@export var polluted_sky_horizon := Color(0.55, 0.45, 0.32)
@export var polluted_clouds := Color(0.55, 0.45, 0.32, 0.95)
## Multiplies the dry-dirt texture while polluted.
@export var polluted_ground_tint := Color(0.78, 0.68, 0.55)
@export var polluted_sun_color := Color(1.0, 0.72, 0.45)
@export var polluted_sun_energy := 1.25
@export var polluted_saturation := 0.72

@export_group("Restored")
@export var restored_fog_color := Color(0.75, 0.85, 0.95)
@export var restored_fog_density := 0.002
@export var restored_volumetric_density := 0.0025
@export var restored_volumetric_albedo := Color(0.85, 0.9, 1.0)
@export var restored_sky_top := Color(0.22, 0.45, 0.85)
@export var restored_sky_horizon := Color(0.68, 0.8, 0.95)
@export var restored_clouds := Color(1.0, 1.0, 1.0, 0.8)
@export var restored_sun_color := Color(1.0, 0.96, 0.88)
@export var restored_sun_energy := 1.35
@export var restored_saturation := 1.12

var _smog_shown := 1.0
var _restore_shown := 0.0
var _initialized := false
var _notice_left := 0.0


func _ready() -> void:
	add_to_group("environment_drivers")
	quality = _load_quality()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("graphics_quality"):
		set_quality(((quality as int) + 1) % QUALITY_NAMES.size() as Quality)
		_save_quality()
		Game.set_info("notice", "Graphics: %s   [F10] to change" % QUALITY_NAMES[quality])
		_notice_left = 2.5


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			Game.set_info("notice", "")

	var district := Game.district
	if district == null or world_environment == null:
		return

	if not _initialized:
		# First frame with a district: build the look, then snap to it so the
		# level doesn't fade in from defaults.
		_configure()
		set_quality(quality)
		_smog_shown = district.smog
		_restore_shown = district.restoration()
		_initialized = true
	else:
		var weight := 1.0 - exp(-blend_speed * delta)
		_smog_shown = lerpf(_smog_shown, district.smog, weight)
		_restore_shown = lerpf(_restore_shown, district.restoration(), weight)

	_apply()


## Switches the expensive features on or off. Safe to call any time.
func set_quality(value: Quality) -> void:
	quality = value
	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	var high := quality == Quality.HIGH
	var medium_up := quality >= Quality.MEDIUM
	env.sdfgi_enabled = high
	env.ssil_enabled = high
	env.ssr_enabled = high
	env.ssao_enabled = medium_up
	env.volumetric_fog_enabled = medium_up
	env.glow_enabled = true

	var viewport := get_viewport()
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == Quality.LOW \
		else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = medium_up

	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	if sun:
		sun.directional_shadow_max_distance = [60.0, 110.0, 160.0][quality]
	if _initialized:
		_apply()


## One-time Environment setup: everything that doesn't change with smog.
func _configure() -> void:
	var env := world_environment.environment
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.ssao_radius = 1.2
	env.ssao_intensity = 1.8
	env.ssao_power = 1.5
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8

	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3

	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2

	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_temporal_reprojection_enabled = true

	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06

	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_mat.sky_cover = _cloud_texture()
		sky_mat.sky_curve = 0.12
		sky_mat.sun_angle_max = 20.0
		sky_mat.ground_bottom_color = Color(0.22, 0.2, 0.17)

	if sun:
		sun.shadow_enabled = true
		sun.light_angular_distance = 1.2  # soft penumbras
		sun.directional_shadow_blend_splits = true
		sun.shadow_blur = 1.5
		sun.light_volumetric_fog_energy = 1.6  # sun shafts through the smog

	if ground:
		ground.material_override = _ground_material()


func _apply() -> void:
	var env := world_environment.environment
	if env == null:
		return
	var smog := _smog_shown

	# Volumetric fog carries the smog when available; the cheap exponential
	# fog does the job alone on Low.
	env.fog_enabled = true
	env.fog_light_color = restored_fog_color.lerp(polluted_fog_color, smog)
	var exp_density := lerpf(restored_fog_density, polluted_fog_density, smog)
	env.fog_density = exp_density * (0.25 if env.volumetric_fog_enabled else 1.0)
	env.fog_sun_scatter = lerpf(0.1, 0.5, smog)
	env.fog_sky_affect = lerpf(0.4, 1.0, smog)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = lerpf(restored_volumetric_density, polluted_volumetric_density, smog)
		env.volumetric_fog_albedo = restored_volumetric_albedo.lerp(polluted_volumetric_albedo, smog)
		# A little self-glow keeps thick smog murky-bright instead of black.
		env.volumetric_fog_emission = Color(0.1, 0.075, 0.045) * smog
		env.volumetric_fog_anisotropy = lerpf(0.3, 0.65, smog)
		env.volumetric_fog_sky_affect = lerpf(0.3, 0.9, smog)

	env.adjustment_saturation = lerpf(restored_saturation, polluted_saturation, smog)

	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_mat.sky_top_color = restored_sky_top.lerp(polluted_sky_top, smog)
		sky_mat.sky_horizon_color = restored_sky_horizon.lerp(polluted_sky_horizon, smog)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
		sky_mat.sky_cover_modulate = restored_clouds.lerp(polluted_clouds, smog)

	if sun:
		sun.light_color = restored_sun_color.lerp(polluted_sun_color, smog)
		sun.light_energy = lerpf(polluted_sun_energy, restored_sun_energy, 1.0 - smog)

	if ground and ground.material_override is ShaderMaterial:
		var ground_mat := ground.material_override as ShaderMaterial
		ground_mat.set_shader_parameter(&"restoration", _restore_shown)
		ground_mat.set_shader_parameter(&"dead_tint", polluted_ground_tint.lerp(Color.WHITE, _restore_shown))


## Ground that regrows: dry dirt blends to lawn through a noise mask as the
## district heals (shaders/ground.gdshader, ambientCG textures).
func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/ground.gdshader")
	for pair in [["dead", "Ground037"], ["green", "Grass004"]]:
		var folder := "res://assets/ambientcg/%s/" % pair[1]
		material.set_shader_parameter(pair[0] + "_albedo", load(folder + "color.jpg"))
		material.set_shader_parameter(pair[0] + "_normal", load(folder + "normal.jpg"))
		material.set_shader_parameter(pair[0] + "_roughness", load(folder + "roughness.jpg"))
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.006
	noise.fractal_octaves = 3
	var mask := NoiseTexture2D.new()
	mask.width = 512
	mask.height = 512
	mask.seamless = true
	mask.normalize = true
	mask.noise = noise
	material.set_shader_parameter(&"mask_noise", mask)
	return material


## Seamless noise panorama for ProceduralSkyMaterial.sky_cover: mostly clear
## with soft cloud banks.
func _cloud_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.004
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.45)
	ramp.set_color(0, Color.BLACK)
	ramp.set_offset(1, 0.8)
	ramp.set_color(1, Color.WHITE)
	var texture := NoiseTexture2D.new()
	texture.width = 2048
	texture.height = 1024
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	return texture


func _load_quality() -> Quality:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return quality
	return clampi(int(config.get_value("graphics", "quality", quality)), 0, QUALITY_NAMES.size() - 1) as Quality


func _save_quality() -> void:
	save_quality(quality as int)


## Saved quality index (High when nothing is saved). Used by the settings menu.
static func saved_quality() -> int:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return Quality.HIGH
	return clampi(int(config.get_value("graphics", "quality", Quality.HIGH)), 0, QUALITY_NAMES.size() - 1)


static func save_quality(index: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep any other sections; a missing file is fine
	config.set_value("graphics", "quality", index)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Couldn't save graphics settings (error %d)" % err)
