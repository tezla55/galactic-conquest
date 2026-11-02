shader_type canvas_item;

// Star-Wars-style launch wipe. The overlay is opaque black at first; the logo is fitted,
// centred and revealed left-to-right behind a soft seam. On the way out a second soft seam
// sweeps left-to-right and makes the entire overlay (black + logo) transparent, revealing
// the start screen behind it. Nothing here is a hard edge.
//
// `wipe` and `exit` run a little past 0..1 so the logo/overlay are fully hidden/revealed at
// the ends of their tweens.

uniform sampler2D logo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 screen_size = vec2(1600.0, 900.0);
uniform vec2 logo_size = vec2(1920.0, 800.0);
uniform float wipe : hint_range(-0.25, 1.25) = -0.2;
uniform float exit : hint_range(-0.25, 1.25) = -0.2;
uniform float softness : hint_range(0.005, 0.15) = 0.035;
uniform float logo_width_fraction : hint_range(0.1, 1.0) = 0.78;
uniform float logo_height_fraction : hint_range(0.1, 1.0) = 0.64;

const vec3 BACKDROP = vec3(0.008, 0.012, 0.022);
const vec3 SEAM = vec3(0.80, 0.92, 1.0);

void fragment() {
	vec2 screen = screen_size;
	float fit = min(screen.x * logo_width_fraction / logo_size.x,
		screen.y * logo_height_fraction / logo_size.y);
	vec2 drawn = max(logo_size * fit, vec2(1.0));
	vec2 origin = (screen - drawn) * 0.5;
	vec2 logo_uv = (UV * screen - origin) / drawn;

	vec4 tex = vec4(0.0);
	if (logo_uv.x >= 0.0 && logo_uv.x <= 1.0 && logo_uv.y >= 0.0 && logo_uv.y <= 1.0) {
		tex = texture(logo_texture, logo_uv);
	}

	// Seams are only drawn while their position is actually on screen, so the blank start
	// and fully-revealed hold never show a residual bright band at an edge.
	float on_screen = step(0.0, wipe) * step(wipe, 1.0);
	float reveal = 1.0 - smoothstep(wipe - softness, wipe + softness, UV.x);
	float reveal_seam = exp(-pow((UV.x - wipe) / softness, 2.0)) * on_screen;
	vec3 col = mix(BACKDROP, tex.rgb, tex.a * reveal);
	col = mix(col, SEAM, clamp(reveal_seam * 0.55, 0.0, 1.0));

	float exit_mask = smoothstep(exit - softness, exit + softness, UV.x);
	float exit_seam = exp(-pow((UV.x - exit) / softness, 2.0))
		* step(0.0, exit) * step(exit, 1.0);
	col = mix(col, SEAM, clamp(exit_seam * 0.30, 0.0, 1.0));
	COLOR = vec4(col, exit_mask);
}
