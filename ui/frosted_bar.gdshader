// Frosted-glass backdrop for the top / bottom bars: a cheap blur of whatever is behind,
// DESATURATED to grey and tinted near-black, then held a little translucent so the map
// still reads through it. The galaxy is heavily blue; the chrome must not echo that.
// Kept light (13 taps, no mipmaps) so it never costs a frame in GL Compatibility.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur : hint_range(0.0, 32.0) = 26.25;
// tint.rgb = the neutral wash, tint.a = how much of it (vs the greyed blur) shows.
uniform vec4 tint : source_color = vec4(0.028, 0.028, 0.032, 0.5);
// Whole-strip opacity — kept well under 1 so the galaxy reads clearly through the bars.
uniform float opacity : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	vec2 o = SCREEN_PIXEL_SIZE * blur;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.28;
	c += texture(screen_tex, SCREEN_UV + vec2( o.x, 0.0)).rgb * 0.12;
	c += texture(screen_tex, SCREEN_UV + vec2(-o.x, 0.0)).rgb * 0.12;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0,  o.y)).rgb * 0.12;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, -o.y)).rgb * 0.12;
	c += texture(screen_tex, SCREEN_UV + vec2( o.x,  o.y) * 0.7).rgb * 0.06;
	c += texture(screen_tex, SCREEN_UV + vec2(-o.x,  o.y) * 0.7).rgb * 0.06;
	c += texture(screen_tex, SCREEN_UV + vec2( o.x, -o.y) * 0.7).rgb * 0.06;
	c += texture(screen_tex, SCREEN_UV + vec2(-o.x, -o.y) * 0.7).rgb * 0.06;
	c += texture(screen_tex, SCREEN_UV + vec2( o.x * 2.0, 0.0)).rgb * 0.04;
	c += texture(screen_tex, SCREEN_UV + vec2(-o.x * 2.0, 0.0)).rgb * 0.04;
	// Kill all hue — Rec.601 luma, then a hair darker so the strip never brightens the frame.
	float g = dot(c, vec3(0.299, 0.587, 0.114)) * 0.85;
	COLOR = vec4(mix(vec3(g), tint.rgb, tint.a), opacity);
}
