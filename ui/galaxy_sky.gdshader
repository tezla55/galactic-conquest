shader_type spatial;
// The star-dome sphere from 3D/galaxy (qj.png equirect) as a faint additive skybox, drawn
// just over background.jpg so both read. Transparent, never writes depth, but depth-tests
// so nearer opaque geometry occludes it (see galaxy_layer.gdshader for the history).
// cull_front: the camera is inside the sphere, so render its INSIDE faces only — no
// double-exposed stars from the near hemisphere.
render_mode unshaded, cull_front, depth_draw_never, blend_add;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.85, 0.88, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	ALBEDO = texture(tex, UV).rgb * tint.rgb * opacity;
	ALPHA = 1.0;
}
