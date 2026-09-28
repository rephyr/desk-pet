shader_type canvas_item;
// How a capsule toy's finish looks (ToyView): 0 normal, 1 holo (a rainbow sheen drifting across),
// 2 gold foil (a moving gold shimmer), 3 ghost (see-through, cool), 4 a silhouette (not found yet).

uniform int mode = 0;
uniform vec4 shade : source_color = vec4(0.17, 0.11, 0.24, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (mode == 1) {
		float t = UV.x + UV.y * 0.6 - TIME * 0.25;
		vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (t + vec3(0.0, 0.33, 0.67)));
		vec3 screen = 1.0 - (1.0 - c.rgb) * (1.0 - rainbow * 0.5);
		c.rgb = mix(c.rgb, screen, 0.85);
	} else if (mode == 2) {
		float s = sin((UV.x + UV.y) * 7.0 - TIME * 2.5) * 0.5 + 0.5;
		vec3 gold = mix(vec3(0.62, 0.46, 0.14), vec3(1.0, 0.95, 0.78), s);
		c.rgb = mix(c.rgb, clamp(c.rgb * gold * 1.5, 0.0, 1.0), 0.75);
	} else if (mode == 3) {
		c.a *= 0.5;
		c.rgb = mix(c.rgb, vec3(0.55, 0.91, 0.99), 0.25);
	} else if (mode == 4) {
		c.rgb = shade.rgb;
	}
	COLOR = c;
}
