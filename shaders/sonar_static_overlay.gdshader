shader_type canvas_item;

uniform float base_darkness : hint_range(0.0, 0.15) = 0.015;
uniform float static_brightness : hint_range(0.0, 0.2) = 0.08;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.02;
uniform bool scope_cutout_enabled = false;
uniform vec2 scope_cutout_center = vec2(0.82, 0.78);
uniform vec2 scope_cutout_half_size = vec2(0.12, 0.1);
uniform float scope_cutout_corner_radius : hint_range(0.0, 0.12) = 0.03;
uniform float scope_cutout_softness : hint_range(0.001, 0.05) = 0.012;


float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}


float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
	vec2 clamped_half_size = max(half_size - vec2(radius), vec2(0.0));
	vec2 distance_to_box = abs(point) - clamped_half_size;
	return length(max(distance_to_box, 0.0)) + min(max(distance_to_box.x, distance_to_box.y), 0.0) - radius;
}


float get_scope_cutout_mask(vec2 uv) {
	if not scope_cutout_enabled:
		return 0.0;

	float sdf = rounded_box_sdf(uv - scope_cutout_center, scope_cutout_half_size, scope_cutout_corner_radius);
	return 1.0 - smoothstep(0.0, scope_cutout_softness, sdf);
}


void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	float flicker = hash(pixel + vec2(floor(TIME * 120.0), floor(TIME * 73.0)));
	float scanline = sin((UV.y + TIME * 3.0) * 900.0) * 0.5 + 0.5;
	float value = base_darkness + flicker * static_brightness + scanline * scanline_strength;
	value = clamp(value, 0.0, 0.14);
	float cutout_mask = get_scope_cutout_mask(UV);
	COLOR = vec4(vec3(value), 1.0 - cutout_mask);
}
