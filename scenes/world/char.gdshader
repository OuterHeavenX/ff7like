shader_type spatial;
// Procedural 3D character parts: vertex colour albedo, soft key light + rim,
// tinted by the map's baked light at the actor (set per frame by CharModel).
// The head additionally blends a pixel face decal projected onto its front.
render_mode unshaded, cull_back;

uniform vec4 light_tint : source_color = vec4(1.0);
uniform vec3 key_dir = vec3(-0.45, 0.85, 0.6);
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform sampler2D face_tex : source_color, filter_nearest, repeat_disable, hint_default_transparent;
uniform float face_frame = 0.0;
uniform float face_frames = 2.0;
uniform vec4 mod_color = vec4(1.0);

varying vec3 world_n;
varying float front;

void vertex() {
	// Palette colours are authored in sRGB, like the map's vertex colours.
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	front = NORMAL.z;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float inside = step(0.0, UV.x) * step(UV.x, 1.0) * step(0.0, UV.y) * step(UV.y, 1.0);
	vec4 f = texture(face_tex, vec2((clamp(UV.x, 0.0, 0.999) + face_frame) / face_frames, UV.y));
	base = mix(base, f.rgb, f.a * inside * step(0.35, front));
	float d = max(dot(normalize(world_n), normalize(key_dir)), 0.0);
	float shade = 0.72 + 0.45 * d;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0) * 0.22;
	vec3 c = (base * shade * light_tint.rgb + rim * light_tint.rgb) * mod_color.rgb;
	ALBEDO = mix(c, flash_color.rgb, flash);
}
