class_name EnvironmentDriver
extends Node
## Blends fog, sky, sun, and ground color between "polluted" and "restored"
## based on Game.district. Displayed values ease toward the real ones so a
## destroyed datacenter clears the sky over several seconds, not instantly.

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var ground: GeometryInstance3D
## Higher = faster visual transition.
@export var blend_speed: float = 0.35

@export_group("Polluted")
@export var polluted_fog_color := Color(0.45, 0.36, 0.25)
@export var polluted_fog_density := 0.035
@export var polluted_sky_top := Color(0.38, 0.32, 0.25)
@export var polluted_sky_horizon := Color(0.55, 0.45, 0.32)
@export var polluted_ground := Color(0.32, 0.3, 0.26)
@export var polluted_sun_color := Color(1.0, 0.72, 0.45)
@export var polluted_sun_energy := 0.5

@export_group("Restored")
@export var restored_fog_color := Color(0.75, 0.85, 0.95)
@export var restored_fog_density := 0.002
@export var restored_sky_top := Color(0.25, 0.5, 0.9)
@export var restored_sky_horizon := Color(0.7, 0.82, 0.95)
@export var restored_ground := Color(0.3, 0.62, 0.25)
@export var restored_sun_color := Color(1.0, 0.97, 0.9)
@export var restored_sun_energy := 1.2

var _smog_shown := 1.0
var _restore_shown := 0.0
var _initialized := false


func _process(delta: float) -> void:
	var district := Game.district
	if district == null or world_environment == null:
		return

	if not _initialized:
		# Snap on the first frame so the level doesn't fade in from defaults.
		_smog_shown = district.smog
		_restore_shown = district.restoration()
		_initialized = true
	else:
		var weight := 1.0 - exp(-blend_speed * delta)
		_smog_shown = lerpf(_smog_shown, district.smog, weight)
		_restore_shown = lerpf(_restore_shown, district.restoration(), weight)

	_apply()


func _apply() -> void:
	var env := world_environment.environment
	if env == null:
		return
	env.fog_enabled = true
	env.fog_density = lerpf(restored_fog_density, polluted_fog_density, _smog_shown)
	env.fog_light_color = restored_fog_color.lerp(polluted_fog_color, _smog_shown)

	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_mat.sky_top_color = restored_sky_top.lerp(polluted_sky_top, _smog_shown)
		sky_mat.sky_horizon_color = restored_sky_horizon.lerp(polluted_sky_horizon, _smog_shown)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color

	if sun:
		sun.light_color = restored_sun_color.lerp(polluted_sun_color, _smog_shown)
		sun.light_energy = lerpf(polluted_sun_energy, restored_sun_energy, 1.0 - _smog_shown)

	if ground and ground.material_override is StandardMaterial3D:
		var ground_mat := ground.material_override as StandardMaterial3D
		ground_mat.albedo_color = polluted_ground.lerp(restored_ground, _restore_shown)
