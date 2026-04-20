shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

uniform float enemy_signal_strength : hint_range(0.0, 1.0) = 0.0;
uniform float door_signal_strength : hint_range(0.0, 1.0) = 0.0;
uniform float light_switch_signal_strength : hint_range(0.0, 1.0) = 0.0;
uniform float corner_radius : hint_range(0.0, 0.5) = 0.08;
uniform float corner_softness : hint_range(0.001, 0.1) = 0.015;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float trace_line(float y, float center, float thickness) {
	float distance_to_line = abs(y - center);
	return 1.0 - smoothstep(thickness, thickness * 2.8, distance_to_line);
}

float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
	vec2 clamped_half_size = max(half_size - vec2(radius), vec2(0.0));
	vec2 distance_to_box = abs(point) - clamped_half_size;
	return length(max(distance_to_box, 0.0)) + min(max(distance_to_box.x, distance_to_box.y), 0.0) - radius;
}

float triangle_wave(float x) {
	return abs(fract(x) - 0.5) * 4.0 - 1.0;
}

void fragment() {
	vec2 uv = UV;
	float enemy_strength = clamp(enemy_signal_strength, 0.0, 1.0);
	float door_strength = clamp(door_signal_strength, 0.0, 1.0);
	float light_switch_strength = clamp(light_switch_signal_strength, 0.0, 1.0);
	float max_strength = max(enemy_strength, max(door_strength, light_switch_strength));
	float screen_mask = 1.0 - smoothstep(
		0.0,
		corner_softness,
		rounded_box_sdf(uv - vec2(0.5), vec2(0.5), corner_radius)
	);

	float grid_x = 1.0 - smoothstep(0.44, 0.5, abs(fract(uv.x * 8.0) - 0.5));
	float grid_y = 1.0 - smoothstep(0.44, 0.5, abs(fract(uv.y * 4.0) - 0.5));
	float grid = max(grid_x, grid_y) * 0.08;

	vec2 coarse_noise_sample = vec2(floor(uv.x * 84.0), floor(TIME * 18.0));
	vec2 fine_noise_sample = vec2(floor(uv.x * 180.0) + 29.0, floor(TIME * 48.0));
	float coarse_noise = hash(coarse_noise_sample);
	float fine_noise = hash(fine_noise_sample);
	float noise_amplitude = mix(0.09, 0.018, max_strength);
	float noise_center = 0.5 + (coarse_noise - 0.5) * noise_amplitude + (fine_noise - 0.5) * 0.012;

	float enemy_phase = uv.x * 22.0 - TIME * mix(3.8, 7.5, enemy_strength);
	float enemy_wave = sin(enemy_phase);
	float enemy_wave_amplitude = mix(0.0, 0.23, enemy_strength);
	float upper_center = mix(noise_center, 0.5 + enemy_wave * enemy_wave_amplitude, enemy_strength);
	float lower_center = mix(noise_center, 0.5 - enemy_wave * enemy_wave_amplitude, enemy_strength);

	float door_phase = uv.x * 18.0 - TIME * 4.6;
	float door_center = 0.5 + sin(door_phase) * (0.18 * door_strength);

	float light_switch_phase = uv.x * 3.4 - TIME * 1.85;
	float light_switch_center = 0.5 + triangle_wave(light_switch_phase) * (0.14 * light_switch_strength);

	float noisy_center_trace = trace_line(uv.y, noise_center, mix(0.014, 0.008, max_strength)) * (1.0 - max_strength * 0.7);
	float upper_trace = trace_line(uv.y, upper_center, 0.0075) * enemy_strength;
	float lower_trace = trace_line(uv.y, lower_center, 0.0075) * enemy_strength;
	float upper_glow = trace_line(uv.y, upper_center, 0.022) * enemy_strength;
	float lower_glow = trace_line(uv.y, lower_center, 0.022) * enemy_strength;
	float door_trace = trace_line(uv.y, door_center, 0.0065) * door_strength;
	float door_glow = trace_line(uv.y, door_center, 0.02) * door_strength;
	float light_switch_trace = trace_line(uv.y, light_switch_center, 0.0065) * light_switch_strength;
	float light_switch_glow = trace_line(uv.y, light_switch_center, 0.02) * light_switch_strength;

	float background_static = (hash(floor(uv * vec2(180.0, 90.0)) + vec2(0.0, floor(TIME * 32.0))) - 0.5) * 0.03;
	vec3 background_color = vec3(0.01, 0.05, 0.02) + vec3(background_static);
	vec3 grid_color = vec3(0.025, 0.18, 0.07) * grid;
	vec3 enemy_trace_color = vec3(0.38, 1.0, 0.54);
	vec3 door_trace_color = vec3(0.28, 0.68, 1.0);
	vec3 light_switch_trace_color = vec3(1.0, 0.7, 0.24);
	vec3 trace = enemy_trace_color * (noisy_center_trace * 0.85 + upper_trace + lower_trace);
	trace += door_trace_color * door_trace;
	trace += light_switch_trace_color * light_switch_trace;
	vec3 glow = enemy_trace_color * (upper_glow + lower_glow) * 0.35;
	glow += door_trace_color * door_glow * 0.32;
	glow += light_switch_trace_color * light_switch_glow * 0.32;

	vec3 final_color = (background_color + grid_color + trace + glow) * screen_mask;
	ALBEDO = final_color;
	EMISSION = final_color * 1.25;
	ALPHA = screen_mask;
}
