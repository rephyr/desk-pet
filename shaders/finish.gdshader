shader_type canvas_item;
// Finish ("foil") effects drawn on top of a pet. Modes match data/finishes.json:
// 0 normal, 1 shiny, 2 holo, 3 ghost, 4 glitch, 5 prismatic.
// Mode 6 is not a finish: a flat dark shape for undiscovered entries in the book.

uniform int mode = 0;
uniform float seed = 0.0; // so pets don't all sparkle in sync
uniform vec3 silhouette_color = vec3(0.22, 0.15, 0.3);

varying vec4 vertex_color; // COLOR before the texture, which carries modulate (fades)

void vertex() {
	vertex_color = COLOR;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

// a bright diagonal band sweeping across every few seconds
float glint(vec2 uv, float speed) {
	float d = uv.x + uv.y * 0.6 - fract(TIME * speed + seed) * 3.0 + 0.8;
	return smoothstep(0.14, 0.0, abs(d));
}

void fragment() {
	vec2 uv = UV;
	float t = floor(TIME * 10.0 + seed * 7.0);
	float glitching = mode == 4 ? step(0.8, hash(t)) : 0.0;
	if (glitching > 0.0) {
		// shift a few horizontal slices sideways
		float band = floor(uv.y * 9.0);
		uv.x += (hash(band + t) - 0.5) * 0.3 * step(0.5, hash(band * 3.1 + t));
	}

	// glitch samples the texture itself (shifted), so it re-applies modulate by hand
	vec4 c = mode == 4 ? texture(TEXTURE, uv) * vertex_color : COLOR;
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float bright = smoothstep(0.2, 0.6, lum); // keeps the outline and eyes dark

	if (mode == 1) {
		c.rgb = mix(c.rgb, vec3(1.0), glint(uv, 0.3) * 0.75 * bright);
	} else if (mode == 2) {
		vec3 rainbow = hue(fract(uv.x * 0.9 + uv.y * 0.5 + TIME * 0.15 + seed));
		c.rgb = mix(c.rgb, rainbow * (0.6 + lum * 0.6), 0.4 * bright);
	} else if (mode == 3) {
		c.rgb = mix(c.rgb, vec3(0.78, 0.9, 1.0), 0.35);
		c.a *= 0.5 + 0.12 * sin(TIME * 2.0 + uv.y * 8.0 + seed);
	} else if (mode == 4) {
		if (glitching > 0.0) {
			c.rgb = hash(t * 1.7) > 0.5 ? c.gbr : c.brg;
		}
	} else if (mode == 5) {
		vec3 rainbow = hue(fract(uv.x + uv.y + TIME * 0.35 + seed));
		c.rgb = mix(c.rgb, rainbow * (0.5 + lum * 0.9), 0.65 * bright);
		c.rgb = mix(c.rgb, vec3(1.0), glint(uv, 0.45) * 0.8 * bright);
	} else if (mode == 6) {
		c.rgb = silhouette_color;
	}
	COLOR = c;
}
