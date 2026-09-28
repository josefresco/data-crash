shader_type spatial;
// Riverbed: cracked clay (assets/generated/mud_*) tiled in world space,
// dry and pale at low water, dark and glossy as `wet` rises (the River
// node drives it from the water table).

uniform sampler2D mud_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// Tiles per meter, and wetness 0..1.
uniform float tile = 0.16;
uniform float wet = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world.xz * tile;
	vec3 dry = texture(mud_color, uv).rgb;
	ALBEDO = mix(dry, dry * vec3(0.4, 0.37, 0.34), wet);
	NORMAL_MAP = texture(mud_normal, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.2, 0.35, wet);
	ROUGHNESS = mix(0.95, 0.22, wet);
}
