shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

// A from-scratch "fake lit" shader for a model whose real colour turned out to be altered
// somewhere in this scene's built-in lit pipeline in a way no individual material property
// ever explained (see the `unshaded` note on death_star_ii's PLANET_ART entry) — plain
// SHADING_MODE_UNSHADED sidestepped the colour bug but also sidestepped ALL lighting,
// leaving the model flat and shadowless, which read as "wrong" for a different reason.
// This does its own, hand-rolled directional shading — geometry normal dotted against a
// fixed light direction toward the galactic core — entirely independent of Godot's actual
// OmniLight3D and its light_color, so the mystery cast can't reach it, while still giving
// the model a real lit/shadow terminator like every other (normally-lit) world in the scene.
// Deliberately macro-only: no tangent-space normal-map perturbation (that needs its own
// TBN varyings) — the model's own greeble geometry already has enough real face-normal
// variation to read as detailed once shaded this way; a flat sphere would look flatter, but
// nothing currently uses this shader is a flat sphere.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 light_world_pos = vec3(0.0, 6.0, 0.0);   // GALAXY_CORE_POS in main.gd
// Dim, cool floor for the unlit hemisphere — matches the scene's own ambient grade
// (env.ambient_light_color / ambient_light_energy in _build_galaxy_3d) rather than a flat
// black, so the shadow side reads as "dim" like everything else here, not "off".
uniform vec3 ambient_floor : source_color = vec3(0.09, 0.11, 0.16);

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tex_color = texture(albedo_tex, UV).rgb;
	vec3 n = normalize(world_normal);
	vec3 light_dir = normalize(light_world_pos - world_pos);
	float ndotl = max(dot(n, light_dir), 0.0);
	vec3 shade = mix(ambient_floor, vec3(1.0), ndotl);
	ALBEDO = tex_color * tint.rgb * shade;
}
