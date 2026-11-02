shader_type spatial;
// The 3D galaxy spiral disk laid into the image stack for real parallax depth. Transparent,
// never writes depth, but depth-tests so a planet / capital ship in front of the disk
// occludes it (see galaxy_layer.gdshader for the history). Additive so a black texture
// background contributes nothing — only the luminous structure glows in.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform sampler2D tex : source_color, filter_linear_mipmap;
// Cools the disk slightly toward the numbered layers' own tint so it doesn't read as a
// separate, warmer object sitting on top.
uniform vec4 tint : source_color = vec4(0.80, 0.83, 1.0, 1.0);
// How strongly the disk adds over the existing layers. main.gd sets this from
// GALAXY_MODEL_OPACITY (~0.3) — kept low on purpose so it deepens the galaxy, not replaces it.
uniform float opacity : hint_range(0.0, 1.0) = 0.3;
// Battle-zoom fade, 1 = full galaxy view, 0 = zoomed onto a battle (main.gd, _apply_zoom).
uniform float fade : hint_range(0.0, 1.0) = 1.0;
// Feather the disk's outer rim to nothing so it blends into the layers instead of hard-
// cutting at the frame edge (the numbered layers fade to transparent at their own edges).
// edge_start..1.0 in UV-radius from centre; set to 1.0 to disable (the star sphere does).
uniform float edge_start : hint_range(0.0, 1.0) = 0.55;
// Soften the disk's own core so it doesn't double the (already bright) galaxy core in the
// layers — fade in from 0 up to core_end in UV-radius from centre; 0.0 disables it.
uniform float core_end : hint_range(0.0, 0.5) = 0.20;

void fragment() {
	vec4 c = texture(tex, UV);
	float r = length(UV - vec2(0.5)) * 2.0;
	float rim = edge_start >= 0.999 ? 1.0 : 1.0 - smoothstep(edge_start, 1.0, r);
	float core = core_end <= 0.001 ? 1.0 : smoothstep(0.0, core_end, r);
	ALBEDO = c.rgb * tint.rgb * opacity * fade * rim * core;
	ALPHA = 1.0;
}
