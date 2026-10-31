shader_type spatial;
// Inverted-hull outline for 3D characters, echoing the 1 px sprite outlines.
render_mode unshaded, cull_front;

uniform float width = 0.02;
uniform vec4 color : source_color = vec4(0.10, 0.06, 0.13, 1.0);

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
