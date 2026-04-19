shader_type canvas_item;

uniform float black_cutoff : hint_range(0.0, 0.1) = 0.025;
uniform float reveal_softness : hint_range(0.01, 0.5) = 0.12;
uniform bool scope_cutout_enabled = false;
uniform vec2 scope_cutout_center = vec2(0.82, 0.78);
uniform vec2 scope_cutout_half_size = vec2(0.12, 0.1);
uniform float scope_cutout_corner_radius : hint_range(0.0, 0.12) = 0.03;
uniform float scope_cutout_softness : hint_range(0.001, 0.05) = 0.012;


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
	vec3 sonar = texture(TEXTURE, UV).rgb;
	float brightness = max(max(sonar.r, sonar.g), sonar.b);
	float alpha = smoothstep(black_cutoff, black_cutoff + reveal_softness, brightness);
	alpha *= 1.0 - get_scope_cutout_mask(UV);
	COLOR = vec4(vec3(brightness), alpha);
}
