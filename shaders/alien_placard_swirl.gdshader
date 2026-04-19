shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 background_color : source_color = vec4(0.01, 0.05, 0.07, 1.0);
uniform vec4 swirl_color : source_color = vec4(0.08, 0.92, 0.86, 1.0);
uniform vec4 accent_color : source_color = vec4(0.58, 1.0, 0.56, 1.0);
uniform float swirl_speed : hint_range(0.0, 3.0) = 0.65;
uniform float ring_density : hint_range(2.0, 24.0) = 10.0;
uniform float glyph_density : hint_range(2.0, 18.0) = 6.0;
uniform float glow_strength : hint_range(0.0, 8.0) = 2.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float radius = length(centered_uv);
	float angle = atan(centered_uv.y, centered_uv.x);
	float time = TIME * swirl_speed;

	float swirl = sin(angle * glyph_density - radius * ring_density * 3.4 + time * 7.0);
	float rings = sin(radius * ring_density * 14.0 - time * 5.0);
	float ripple = sin((centered_uv.x + centered_uv.y) * 19.0 + time * 3.5);
	float grain = hash(floor(UV * 20.0) + floor(time * 8.0)) * 2.0 - 1.0;

	float band = smoothstep(0.78, 0.08, abs(swirl) + abs(rings) * 0.35);
	float filaments = smoothstep(0.7, 0.15, abs(ripple + grain * 0.18));
	float edge_fade = smoothstep(0.72, 0.08, radius);
	float pulse = 0.55 + 0.45 * sin(time * 2.7 + radius * 12.0);

	vec3 color = mix(background_color.rgb, swirl_color.rgb, band * edge_fade);
	color = mix(color, accent_color.rgb, filaments * 0.42 * edge_fade);

	float emissive_mask = max(band, filaments * 0.7) * edge_fade * pulse;
	ALBEDO = color;
	EMISSION = color * emissive_mask * glow_strength;
	ALPHA = 0.92;
}
