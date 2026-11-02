shader_type spatial;
// The far backdrop plate: transparent, never writes depth, but depth-tests so opaque
// geometry in front of it composites correctly (see galaxy_layer.gdshader for the history).
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// The static backdrop plate. As the battle camera zooms in, it pushes into the texture
// (zoom_amount) and blurs via mipmap LOD (max_blur_lod) to read as "far away, out of
// focus" — depth-of-field without an actual DOF pass.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float zoom_t : hint_range(0.0, 1.0) = 0.0;
// Defaults here are just a fallback — main.gd always sets these explicitly from
// BG_MAX_BLUR_LOD / BG_ZOOM_AMOUNT so they're easy to find and tune in one place.
uniform float max_blur_lod : hint_range(0.0, 10.0) = 8.0;
// Kept small on purpose — the backdrop should read as "roughly where it always was,
// just a bit softer," not visibly zoom in like the numbered layers do.
uniform float zoom_amount : hint_range(0.0, 0.9) = 0.03;
uniform vec4 tint : source_color = vec4(0.66, 0.68, 0.8, 1.0);
uniform vec4 emission_tint : source_color = vec4(0.5, 0.55, 0.72, 1.0);
uniform float emission_energy : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	vec2 centred = UV - vec2(0.5);
	vec2 zoomed_uv = vec2(0.5) + centred * (1.0 - zoom_t * zoom_amount);
	vec4 c = textureLod(tex, zoomed_uv, zoom_t * max_blur_lod);
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a * tint.a;
	EMISSION = c.rgb * emission_tint.rgb * emission_energy;
}
