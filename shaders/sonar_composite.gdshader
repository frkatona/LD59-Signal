shader_type canvas_item;

uniform float black_cutoff : hint_range(0.0, 0.1) = 0.025;
uniform float reveal_softness : hint_range(0.01, 0.5) = 0.12;


void fragment() {
	vec3 sonar = texture(TEXTURE, UV).rgb;
	float brightness = max(max(sonar.r, sonar.g), sonar.b);
	float alpha = smoothstep(black_cutoff, black_cutoff + reveal_softness, brightness);
	COLOR = vec4(vec3(brightness), alpha);
}
