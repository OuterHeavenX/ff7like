shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 base_color : source_color = vec3(0.10, 0.22, 0.32);
uniform vec3 ambient = vec3(1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.4 + wpos.x * 1.3 + wpos.z * 0.7) * 0.025;
}

void fragment() {
	// Pixel-snapped ripples so the water matches the 24 px/unit art.
	vec2 p = floor(wpos.xz * 24.0) / 24.0;
	float r1 = sin(p.x * 2.7 + TIME * 1.1) * sin(p.y * 4.1 - TIME * 0.8);
	float r2 = sin((p.x + p.y) * 3.3 - TIME * 1.6);
	float hl = step(0.86, r1 * 0.7 + r2 * 0.4);
	float dark = step(r1, -0.75) * 0.25;
	vec3 lit = COLOR.rgb;
	vec3 c = base_color * (0.55 + lit * 0.9) * (1.0 - dark) + hl * lit * vec3(0.55, 0.6, 0.65);
	ALBEDO = c;
}
