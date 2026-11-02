shader_type canvas_item;

// A soft blue/white fade hugging the INSIDE of a planet's own visible edge — brightest on the
// lit side, still faintly present all the way around (real atmospheres scatter light around
// the WHOLE limb, not just the sunlit crescent — a night-side photo of Earth still shows a
// faint blue line at the very edge). Replaced the earlier 3D additive shell (removed
// 2026-09-13, see CLAUDE.md) — that version needed this scene's own heavy bloom to be
// visible at all, and bloom's blur then smeared it into a halo wrapping the WHOLE silhouette
// regardless of lighting. This is a plain 2D CanvasItem draw with ordinary alpha blending —
// no glow/bloom involved anywhere — composited directly onto the already-rendered planet
// pixels, same as the constellation lines / ownership rings (main.gd's _draw()) already draw
// over the 3D scene for exactly this "bloom/lighting can't be trusted to render a precise
// shape" reason.
//
// `2026-09-13` (second pass, user feedback: "too bright, looks like a fake 2D ring, needs a
// gradient effect and ~40% opacity"): collapsed from two separately-stacked terms (a wide
// lit-only inner fade PLUS an independent always-on thin rim band) into ONE continuous
// radial gradient, scaled by a single lit/dark multiplier — two stacked terms with different
// widths created a visible seam that read as a drawn ring outline rather than a soft glow.
// `inner_edge` starts well before the rim for a genuinely gradual fade, and the overall
// result is capped at `max_opacity` — `dark_side_min` keeps the dark hemisphere's share of
// that at a fraction of the lit side's, never fully zero, never as bright either.
//
// `2026-09-13` (third pass, user feedback: "almost there, just make the fade shorter — like
// 25% of its current size"): `inner_edge` moved from 0.45 to 0.8625 — the fade band's own
// WIDTH (1.0 - inner_edge) is now exactly a quarter of what it was (0.55 → 0.1375), so the
// haze hugs a much narrower strip right at the true limb instead of bleeding a quarter of
// the way across the visible disc.

uniform vec4 glow_color : source_color = vec4(0.55, 0.78, 1.0, 1.0);
uniform float inner_edge : hint_range(0.0, 0.99) = 0.8625; // r where the fade starts (0=centre, 1=rim)
uniform float max_opacity : hint_range(0.0, 1.0) = 0.4;    // overall cap, at the rim, lit side
uniform float dark_side_min : hint_range(0.0, 1.0) = 0.22; // dark side's share of max_opacity
uniform vec2 light_dir = vec2(0.0, 1.0);                   // normalised 2D direction toward the light
uniform float angular_falloff : hint_range(0.2, 6.0) = 1.1; // how tightly the brighter half hugs the lit side

// `2026-09-19` (playtest: "atmosphere outlines appear over fleets above them"): this whole
// effect is a 2D overlay drawn AFTER the 3D scene, so it painted straight over any ship parked
// in front of the planet. main.gd hands each ship's projected footprint in as a CAPSULE
// (two end points + a radius, all in this rect's own -1..1 UV space) and the glow simply
// fades to nothing inside it — the ship reads as sitting in front of the atmosphere.
const int MAX_OCCLUDERS = 4;
uniform int occluder_count = 0;
uniform vec2 occ_a[MAX_OCCLUDERS];
uniform vec2 occ_b[MAX_OCCLUDERS];
uniform float occ_r[MAX_OCCLUDERS];

float capsule_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}
	float radial = smoothstep(inner_edge, 1.0, r);
	// +1e-4 avoids normalize(0) at the dead centre, where radial is 0 anyway so it's moot.
	float ang = dot(normalize(uv + vec2(1e-4)), light_dir);
	float lit = pow(clamp(ang, 0.0, 1.0), angular_falloff);
	float side = mix(dark_side_min, 1.0, lit);
	float visible = 1.0;
	for (int i = 0; i < MAX_OCCLUDERS; i++) {
		if (i >= occluder_count) { break; }
		float d = capsule_dist(uv, occ_a[i], occ_b[i]) - occ_r[i];
		visible = min(visible, smoothstep(0.0, 0.06, d));
	}
	COLOR = vec4(glow_color.rgb, glow_color.a * radial * side * max_opacity * visible);
}
