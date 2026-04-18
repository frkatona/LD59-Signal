shader_type canvas_item;

uniform float base_darkness : hint_range(0.0, 0.15) = 0.015;
uniform float static_brightness : hint_range(0.0, 0.2) = 0.08;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.02;


float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}


void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	float flicker = hash(pixel + vec2(floor(TIME * 120.0), floor(TIME * 73.0)));
	float scanline = sin((UV.y + TIME * 3.0) * 900.0) * 0.5 + 0.5;
	float value = base_darkness + flicker * static_brightness + scanline * scanline_strength;
	value = clamp(value, 0.0, 0.14);
	COLOR = vec4(vec3(value), 1.0);
}
