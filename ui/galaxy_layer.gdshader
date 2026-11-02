shader_type spatial;
// Transparent, never writes depth (the six layers sit at the same Z and lean on
// render_priority for order) — but it DOES depth-test now, so opaque geometry in front of
// the disk (planets, capital ships) correctly occludes the wisps behind them instead of
// the layer painting straight over the ship. (The old `depth_test_disabled` +
// "GL Compat never composites depth-tested geometry" note was a misdiagnosis — 2026-09-10.)
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// One of the six numbered galaxy-image layers. `alpha_mult` is the per-layer battle-zoom
// fade (GALAXY_LAYER_FADE_EXP, computed on the CPU); `blur_lod` gives it a slight
// mipmap-based blur as the battle camera moves in, same trick as the background plate.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_mult : hint_range(0.0, 1.0) = 1.0;
uniform float blur_lod : hint_range(0.0, 8.0) = 0.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform float emission_energy : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 c = textureLod(tex, uv, blur_lod);
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a * tint.a * alpha_mult;
	EMISSION = c.rgb * tint.rgb * emission_energy;
}
