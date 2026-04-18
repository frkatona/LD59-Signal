shader_type spatial;
render_mode unshaded, depth_draw_opaque;

uniform vec3 ping_origin_ws = vec3(0.0, 0.0, 0.0);
uniform float ping_radius = 0.0;
uniform float ping_band_width = 0.9;
uniform float ping_band_fade = 0.2;
uniform bool pulse_active = false;

varying vec3 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float brightness = 0.0;
	if (pulse_active) {
		float distance_from_origin = distance(world_position, ping_origin_ws);
		float shell_distance = abs(distance_from_origin - ping_radius);
		float inner_falloff = max(ping_band_width - ping_band_fade, 0.0);
		brightness = 1.0 - smoothstep(inner_falloff, ping_band_width, shell_distance);
	}

	ALBEDO = vec3(brightness);
	EMISSION = vec3(brightness);
	ALPHA = 1.0;
}
