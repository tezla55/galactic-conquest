shader_type spatial;

// Procedural deep-zoom background stars, drawn as a MultiMesh of tiny additive quads.
// Additive blending means only the bright dot contributes; the space between stars adds
// nothing. `fade` is the global fade-in (0..1) driven by main.gd.

render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D star_texture : source_color, filter_linear;
uniform float fade = 0.0;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec4 t = texture(star_texture, UV);
	ALBEDO = t.rgb * t.a * v_color.rgb * fade;
	ALPHA = 1.0;
}
