shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : source_color, filter_nearest;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(TIME * 2.2 + w.x * 1.7 + w.z) * 0.04 * (1.0 - UV.y);
	VERTEX.z += cos(TIME * 1.8 + w.x * 1.3) * 0.04;
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb * COLOR.rgb;
}
