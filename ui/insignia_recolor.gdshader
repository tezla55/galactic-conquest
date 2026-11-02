shader_type canvas_item;

// Recolours a faction insignia (ui/art/Insignia_Logos/*.svg) to a single flat `tint`,
// replacing whatever colours the source artwork actually used. A plain multiplicative
// modulate can't do this cleanly: it darkens each channel independently rather than
// replacing the hue, so a saturated source fill (e.g. Resistance's orange starbird)
// tinted blue comes out a muddy brown, not blue. This instead uses the source pixel's own
// alpha as coverage and repaints every covered texel a single flat colour, so the result
// is always a clean hue regardless of the source art's own colours.
//
// `use_luminance_mask` (the galaxy map's own home-world insignia; off for the wizard's
// faction-select icons) additionally treats BRIGHT/white areas of the source art as more
// transparent, not just less "tinted" — used so a logo drawn as dark linework over a light
// disc (Republic/Imperial/CIS) reads as its linework alone instead of a flat coloured
// blob, and a black-fill/white-stroke crest (First Order) shows the fill and not the
// stroke, per the user's own "interpret the white as transparent, the black becomes the
// tint" description. `2026-09-15`.

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform bool use_luminance_mask = false;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mask = tex.a;
	if (use_luminance_mask) {
		float luminance = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		mask *= (1.0 - luminance);
	}
	COLOR = vec4(tint.rgb, tint.a * mask * opacity);
}
