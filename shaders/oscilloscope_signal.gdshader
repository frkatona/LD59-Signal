shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

uniform float signal_strength : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float trace_line(float y, float center, float thickness) {
	float distance_to_line = abs(y - center);
	return 1.0 - smoothstep(thickness, thickness * 2.8, distance_to_line);
}

void fragment() {
	vec2 uv = UV;
	float clamped_strength = clamp(signal_strength, 0.0, 1.0);
	float edge_distance = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
	float screen_mask = smoothstep(0.0, 0.06, edge_distance);

	float grid_x = 1.0 - smoothstep(0.44, 0.5, abs(fract(uv.x * 8.0) - 0.5));
	float grid_y = 1.0 - smoothstep(0.44, 0.5, abs(fract(uv.y * 4.0) - 0.5));
	float grid = max(grid_x, grid_y) * 0.08;

	vec2 coarse_noise_sample = vec2(floor(uv.x * 84.0), floor(TIME * 18.0));
	vec2 fine_noise_sample = vec2(floor(uv.x * 180.0) + 29.0, floor(TIME * 48.0));
	float coarse_noise = hash(coarse_noise_sample);
	float fine_noise = hash(fine_noise_sample);
	float noise_amplitude = mix(0.09, 0.018, clamped_strength);
	float noise_center = 0.5 + (coarse_noise - 0.5) * noise_amplitude + (fine_noise - 0.5) * 0.012;

	float phase = uv.x * 22.0 - TIME * mix(3.8, 7.5, clamped_strength);
	float dual_wave = sin(phase);
	float wave_amplitude = mix(0.0, 0.23, clamped_strength);
	float upper_center = mix(noise_center, 0.5 + dual_wave * wave_amplitude, clamped_strength);
	float lower_center = mix(noise_center, 0.5 - dual_wave * wave_amplitude, clamped_strength);

	float noisy_center_trace = trace_line(uv.y, noise_center, mix(0.014, 0.008, clamped_strength)) * (1.0 - clamped_strength * 0.7);
	float upper_trace = trace_line(uv.y, upper_center, 0.0075) * clamped_strength;
	float lower_trace = trace_line(uv.y, lower_center, 0.0075) * clamped_strength;
	float upper_glow = trace_line(uv.y, upper_center, 0.022) * clamped_strength;
	float lower_glow = trace_line(uv.y, lower_center, 0.022) * clamped_strength;

	float background_static = (hash(floor(uv * vec2(180.0, 90.0)) + vec2(0.0, floor(TIME * 32.0))) - 0.5) * 0.03;
	vec3 background_color = vec3(0.01, 0.05, 0.02) + vec3(background_static);
	vec3 grid_color = vec3(0.025, 0.18, 0.07) * grid;
	vec3 trace_color = vec3(0.38, 1.0, 0.54);
	vec3 trace = trace_color * (noisy_center_trace * 0.85 + upper_trace + lower_trace);
	vec3 glow = trace_color * (upper_glow + lower_glow) * 0.35;

	vec3 final_color = (background_color + grid_color + trace + glow) * screen_mask;
	ALBEDO = final_color;
	EMISSION = final_color * 1.25;
	ALPHA = screen_mask;
}
