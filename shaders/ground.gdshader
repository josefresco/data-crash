// Ground that heals: patchy dry dirt (Ground037) gives way to lush lawn
// (Grass004) as `restoration` rises. A large-scale noise mask decides where
// grass comes back first, so it spreads in patches instead of fading evenly.
// A second, coarser noise breaks up tiling at a distance. World-space UVs.
shader_type spatial;

uniform sampler2D dead_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dead_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dead_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D green_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D green_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D green_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_noise : filter_linear, repeat_enable;

// 0 = polluted, 1 = fully restored (DistrictState.restoration()).
uniform float restoration : hint_range(0.0, 1.0) = 0.0;
// Extra tint on the dead ground (browner under smog).
uniform vec3 dead_tint : source_color = vec3(1.0);
// Meters covered by one texture tile.
uniform float tile_meters = 4.0;
// Meters covered by one tile of the regrowth mask.
uniform float mask_meters = 70.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_position.xz / tile_meters;
	vec2 green_uv = uv * 1.3 + vec2(0.37, 0.61);

	// Regrowth: where the mask is low, grass returns first; soft edges.
	float mask = texture(mask_noise, world_position.xz / mask_meters).r;
	float grow = restoration * 1.15 - 0.075;
	float green = smoothstep(mask - 0.08, mask + 0.08, grow);

	// Macro variation hides tiling.
	float macro = mix(0.82, 1.1, texture(mask_noise, world_position.xz / 23.0 + vec2(0.5)).r);

	vec3 dead = texture(dead_albedo, uv).rgb * dead_tint;
	vec3 lush = texture(green_albedo, green_uv).rgb;
	ALBEDO = mix(dead, lush, green) * macro;
	NORMAL_MAP = mix(texture(dead_normal, uv).rgb, texture(green_normal, green_uv).rgb, green);
	ROUGHNESS = mix(texture(dead_roughness, uv).r, texture(green_roughness, green_uv).r, green);
	SPECULAR = 0.3;
}
