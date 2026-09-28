shader_type spatial;
// River surface: two scrolling ripple normal maps (world-space, so the
// water width can scale), foam along the banks (UV.y 0 and 1 are the
// edges), and a brown "murk" tint that clears as the smog does.

render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.1, 0.24, 0.3, 0.9);
uniform vec4 shallow_color : source_color = vec4(0.28, 0.42, 0.4, 0.72);
uniform vec4 foam_color : source_color = vec4(0.88, 0.92, 0.9, 0.9);
uniform vec4 murk_color : source_color = vec4(0.33, 0.27, 0.17, 0.92);
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
// Current (m/s) along the river, ripple size (1 / tile meters), murk 0..1.
uniform vec2 flow = vec2(0.7, 0.05);
uniform float ripple_scale = 0.09;
uniform float murk = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world.xz * ripple_scale;
	vec3 n1 = texture(ripple_a, uv + TIME * flow * 0.05).rgb;
	vec3 n2 = texture(ripple_b, uv * 1.8 - TIME * flow * 0.03 + vec2(0.31, 0.67)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.7;
	float edge = min(UV.y, 1.0 - UV.y);
	float foam = smoothstep(0.07, 0.0, edge + (n1.r - 0.5) * 0.06);
	float depth = smoothstep(0.0, 0.35, edge);
	vec4 water = mix(shallow_color, deep_color, depth);
	water = mix(water, murk_color, murk);
	ALBEDO = mix(water.rgb, foam_color.rgb, foam);
	ALPHA = mix(water.a, foam_color.a, foam);
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.6;
	METALLIC = 0.1;
}
