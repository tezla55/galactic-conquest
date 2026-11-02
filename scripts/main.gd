extends Control

## The galactic map. It reads GalaxyState and calls TurnResolver; it decides nothing
## about who wins, what a planet is worth, or how a battle is configured.

var state: GalaxyState
var selected_fleet: Fleet = null
var pending_dest: StringName = &""
var _inspect_id: StringName = &""      ## world last clicked — its details show in the panel, reachable or not
var _hover_id: StringName = &""        ## world under the cursor — gets a name label
var _press_pos := Vector2.ZERO          ## where the left button went down (a click vs. a pan-drag)
var _press_active := false
var _press_moved := false               ## the press travelled far enough that it's a drag, not a click
var _pan_button_down := false           ## middle/right button held — always pans
var _credits_badge: Control
var _credits_value: Label
var _credits_income: Label
var _notice: String = ""   ## A one-off warning shown until the next interaction.

var _topbar: Control              ## slim frosted strip, top — centred info / status / message
var _topbar_bg: ColorRect
var _bottombar: Control           ## slim frosted strip, bottom — centred gameplay buttons
var _gear_button: Button          ## top-right corner — opens the Settings popup
var _settings_popup: Control      ## Exit / Display / KYBER Setup / Log / New Campaign
var _settings_scrim: Control      ## click-catcher behind the popup
var _panel_title: Label
var _turn_box: VBoxContainer       ## top-left: current faction insignia + TURN N
var _turn_icon: TextureRect
var _turn_label: Label
var _status_row: HBoxContainer     ## faction insignia + worlds held, both sides
var _status_me_icon: TextureRect
var _status_me_count: Label
var _status_them_icon: TextureRect
var _status_them_count: Label
var _panel_body: RichTextLabel
var _end_turn_button: Button
var _battle_box: HBoxContainer
var _move_button: Button           ## bottom bar, movement row — left of End turn
var _cancel_button: Button         ## bottom bar, movement row — right of End turn
var _buy_button: Button
var _reinforce_button: Button
var _training_button: Button
var _row_mouse: Control            ## bottom bar, one horizontal row in mouse mode
var _row_battle: Control           ## bottom bar, the KYBER / manual-result controls
var _kyber_setup_button: Button
var _log_button: Button
var _music_toggle_button: Button
var _saves_modal: Control
var _autosave_key: String = ""   ## "<seed>:<turn>" of the last autosave, so it fires once per turn
var _ai_opening_seed: int = -1   ## >= 0 while the enemy's opening move is scheduled but not yet played
const AI_OPENING_DELAY_S := 1.2
var _display_toggle_button: Button

# KYBER Setup modal (Windows only). Built on demand, freed on close.
var _kyber_modal: Control
var _kyber_path_edit: LineEdit
var _kyber_status_label: Label
var _kyber_launch_button: Button
var _kyber_message: String = ""

# KYBER live link (Windows only) + activity log modal.
var _kyber_link: KyberLink
var _kyber_log_reader: KyberLogReader
## Follows KYBER's daily log across the current battle for the round winner (Supremacy / GA
## give the plugin nothing to read). Armed on "Play in KYBER", disarmed when the battle is
## no longer pending. A determinate plugin gc_result still wins over it.
var _kyber_watch := KyberMatchWatch.new()
var _kyber_staged: Dictionary = {}   ## A gc_result waiting for the player to Apply.
## After "Play in KYBER": { level: String, deadline_ms: int } while waiting for SWBF2 to
## actually load the battle map. Empty otherwise. Cleared on the plugin's "level" message
## (success), a "load_ack" with running=false / "load_failed", or the deadline.
var _kyber_awaiting: Dictionary = {}
## True only once KYBER has confirmed the requested level actually loaded. The "End match"
## escape hatch is hidden until then — being linked to KYBER does not mean a match is live.
var _kyber_match_live := false
## Co-op matches expose no readable result. Manual "<side> won" buttons stay hidden until
## this wall-clock time so the match has time to play out; set when SWBF2 confirms the map
## loaded. 0 means no hold.
var _coop_result_unlock_ms: int = 0
## True once a co-op match actually went live. Distinguishes "the 3-minute hold is over"
## from "this co-op battle was never launched" — the latter must still show only
## Reconnect + Abandoned, not the manual result path.
var _coop_result_armed := false
## Battle id whose ground-phase winner has already been staged for a direct map switch.
## Prevents a second ship-phase log line from staging the same result twice.
var _groundwin_pending_battle_id := ""
var _last_link_status: int = -1      ## Redraw the panel when the link connects / drops.
var _kyber_play_button: Button
var _kyber_connect_button: Button
var _kyber_end_row: HBoxContainer
var _kyber_result_label: Label
var _kyber_apply_button: Button
var _win_buttons: Array[Button] = []     ## manual "<side> won" buttons — labelled per campaign in _refresh
## `2026-09-16`: tucked into _more_popup (with Abandoned) instead of sitting in the main
## battle row — a live playthrough found Apply result buried among four other buttons that
## are only ever needed as a fallback (no automatic KYBER result, or it needs correcting).
## The per-faction "→ <side>" force-winner buttons that used to sit alongside them are
## removed outright, not relocated — end_kyber_match(0) (the plain "End match" button,
## still in _kyber_end_row) is the one real escape hatch; forcing a SPECIFIC winner that way
## was a testing convenience, not something a normal player should reach for mid-campaign.
var _more_button: Button                 ## opens _more_popup — the win/Abandoned fallback buttons
var _more_popup: Control
var _more_scrim: Control
var _more_menu_box: VBoxContainer        ## the popup's own list — win buttons + Abandoned live here normally
var _abandon_button: Button
var _restart_battle_button: Button   ## More…: re-send `restart` to KYBER for a stuck/misfired match
## `2026-09-18`: Offline mode has no automatic KYBER result at all, ever — the win/Abandoned
## buttons ARE the whole result path there, not a fallback, so hiding them behind "More…"
## (a popup whose whole point is decluttering buttons Offline never shows in the first place)
## was pure unhelpful indirection, reported live. _refresh reparents _win_buttons/
## _abandon_button into _battle_box directly instead of _more_menu_box while offline, and
## hides _more_button entirely for that case.
var _log_modal: Control
var _log_text: TextEdit
var _hero_asset_edit: LineEdit
var _grpc_cmd_edit: LineEdit
var _log_shown_count: int = -1
var _difficulty_modal: Control
var _start_screen: Control
var _victory_modal: Control
## Which victor the popup has already been shown for — guards against _refresh (called on
## lots of unrelated clicks, not just once) reopening a modal the player closed on purpose.
## Reset alongside starting a fresh campaign so its own eventual outcome shows again.
var _victory_modal_shown_for: StringName = &""

# Online multiplayer (GcNet, bridge/gc_net.gd) — a direct peer-to-peer link between two GC
# instances; null outside an online game. The host is the sole authority: only it ever
# calls TurnResolver. `_net_detected_ip` caches the auto-detected public IP for the
# "Host Online Game" screen (one lookup per app run, not one per keystroke/redraw).
var _gc_net: GcNet = null
## Hosting only, while the "Hosting Online Game" modal is up: a SECOND, independent link
## trying the UDP hole-punch fallback in parallel with `_gc_net`'s own TCP listen — only
## engaged once UPnP fails (see _start_online_host). Whichever of the two actually gets a
## peer first wins outright: the other is closed and this is cleared back to null. Needs
## its own poll() call (below) since it isn't `_gc_net` yet at this point.
var _gc_net_udp_fallback: GcNet = null
## Client only: the address last used to join, so a "Try to reconnect" button (see
## _on_gc_net_disconnected) has something to dial without the player re-typing the code.
var _last_join_ip: String = ""
var _last_join_port: int = 0
var _disconnect_modal: Control = null
var _net_detected_ip: String = ""
var _net_ip_request: HTTPRequest = null
# Set the instant a peer joins an online-hosted campaign (KyberEaId.current_log_length) —
# only identities that authenticate AFTER this point are ever candidates for automatic
# team assignment (bridge/kyber_ea_id.gd). A long day's KYBER log can carry plenty of
# stale entries from earlier, unrelated matches; those must never be mistaken for either
# of THIS campaign's two players. 0 outside an online-hosted game.
var _kyber_auth_scan_offset: int = 0

# 3D galaxy backdrop + map (built in code, per the "no editor wiring" rule). A static,
# straight-on galaxy built from stacked image layers; the worlds are tiny glowing points
# scattered across it (nothing in the centre).
var _galaxy_root: Node3D
var _decoration_stars: Node3D      ## parallax star sprites in front of/inside the galaxy
var _decor_star_nodes: Array[Sprite3D] = []
var _decor_star_texture: Texture2D
var _zoom_starfield: MultiMeshInstance3D
var _zoom_starfield_mat: ShaderMaterial
var _zoom_starfield_alpha := 0.0
var _camera: Camera3D
var _planets_root: Node3D
var _planet_nodes: Dictionary = {}   ## planet id -> Node3D (glow + tiny body)
var _planet_glow_base_modulate: Dictionary = {}   ## planet id -> Color, for battle-zoom fade
var _planet_body_nodes: Dictionary = {}   ## planet id -> Node3D (just the body), for the slow spin

# The atmosphere edge-glow: a 2D screen-space overlay (ui/planet_edge_glow.gdshader), not a 3D
# shell — see that shader's own header. _atmosphere_tint is populated in _planet_body (which
# world wants one, and what colour); _atmosphere_glow_nodes holds the actual per-world 2D
# ColorRect (each with its own ShaderMaterial instance, since every world needs its own
# light_dir/tint), parented under _atmosphere_layer so they composite over the 3D scene the
# same way _draw()'s constellation lines / ownership rings already do, but as real tracked
# nodes (position/size set every frame in _update_atmosphere_glows) rather than immediate-mode
# draw calls, since each one needs its own persistent shader parameters.
var _atmosphere_tint: Dictionary = {}          ## planet id -> Color
var _atmosphere_layer: Control
var _atmosphere_glow_nodes: Dictionary = {}    ## planet id -> ColorRect

# A capital world's own faction insignia, floating just north of it — see FACTION_INSIGNIA's
# own doc comment and ui/insignia_recolor.gdshader's header. Two TextureRects per home world
# (a soft halo behind the recoloured icon itself), parented under _insignia_layer for the
# same "composite over the 3D scene, under the UI chrome" z-order reason _atmosphere_layer
# already is. Positioned/tinted every frame in _update_insignia_icons, same shape as
# _update_atmosphere_glows.
var _insignia_layer: Control
var _insignia_icon_nodes: Dictionary = {}   ## planet id -> TextureRect
var _insignia_glow_nodes: Dictionary = {}   ## planet id -> TextureRect
var _insignia_glow_texture: GradientTexture2D   ## shared, built once — see _insignia_glow_tex()

# Fleets: one capital-ship model per Fleet, parked in orbit around whatever world it
# currently reads as being at (see _fleet_display_location). Synced from state each
# _refresh() — nothing here decides where a fleet is allowed to go.
var _fleets_root: Node3D
var _fleet_nodes: Dictionary = {}     ## fleet id -> Node3D
var _fleet_targets: Dictionary = {}   ## fleet id -> Vector3, the position last commanded

# Battle camera: zooms onto the contested world while a battle is pending, and fades the
# galaxy's background layers out (nearest layers slowest) so the world reads clearly.
var _sky_layers: Array = []      ## ShaderMaterial (galaxy_layer.gdshader), front (index 0) to back
var _galaxy_model_mat: ShaderMaterial   ## the 3D spiral-disk model's material — faded with battle zoom
var _galaxy_model_disk: MeshInstance3D  ## the disk mesh — turned very slowly in _process
var _bg_shader_mat: ShaderMaterial   ## background.jpg's material — blurs with battle zoom
var _bg_node: MeshInstance3D      ## repositioned every zoom tick to counteract the camera dolly
var _bg_dist_k := 0.0            ## distance * tan(fov/2) at rest — kept constant so apparent size never changes
var _zoom_t := 0.0               ## 0 = full galaxy view, 1 = zoomed on a battle
var _zoom_planet_id: StringName = &""   ## which battle we're zoomed on, "" if none
var _zoom_target_pos := Vector3.ZERO       ## what the camera is actually lerping toward
var _zoom_target_pos_raw := Vector3.ZERO   ## latest cursor-projected point; _process eases the above toward this
var _zoom_tween: Tween
var _view_zoom_target := 0.0     ## where manual scroll wants _zoom_t to settle (see _process)

const BACKGROUND_TEX := "res://ui/art/background.jpg"
const GALAXY_DIR := "res://ui/art/galaxy/"
const GALAXY_LAYER_COUNT := 6         ## 1.png (front) … 6.png (back), stacked centred
const GALAXY_QUAD := Vector2(70.0, 35.0)   ## world size of the galaxy image plane
## Procedural deep-zoom star bed: thousands of tiny additive quads spread across several
## depths behind the planet. No photo/texture tiling, so there are no seams; the varied z gives
## real parallax when the camera pans.
const DEEP_STAR_COUNT := 5200
const DEEP_STAR_SEED := 0x7E3A51
const DEEP_STAR_Z_MIN := -45.0
const DEEP_STAR_Z_MAX := -22.0
const DEEP_STAR_HALF_X := 50.0
const DEEP_STAR_HALF_Y := 32.0
const DEEP_STARS_SHADER := preload("res://ui/deep_stars.gdshader")
## Decorative depth stars: static sprites at several z depths in front of and behind the
## galaxy, so the camera moving in has real parallax instead of a flat plate.
const DECOR_STAR_COUNT := 300
const DECOR_STAR_SEED := 0x2B7E51
const GALAXY_UV_CROP := 0.10          ## drop the top of each layer (Stellarium watermark)

## A real 3D spiral disk + star sphere from 3D/galaxy laid into the flat image stack so the
## galaxy parallaxes with real depth as the camera moves. Both additive and low-opacity so
## they deepen the art without overpowering it. The disk turns very slowly (the ONLY moving
## thing in the scene); the sphere is a static star skybox.
const GALAXY_MODEL := "res://3D/galaxy/source/galaxy.fbx"
const GALAXY_MODEL_TEX := "res://3D/galaxy/textures/glaxy.png"
const GALAXY_MODEL_MESH_NAME := "Galaxy"          ## the textured disk
const GALAXY_SPHERE_MESH_NAME := "Sphere001"      ## the star-dome sphere (qj.png equirect)
const GALAXY_SPHERE_TEX := "res://3D/galaxy/textures/qj.png"
const GALAXY_MODEL_NATIVE_WIDTH := 1.807268       ## the disk mesh's native AABB width (see tools/inspect_model.gd)
const GALAXY_SPHERE_NATIVE_DIAM := 8.0            ## the sphere mesh's native AABB size
const GALAXY_MODEL_DIAMETER := 56.0               ## world units — its on-screen size, matched to the image stack
const GALAXY_MODEL_POS := Vector3(0.0, 3.8, -1.8) ## a touch forward of / above the image stack for more parallax
const GALAXY_MODEL_TILT_DEG := Vector3(-53.0, 0.0, 5.0)
const GALAXY_MODEL_MIRROR := true                 ## flip the disk so its spiral winds the same way as the 2D art
const GALAXY_MODEL_SPIN_DEG_S := 0.3              ## degrees/sec about the disk normal — barely-there motion
const GALAXY_MODEL_OPACITY := 0.25
const GALAXY_MODEL_TINT := Color(0.6, 0.67, 0.92)   ## cooled toward the layers' tint so it deepens, not replaces
const GALAXY_MODEL_EDGE_START := 0.44             ## UV-radius where the disk starts feathering to nothing
const GALAXY_SPHERE_RADIUS := 120.0               ## huge — the camera sits well inside it (skybox)
const GALAXY_SPHERE_OPACITY := 0.4                ## additive over background.jpg — qj.png is near-black, so
												 ## even this leaves the plate fully readable; the stars just register

## Where each world sits on the galaxy image, in [-1, 1] (x right, y up). The centre is
## kept clear, and the layout is a planar embedding of the hyperlane graph — no two
## constellation lines cross (verified by tools/layout_check.gd).
const GALAXY_LAYOUT := {
	&"kamino": Vector2(-0.92, -0.12),
	&"kamino_naboo_space": Vector2(-0.55, 0.10),
	&"naboo": Vector2(-0.25, 0.56),
	&"naboo_kashyyyk_space": Vector2(0.08, 0.50),
	&"kashyyyk": Vector2(0.35, 0.64),
	&"felucia_kashyyyk_space": Vector2(0.40, 0.22),
	&"naboo_felucia_space": Vector2(-0.15, -0.10),
	&"felucia": Vector2(0.25, -0.20),
	&"geonosis_felucia_space": Vector2(0.74, -0.20),
	&"geonosis": Vector2(1.12, 0.32),
	&"kashyyyk_geonosis_space": Vector2(0.735, 0.48),
}
const MAP_SPREAD := Vector2(13.6, 5.6)   ## [-1,1] layout → world units on the plane (z = 0.4)
const MAP_Y_OFFSET := 0.4                 ## small lift onto the disk

## A per-world surface, kept so faint it barely shows through the glow — a textured
## micro-sphere (`_planet_body`). Keys, all optional, layered onto one StandardMaterial3D:
##   tex          equirect albedo (res:// path)
##   normal       tangent-space normal map — the real per-pixel relief lighting. The
##                dropped-in "_full" art packs ship this as their "(bump)" file (verified
##                mid-blue ~128/128/255); Scarif's water planet has a proper one; Tatooine's
##                is derived from the beach pack's displacement map (tools/downscale_planet_art.py).
##   normal_scale strength multiplier for `normal` (default 1.0)
##   roughness    grayscale spec/roughness ("(shiness)" in the packs)
##   bump         grayscale height — parallax/heightmap input, used ONLY when there's no
##                `normal` (Naboo's pack has no normal map)
##   tint         albedo_color MULTIPLY on top of `tex` (Kamino: saturate an already-blue
##                texture; Scarif/Tatooine: lift a dark source toward the world's real hue)
## The big source maps (some 16000x8000, ~250 MB) live in ui/art/<planet>_full/ etc., each
## .gdignore'd; the game reads the baked-down copies in ui/art/planets/ (see that tool).
const PLANET_ART := {
	# Kamino is a water world (`2026-09-19`, playtest: "should be a darker blue, look like a
	# water planet"): a deeper tint on the ocean texture, NO relief (it used to borrow Naboo's
	# height map, which read as rocky terrain), and a low `roughness_value` so the sun gets a
	# real specular sheen off the "sea" instead of a matte ball.
	&"kamino": {"tex": "res://ui/art/Kamino.jpg", "tint": Color(0.16, 0.28, 0.58), "roughness_value": 0.38},
	&"geonosis": {
		"tex": "res://ui/art/planets/geonosis_diffuse.jpg",
		"normal": "res://ui/art/planets/geonosis_normal.png",
	},
	&"naboo": {
		# Baked copy with land/ocean colours corrected (green land, blue sea — the pack's own
		# diffuse ships them the other way round); see tools in DEVLOG 2026-09-19.
		"tex": "res://ui/art/planets/naboo_diffuse.jpg",
		"roughness": "res://ui/art/Naboo/Exotic 01 (Roughness) 4k.png",
		"bump": "res://ui/art/Naboo/Exotic 01 (Bump) 4k.png",
	},
	&"kashyyyk": {
		"tex": "res://ui/art/planets/kashyyyk_diffuse.jpg",
		"normal": "res://ui/art/planets/kashyyyk_normal.png",
		"roughness": "res://ui/art/planets/kashyyyk_rough.png",
	},
	&"felucia": {
		"tex": "res://ui/art/planets/felucia_diffuse.jpg",
		"normal": "res://ui/art/planets/felucia_normal.png",
		"roughness": "res://ui/art/planets/felucia_rough.png",
	},
}
## Fallback body colour for a world with neither texture nor model in PLANET_ART. Every
## current world has one or the other, so this is just a safety net for a future addition.
const PLANET_FALLBACK_TINT := Color("cfcabf")
## See `_apply_model_textures`'s `unshaded` handling and the shader file's own header comment.
const MODEL_FAKE_LIT_SHADER := preload("res://ui/model_fake_lit.gdshader")
## A soft blue/white fade hugging the INSIDE of a planet's own edge, lit side only — a 2D
## screen-space overlay (see the shader's own header for why, and _update_atmosphere_glows).
const EDGE_GLOW_SHADER := preload("res://ui/planet_edge_glow.gdshader")
const ATMOSPHERE_TINT_DEFAULT := Color(0.72, 0.86, 1.0)
## Below this on-screen body radius (px) the glow is hidden outright rather than drawn
## illegibly small — a world at rest in galaxy view is a handful of pixels, where any version
## of this effect is sub-pixel noise anyway.
const EDGE_GLOW_MIN_SCREEN_R := 8.0
const PLANET_MESH_R := .20          ## the little planet body — bigger than a star
const PLANET_GLOW := 2.0             ## a planet's soft coloured halo
const PLANET_GLOW_ENERGY := 1.7       ## over-brightens the glow's modulate so it blooms
const STAR_GLOW := 0.44               ## a hyperlane star's (smaller) solid white glow
## Every world sits at the exact same world Z (_layout_world_pos hardcodes 0.4) — there is
## no real depth in this scene, just a flat plane the camera looks at from high +Z. So "a
## world further from the camera" is purely a faked illusion, the same way PLANET_GLOW_
## ZOOM_FADE and no_depth_test's zoom-dependent flip already are: a world north of the
## galactic core (positive layout Y — the same axis _layout_world_pos maps straight onto
## world Y, i.e. screen "up") scales down toward this floor, nothing shrinks south of the
## core (layout Y <= 0). See _planet_depth_scale / its one call site in _build_map_3d.
const PLANET_NORTH_SCALE_MIN := 0.65

## A world's glow colour: warm off-white/yellow while neutral, then **player-relative** —
## the side the player chose glows blue, the enemy red — in either campaign (see
## _campaign_glow / _sync_planet_glow_colors). Set purely via Sprite3D.modulate, never
## baked into the gradient texture, so it can change at runtime without a texture rebuild.
const GLOW_NEUTRAL := Color(1.0, 0.92, 0.72)
const GLOW_FRIENDLY := Color(0.35, 0.55, 1.0)   ## the player's worlds
const GLOW_HOSTILE := Color(1.0, 0.28, 0.22)    ## the enemy's

## `2026-09-15`: a faction's symbol, drawn two places — floating just north of its own home
## world on the map (_update_insignia_icons, tinted player-relative blue/red like the
## ownership ring, plus a soft halo — see ui/insignia_recolor.gdshader's header for why a
## plain multiply-tint can't just be applied to FACTION_INSIGNIA's own textures) and above
## its button on the wizard's faction-select step (recoloured flat white instead — that step
## is about picking a side, not reading who currently controls it). One dict covers all six
## factions across all three campaigns, since Planet.capital_faction (core/planet.gd)
## already names which faction a given world is home to with no campaign-specific data
## needed here.
const FACTION_INSIGNIA := {
	Faction.REPUBLIC: preload("res://ui/art/Insignia_Logos/Republic_Emblem.svg"),
	Faction.SEPARATIST: preload("res://ui/art/Insignia_Logos/CIS_roundel.svg"),
	Faction.EMPIRE: preload("res://ui/art/Insignia_Logos/Imperial_Emblem.svg"),
	Faction.REBELLION: preload("res://ui/art/Insignia_Logos/Alliance_Starbird.svg"),
	Faction.FIRST_ORDER: preload("res://ui/art/Insignia_Logos/First_Order.svg"),
	Faction.RESISTANCE: preload("res://ui/art/Insignia_Logos/Resistance_starbird.svg"),
}
const INSIGNIA_RECOLOR_SHADER := preload("res://ui/insignia_recolor.gdshader")
const SPLASH_LOGO := preload("res://images/SWBF2_GC_Logo.png")
const SPLASH_WIPE_SHADER := preload("res://ui/splash_wipe.gdshader")
## Launch splash timings (seconds). The logo wipes in left-to-right behind a soft seam,
## holds, then a second seam wipes the whole overlay away to the start screen.
const SPLASH_WIPE_TIME := 1.45
const SPLASH_HOLD_TIME := 0.6
const SPLASH_WIPE_OUT_TIME := 0.9
const INSIGNIA_SCALE := 1.1        ## icon diameter, as a multiple of the ownership ring's own radius (r)
## `2026-09-15` second pass: "too much glow, hard to make out" — the halo was both too big
## (1.9x the icon's own diameter) and too bright at its own centre, washing the icon itself
## out rather than framing it. Both cut.
const INSIGNIA_GLOW_SCALE := 1.35  ## soft halo diameter, as a multiple of the icon's own diameter
const INSIGNIA_NORTH_GAP := 10.0   ## clear space (px), ring edge to icon edge, so it floats above — not on — the planet
const INSIGNIA_OPACITY := 0.97     ## just short of fully solid — enough translucency to still read as a hologram

## Clone Wars capital ships, parked in orbit around whatever world the fleet is at (GCW's
## are in GCW_FLEET_ART). Falls back to a player-relative tinted hull if a model won't load
## (see _campaign_fleet_tint / _build_fleet_model). `rot` corrects for the model's authored
## orientation — both ships come in lying on their side (we'd be looking at their profile);
## rotated so we look down on the dorsal hull instead, like the classic top-down icon. `tex`/`normal` apply the Separatist's diffuse +
## normal maps onto its material — its glTF export carries no textures of its own
## (verified: a flat grey material, no image), unlike the Republic's, which is a
## flat-shaded multi-material Sketchfab model with no texture files to apply either.
## _apply_model_textures also supports `roughness`/`metallic`/`ao`, deliberately unused
## here — this scene has no reflection probe, so a metallic surface has nothing to
## reflect and renders almost black.
const FLEET_ART := {
	Faction.REPUBLIC: {
		# `2026-09-20` (playtest 920): replaced with the newer Sketchfab Venator dropped into 3D/
		# (CC-BY-4.0, "Commander Cody" — see its license.txt). Authored long along +X, nose at +X,
		# dorsal +Y, so a +90 about X turns the dorsal hull up toward the top-down map camera.
		"model": "res://3D/republic_venator_class_star_destroyer/scene.gltf",
		"rot": Vector3(30.0, 15.0, 15.0),
		# The model carries its own textures, so only a light dull-metal touch (see
		# _apply_hull_finish) — the earlier heavy grey wash was for the old flat-coloured model.
		"hull": {"albedo": Color(0.92, 0.94, 0.97), "roughness": 0.55, "metallic": 0.15, "specular": 0.4},
	},
	Faction.SEPARATIST: {
		"model": "res://3D/star-wars-separatist-dreadnaught/source/Dreadnought.glb",
		"rot": Vector3(-60.0, 0.0, -50.0),
		# No metallic/AO here on purpose — this scene has no reflection probe/environment
		# map, so a fully metallic surface has nothing to reflect and renders almost
		# black (physically correct, looks wrong here). Diffuse + normal only.
		"tex": "res://3D/star-wars-separatist-dreadnaught/textures/Dreadnaught_diffuse.png",
		"normal": "res://3D/star-wars-separatist-dreadnaught/textures/Dreadnaught_normal.png",
	},
}

## --- Galactic Civil War campaign visuals -----------------------------------
## Parallel to GALAXY_LAYOUT / PLANET_ART / FLEET_ART above; the accessor helpers
## (_campaign_layout / _campaign_planet_art / _campaign_glow / _campaign_fleet_*) pick
## the set by state.campaign_id so the Clone Wars paths stay byte-identical.
##
## Deliberately a different shape from Clone Wars. Death Star II + Endor bunkered
## bottom-left (a DIRECT edge, no lane — the shield-generator moon guards the station).
## From Endor there are **two ways forward**: a SHORT one to Kessel (`endor_kessel_space`,
## one lane node — 2 hops), and a LONG one to Tatooine (`endor_tatooine_1/2_space`, two lane
## nodes — 3 hops; node 1 also branches to Kessel). Kessel is the easy first objective. **Hoth sits in a dead-end BELOW Bespin** — reachable only by the direct
## Bespin jump or by hanging off the `bespin_tatooine_space` junction (a 3-way node).
## Scarif + Yavin top, Tatooine mid-right.
const GCW_LAYOUT := {
	&"death_star_ii": Vector2(-0.97, 0.08),
	&"endor": Vector2(-0.67, -0.28),
	&"hoth": Vector2(1.14, -0.70),
	&"bespin": Vector2(1.05, -0.13),
	&"kessel": Vector2(-0.11, 0.20),
	&"scarif": Vector2(0.73, 0.48),
	&"tatooine": Vector2(0.39, -0.59),
	&"yavin_iv": Vector2(0.19, 0.29),
	&"endor_kessel_space": Vector2(-0.51, 0.19),
	&"endor_tatooine_1_space": Vector2(-0.31, -0.43),
	&"endor_tatooine_2_space": Vector2(-0.02, -0.50),
	&"bespin_scarif_space": Vector2(0.87, 0.15),
	&"kessel_scarif_space": Vector2(0.12, 0.58),
	&"kessel_scarif_space_2": Vector2(0.40, 0.6),
	&"bespin_tatooine_space": Vector2(0.70, -0.36),
	&"scarif_tatooine_space": Vector2(0.53, 0.01),
	&"scarif_yavin_space": Vector2(0.48, 0.29),
	&"tatooine_yavin_space": Vector2(0.18, -0.13),
}
## Same keys as PLANET_ART (see that comment). Baked maps in ui/art/planets/. Hoth / Endor
## carry the "_full" pack's real diffuse + normal map; Tatooine the beach pack's diffuse +
## roughness + a normal derived from its displacement; Scarif the "dark water planet"
## diffuse + normal, lifted toward its real tropical hue. Kessel / Bespin / Yavin are a
## single equirect diffuse (SBS pack — a gas giant and two rock/jungle worlds with no real
## relief to map). Death Star II stays a flat tint — it's a station, not a world.
const GCW_PLANET_ART := {
	&"hoth": {
		"tex": "res://ui/art/planets/hoth_diffuse.jpg",
		"normal": "res://ui/art/planets/hoth_normal.png",
		"tint": Color(0.92, 0.96, 1.05),
	},
	&"endor": {
		"tex": "res://ui/art/planets/endor_diffuse.jpg",
		"normal": "res://ui/art/planets/endor_normal.png",
	},
	&"tatooine": {
		"tex": "res://ui/art/planets/tatooine_diffuse.jpg",
		"normal": "res://ui/art/planets/tatooine_normal.png",
		"normal_scale": 0.6,
		"roughness": "res://ui/art/planets/tatooine_rough.png",
		"tint": Color(1.5, 1.28, 0.9),
	},
	&"scarif": {
		"tex": "res://ui/art/planets/scarif_diffuse.jpg",
		"normal": "res://ui/art/planets/scarif_normal.png",
		"tint": Color(1.35, 1.5, 1.5),
	},
	# None of these three shipped with their own normal map — reusing another planet's gives
	# them real per-pixel relief instead of a flat-shaded sphere. `normal_scale` toned down
	# from 1.0 since a borrowed map's relief doesn't necessarily match this planet's own
	# terrain scale.
	&"kessel": {"tex": "res://ui/art/planets/kessel_diffuse.png", "tint": Color(0.8, 0.78, 0.82), "normal": "res://ui/art/planets/geonosis_normal.png", "normal_scale": 0.5},
	# A gas giant: no relief map at all (it borrowed Scarif's rocky normal map, which read as
	# terrain on a cloud-top world — playtest 2026-09-18) and a smooth, soft sheen.
	&"bespin": {"tex": "res://ui/art/planets/bespin_diffuse.png", "roughness_value": 0.55},
	&"yavin_iv": {"tex": "res://ui/art/planets/yavin_diffuse.png", "normal": "res://ui/art/planets/endor_normal.png", "normal_scale": 0.5},   # both forest moons
	# The DS2 as a battle station — its own FBX (every mesh shipped twice, so `dedupe_meshes`
	# strips the coincident copies that z-fought). Modelled half-built, which is canon for the
	# second Death Star; the greeble diffuse + normal go on every surface.
	#
	# 2026-09-12 investigation: the replaced FBX renders with a persistent warm/golden cast
	# under the scene's lit pipeline no matter what `tint` is set to (tested the full range
	# 1.0 down to 0.01 — visually almost identical), even with vertex_color_use_as_albedo,
	# specular, emission, next_pass, triplanar/rim/clearcoat/refraction/detail all ruled out
	# individually. An isolated scene (raw FBX + a plain white light, no GC pipeline) renders
	# it perfectly neutral, proving the model/texture themselves are fine — so the cause is
	# somewhere in this scene's lit rendering path, not a material property, and it wasn't
	# found. Since the user's actual ask is "it should read as grey/silver metal" rather than
	# specifically "keep it dynamically lit", the pragmatic fix is to take DS2 out of that
	# lighting path entirely: `unshaded` swaps its surfaces to `model_fake_lit.gdshader`
	# (see that file's header) — a hand-rolled directional shade (geometry normal vs. the
	# galactic core) with **no dependency on Godot's actual OmniLight3D/light_color at all**,
	# so the mystery can't touch it, while still giving DS2 a real lit/shadow terminator
	# instead of the flat, fully-lit-everywhere look a plain `SHADING_MODE_UNSHADED` gave it
	# (2026-09-12, first pass — fixed the colour but read as "wrong" for a new reason). The
	# diffuse texture is already confirmed neutral grey by direct inspection, so `tint` is a
	# plain white pass-through — no colour-correction guesswork needed anymore.
	&"death_star_ii": {
		"model": "res://ui/art/DeathStarII/source/again.FBX.fbx",
		"dedupe_meshes": true,
		"rot": Vector3(-12.0, 295.0, 0.0),   # turn the completed hull toward the camera
		"tex": "res://ui/art/DeathStarII/textures/greebsplane_dDo_g.jpg",
		"normal": "res://ui/art/DeathStarII/textures/DeathStarPlane_Normal.tga.png",
		"tint": Color(1.0, 1.0, 1.0),
		"unshaded": true,
		"no_atmosphere": true,   # a battle station, not a planet — no air to glow at the rim
	},
}
## GCW capital ships — same shape as FLEET_ART (`model` + `rot`, optional `tex`/`normal`).
## **Both are authored fore-aft along Z, dorsal +Y** (measured 2026-09-10: ISD AABB
## 1267×520×1724, MC cruiser 559×491×2577 — Z is the long axis for each). So `rot` is just a
## small forward pitch (tip the dorsal hull toward the slightly-raised camera) + a yaw for a
## 3/4 view. The old MC value `(-74, 32, 0)` predated that measurement and stood it on its nose.
const GCW_FLEET_ART := {
	Faction.EMPIRE: {
		"model": "res://3D/imperial_star_destroyer/scene.gltf",
		"rot": Vector3(16.0, 26.0, 0.0),
	},
	Faction.REBELLION: {
		"model": "res://3D/mon_calamari_cruiser/scene.gltf",
		"rot": Vector3(16.0, 40.0, 0.0),
	},
}

## --- Sequel-era campaign visuals --------------------------------------------
## Parallel to GALAXY_LAYOUT / PLANET_ART / FLEET_ART and their GCW_ counterparts; the
## _campaign_* accessors below add a third branch for state.campaign_id == "sequel_era" so
## the other two campaigns' paths stay byte-identical.
##
## An outer loop — Starkiller Base (First Order home, top-left) - Ajan Kloss (top-middle) -
## Crait (Resistance home, bottom-middle) - Takodana (bottom-left) - Jakku (middle-left) -
## back to Starkiller Base — plus, since 2026-09-12, two deliberate extras on top of it:
## Crait-Ajan Kloss is a THREE-node arc swinging right, around the galactic core (bulging
## into positive x, disjoint from everything else's x range, so it cannot cross anything),
## replacing the single node that used to cut straight through the middle; and a second,
## outer Starkiller Base-Jakku route (further left/out than the direct one) plus a new
## Crait-Jakku bypass (swinging below/outside Takodana) — both new lanes start or end at a
## planet the loop already touches, so they always share an endpoint with whatever they'd
## otherwise risk crossing (data/campaigns/sequel_era/planets.json's own "_layout" note has
## the full reasoning). That file's x/y mirror this arrangement (screen-space, y grows
## downward — the OPPOSITE sign convention from this dict, same as every other campaign's
## pair of layouts) purely for test_campaigns.gd's planarity check; not algebraically
## derived from these values, just kept in the same relative arrangement.
const SEQUEL_LAYOUT := {
	&"starkiller_base": Vector2(-0.55, 1.35),
	&"ajankloss_starkiller_space": Vector2(-0.20, 1.51),
	&"ajan_kloss": Vector2(0.23, 1.58),
	&"crait_ajankloss_space_3": Vector2(0.62, 1.250),
	&"crait_ajankloss_space_2": Vector2(0.55, 0.64),
	&"crait_ajankloss_space_2b": Vector2(0.80, 0.41),
	&"crait_ajankloss_space_1": Vector2(0.45, 0.07),
	&"crait": Vector2(0.15, -0.55),
	&"takodana_crait_space": Vector2(-0.325, -0.725),
	&"takodana": Vector2(-0.65, -0.70),
	&"jakku_takodana_space": Vector2(-0.80, -0.325),
	&"crait_jakku_space": Vector2(-0.260, -0.05),
	&"jakku": Vector2(-0.52, 0.15),
	&"starkiller_jakku_space": Vector2(-0.58, 0.75),
	&"starkiller_jakku_outer_space": Vector2(-0.9, 0.72),
}
## Real art dropped in 2026-09-12 for four of the five worlds (Crait still has none — its
## own tint-only fallback stays). `tools/downscale_planet_art.py` gained the Jakku/Takodana
## jobs alongside the existing per-planet ones; a bare `{"tint"}` (still Crait's) falls back
## to PLANET_FALLBACK_TINT's flat emissive ball, same as any world with neither `tex` nor
## `model` in the other two campaigns' art dicts.
const SEQUEL_PLANET_ART := {
	# The newest Sketchfab community model (CC-BY-4.0, GrizzleSyrens — see the license.txt
	# alongside it), per the user's own pick over the pack's older/alternate exports. Its
	# AABB (measured: ~1.07 x 1.06 x 1.10) is close to a cube, not one obviously "long" axis
	# like a ship's hull — no strong rotation cue from the geometry alone, so `rot` here is a
	# mild tilt/turn for visual interest (a flat-on view reads as less three-dimensional),
	# the same way DS2's own rot was picked, not measured off anything in particular.
	# Renders with the exact same warm/gold cast under this scene's lit pipeline that DS2's
	# replaced FBX had (2026-09-12 investigation, still unexplained) — confirmed the model's
	# own textures are neutral grey by direct sampling (Black_Ice_baseColor averages
	# (136,136,137), Planet_Surface1 (198,199,195), well within noise of true grey) before
	# ever reaching for `unshaded` again, same as that investigation's own discipline. Same
	# fix: `model_fake_lit.gdshader` gives it a real lit/shadow terminator without going
	# anywhere near the part of the pipeline that alters the colour.
	&"starkiller_base": {
		"model": "res://ui/art/Starkiller Base/starkiller_base_original_model/StarKillerBaseV2.glb",
		"rot": Vector3(-10.0, 40.0, 0.0),
		"tint": Color(1.0, 1.0, 1.0),
		"unshaded": true,
	},
	# Ajan Kloss has no real texture pack of its own — reuses Endor's exact diffuse+normal
	# pair directly (both real assets, already baked down for GCW's own Endor). A tint
	# pushes it away from reading as literally the same planet: cooler and slightly more
	# saturated green than Endor's own untinted look, closer to Ajan Kloss's own
	# on-screen depiction (denser, mistier jungle) than a plain reskin would.
	&"ajan_kloss": {
		"tex": "res://ui/art/planets/endor_diffuse.jpg",
		"normal": "res://ui/art/planets/endor_normal.png",
		"tint": Color(0.92, 1.0, 0.95),
	},
	# The same Poly Haven "aerial_beach_02" dune pack GCW's Tatooine already uses (see the
	# downscale tool's own comment) — a different tint (more rust/amber, less pale-bright
	# than Tatooine's Color(1.5, 1.28, 0.9)) keeps the two deserts from reading as identical
	# even though they're the same source photograph.
	&"jakku": {
		"tex": "res://ui/art/planets/jakku_diffuse.jpg",
		"normal": "res://ui/art/planets/jakku_normal.png",
		"normal_scale": 0.6,
		"roughness": "res://ui/art/planets/jakku_rough.png",
		"tint": Color(1.35, 1.05, 0.72),
	},
	# "Terran 09" — its own real pack, not reused from anywhere else, so no distinguishing
	# tint is needed for that reason; a light warm lift keeps it consistent with how every
	# other real-texture world here is graded rather than left at a flat 1.0 pass-through.
	&"takodana": {
		"tex": "res://ui/art/planets/takodana_diffuse.jpg",
		"normal": "res://ui/art/planets/takodana_normal.png",
		"roughness": "res://ui/art/planets/takodana_rough.png",
		"tint": Color(1.1, 1.08, 0.95),
	},
	# `2026-09-13`: was tint-only (no real texture/normal at all — the one gap this campaign's
	# art pass never filled). Reuses Hoth's own diffuse+normal pair directly, at the user's
	# request — both are pale, cratered, airless-reading worlds under equirect projection, a
	# reasonable stand-in the same way Ajan Kloss reuses Endor's. Crait's own existing warm
	# red tint (a "red crystal salt flat," not Hoth's icy white) is what keeps it from reading
	# as literally the same planet re-skinned.
	&"crait": {
		"tex": "res://ui/art/planets/hoth_diffuse.jpg",
		"normal": "res://ui/art/planets/hoth_normal.png",
		"tint": Color(0.88, 0.55, 0.45),
	},
}
## No dedicated MC85 Star Cruiser / First Order Star Destroyer models exist in this project,
## so — at the user's request, 2026-09-12 — this reuses GCW's own Imperial Star Destroyer /
## Mon Calamari cruiser models directly: a First Order Star Destroyer is canonically an
## evolution of the Imperial ISD design, and the MC85 is the same Mon Calamari cruiser
## lineage as GCW's, so this is a deliberate, reasonable stand-in, not the "no model" gap
## GCW_FLEET_ART's own comment describes. Same `rot` as GCW — both models keep the same
## authored orientation regardless of which faction/campaign points at them.
const SEQUEL_FLEET_ART := {
	Faction.FIRST_ORDER: {
		"model": "res://3D/imperial_star_destroyer/scene.gltf",
		"rot": Vector3(16.0, 26.0, 0.0),
	},
	Faction.RESISTANCE: {
		"model": "res://3D/mon_calamari_cruiser/scene.gltf",
		"rot": Vector3(16.0, 40.0, 0.0),
	},
}

const FLEET_SHIP_LEN := 0.85     ## a parked ship's longest dimension, world units
## How far below its world a parked ship sits at galaxy view, in world units. Planets'
## atmospheric glows cover the ship when it is centred on the world; dropping it clear of the
## glow makes it readable at a glance. This fades out as the camera zooms in, so the battle
## view keeps the ship exactly where it always was.
const FLEET_DROP_Y := 0.9
## `2026-09-13`: cut from 0.78, then further from 0.45 — the first cut wasn't enough once
## BATTLE_CAMERA_DIST also came in closer (which scales the WHOLE scene up together, so
## simply zooming in more doesn't by itself bring two fleets closer together on screen —
## their absolute pixel gap grows right along with the planet, unless their own world-space
## separation shrinks by more than the camera's own zoom gained). This is the general orbit
## radius used at any zoom level, not a battle-only value, so this also brings fleets parked
## at a world closer together at ordinary galaxy view — a reasonable side effect, not a
## special case.
const FLEET_ORBIT_R := 0.28      ## how far a ship sits from its world's centre
const FLEET_MOVE_TIME := 0.9     ## seconds for a fleet to glide between worlds
const FLEET_SPAWN_TIME := 0.45   ## materialise-in / dissolve-out time

const GEAR_SIZE := 40.0   ## the top-right Settings gear button
## Fixed bottom-bar height. Matches the old mouse-mode two-row bar (measured: 104 px at the
## base 1600x900 viewport) and does not change when the controller bar replaces the mouse
## row — both are a single horizontal row centred inside this strip.
const BOTTOM_BAR_HEIGHT := 104.0
## Fixed top-bar height in both normal play and battle states. The bar used to grow with its
## text, which made the map jump whenever the selected world/briefing changed length. Content
## is deliberately trimmed to fit this strip (title + tally + up to four body lines) instead.
const TOP_BAR_HEIGHT := 148.0

## The default, fully-zoomed-out galaxy camera. Battle zoom lerps away from this.
const CAMERA_HOME_POS := Vector3(0.0, 3.4, 34.0)
const CAMERA_HOME_FOV := 40.0
## `2026-09-13`: pulled closer (was 6.5, then 5.0) and the FOV narrowed (was 20.0) — user ask
## for "more cinematically framed," then "still doesn't zoom in enough, the planet is too
## small" on the first attempt at this — pulled in further still.
const BATTLE_CAMERA_DIST := 3.0     ## camera distance from the map plane at full zoom
## `2026-09-13`: cut from 0.4, then 0.12 — still read as "a little too low, needs to be
## centred" at the closer BATTLE_CAMERA_DIST. The camera has no tilt/look_at at all (a
## fixed-orientation pan, see _apply_zoom), so ANY nonzero value here shifts the world
## directly down-screen by however far it lifts the camera above it; left small rather than
## zero purely for a hair of top-bar clearance.
const BATTLE_CAMERA_Y_LIFT := 0.03
const BATTLE_CAMERA_FOV := 16.0
## `2026-09-13`: lengthened (was 1.3) alongside the easing change below — EASE_OUT alone,
## over the old shorter duration, read as "way too fast" (most of a TRANS_CUBIC EASE_OUT
## curve's motion happens in its first fraction of a second; cramming that into 1.3s at this
## much closer BATTLE_CAMERA_DIST made the whole move feel like a jump-cut). More time for
## the same curve to play out reads as deliberate instead of rushed.
const BATTLE_ZOOM_TIME := 1.8
## `2026-09-14`: rebuilt again — "zooms into the direct center before starting to steer
## towards the planet... more of a whip, doesn't seem natural." The previous two versions
## both computed the camera's straight-line position (_apply_zoom's own plain lerp) and then
## ADDED a separate sine-weighted lateral offset on top of it — two independently-computed
## motions overlaid, rather than one real path. Early in the transition the straight-line
## term (closing the distance, narrowing the FOV) reads as far more visually dominant than a
## same-magnitude lateral offset (a camera "zooming in" is a much stronger visual cue than
## the same displacement sideways), so the two-motions-added-together always read as "zoom
## in first, THEN get yanked sideways" no matter how the two were balanced — an additive
## combination of two independent motions can't produce one continuous, natural-looking
## curve; it reads as two things happening near each other in time. Replaced with a genuine
## quadratic Bézier curve for the camera's position (_apply_battle_zoom computes it directly,
## replacing — not adding to — the straight-line value _apply_zoom already set): one single
## continuous formula the whole transition, curving toward `battle_pos` by construction
## rather than "arriving straight, then correcting." `BATTLE_SWOOP_FRACTION` sets how far the
## curve's own control point sits off the straight home→battle line, as a fraction of that
## line's own length — small enough that even the curve's maximum deviation (exactly half of
## the control point's own offset, at the curve's t=0.5) stays comfortably inside frame at
## the closer end of the transition.
const BATTLE_SWOOP_FRACTION := 0.16
## How far a fleet's own model shrinks by full battle zoom — FLEET_ZOOM_SCALE_MAX at galaxy
## view, this at t=1.0. Ships are deliberately drawn far larger than real scale everywhere
## else on this map (a readability choice, not a physical one), so this doesn't aim for
## correct scale either — just a bit more proportionate to the now much-closer, much-larger-
## on-screen planet than the constant full-size hull the un-scaled version showed at any zoom.
## `2026-10-28`: the galaxy-view size was too small to spot among the planet glows, so the
## zoom-out end of the range is now larger while the fully-zoomed-in end stays untouched.
const FLEET_ZOOM_SCALE_MIN := 0.55
const FLEET_ZOOM_SCALE_MAX := 1.55
## When the AI attacks one of the player's worlds, hold on the galaxy map this long — camera
## stays out, the enemy fleet glides in — before the camera zooms to the battle and the
## KYBER controls appear. Otherwise it snaps straight to the battle screen and reads as a bug.
const BATTLE_INTRO_MS := 2600
## Co-op has no automatic result, so its manual "<side> won" buttons stay hidden for this
## long after SWBF2 confirms the map loaded — enough time for a real round instead of an
## instant report. Three minutes.
const COOP_RESULT_HOLD_MS := 3 * 60 * 1000
## Manual scroll-wheel zoom (disabled while a battle is pending — the battle camera owns
## the view then). Shares _zoom_t / _apply_zoom with the battle zoom, but instead of a
## one-shot tween per wheel notch (restarting an ease curve on every tick reads as
## stuttery, especially once already zoomed in), each notch just moves a target value
## and _process eases _zoom_t toward it continuously every frame — smooth regardless of
## how fast the wheel fires, and naturally decelerates as it settles.
const VIEW_ZOOM_STEP := 0.12
const VIEW_ZOOM_SMOOTH_RATE := 8.0   ## higher = catches up to the target faster
## Continuous controller zoom: target change per second at a fully pulled trigger. The
## existing VIEW_ZOOM_SMOOTH_RATE easing turns this into a smooth glide, not notches.
const PAD_ZOOM_RATE := 0.85
## background_blur.gdshader's params, set explicitly here (rather than left at the
## shader's own defaults) so they're easy to find and tune alongside every other zoom
## constant. The background should barely seem to move — it's meant to read as "the same
## backdrop, just a bit softer," not visibly zoom in the way the numbered layers do.
## The real reason blur wasn't visibly doing anything (before this was cranked up trying
## to compensate): background.jpg's .import had mipmaps/generate=false, so
## textureLod(tex, uv, lod>0) had nothing to sample but level 0 and silently clamped to
## it — sharp at any LOD. Fixed at the asset level; a sane value here now actually blurs.
const BG_MAX_BLUR_LOD := 3.0     ## 0-10ish; how blurry (mip level) the backdrop gets at full zoom
## The camera-tracking reposition in _apply_zoom already keeps the backdrop's on-screen
## size fixed — this UV-space zoom is a separate, additional push-in on top of that.
## Small on purpose: "barely zoom, mostly rely on blur for the depth illusion."
const BG_ZOOM_AMOUNT := 0.14
## Per-layer fade rate as we zoom in: opacity = (1 - zoom)^exponent. 1.png..4.png (index
## 0-3, front to back) fade out one after another, nearest first, down to nothing.
const GALAXY_LAYER_FADE_EXP: Array[float] = [6.0, 4.0, 2.5, 1.3, 1.0, 0.5]
## 5.png and 6.png (index 4, 5 — the back-most two) never fully disappear, but do dim as
## we zoom in rather than staying flat at full opacity — lerped straight to this floor.
const GALAXY_LAYER_KEEP_FROM := 6
const GALAXY_LAYER_MIN_OPACITY := 0.5
## Mipmap-based blur on the numbered layers as we zoom in (galaxy_layer.gdshader's
## blur_lod) — hides how pixelated these images get up close. Lighter than the
## background plate's own blur, but every layer gets it, including the two that stay.
const GALAXY_LAYER_BLUR_LOD := 6.0
## A world's glow thins out as the camera zooms onto it for battle, so the real planet
## (barely visible at rest, behind the glow) reads clearly up close. Fraction of the
## glow's base opacity remaining at full zoom.
const PLANET_GLOW_ZOOM_FADE := 0.16
## Below this _zoom_t, a world's glow draws IN FRONT of its body (no_depth_test = true) —
## at the galaxy view a world is a tiny point and should read as a glowing light, not a
## barely-visible speck behind its own halo. At/above it the glow is depth-tested (occluded
## by the body) instead, so a battle-zoomed planet's model reads clearly with the glow just
## haloing its silhouette. See _apply_zoom.
const GLOW_FRONT_ZOOM_T := 0.5
## A slow, continuous spin for every planet body (radians/sec) — just enough to read as
## "a real world turning," not a toy spinning fast. Hyperlane stars don't spin.
const PLANET_SPIN_SPEED := 0.05

## The galaxy's own sun: a physical star at the same point as the core light (below), so
## the light source actually has a visible body. Reuses the hyperlane-star look, just
## much bigger/brighter. It is not one of _planet_nodes, so the zoom-fade loop never
## touches it — it stays at full brightness at any zoom level, battle or manual.
const GALAXY_CORE_POS := Vector3(0, 6, 0)   ## shared with the core OmniLight3D
const CORE_STAR_GLOW := 6.2
const CORE_STAR_ENERGY := 1.0
## Stretched wide and flat rather than a plain round dot, so it reads as the galaxy's own
## bulge (seen edge-on-ish, like the backdrop art's) instead of a star sitting in front of
## it. (x, y) scale on the billboard — x wide, y flat.
const CORE_STAR_ASPECT := Vector2(1.8, 0.55)

var _music: GalaxyMusic
var _ui_sfx: GcUiSfx
var _battle_active := false
var _seen_battle_id: String = ""       ## the pending battle _refresh last reacted to
var _battle_intro_end_ms: int = 0      ## > now while the "AI attacks you" map beat is playing
var _window_focused := true
# `KyberPluginInstaller.kyber_running()` shells out to `tasklist` (blocking, ~0.1–1s) —
# never call it from _refresh(). Cache it, refreshed at most once every few seconds and
# only while it actually matters (a battle is pending and the link is down).
var _kyber_running_cache := false
var _kyber_running_checked_ms := -100000

# --- Controller / gamepad (ui/controller_*.gd, ui/map_cursor.gd, ui/prompt_bar.gd) ----
# The actual device/family tracking lives in ControllerDevice; the map cursor is a pure
# directional helper; every menu still uses Godot's normal focus/`ui_accept` path.
var _controller: ControllerDevice
var _map_cursor := MapCursor.new()
var _pad_cursor_id: StringName = &""
var _pad_last_region := "map"       ## "map" | "bar" | "layer" (for focus restoration)
var _ui_layers: Array[Dictionary] = []   ## open modal/popup stack: {control, cancel, previous_focus}
var _pad_repeat_dir := Vector2.ZERO
var _pad_repeat_wait := 0.0
var _pad_axis_armed := true
var _pad_dpad_held := false
var _controls_modal: Control
var _controls_status_label: Label
var _controls_style_button: Button
var _controls_legend_icons: Array[GlyphIcon] = []
var _pad_auto_focused_battle := ""
var _keyboard_map_nav := false

# Controller bottom bar: display-only pills for the direct face-button actions, shown in
# place of the mouse rows while the controller is active. Not focusable by design.
var _pad_bar: HBoxContainer
var _pad_upgrade_bar: HBoxContainer
var _pad_pill_confirm: PadActionPill
var _pad_pill_cancel: PadActionPill
var _pad_pill_west: PadActionPill
var _pad_pill_north: PadActionPill
var _pad_upgrade_a: PadActionPill
var _pad_upgrade_b: PadActionPill
var _pad_menu := "main"            ## "main" | "upgrades"
var _pad_upgrade_index := 0

# Mouse UI is switched off while controller mode is active; these remember how to restore
# it. The bottom bar is the controller's UI, not a hover-target for a stray mouse.
var _mouse_filters: Dictionary = {}
var _mouse_hover_colors: Dictionary = {}
var _theme_button_normal: StyleBoxFlat
var _theme_button_hover: StyleBoxFlat


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		# A brand-new install (no user://display.cfg yet) starts maximized — friendlier than
		# the fixed 1600×900 default on a real monitor. Once the player has set anything
		# (fullscreen, a dragged size), DisplaySettings takes over as normal.
		if FileAccess.file_exists(DisplaySettings.CONFIG_PATH):
			DisplaySettings.apply(DisplaySettings.load_saved())
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	# A valid placeholder state so the 3D map can build; the mandatory start screen
	# (_show_start_screen, below) replaces it via _start_new_campaign_at before anything
	# is interactive — so no AI opening move here (that runs on the real campaign).
	var boot_campaign := CampaignSettings.load_saved()
	state = ContentLoader.new_campaign(boot_campaign, _saved_faction_for(boot_campaign),
		randi(), DifficultySettings.load_saved(), false)
	_init_fonts()
	theme = _build_button_theme()
	# Created BEFORE _build_galaxy_3d() — that function calls _build_map_3d() internally,
	# which creates each world's atmosphere glow node and parents it here immediately; doing
	# this after would leave _atmosphere_layer null for that very first call and crash on
	# _atmosphere_layer.add_child(rect). Also before the top/bottom bars so it always
	# composites underneath them in z-order — a planet under the top bar (rare, but the map
	# can pan there) should never draw its edge glow over the UI chrome.
	_atmosphere_layer = Control.new()
	_atmosphere_layer.name = "AtmosphereGlow"
	_atmosphere_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmosphere_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_atmosphere_layer)
	# Same reasoning, same ordering requirement as _atmosphere_layer just above — a capital
	# world's insignia nodes are created inside _build_map_3d() too. On top of the atmosphere
	# glow (added after it) so a home world's insignia never renders underneath its own
	# planet's edge-glow haze.
	_insignia_layer = Control.new()
	_insignia_layer.name = "FactionInsignia"
	_insignia_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_insignia_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_insignia_layer)
	_build_galaxy_3d()
	_build_panel()
	# Controller support is entirely additive: the gamepad layer observes input and
	# contributes focus/prompt/cursor helpers, while every existing mouse handler stays.
	_controller = ControllerDevice.new()
	_controller.name = "ControllerDevice"
	add_child(_controller)
	_controller.mode_changed.connect(_on_input_mode_changed)
	_controller.family_changed.connect(_on_controller_family_changed)
	_controller.connection_changed.connect(_on_controller_connection_changed)
	_reset_pad_cursor()
	_apply_cursor_visibility()
	if OS.get_name() == "Windows":
		_kyber_link = KyberLink.new()
		_kyber_link.connect_to()
		_kyber_log_reader = KyberLogReader.new()
	if DisplayServer.get_name() != "headless":
		_music = GalaxyMusic.new()
		add_child(_music)
		_music.start()
		_update_music()   # respect a persisted mute (GcPrefs) from the very first frame
		_ui_sfx = GcUiSfx.new()
		add_child(_ui_sfx)
	get_viewport().size_changed.connect(_layout_topbar)
	_build_credits_badge()
	_refresh()
	if DisplayServer.get_name() != "headless":
		_show_start_screen()
		_show_launch_splash()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false
			_reset_pad_state()
			if _controller != null:
				_controller.set_window_focused(false)
			if DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_update_music()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true
			_reset_pad_state()
			if _controller != null:
				_controller.set_window_focused(true)
			_apply_cursor_visibility()
			_update_music()
			# Safety net: normally _exit_battle_view() runs when a gc_result lands
			# (_stage_kyber_result). If the match was force-quit instead — SWBF2/KYBER closed
			# without ever finishing — no result ever arrives, so nothing else undoes the 5fps
			# render-loop-off throttle _enter_battle_view() applied; GC would stay unusable
			# forever. The player getting focus back onto GC (alt-tab, taskbar click) is the
			# one reliable signal that they're done waiting on the match, so treat it as "exit
			# battle view" too. Harmless if a real result already did this — see the guard in
			# _exit_battle_view.
			if _battle_active:
				_exit_battle_view()


func _update_music() -> void:
	if _music != null:
		_music.set_playing(_window_focused and not _battle_active and not GcPrefs.music_muted())


## Thin null-checked wrappers around `_ui_sfx` (unset headless, e.g. under the test suite)
## so call sites don't each need their own `is_instance_valid` guard. Only an actual
## confirmation rumbles — navigation sounds must not buzz the pad.
func _sfx_confirm() -> void:
	if _ui_sfx != null:
		_ui_sfx.confirm()
	_rumble(0.40, 0.25, 0.08)

func _sfx_cancel() -> void:
	if _ui_sfx != null:
		_ui_sfx.cancel()

func _sfx_move() -> void:
	if _ui_sfx != null:
		_ui_sfx.move()


## Haptics live here rather than in ControllerDevice so ui/controller_device.gd does not
## have to import bridge/gc_prefs.gd (the project keeps ui/ and bridge/ independent).
func _rumble(weak: float, strong: float, seconds: float) -> void:
	if _controller != null and GcPrefs.vibration():
		_controller.rumble(weak, strong, seconds)


func _music_toggle_label() -> String:
	return "Music: Off" if GcPrefs.music_muted() else "Music: On"


func _on_toggle_music_pressed() -> void:
	GcPrefs.set_music_muted(not GcPrefs.music_muted())
	if is_instance_valid(_music_toggle_button):
		_music_toggle_button.text = _music_toggle_label()
	_update_music()


## The top bar has a fixed height regardless of its text, so selecting a different world or
## entering a battle never resizes the map. Content is designed to fit (see TOP_BAR_HEIGHT).
## Called on build, on resize, and at the end of _refresh (content changes).
func _layout_topbar() -> void:
	if _topbar == null:
		return
	var vp := get_viewport_rect().size
	_topbar.offset_bottom = TOP_BAR_HEIGHT
	if _turn_box != null:
		_turn_box.position = Vector2(Tokens.SPACE_4,
			(TOP_BAR_HEIGHT - _turn_box.get_combined_minimum_size().y) * 0.5)
	if _bottombar != null:
		# Fixed height in both input modes: the mouse row and the controller row are each a
		# single horizontal line, centred in the same strip. Never resize on mode switch.
		_bottombar.offset_top = -BOTTOM_BAR_HEIGHT
		_bottombar.visible = _bottombar_has_visible_action()
	if _credits_badge != null and is_instance_valid(_bottombar):
		# Treasury lives on the buying bar now, vertically centred against the buttons.
		_credits_badge.position = Vector2(Tokens.SPACE_4,
			(BOTTOM_BAR_HEIGHT - _credits_badge.get_combined_minimum_size().y) * 0.5)
	if _gear_button != null:
		# Anchor the right edge — its actual width can exceed GEAR_SIZE depending on the fallback
		# glyph metrics, so measure it rather than assuming.
		var gear_w := maxf(GEAR_SIZE, _gear_button.get_combined_minimum_size().x)
		_gear_button.size = Vector2(gear_w, GEAR_SIZE)
		_gear_button.position = Vector2(vp.x - gear_w - Tokens.SPACE_3, Tokens.SPACE_2)
		_gear_button.visible = not is_instance_valid(_start_screen)
	if is_instance_valid(_settings_popup) and _settings_popup.visible:
		var pop_w := maxf(_settings_popup.size.x, _settings_popup.get_combined_minimum_size().x)
		_settings_popup.position = Vector2(
			vp.x - pop_w - Tokens.SPACE_3,
			Tokens.SPACE_2 + GEAR_SIZE + Tokens.SPACE_1)
	if is_instance_valid(_more_popup) and _more_popup.visible and is_instance_valid(_more_button):
		# Opens UPWARD, centred over the button — the battle row sits in the bottom bar, so
		# a popup that dropped down like the settings one would run off the bottom edge.
		var mp_w := maxf(_more_popup.size.x, _more_popup.get_combined_minimum_size().x)
		var mp_h := maxf(_more_popup.size.y, _more_popup.get_combined_minimum_size().y)
		var btn_pos := _more_button.global_position
		var btn_center_x := btn_pos.x + _more_button.size.x * 0.5
		_more_popup.position = Vector2(
			clampf(btn_center_x - mp_w * 0.5, 16.0, vp.x - mp_w - 16.0),
			btn_pos.y - mp_h - Tokens.SPACE_2)


## Any gameplay control in the bottom bar currently on screen? (else hide the strip).
func _bottombar_has_visible_action() -> bool:
	for row: Control in [_row_mouse, _row_battle, _pad_bar, _pad_upgrade_bar]:
		if is_instance_valid(row) and row.visible:
			return true
	return false


func _mouse_row_has_action() -> bool:
	for b in [_move_button, _cancel_button, _reinforce_button, _buy_button,
			_training_button, _end_turn_button]:
		if is_instance_valid(b) and (b as Button).visible:
			return true
	return false


func _process(delta: float) -> void:
	for id in _planet_body_nodes:
		var b: Node3D = _planet_body_nodes[id]
		if is_instance_valid(b):
			b.rotate_y(PLANET_SPIN_SPEED * delta)
	_update_atmosphere_glows()
	_update_insignia_icons()

	# Re-apply the fixed top-bar height and reposition the gear/popups every frame. The bar
	# itself no longer measures its text (that was the old source of resize-on-content-change),
	# but the credits badge and open popups still need to track viewport changes.
	_layout_topbar()
	_pad_process(delta)

	# The legal-destination pulse is immediate-mode drawing driven by the wall clock, so
	# without a redraw each frame it only advanced when something else happened to dirty the
	# canvas (reported live as the pulse freezing between planet selections).
	if selected_fleet != null:
		queue_redraw()

	# The 3D galaxy disk turns very slowly about its own normal (local Z). Only the model
	# moves — the image layers, background and star sphere stay put.
	if is_instance_valid(_galaxy_model_disk):
		_galaxy_model_disk.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(GALAXY_MODEL_SPIN_DEG_S) * delta)

	# The "AI attacks you" map beat just ended — now zoom in and show the battle controls.
	if _battle_intro_end_ms > 0 and Time.get_ticks_msec() >= _battle_intro_end_ms:
		_battle_intro_end_ms = 0
		_notice = ""
		_refresh()

	# Co-op result hold expired: reveal the manual "<side> won" buttons.
	if _coop_result_unlock_ms > 0 and Time.get_ticks_msec() >= _coop_result_unlock_ms:
		_coop_result_unlock_ms = 0
		if _notice.begins_with("KYBER can't read co-op results — the result buttons unlock"):
			_notice = "KYBER can't read co-op match results — log the match result below."
		_refresh()

	# Manual zoom easing: only while free (no battle owns the camera) and no battle-zoom
	# tween is already driving _zoom_t (it and this would otherwise fight every frame).
	# Continuous per-frame easing rather than a per-wheel-notch tween, so rapid scrolling
	# stays smooth instead of restarting an ease curve on every tick. _zoom_target_pos
	# eases toward the latest cursor projection too, not just snapping to it — a small
	# cursor drift near a screen edge (where the projection is far more sensitive per
	# pixel, at a wide FOV) used to yank the camera's endpoint around instantly.
	var tween_active := _zoom_tween != null and _zoom_tween.is_valid()
	var pos_settled := _zoom_target_pos.is_equal_approx(_zoom_target_pos_raw)
	var t_settled := is_equal_approx(_zoom_t, _view_zoom_target)
	if _zoom_planet_id == &"" and not tween_active and not (pos_settled and t_settled):
		var rate := 1.0 - exp(-VIEW_ZOOM_SMOOTH_RATE * delta)
		_zoom_target_pos = _zoom_target_pos.lerp(_zoom_target_pos_raw, rate)
		_apply_zoom(lerpf(_zoom_t, _view_zoom_target, rate))

	_update_zoom_starfield(delta)

	if _gc_net != null:
		_gc_net.poll()
	if _gc_net_udp_fallback != null:
		_gc_net_udp_fallback.poll()

	if _kyber_link == null or GcPrefs.offline_mode():
		return
	_kyber_link.poll()
	if _kyber_link.status != _last_link_status:
		var was_online := _last_link_status == KyberLink.Status.ONLINE
		_last_link_status = _kyber_link.status
		# `2026-10-08` (playtest 104, item 11): the plugin going ONLINE means the host just
		# started a server in KYBER — but nothing happens until they tab back to GC and start
		# a battle from here, which isn't obvious from inside KYBER's own lobby. Nudge them,
		# but only on a fresh connect with nothing already queued — this must not fire mid-
		# battle on an incidental reconnect blip, or right after GC's own `load` just landed.
		if _kyber_link.status == KyberLink.Status.ONLINE and not was_online \
				and _kyber_awaiting.is_empty() and not state.has_pending_battle():
			_gc_chat("Switch back to Galactic Conquest to start a battle.")
		_refresh()
	for line in _kyber_log_reader.poll():
		GcLog.note("kyber-log", line)
		var log_winner := _kyber_watch.feed(line)
		if log_winner != 0:
			_stage_log_winner(log_winner)
		var boarded := _kyber_watch.take_capital_ship_boarded()
		if boarded != &"":
			_skip_capital_ship_phase(boarded)
		if _kyber_watch.take_load_confirmed() and state.has_pending_battle() and not _battle_active:
			# KYBER's own log says our battle map loaded — go live even if the plugin's `level`
			# message never came (its echo heuristic misjudges small/fast maps like Blast).
			var live_map := String(_kyber_awaiting.get("level", "the battle map"))
			_kyber_battle_is_live(live_map if live_map != "" else "the battle map")
	var result := _kyber_link.take_result()
	if not result.is_empty():
		_stage_kyber_result(result)
	_poll_kyber_await()
	if is_instance_valid(_log_modal) and _log_text != null:
		_sync_log_text()


## The galaxy: `background.jpg` and six stacked image layers on parallel quads facing a
## straight-on camera — static, centred. The worlds are tiny glowing points scattered
## across the disk (`GALAXY_LAYOUT`), never the centre. `_draw` adds the 2D overlay.
func _build_galaxy_3d() -> void:
	var root := Node3D.new()
	root.name = "Galaxy3D"
	add_child(root)
	_galaxy_root = root

	# Look target: PS2/PS3-era space game — a hard key light, shadow sides that fall to
	# near-black, saturated mid-tones, and generous bloom halation off every lit edge.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.34, 0.5)
	env.ambient_light_energy = 0.10          # was 0.25 — deep unlit sides, era-appropriate key/fill ratio
	# Filmic tonemap with a low white point rolls bright hull + ice into the bloom instead
	# of clipping to a flat white; exposure just under 1 keeps the darker grade from lifting.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 3.5
	env.glow_enabled = true
	env.glow_intensity = 1.15               # was 0.85
	env.glow_strength = 1.2
	env.glow_bloom = 0.45                   # was 0.25 — heavier halation
	env.glow_hdr_threshold = 0.7            # a touch higher so shadow grain doesn't bloom, lit edges do
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Saturated-CRT punch on the composited frame.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 1.24
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	# Camera raised so the galaxy + worlds sit low — centred in the space below the top bar.
	var cam := Camera3D.new()
	cam.fov = CAMERA_HOME_FOV
	cam.current = true
	cam.position = CAMERA_HOME_POS
	root.add_child(cam)
	_camera = cam

	# The key light sits at the galaxy's own centre (the bulge in the backdrop art), not at
	# a fixed angle — every world and ship is lit from the direction of the galactic core
	# relative to its own position, so worlds on opposite sides of the disk light up from
	# opposite sides too, instead of a single flat sun angle for the whole galaxy.
	var core_light := OmniLight3D.new()
	core_light.position = GALAXY_CORE_POS
	core_light.light_energy = 30.0
	core_light.light_color = Color(1.0, 0.88, 0.6)   # warmer/more golden, matching the galaxy's own bulge
	core_light.omni_range = 40.0
	core_light.omni_attenuation = 1.0
	core_light.shadow_enabled = true
	core_light.light_cull_mask = 1   # worlds only — ships have their own cooler light on layer 2
	root.add_child(core_light)
	# Fleets read yellow under the warm core light (playtest 920v3). They get a white-blue key from
	# the same spot instead, on their own render/light layer, with NO shadow map: the cube shadow
	# map is what striped flat hull plates with seams.
	var fleet_light := OmniLight3D.new()
	fleet_light.position = GALAXY_CORE_POS
	fleet_light.light_energy = 19.0
	fleet_light.light_color = FLEET_LIGHT_COLOR
	fleet_light.omni_range = 40.0
	fleet_light.omni_attenuation = 1.0
	fleet_light.shadow_enabled = false
	fleet_light.light_cull_mask = FLEET_LIGHT_LAYER
	root.add_child(fleet_light)
	_build_core_star()

	# Background plate, then 6.png (back) up to 1.png (front), all centred and static.
	# The numbered layers' materials are kept (front-first) so battle zoom can fade them.
	_build_background_quad()
	_sky_layers.clear()
	for i in range(GALAXY_LAYER_COUNT, 0, -1):
		var mat := _add_sky_quad("%s%d.png" % [GALAXY_DIR, i], GALAXY_QUAD, -4.0,
			-30 + (GALAXY_LAYER_COUNT - i), GALAXY_UV_CROP, Color(0.78, 0.79, 0.88))
		_sky_layers.append(mat)
	_sky_layers.reverse()   # loop ran back (6) to front (1); index 0 should be the front

	_build_galaxy_model()
	_build_decoration_stars()
	_build_zoom_starfield()

	_fleets_root = Node3D.new()
	_fleets_root.name = "Fleets3D"
	root.add_child(_fleets_root)

	_build_map_3d()


## The back-most plate — its own shader (background_blur.gdshader) so it can blur into
## itself as the battle camera moves in, implying depth, while _apply_zoom keeps it
## geometrically fixed on screen (see the comment there) — it's meant to read as "not
## really 3D," a stationary backdrop infinitely far away, not something the camera dollies
## past. Kept separate from _add_sky_quad since it needs a ShaderMaterial, not a
## StandardMaterial3D.
func _build_background_quad() -> void:
	var tex: Texture2D = load(BACKGROUND_TEX)
	var shader: Shader = load("res://ui/background_blur.gdshader")
	if tex == null or shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = -40
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("max_blur_lod", BG_MAX_BLUR_LOD)
	mat.set_shader_parameter("zoom_amount", BG_ZOOM_AMOUNT)
	var q := QuadMesh.new()
	q.size = Vector2(86.0, 48.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.0, -6.0)
	_galaxy_root.add_child(mi)
	_bg_shader_mat = mat
	_bg_node = mi
	# distance * tan(half-fov) at rest — hold this constant as the camera dollies/narrows
	# its FOV and the background's apparent screen size never changes.
	_bg_dist_k = (CAMERA_HOME_POS.z - mi.position.z) * tan(deg_to_rad(CAMERA_HOME_FOV * 0.5))


## A camera-facing textured quad for the sky stack. `crop` trims that fraction off the top
## of the texture (the layers carry a Stellarium watermark up there). Uses
## galaxy_layer.gdshader (not a plain StandardMaterial3D) so the numbered layers can blur
## slightly, as well as fade, during a battle zoom. Returns the material for that purpose.
func _add_sky_quad(tex_path: String, size: Vector2, z: float, priority: int,
		crop: float, tint: Color) -> ShaderMaterial:
	var tex: Texture2D = load(tex_path)
	var shader: Shader = load("res://ui/galaxy_layer.gdshader")
	if tex == null or shader == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("uv_offset", Vector2(0.0, crop))
	m.set_shader_parameter("uv_scale", Vector2(1.0, 1.0 - crop))
	var q := QuadMesh.new()
	q.size = Vector2(size.x, size.y * (1.0 - crop))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0.0, size.y * crop * 0.5, z)   # keep the disk centred after the crop
	_galaxy_root.add_child(mi)
	return m


## The 3D spiral disk + star sphere from 3D/galaxy, laid into the image stack for real
## parallax depth. Both additive (galaxy_model.gdshader) and low-opacity so they deepen the
## art without overpowering the layers. The disk turns very slowly (`_process`, the only
## motion in the scene); the sphere is a static star skybox. The model's baked rotation
## animation is dropped.
func _build_galaxy_model() -> void:
	if not ResourceLoader.exists(GALAXY_MODEL):
		return
	var packed: PackedScene = load(GALAXY_MODEL)
	var shader: Shader = load("res://ui/galaxy_model.gdshader")
	var tex: Texture2D = load(GALAXY_MODEL_TEX)
	if packed == null or shader == null or tex == null:
		return
	var src := packed.instantiate()
	var disk := src.find_child(GALAXY_MODEL_MESH_NAME, true, false)
	var sphere := src.find_child(GALAXY_SPHERE_MESH_NAME, true, false)
	var disk_mesh: Mesh = (disk as MeshInstance3D).mesh if disk is MeshInstance3D else null
	var sphere_mesh: Mesh = (sphere as MeshInstance3D).mesh if sphere is MeshInstance3D else null
	src.free()   # orphan — we only wanted the two meshes, not the model's baked rotation anim

	# --- the star sphere: a faint additive skybox, drawn just over background.jpg ---
	var sky_shader: Shader = load("res://ui/galaxy_sky.gdshader")
	var sky_tex: Texture2D = load(GALAXY_SPHERE_TEX)
	if sphere_mesh != null and sky_shader != null and sky_tex != null:
		var sky_mat := ShaderMaterial.new()
		sky_mat.shader = sky_shader
		sky_mat.render_priority = -38   # background.jpg is -40; stars sit just over it
		sky_mat.set_shader_parameter("tex", sky_tex)
		sky_mat.set_shader_parameter("opacity", GALAXY_SPHERE_OPACITY)
		var sky := MeshInstance3D.new()
		sky.name = "GalaxyStarSphere"
		sky.mesh = sphere_mesh
		sky.material_override = sky_mat
		sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ss := (GALAXY_SPHERE_RADIUS * 2.0) / GALAXY_SPHERE_NATIVE_DIAM
		sky.scale = Vector3(ss, ss, ss)
		sky.position = Vector3(0.0, CAMERA_HOME_POS.y, 0.0)   # centred on the resting camera
		_galaxy_root.add_child(sky)

	# --- the spiral disk: additive, feathered, tilted to the layers, turning very slowly ---
	if disk_mesh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = -24   # after the numbered layers (-30..-25), before the planets (0)
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("tint", GALAXY_MODEL_TINT)
	mat.set_shader_parameter("opacity", GALAXY_MODEL_OPACITY)
	mat.set_shader_parameter("edge_start", GALAXY_MODEL_EDGE_START)
	mat.set_shader_parameter("fade", 1.0)

	# Holder carries the tilt + position; the mesh child carries the mirror + the slow spin
	# about the disk normal (the FBX disk lies in local XY, thin in Z).
	var holder := Node3D.new()
	holder.name = "GalaxyModel"
	holder.rotation_degrees = GALAXY_MODEL_TILT_DEG
	holder.position = GALAXY_MODEL_POS
	_galaxy_root.add_child(holder)

	var mi := MeshInstance3D.new()
	mi.name = "GalaxyModelDisk"
	mi.mesh = disk_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := GALAXY_MODEL_DIAMETER / GALAXY_MODEL_NATIVE_WIDTH
	mi.scale = Vector3(-s if GALAXY_MODEL_MIRROR else s, s, s)
	holder.add_child(mi)

	_galaxy_model_mat = mat
	_galaxy_model_disk = mi


## Static sensation-of-depth stars. Each sprite sits at its own z between the camera and the
## galaxy (foreground) or behind the planet plane (mid/deep). Because the camera physically
## dollies toward the zoom target, these pass by at different rates and sell the 3D space
## instead of looking like another flat 2D plate.
func _build_decoration_stars() -> void:
	if _galaxy_root == null:
		return
	var root := Node3D.new()
	root.name = "DecorationStars"
	_galaxy_root.add_child(root)
	_decoration_stars = root
	_decor_star_nodes.clear()
	var tex := _decor_star_texture_cached()
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_STAR_SEED
	for i in DECOR_STAR_COUNT:
		var layer_roll := rng.randf()
		var z: float
		var depth_size: float
		var no_depth := false
		if layer_roll < 0.42:
			z = rng.randf_range(1.2, 15.0)      # foreground, between camera and map
			depth_size = rng.randf_range(0.045, 0.11)
			no_depth = true
		elif layer_roll < 0.78:
			z = rng.randf_range(-9.5, 0.15)     # inside/behind the galaxy plate
			depth_size = rng.randf_range(0.07, 0.17)
		else:
			z = rng.randf_range(-27.0, -10.0)   # deep background, past the layers
			depth_size = rng.randf_range(0.14, 0.34)
		# Extent of the visible frame at this depth (home camera at z=34, 40° vertical FOV),
		# with a little bleed so stars reach the corners and the bars.
		var depth := maxf(CAMERA_HOME_POS.z - z, 1.0)
		var half_h := depth * tan(deg_to_rad(CAMERA_HOME_FOV * 0.5)) * 1.12
		var half_w := half_h * 1.78 * 1.08
		var star := Sprite3D.new()
		star.texture = tex
		star.shaded = false
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.no_depth_test = no_depth
		star.pixel_size = depth_size / 64.0
		star.position = Vector3(rng.randf_range(-half_w, half_w), rng.randf_range(-half_h, half_h), z)
		var warm := rng.randf()
		var tint := Color(0.80, 0.90, 1.0).lerp(Color(1.0, 0.93, 0.80), warm * 0.45)
		var alpha := rng.randf_range(0.45, 1.0)
		star.modulate = Color(tint, alpha)
		star.set_meta("base_alpha", alpha)
		star.render_priority = 12 if no_depth else 0
		root.add_child(star)
		_decor_star_nodes.append(star)


## One soft radial dot, shared by every decoration star. Built procedurally (no imported
## image) so it stays crisp at any zoom and costs one texture for the whole field.
func _decor_star_texture_cached() -> Texture2D:
	if _decor_star_texture != null:
		return _decor_star_texture
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	grad.add_point(0.10, Color(1.0, 1.0, 1.0, 0.95))
	grad.add_point(0.28, Color(1.0, 1.0, 1.0, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_decor_star_texture = tex
	return tex


## A procedural deep-zoom star bed: thousands of tiny additive quads at many depths behind
## the planet plane. No image is tiled, so there are no seams; the spread in z gives real
## parallax when the camera pans. It stays invisible for most of the zoom range, then fades in
## slowly over the last notches (see _update_zoom_starfield).
func _build_zoom_starfield() -> void:
	if _galaxy_root == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = DEEP_STARS_SHADER
	mat.set_shader_parameter("star_texture", _decor_star_texture_cached())
	mat.set_shader_parameter("fade", 0.0)
	mat.render_priority = -18

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = DEEP_STAR_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = DEEP_STAR_SEED
	for i in DEEP_STAR_COUNT:
		var pos := Vector3(
			rng.randf_range(-DEEP_STAR_HALF_X, DEEP_STAR_HALF_X),
			rng.randf_range(-DEEP_STAR_HALF_Y, DEEP_STAR_HALF_Y),
			rng.randf_range(DEEP_STAR_Z_MIN, DEEP_STAR_Z_MAX))
		var size := rng.randf_range(0.06, 0.14)
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * size), pos))
		var warm := rng.randf()
		var tint := Color(0.78, 0.88, 1.0).lerp(Color(1.0, 0.92, 0.78), warm * 0.4)
		var brightness := rng.randf_range(0.35, 1.0)
		mm.set_instance_color(i, Color(tint.r * brightness, tint.g * brightness,
			tint.b * brightness, 1.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DeepZoomStars"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	_galaxy_root.add_child(mmi)
	_zoom_starfield = mmi
	_zoom_starfield_mat = mat


func _build_map_3d() -> void:
	if state == null or _galaxy_root == null:
		return
	_planets_root = Node3D.new()
	_planets_root.name = "Map3D"
	_galaxy_root.add_child(_planets_root)

	for p: Planet in state.planets.values():
		var node: Node3D
		if p.capturable:
			node = _planet_body(p)
			if node.get_child_count() > 0:
				_planet_body_nodes[p.id] = node.get_child(0)   # the body, for the slow spin
			node.scale = Vector3.ONE * _planet_depth_scale(p)
		else:
			node = _star_sprite()
		node.position = _planet_world_pos(p)
		_planets_root.add_child(node)
		_planet_nodes[p.id] = node
		if node is Sprite3D:
			_planet_glow_base_modulate[p.id] = (node as Sprite3D).modulate
		if _atmosphere_tint.has(p.id):
			_atmosphere_glow_nodes[p.id] = _make_atmosphere_glow_node(_atmosphere_tint[p.id])
		if p.capital_faction != &"" and FACTION_INSIGNIA.has(p.capital_faction):
			var nodes := _make_insignia_nodes(p.capital_faction)
			_insignia_glow_nodes[p.id] = nodes["glow"]
			_insignia_icon_nodes[p.id] = nodes["icon"]
	_sync_planet_glow_colors()


## One 2D ColorRect + its own ShaderMaterial per world wanting an atmosphere — see
## ui/planet_edge_glow.gdshader's header. Its own ShaderMaterial (not a shared one) because
## every world needs its own tint and its own per-frame light_dir (_update_atmosphere_glows).
func _make_atmosphere_glow_node(tint: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE   # the shader ignores this; ColorRect just needs a non-transparent draw to shade
	var mat := ShaderMaterial.new()
	mat.shader = EDGE_GLOW_SHADER
	mat.set_shader_parameter("glow_color", tint)
	rect.material = mat
	rect.visible = false   # _update_atmosphere_glows turns it on once it has a real position
	_atmosphere_layer.add_child(rect)
	return rect


## Body-hugging screen radius — where the edge glow's own circle should sit. Distinct from
## _screen_radius (the bigger player-relative OWNERSHIP glow's radius, used for the ring/click
## target/line-trim) — this one tracks PLANET_MESH_R, the actual solid body, since the whole
## point is a fade confined to inside that circle, never a separate ring outside it.
func _screen_body_radius(planet: Planet) -> float:
	if _camera == null or not _planet_nodes.has(planet.id):
		return 12.0
	var node: Node3D = _planet_nodes[planet.id]
	var span := PLANET_MESH_R * node.scale.x
	var edge := node.global_position + _camera.global_transform.basis.x * span
	return _screen_position(planet).distance_to(_camera.unproject_position(edge))


## Called every _process() frame: positions/sizes each world's edge-glow ColorRect to exactly
## bound its own on-screen body circle, and points its light_dir at the galactic core's own
## screen-space projection — the same GALAXY_CORE_POS every world's real lighting already
## keys off, just projected to 2D here since this draws in screen space, not world space.
func _update_atmosphere_glows() -> void:
	if _camera == null or state == null:
		return
	var core_screen := _camera.unproject_position(GALAXY_CORE_POS)
	var capsules := _fleet_screen_capsules()
	for id in _atmosphere_glow_nodes:
		var rect: ColorRect = _atmosphere_glow_nodes[id]
		var planet := state.get_planet(id)
		if planet == null:
			rect.visible = false
			continue
		var r := _screen_body_radius(planet)
		if r < EDGE_GLOW_MIN_SCREEN_R:
			rect.visible = false
			continue
		var center := _screen_position(planet)
		rect.position = center - Vector2(r, r)
		rect.size = Vector2(r, r) * 2.0
		rect.visible = true
		var dir := (core_screen - center)
		var mat: ShaderMaterial = rect.material
		mat.set_shader_parameter("light_dir", dir.normalized() if dir.length() > 0.001 else Vector2.UP)
		_set_glow_occluders(mat, center, r, capsules)


## Each live ship's on-screen footprint as a capsule (two end points + a radius, in pixels),
## so the 2D atmosphere overlay can knock itself out where a ship sits in front of a planet
## (see planet_edge_glow.gdshader's header). The ship's own long axis/width come from its
## model's un-rotated AABB, measured once and cached on the node.
func _fleet_screen_capsules() -> Array:
	var out: Array = []
	if _camera == null:
		return out
	for id in _fleet_nodes:
		var n: Node3D = _fleet_nodes[id]
		if not is_instance_valid(n):
			continue
		# The holder is positioned/scaled for the map; the body carries the actual hull
		# (plus the galaxy-view drop). Measure the body so the capsule follows both.
		var body: Node3D = n.get_meta("body", n) as Node3D
		if not is_instance_valid(body) or body.scale.x < 0.05:
			continue
		if not body.has_meta("occ"):
			var box := _aggregate_aabb(body, Transform3D.IDENTITY)
			var sz := box.size
			var axis := Vector3.RIGHT
			var len_h := sz.x * 0.5
			var wid := maxf(sz.y, sz.z) * 0.5
			if sz.y >= sz.x and sz.y >= sz.z:
				axis = Vector3.UP; len_h = sz.y * 0.5; wid = maxf(sz.x, sz.z) * 0.5
			elif sz.z >= sz.x and sz.z >= sz.y:
				axis = Vector3.BACK; len_h = sz.z * 0.5; wid = maxf(sz.x, sz.y) * 0.5
			# Endpoints pulled in by the width so the capsule's round caps land on the hull's ends.
			var c := box.get_center()
			var half := maxf(len_h - wid * 0.6, 0.0)
			body.set_meta("occ", [c - axis * half, c + axis * half, wid * 0.55])
		var occ: Array = body.get_meta("occ")
		var a_w: Vector3 = body.global_transform * (occ[0] as Vector3)
		var b_w: Vector3 = body.global_transform * (occ[1] as Vector3)
		var a_s := _camera.unproject_position(a_w)
		var b_s := _camera.unproject_position(b_w)
		var rad_world: float = float(occ[2]) * body.global_transform.basis.get_scale().x
		var edge := _camera.unproject_position(a_w + _camera.global_transform.basis.x * rad_world)
		out.append([a_s, b_s, a_s.distance_to(edge)])
	return out


## Feed the capsules that overlap this world's edge-glow rect into its shader, converted to
## the rect's own -1..1 UV space (`centre`/`r` = the rect's screen centre and body radius).
func _set_glow_occluders(mat: ShaderMaterial, centre: Vector2, r: float, capsules: Array) -> void:
	var a := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var b := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var rr := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var count := 0
	for cap in capsules:
		if count >= 4:
			break
		var pa: Vector2 = (cap[0] - centre) / r
		var pb: Vector2 = (cap[1] - centre) / r
		var rad: float = float(cap[2]) / r
		# Skip a ship nowhere near this disc (its nearest point to the centre is out of reach).
		var ba := pb - pa
		var h := clampf(-pa.dot(ba) / maxf(ba.dot(ba), 0.000001), 0.0, 1.0)
		if (pa + ba * h).length() - rad > 1.1:
			continue
		a[count] = pa
		b[count] = pb
		rr[count] = rad
		count += 1
	mat.set_shader_parameter("occluder_count", count)
	mat.set_shader_parameter("occ_a", a)
	mat.set_shader_parameter("occ_b", b)
	mat.set_shader_parameter("occ_r", rr)


## One recoloured icon TextureRect + one soft halo TextureRect for a capital world's own
## insignia — see FACTION_INSIGNIA's doc comment and ui/insignia_recolor.gdshader's header.
## The icon gets its own ShaderMaterial instance (not shared) since every world's insignia
## needs its own current tint, same reason _make_atmosphere_glow_node's ColorRects each get
## their own material rather than one shared across every world.
func _make_insignia_nodes(faction: StringName) -> Dictionary:
	var glow := TextureRect.new()
	glow.texture = _insignia_glow_tex()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	_insignia_layer.add_child(glow)

	var icon := TextureRect.new()
	icon.texture = FACTION_INSIGNIA[faction]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = INSIGNIA_RECOLOR_SHADER
	mat.set_shader_parameter("use_luminance_mask", true)
	icon.material = mat
	icon.visible = false
	_insignia_layer.add_child(icon)

	return {"glow": glow, "icon": icon}


## A soft white radial-gradient texture shared by every world's insignia halo — modulated
## per-instance to that world's current owner colour at draw time. A plain white source, so
## ordinary multiply-modulate tinting works fine here, unlike the insignia artwork itself
## (see ui/insignia_recolor.gdshader's header for why that needs a real recolour, not a tint).
func _insignia_glow_tex() -> GradientTexture2D:
	if _insignia_glow_texture == null:
		var tex := GradientTexture2D.new()
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		# `2026-09-15` second pass: the halo's own alpha (0.85 at centre) was bright enough
		# to wash the icon out rather than sit behind it — cut well down, on top of
		# INSIGNIA_GLOW_SCALE shrinking its overall size.
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray(
			[Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
		tex.gradient = grad
		_insignia_glow_texture = tex
	return _insignia_glow_texture


## Called every _process() frame: floats each capital world's insignia (icon + soft halo)
## just north of it — clear of the ownership ring, never overlapping the planet itself, per
## the user's own "above or to the north, not on top of them" — tinted player-relative same
## as that ring (a captured capital's insignia flips colour the instant the ring does, no
## separate logic needed), and faded by the same _overlay_fade() every other galaxy-view-
## scale 2D element already uses.
func _update_insignia_icons() -> void:
	if _camera == null or state == null:
		return
	var fade := _overlay_fade()
	for id in _insignia_icon_nodes:
		var icon: TextureRect = _insignia_icon_nodes[id]
		var glow: TextureRect = _insignia_glow_nodes[id]
		var planet := state.get_planet(id)
		if planet == null:
			icon.visible = false
			glow.visible = false
			continue
		var r := _screen_radius(planet)
		if r < EDGE_GLOW_MIN_SCREEN_R:
			icon.visible = false
			glow.visible = false
			continue

		var icon_d := r * INSIGNIA_SCALE
		var center := _screen_position(planet) - Vector2(0.0, r + INSIGNIA_NORTH_GAP + icon_d * 0.5)
		var col := _faded(_owner_color(planet.owner), fade)

		icon.size = Vector2.ONE * icon_d
		icon.position = center - icon.size * 0.5
		icon.visible = true
		var mat: ShaderMaterial = icon.material
		mat.set_shader_parameter("tint", col)
		mat.set_shader_parameter("opacity", INSIGNIA_OPACITY)

		var glow_d := icon_d * INSIGNIA_GLOW_SCALE
		glow.size = Vector2.ONE * glow_d
		glow.position = center - glow.size * 0.5
		glow.modulate = col
		glow.visible = true


## A planet north of the galactic core (positive layout Y) reads smaller, as if further
## from the camera — a faked distance cue on an otherwise flat plane (see PLANET_NORTH_
## SCALE_MIN's comment). South of the core (layout Y <= 0), unchanged. Lane star nodes are
## deliberately excluded — the user asked for planets specifically.
func _planet_depth_scale(p: Planet) -> float:
	var y: float = _campaign_layout().get(p.id, Vector2.ZERO).y
	return lerpf(1.0, PLANET_NORTH_SCALE_MIN, clampf(y, 0.0, 1.0))


## Keeps every capturable world's glow colour matching its owner — neutral off-white,
## Republic blue, Separatist red — and respects the current battle-zoom fade at the same
## time (so a capture mid-zoom doesn't pop back to full brightness). Reads state.planets
## only; never decides who owns what.
func _sync_planet_glow_colors() -> void:
	if state == null:
		return
	var glow_factor := lerpf(1.0, PLANET_GLOW_ZOOM_FADE, _zoom_t)
	for p: Planet in state.planets.values():
		if not p.capturable:
			continue
		var node: Node3D = _planet_nodes.get(p.id)
		if node == null or not (node is Sprite3D):
			continue
		var c := _campaign_glow(p.owner)
		var base := Color(c.r * PLANET_GLOW_ENERGY, c.g * PLANET_GLOW_ENERGY, c.b * PLANET_GLOW_ENERGY)
		_planet_glow_base_modulate[p.id] = base
		(node as Sprite3D).modulate = base * glow_factor


## A billboard glow. `stops` is a list of [offset, Color] for the radial gradient (centre
## → edge). `span` is its world size; `energy` over-brightens the modulate so it feeds bloom.
func _glow_sprite(span: float, tint: Color, energy: float, stops: Array) -> Sprite3D:
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in stops:
		offs.append(st[0])
		cols.append(st[1])
	grad.offsets = offs
	grad.colors = cols
	tex.gradient = grad
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	# Starts NOT depth-tested — always-on-top, so at the resting galaxy view (zoom_t = 0) a
	# world reads as a glowing point of light rather than a barely-visible speck behind its
	# own halo. _apply_zoom flips this to depth-tested (occluded by the body / a parked ship)
	# once the camera crosses GLOW_FRONT_ZOOM_T zooming in on a battle, so the model reads
	# clearly close up, the soft outer falloff still haloing its silhouette. Hyperlane stars
	# have no body, so the flip is invisible on them either way.
	s.no_depth_test = true
	s.pixel_size = span / 128.0
	s.modulate = Color(tint.r * energy, tint.g * energy, tint.b * energy)
	return s


## A hyperlane star: a small solid white point that bleeds into a glow.
func _star_sprite(span: float = STAR_GLOW, energy: float = 2.2) -> Sprite3D:
	return _glow_sprite(span, Color.WHITE, energy, [
		[0.0, Color(1, 1, 1, 1.0)], [0.28, Color(1, 1, 1, 0.7)],
		[0.6, Color(0.8, 0.9, 1.0, 0.18)], [1.0, Color(0.7, 0.85, 1.0, 0.0)]])


## The galaxy core's own physical star — bigger/brighter than a hyperlane star, parked at
## GALAXY_CORE_POS. Deliberately outside _planet_nodes so nothing ever dims it.
func _build_core_star() -> void:
	var star := _star_sprite(CORE_STAR_GLOW, CORE_STAR_ENERGY)
	star.position = GALAXY_CORE_POS
	star.scale = Vector3(CORE_STAR_ASPECT.x, CORE_STAR_ASPECT.y, 1.0)
	_galaxy_root.add_child(star)


## A world: a soft glow — off-white/yellow while neutral, the owning faction's colour once
## captured (see _sync_planet_glow_colors) — clearly bigger than a hyperlane star, with a
## barely-there lit body (model / textured sphere) at its heart. The gradient texture
## itself is colourless (white, alpha-only falloff); the actual colour is applied purely
## via modulate so it can change at runtime without rebuilding the texture.
func _planet_body(p: Planet) -> Node3D:
	var holder := _glow_sprite(PLANET_GLOW, GLOW_NEUTRAL, PLANET_GLOW_ENERGY, [
		[0.0, Color(1, 1, 1, 0.95)],
		[0.20, Color(1, 1, 1, 0.6)],
		[0.46, Color(1, 1, 1, 0.16)],
		[1.0, Color(1, 1, 1, 0.0)]])
	var art: Dictionary = _campaign_planet_art().get(p.id, {})

	var body: Node3D = null
	if art.has("model"):
		body = _load_scaled_model(String(art["model"]), PLANET_MESH_R * 2.0)
		if body != null:
			if bool(art.get("dedupe_meshes", false)):
				_dedupe_coincident_meshes(body)
			if art.has("rot"):
				body.rotation_degrees = art["rot"]
			else:
				body.rotate_y(randf() * TAU)
			_apply_model_textures(body, art)   # tex/normal/spec onto an export with none wired
			if art.has("tint"):
				_tint_planet_model(body, art["tint"])
	if body == null:
		var mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = PLANET_MESH_R
		sm.height = PLANET_MESH_R * 2.0
		sm.radial_segments = 32
		sm.rings = 16
		mesh.mesh = sm
		mesh.rotation_degrees = Vector3(0.0, randf() * 360.0, 12.0)
		var mat := StandardMaterial3D.new()
		# Depth test ON (like the ships) so the sky layers — which now depth-test — sit
		# behind the world, and so a fleet parked in front of its planet occludes it.
		if art.has("tex") or art.has("roughness") or art.has("bump") or art.has("normal"):
			# True to the source texture — no recolouring, no emission baked on top of
			# it (that used to feed the diffuse straight into emission too, which the
			# scene's bloom blew out into a washed-out colour). The core light does the
			# shading; the glow sprite supplies the colour around it. `tint` multiplies
			# on top when present (Kamino: darkens/saturates an already-correct texture;
			# Naboo: no texture at all here — see PLANET_ART — so tint IS the colour).
			mat.roughness = float(art.get("roughness_value", 0.75))   # a little specular sheen rather than fully matte
			if art.has("tex"):
				mat.albedo_texture = load(String(art["tex"]))
			if art.has("tint"):
				mat.albedo_color = art["tint"]
			if art.has("roughness"):
				# 1.0 so the texture has the full 0-1 range to work with — real per-pixel
				# variation (water vs. land vs. cloud) instead of one flat value, and a
				# proper soft specular sheen wherever the surface is actually smooth.
				mat.roughness = 1.0
				mat.roughness_texture = load(String(art["roughness"]))
			if art.has("normal"):
				# A real tangent-space normal map — the dropped-in "_full" packs ship one as
				# their "(bump)" file (verified mid-blue ~128/128/255), and Scarif's water
				# planet has a proper one. This does the per-pixel relief lighting; cheaper
				# and cleaner up close than parallax, so a world with a normal map skips the
				# heightmap branch below.
				mat.normal_enabled = true
				mat.normal_scale = float(art.get("normal_scale", 1.0))
				mat.normal_texture = load(String(art["normal"]))
			elif art.has("bump"):
				# Only a grayscale height map available (Naboo's pack has no normal map) —
				# StandardMaterial3D's parallax/heightmap input is the right fit for that,
				# not normal_texture, which would misread it.
				mat.heightmap_enabled = true
				mat.heightmap_texture = load(String(art["bump"]))
				mat.heightmap_scale = 6.0
		else:
			# No real art for this world — a flat tint needs a touch of emission or its
			# unlit hemisphere reads as a black silhouette.
			mat.roughness = 0.75
			var tint: Color = art.get("tint", PLANET_FALLBACK_TINT)
			mat.albedo_color = tint
			mat.emission_enabled = true
			mat.emission = tint
			mat.emission_energy_multiplier = 0.4
		mesh.material_override = mat
		body = mesh
	# Nudged in FRONT of the glow sprite's billboard plane so the (now depth-tested) glow is
	# occluded by the body — the model reads clearly close up, with the glow haloing its
	# edge. At rest the world is still tiny inside a big soft halo; battle zoom fades the
	# halo further (see _apply_zoom + PLANET_GLOW_ZOOM_FADE).
	body.position = Vector3(0.0, 0.0, 0.04)
	holder.add_child(body)
	# The atmosphere itself is a 2D screen-space overlay now (_atmosphere_tint /
	# _update_atmosphere_glows / ui/planet_edge_glow.gdshader), not a 3D shell — see that
	# shader's header for why. This just records whether/what colour this world wants one;
	# _build_map_3d creates the actual 2D node once this holder's screen position exists.
	if not bool(art.get("no_atmosphere", false)):
		_atmosphere_tint[p.id] = art.get("atmosphere_tint", ATMOSPHERE_TINT_DEFAULT)
	return holder


## Instance a model scene and scale/centre it to `diameter` (its longest AABB dimension
## becomes `diameter`). null if it won't load — an unsupported source format (e.g. .3ds,
## which Godot's importer doesn't read) included. Shared by planet bodies and fleet ships.
func _load_scaled_model(path: String, diameter: float) -> Node3D:
	# ResourceLoader.exists checks for a registered loader without logging — plain load()
	# on a format Godot doesn't import (e.g. .3ds) prints an ERROR to the console.
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var inst := packed.instantiate()
	if inst == null:
		return null
	var holder := Node3D.new()
	holder.add_child(inst)
	var box := _aggregate_aabb(inst, inst.transform)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.0:
		var s := diameter / longest
		inst.scale = Vector3(s, s, s)
		inst.position = -box.get_center() * s
	_prep_model_surfaces(inst)
	return holder


## The DS2 station FBX has NO true duplicate meshes (measured: every piece has a distinct
## triangle count) — but it IS built as ~4 near-concentric spherical shells at almost the
## same radius, which z-fight into a flickering mess, plus two zero-thickness garbage
## planes. So: free the degenerate planes, then **nest the concentric shells** — biggest
## stays full size, each smaller one is scaled in a couple percent more (about the model
## centre, not its FBX node origin) so the layers sit cleanly inside the outer hull instead
## of fighting it. Offset detail meshes (the dish, greebles) are left alone.
func _dedupe_coincident_meshes(node: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes.append(n)
		for c in n.get_children():
			stack.append(c)

	var shells: Array[MeshInstance3D] = []   # concentric, roughly spherical, near the centre
	for mi in meshes:
		var ab := mi.mesh.get_aabb()
		var longest := maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		var shortest := minf(ab.size.x, minf(ab.size.y, ab.size.z))
		if longest <= 0.0 or shortest / longest < 0.02:
			mi.get_parent().remove_child(mi)   # a degenerate plane — pure z-fight noise
			mi.queue_free()
			continue
		var centred := ab.get_center().length() < longest * 0.15
		var spherical := shortest / longest > 0.8
		if centred and spherical:
			shells.append(mi)

	shells.sort_custom(func(a, b):
		return a.mesh.get_aabb().size.length() > b.mesh.get_aabb().size.length())
	for i in shells.size():
		if i == 0:
			continue
		var mi := shells[i]
		var f := 1.0 - i * 0.03
		var off := mi.transform.basis * mi.mesh.get_aabb().get_center()   # local centre → parent
		mi.scale *= f
		mi.position += (1.0 - f) * off   # keep the shell centred while it shrinks


## Per-instance material fixups for a loaded model (ship / planet).
##  - **Depth test stays ON.** An earlier note here claimed GL Compatibility never
##    composites depth-tested opaque geometry in this scene — that was a misdiagnosis
##    (verified 2026-09-10: the ISD renders solid with depth testing, and see-through
##    with `no_depth_test` because then its own far hull draws over the near hull).
##  - Force `CULL_BACK`: both ship models import every surface double-sided
##    (`cull_mode` DISABLED), which with the punchy contrast just adds z-fighting noise;
##    a solid hull's interior is never meant to show.
##  - `DEPTH_DRAW_ALWAYS` so a model still writes depth even if a surface came in
##    flagged transparent (some greeble materials do), keeping the hull self-sorting.
func _prep_model_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				# BaseMaterial3D covers StandardMaterial3D and ORMMaterial3D (what
				# Godot's glTF/FBX importer picks for an ORM texture setup).
				if mat is BaseMaterial3D:
					var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
					m.cull_mode = BaseMaterial3D.CULL_BACK
					m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
					# The scene's core light does all the shading; a baked-emissive hull just
					# blows out into the bloom as a flat white blob (DS2 especially).
					m.emission_enabled = false
					# The new DS2 FBX (2026-09-12) imports with vertex_color_use_as_albedo
					# TRUE on every surface despite the mesh carrying no vertex colour array
					# at all (confirmed directly: ArrayMesh surface format has no
					# ARRAY_FORMAT_COLOR bit) — the shader still multiplies the albedo by
					# whatever's in that unpopulated attribute slot. A real, worth-keeping
					# fix on its own (multiplying by a vertex colour the mesh doesn't have
					# is never correct for any model), but NOT what was behind DS2's warm
					# cast — tested in isolation, no visible effect either way; see the
					# `unshaded` note on death_star_ii's PLANET_ART entry for how that was
					# actually worked around. (A `specular = 0.0` was tried alongside it for
					# the same investigation — turned out to be a no-op Godot 3 property name
					# that doesn't exist on Godot 4's BaseMaterial3D at all, "remapped
					# parameter not found" on every surface — removed; that's also why it had
					# "zero visible effect" earlier. `metallic_specular` is the Godot 4
					# equivalent, not worth adding here since roughness already drives how
					# matte a hull reads.)
					m.vertex_color_use_as_albedo = false
					# Fine greeble/panel-line textures (DS2, the ISD) read "crunchy"/aliased up
					# close — traced to the imported textures' own `.import` files having
					# `mipmaps/generate=false` (fixed there), plus the default texture filter
					# leaving out anisotropic sampling, which matters more here than usual
					# since the camera looks down at every hull from an angle, not straight-on.
					m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					mi.set_surface_override_material(i, m)
	for child in node.get_children():
		_prep_model_surfaces(child)


## Multiplies `tint` onto each surface's own albedo_color under `node`, the same way
## `tint` behaves for a textured body (see PLANET_ART) — it was a straight replacement
## briefly, which flattened Felucia.fbx's two authored materials (near-white/orange) into
## one solid colour and read as a painted ball with no model detail at all. Multiplying
## keeps their split: the near-white surface takes the tint almost as-is, the orange one
## comes out a darker, differently-shaded colour, so the model's own shape still reads.
## Runs after _prep_model_surfaces, so it edits the already-duplicated per-instance
## materials.
func _tint_planet_model(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					bm.albedo_color = bm.albedo_color * tint
	for child in node.get_children():
		_tint_planet_model(child, tint)


## Wires up an explicit texture set (FLEET_ART's tex/normal/roughness/metallic/ao) onto
## every mesh surface under `node` — for a model whose own export carries no textures.
## Runs after _prep_model_surfaces, so it edits the already-duplicated per-instance
## materials, not a shared imported resource.
##
## `unshaded` (see death_star_ii): swaps the surface to `model_fake_lit.gdshader` instead of
## tweaking the BaseMaterial3D in place — a from-scratch directional shade (geometry normal
## vs. the galactic core) that keeps a real lit/shadow terminator without going anywhere near
## Godot's actual lit pipeline, where this model's colour was being altered in a way no
## individual material property ever explained.
func _apply_model_textures(node: Node, art: Dictionary) -> void:
	if not (art.has("tex") or art.has("normal") or art.has("roughness") or art.has("metallic") or art.has("ao") or art.has("unshaded")):
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				if bool(art.get("unshaded", false)):
					# `art["tex"]` overrides with one shared texture for every surface (DS2 —
					# a single diffuse across the whole model); otherwise each surface keeps
					# its OWN already-correct texture (Starkiller Base — 7+ distinct
					# per-surface materials baked into the model itself, e.g. Black_Ice vs.
					# Planet_Surface1 vs. Metalic_Texture) by reading it back off the
					# surface's current material before replacing it with the shader.
					var albedo_tex: Texture2D = null
					if art.has("tex"):
						albedo_tex = load(String(art["tex"]))
					else:
						var current := mi.get_active_material(i)
						if current is BaseMaterial3D:
							albedo_tex = (current as BaseMaterial3D).albedo_texture
					var sm := ShaderMaterial.new()
					sm.shader = MODEL_FAKE_LIT_SHADER
					if albedo_tex != null:
						sm.set_shader_parameter("albedo_tex", albedo_tex)
					sm.set_shader_parameter("tint", Color(art.get("tint", Color.WHITE)))
					sm.set_shader_parameter("light_world_pos", GALAXY_CORE_POS)
					mi.set_surface_override_material(i, sm)
					continue
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var m := mat as BaseMaterial3D
					if art.has("tex"):
						m.albedo_texture = load(String(art["tex"]))
						m.albedo_color = Color.WHITE
					if art.has("normal"):
						m.normal_enabled = true
						m.normal_texture = load(String(art["normal"]))
					if art.has("roughness"):
						m.roughness_texture = load(String(art["roughness"]))
					if art.has("metallic"):
						m.metallic = 1.0
						m.metallic_texture = load(String(art["metallic"]))
					if art.has("ao"):
						m.ao_enabled = true
						m.ao_texture = load(String(art["ao"]))
	for child in node.get_children():
		_apply_model_textures(child, art)


## Combined AABB of every VisualInstance3D under `node`, in `node`'s parent space.
func _aggregate_aabb(node: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var seeded := false
	if node is VisualInstance3D:
		var local: AABB = (node as VisualInstance3D).get_aabb()
		out = xform * local
		seeded = true
	for child in node.get_children():
		if child is Node3D:
			var child_box := _aggregate_aabb(child, xform * (child as Node3D).transform)
			if child_box.size != Vector3.ZERO:
				out = out.merge(child_box) if seeded else child_box
				seeded = true
	return out


## --- per-campaign visual sets (Clone Wars constants above; GCW_* set added alongside) ---
## `state` is set before _build_map_3d / _sync_fleet_nodes / _sync_planet_glow_colors run,
## and a New Campaign swaps it then rebuilds the map — so these key off it directly.
func _is_gcw() -> bool:
	return state != null and state.campaign_id == &"galactic_civil_war"

func _is_sequel() -> bool:
	return state != null and state.campaign_id == &"sequel_era"


## Whichever faction is "you" right now — the one whose fleets you can click, whose
## treasury the buy/reinforce buttons spend from, whose colour is blue, whose capital being
## lost means DEFEAT. Single player: always `player_faction` (fixed for the whole war,
## including while the AI's own attack on the player is pending — the human is always the
## human, whoever's "turn" it nominally is). **Local two player** (`state.two_player`, no
## `_gc_net`): always `active_faction`, since control is physically handed back and forth
## each phase and whichever side just moved a fleet is definitionally the one now at the
## keyboard — this is what makes the map's ownership colours, the turn banner, and every
## "you attack/defend" framing flip correctly each time a hotseat phase changes hands, with
## no special-casing needed anywhere else. **Online two player** (`_gc_net != null`): always
## `_gc_net.my_faction` — the OPPOSITE of local hotseat's reasoning, and deliberately so:
## each human has their own permanent screen here, so "you" must stay fixed to whichever
## side that screen is playing even while it's the other (remote) human's turn, exactly
## like single player's fixed `player_faction` — the map must never flip colours out from
## under a networked player just because it isn't their turn right now.
func _current_seat_faction() -> StringName:
	if state == null:
		return Faction.REPUBLIC
	if _gc_net != null:
		return _gc_net.my_faction
	if state.two_player:
		return state.active_faction
	return state.player_faction


func _campaign_layout() -> Dictionary:
	if _is_gcw():
		return GCW_LAYOUT
	if _is_sequel():
		return SEQUEL_LAYOUT
	return GALAXY_LAYOUT

func _campaign_planet_art() -> Dictionary:
	if _is_gcw():
		return GCW_PLANET_ART
	if _is_sequel():
		return SEQUEL_PLANET_ART
	return PLANET_ART

## Player-relative ownership colour, shared by the 3D glow and the 2D overlay: whoever is
## currently "you" (_current_seat_faction — in two-player, flips with each hotseat phase)
## is blue, the enemy red, everyone else neutral — in any campaign.
func _campaign_glow(owner: StringName) -> Color:
	if state != null and owner == _current_seat_faction():
		return GLOW_FRIENDLY
	if state != null and owner == Faction.opponent(_current_seat_faction()):
		return GLOW_HOSTILE
	return GLOW_NEUTRAL

func _owner_color(owner: StringName) -> Color:
	if state != null and owner == _current_seat_faction():
		return Tokens.FRIENDLY
	if state != null and owner == Faction.opponent(_current_seat_faction()):
		return Tokens.HOSTILE
	return Tokens.NEUTRAL

func _campaign_fleet_art(owner: StringName) -> Dictionary:
	if _is_gcw():
		return GCW_FLEET_ART.get(owner, {})
	if _is_sequel():
		return SEQUEL_FLEET_ART.get(owner, {})
	return FLEET_ART.get(owner, {})

func _campaign_fleet_tint(owner: StringName) -> Color:
	# GCW hulls (and the rare CW model-load fallback) take the player-relative colour.
	return _owner_color(owner)


## A world's point in 3D space — scattered across the galaxy image from the campaign's
## layout, just in front of the layer stack (z = 0.4).
func _planet_world_pos(p: Planet) -> Vector3:
	return _layout_world_pos(_campaign_layout().get(p.id, Vector2.ZERO))


## Same mapping as _planet_world_pos, for a raw normalised [-1,1] point rather than a
## real Planet — used for the purely decorative hyperlane markers.
func _layout_world_pos(n: Vector2) -> Vector3:
	return Vector3(n.x * MAP_SPREAD.x, n.y * MAP_SPREAD.y + MAP_Y_OFFSET, 0.4)


# --- Fleet 3D visuals ----------------------------------------------------------

## Keeps one ship node per Fleet in sync with `state.fleets` — spawning new ones,
## gliding moved ones to their new world, and dissolving ones that no longer exist.
## Purely a read of state; it never decides where a fleet may go.
func _sync_fleet_nodes() -> void:
	if state == null or _fleets_root == null:
		return

	# Group by the world each fleet currently reads as being at, so co-located fleets
	# (e.g. attacker + defender during a pending battle) split into an orbit together.
	var by_planet: Dictionary = {}   ## planet id -> Array[Fleet]
	for f: Fleet in state.fleets.values():
		var loc := _fleet_display_location(f)
		if not by_planet.has(loc):
			by_planet[loc] = []
		(by_planet[loc] as Array).append(f)

	var live_ids: Dictionary = {}
	for planet_id in by_planet:
		var group: Array = by_planet[planet_id]
		group.sort_custom(func(a: Fleet, b: Fleet) -> bool: return String(a.id) < String(b.id))
		for i in group.size():
			var f: Fleet = group[i]
			live_ids[f.id] = true
			var target := _fleet_world_pos(planet_id, i, group.size())
			if not _fleet_nodes.has(f.id):
				_spawn_fleet_node(f, target)
			else:
				var prev_target: Vector3 = _fleet_targets.get(f.id, target)
				if not prev_target.is_equal_approx(target):
					_move_fleet_node(_fleet_nodes[f.id], target)
			_fleet_targets[f.id] = target

	for id in _fleet_nodes.keys().duplicate():
		if not live_ids.has(id):
			_despawn_fleet_node(id)


## Where a fleet appears right now. Normally its actual world — except the attacker in a
## pending battle, shown parked at the contested world for the fight's duration; state
## itself doesn't move it there until the result comes back (or moves it back if the
## match is abandoned), and this is a display-only stand-in for that gap.
func _fleet_display_location(f: Fleet) -> StringName:
	if state.has_pending_battle():
		var req := Battle.Request.from_dict(state.pending_battle)
		if f.id == req.attacker_fleet_id:
			return req.planet_id
	return f.location


## A parked ship's position: a small ring around its world, split evenly among however
## many fleets are camped there right now, nudged toward the camera so ships read in
## front of the glow.
func _fleet_world_pos(planet_id: StringName, index: int, count: int) -> Vector3:
	var planet := state.get_planet(planet_id)
	var centre := _planet_world_pos(planet) if planet != null else Vector3.ZERO
	var angle := (TAU / maxf(float(count), 1.0)) * index
	var offset := Vector3(cos(angle), sin(angle) * 0.4, 0.0) * FLEET_ORBIT_R
	return centre + offset + Vector3(0.0, 0.0, 0.55)


func _spawn_fleet_node(f: Fleet, target: Vector3) -> void:
	# The holder carries world position + zoom scale; the visual body carries the spawn/
	# despawn scale and the galaxy-view downward drop, so those animations never fight the
	# zoom compensation (or each other).
	var holder := Node3D.new()
	holder.name = "Fleet_%s" % f.id
	holder.position = target
	var fleet_scale := _fleet_zoom_scale(_zoom_t)
	holder.scale = Vector3.ONE * fleet_scale
	var body := _build_fleet_model(f.owner)
	# Keep the drop a constant world-space offset; the holder's zoom compensation must not
	# magnify it (or the ship drifts into the world's name at galaxy view).
	body.position = Vector3(0.0, -_fleet_vertical_drop(_zoom_t) / fleet_scale, 0.0)
	body.scale = Vector3.ZERO
	holder.add_child(body)
	holder.set_meta("body", body)
	_fleets_root.add_child(holder)
	_fleet_nodes[f.id] = holder
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ONE, FLEET_SPAWN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _move_fleet_node(node: Node3D, target: Vector3) -> void:
	var tw := create_tween()
	tw.tween_property(node, "position", target, FLEET_MOVE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _despawn_fleet_node(id: StringName) -> void:
	var node: Node3D = _fleet_nodes.get(id)
	_fleet_nodes.erase(id)
	_fleet_targets.erase(id)
	if node == null or not is_instance_valid(node):
		return
	var body: Node3D = node.get_meta("body", null) as Node3D
	if body == null or not is_instance_valid(body):
		node.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ZERO, FLEET_SPAWN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)


## A faction's capital ship — Venator / Dreadnought (Clone Wars), Star Destroyer / Mon
## Calamari cruiser (GCW) — scaled to FLEET_SHIP_LEN. A model that won't load falls back to
## the player-relative tinted hull (see _campaign_fleet_art / _campaign_fleet_tint).
func _build_fleet_model(owner: StringName) -> Node3D:
	var art: Dictionary = _campaign_fleet_art(owner)
	var body: Node3D = null
	if art.has("model"):
		body = _load_scaled_model(String(art["model"]), FLEET_SHIP_LEN)
		if body != null:
			if art.has("rot"):
				body.rotation_degrees = art["rot"]
			_apply_model_textures(body, art)
			if art.has("hull"):
				_apply_hull_finish(body, art["hull"])
			# The core OmniLight's cube shadow map is far too coarse for a ship-sized caster: it
			# self-shadows a hull into blocky tiles/squares (Venator, 2026-09-20). No hull-on-hull
			# shadows — the lit/dark terminator comes from the surface shading alone.
			_disable_shadow_casting(body)
	if body == null:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(FLEET_SHIP_LEN, FLEET_SHIP_LEN * 0.22, FLEET_SHIP_LEN * 0.42)
		mesh.mesh = box
		var tint: Color = _campaign_fleet_tint(owner)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.6
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 1.4
		mesh.material_override = mat
		body = mesh
	_set_fleet_layer(body)
	return body


## A brushed-metal-ish hull finish for a flat-shaded model, from a FLEET_ART `"hull"` dict
## `{albedo: Color multiplied onto each surface, roughness, specular, metallic}`. `2026-09-19`
## (playtest: the Venator "looks like plastic"): a glossy near-white surface with a tight
## specular reads as moulded plastic. Real metal needs a reflection probe this scene doesn't
## have (a fully `metallic` surface renders black — see PLANET_ART's note), so this fakes the
## look instead: a duller steel-grey albedo, HIGH roughness (a broad, soft "dull shine"
## highlight instead of a hard pinpoint one), a hint of metallic, and a touch of specular.
const FLEET_LIGHT_LAYER := 2
const FLEET_LIGHT_COLOR := Color(0.94, 0.96, 1.0)


## Moves a ship model onto the fleet render layer, so only the cool fleet light touches it.
func _set_fleet_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = FLEET_LIGHT_LAYER
	for c in node.get_children():
		_set_fleet_layer(c)


func _disable_shadow_casting(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_disable_shadow_casting(c)


func _apply_hull_finish(node: Node, spec: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(i)
				if mat == null:
					mat = mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
					m.albedo_color = m.albedo_color * Color(spec.get("albedo", Color.WHITE))
					m.roughness = float(spec.get("roughness", m.roughness))
					m.metallic = float(spec.get("metallic", m.metallic))
					m.metallic_specular = float(spec.get("specular", m.metallic_specular))
					mi.set_surface_override_material(i, m)
	for c in node.get_children():
		_apply_hull_finish(c, spec)


# --- Battle camera ---------------------------------------------------------------

## Zooms the camera onto a pending battle's world (and back out once it resolves),
## fading the galaxy layers to keep the world legible. Driven purely by
## `state.has_pending_battle()` / `pending_battle.planet_id` — no rule-deciding here.
## A new battle appeared. If the AI moved a fleet in and attacked one of the player's
## worlds, hold on the galaxy map for a beat (BATTLE_INTRO_MS) — camera out, fleet gliding
## in, a plain-language notice — before the camera zooms in and the KYBER controls appear.
## The player's own attacks are entered deliberately, so they skip this.
func _check_battle_intro() -> void:
	var battling := state.has_pending_battle()
	var id := String(state.pending_battle.get("id", "")) if battling else ""
	if id == _seen_battle_id:
		return
	_seen_battle_id = id
	_battle_intro_end_ms = 0
	if not battling:
		return
	if StringName(state.pending_battle.get("attacker", &"")) == _current_seat_faction():
		return
	var attacker := StringName(state.pending_battle.get("attacker", &""))
	var planet := state.get_planet(StringName(state.pending_battle.get("planet_id", &"")))
	_battle_intro_end_ms = Time.get_ticks_msec() + BATTLE_INTRO_MS
	_notice = "The %s attacks %s — a fleet has moved in." % [
		Faction.short_name(attacker),
		planet.display_name if planet != null else "your world"]


func _battle_intro_playing() -> bool:
	return _battle_intro_end_ms > 0 and Time.get_ticks_msec() < _battle_intro_end_ms


func _update_battle_zoom() -> void:
	if state == null:
		return
	if state.has_pending_battle() and not _battle_intro_playing():
		var planet_id := StringName(state.pending_battle.get("planet_id", &""))
		if planet_id != _zoom_planet_id:
			_zoom_planet_id = planet_id
			var planet := state.get_planet(planet_id)
			if planet != null:
				_zoom_target_pos = _planet_world_pos(planet)
				_zoom_target_pos_raw = _zoom_target_pos   # so post-battle scrolling doesn't ease from a stale point
			_start_zoom(1.0)
	elif _zoom_planet_id != &"":
		_zoom_planet_id = &""
		_start_zoom(0.0)


## Only used by the battle-zoom path now — a deterministic one-shot transition to/from a
## known world, which suits a tween. Manual scroll zoom eases continuously in _process
## instead (see VIEW_ZOOM_SMOOTH_RATE); this keeps _view_zoom_target in step so scrolling
## right after a battle starts from the right baseline instead of fighting a stale target.
func _start_zoom(target_t: float, duration: float = BATTLE_ZOOM_TIME) -> void:
	_view_zoom_target = target_t
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	# `2026-09-13`: TRANS_SINE/EASE_IN_OUT eases IN at the start too — a sine ease-in's first
	# ~20-30% barely moves at all before accelerating, which read as "a big delay before it
	# starts." EASE_OUT alone starts moving immediately and decelerates into the landing —
	# no stall at the front, still settles smoothly. TRANS_CUBIC's own EASE_OUT curve front-
	# loads MOST of its motion into a small initial fraction of the duration, though, which at
	# BATTLE_ZOOM_TIME's original 1.3s read as "way too fast" (a near-instant snap, then a
	# long slow coast) — TRANS_QUAD is a gentler deceleration, spreading the visible motion
	# out over more of the duration instead of front-loading almost all of it.
	_zoom_tween.tween_method(_apply_battle_zoom, _zoom_t, target_t, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Manual zoom: each wheel notch re-aims _zoom_target_pos at the world point under the
## cursor (via the camera's own projection, so it stays correct at any zoom level) and
## nudges _view_zoom_target toward/away from it — _process eases _zoom_t there smoothly.
## Disabled while a battle owns the camera. A no-op at either end of the range: without
## this check, further notches at max/min zoom keep re-aiming at the (drifting) cursor
## with nothing to ease toward yet, which reads as the camera creeping on its own.
func _handle_scroll_zoom(event: InputEventMouseButton) -> void:
	if state == null or _camera == null or state.has_pending_battle():
		return
	var delta := VIEW_ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -VIEW_ZOOM_STEP
	var new_target := clampf(_view_zoom_target + delta, 0.0, 1.0)
	if is_equal_approx(new_target, _view_zoom_target):
		return
	if new_target > _view_zoom_target:
		var depth := maxf(_camera.position.z - 0.4, 0.1)
		_zoom_target_pos_raw = _camera.project_position(event.position, depth)
	_view_zoom_target = new_target
	_zoom_planet_id = &""   # a free/manual zoom, not tied to any battle world
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()   # hand control to the per-frame easing in _process


## Applies one frame of the zoom: camera position/FOV lerp home → the battle world, and
## each galaxy layer fades by its own exponent (front layers slowest — see
## GALAXY_LAYER_FADE_EXP). Also drives `_draw`'s overlay, which projects off the camera.
func _apply_zoom(t: float) -> void:
	_zoom_t = t
	if _camera != null:
		var battle_pos := Vector3(
			_zoom_target_pos.x, _zoom_target_pos.y + BATTLE_CAMERA_Y_LIFT,
			_zoom_target_pos.z + BATTLE_CAMERA_DIST)
		_camera.position = CAMERA_HOME_POS.lerp(battle_pos, t)
		_camera.fov = lerpf(CAMERA_HOME_FOV, BATTLE_CAMERA_FOV, t)
		# Keep the background plate's apparent screen size and framing exactly what it was
		# at rest — dead centred on the camera, pushed back exactly as much as the FOV
		# narrows brings it forward. It should read as an infinitely-distant backdrop,
		# not something the camera dollies past; only its blur (the shader, driven by
		# zoom_t below) changes with zoom, to imply depth without actually moving.
		if _bg_node != null:
			var half_fov := deg_to_rad(_camera.fov * 0.5)
			var dist := _bg_dist_k / maxf(tan(half_fov), 0.001)
			_bg_node.position = Vector3(_camera.position.x, _camera.position.y, _camera.position.z - dist)
	if _bg_shader_mat != null:
		_bg_shader_mat.set_shader_parameter("zoom_t", t)
	for i in _sky_layers.size():
		var mat: ShaderMaterial = _sky_layers[i]
		if mat == null:
			continue
		var a: float
		if i >= GALAXY_LAYER_KEEP_FROM:
			a = lerpf(1.0, GALAXY_LAYER_MIN_OPACITY, t)
		else:
			var exponent: float = GALAXY_LAYER_FADE_EXP[i] if i < GALAXY_LAYER_FADE_EXP.size() else 6.0
			a = pow(clampf(1.0 - t, 0.0, 1.0), exponent)
		mat.set_shader_parameter("alpha_mult", a)
		mat.set_shader_parameter("blur_lod", t * GALAXY_LAYER_BLUR_LOD)
	if _galaxy_model_mat != null:
		# Fade the 3D disk out as the battle camera moves in — it would loom oddly otherwise.
		_galaxy_model_mat.set_shader_parameter("fade", pow(clampf(1.0 - t, 0.0, 1.0), 2.0))
	# Only real (capturable) worlds thin out to reveal what's underneath — hyperlane stars
	# stay identifiable at any zoom level, since a fleet still needs to see them to land.
	var glow_factor := lerpf(1.0, PLANET_GLOW_ZOOM_FADE, t)
	var glow_in_front := t < GLOW_FRONT_ZOOM_T
	for id in _planet_nodes:
		var n: Node3D = _planet_nodes[id]
		if not (n is Sprite3D):
			continue
		# In front of the body at the galaxy view, behind it once zoomed onto a battle (see
		# GLOW_FRONT_ZOOM_T) — every world's glow, not just capturable ones, so a hyperlane
		# star's own zoom-in reads the same way.
		(n as Sprite3D).no_depth_test = glow_in_front
		if not _planet_glow_base_modulate.has(id):
			continue
		var p := state.get_planet(id) if state != null else null
		if p != null and not p.capturable:
			continue
		(n as Sprite3D).modulate = (_planet_glow_base_modulate[id] as Color) * glow_factor
	# Ships are much larger at galaxy view (easy to miss among the planet glows) and shrink
	# back to their previous fully-zoomed-in size. The downward drop also fades out with zoom
	# so the battle view is unchanged. Applies at any zoom level (not just a battle's own
	# tween), including manual scroll-zoom.
	var fleet_scale := _fleet_zoom_scale(t)
	var fleet_drop := _fleet_vertical_drop(t)
	for id in _fleet_nodes:
		var fn: Node3D = _fleet_nodes[id]
		if not is_instance_valid(fn):
			continue
		fn.scale = Vector3.ONE * fleet_scale
		var body: Node3D = fn.get_meta("body", null) as Node3D
		if is_instance_valid(body):
			body.position.y = -fleet_drop / maxf(fleet_scale, 0.001)
	_update_decor_star_fade(t)
	queue_redraw()


## Decoration stars give parallax while the camera moves in, but a star very close to the
## battle camera would become a huge pale blob. Fade them out late in the zoom, after they
## have done their depth work.
func _update_decor_star_fade(t: float) -> void:
	var fade := 1.0 - smoothstep(0.55, 0.90, t)
	for star in _decor_star_nodes:
		if not is_instance_valid(star):
			continue
		star.visible = fade > 0.01
		var base: float = float(star.get_meta("base_alpha", 1.0))
		star.modulate.a = base * fade


## Zoom-level target for the photographic star plate. It only starts in the last two wheel
## notches: ~25% at 0.84, ~50% at 0.96, full at 1.0.
func _zoom_starfield_target(t: float) -> float:
	if t <= 0.78:
		return 0.0
	if t <= 0.84:
		return lerpf(0.0, 0.25, (t - 0.78) / 0.06)
	if t <= 0.96:
		return lerpf(0.25, 0.50, (t - 0.84) / 0.12)
	return lerpf(0.50, 1.0, (t - 0.96) / 0.04)


## Time-smoothed fade so the photo never snaps on when the wheel is spun quickly. Fading in
## is deliberately slow (a full 0→1 takes ~2 s; the last 0.5→1 takes ~1 s); fading out on the
## way back is quicker so normal galaxy view clears promptly.
func _update_zoom_starfield(delta: float) -> void:
	if _zoom_starfield == null or _zoom_starfield_mat == null:
		return
	var target := _zoom_starfield_target(_zoom_t)
	var rate := 0.50 if target > _zoom_starfield_alpha else 1.25
	_zoom_starfield_alpha = move_toward(_zoom_starfield_alpha, target, rate * delta)
	_zoom_starfield_mat.set_shader_parameter("fade", _zoom_starfield_alpha)
	_zoom_starfield.visible = _zoom_starfield_alpha > 0.002


## Apparent-size compensation for parked ships: large at galaxy view, the previous smaller
## size at full battle zoom.
func _fleet_zoom_scale(t: float) -> float:
	return lerpf(FLEET_ZOOM_SCALE_MIN, FLEET_ZOOM_SCALE_MAX,
		pow(clampf(1.0 - t, 0.0, 1.0), 1.35))


## How far below its world a ship sits at the current zoom. Fades to zero before the battle
## camera arrives, so the fully-zoomed-in framing is unchanged.
func _fleet_vertical_drop(t: float) -> float:
	return FLEET_DROP_Y * (1.0 - smoothstep(0.15, 0.80, t))


## The battle-zoom tween's own callback (see _start_zoom) — runs everything _apply_zoom
## already does (FOV, sky-layer fades, glow fades, fleet scale, all driven by `t` directly),
## then REPLACES the camera position it computed (a plain straight-line lerp) with a genuine
## quadratic Bézier curve through the same two endpoints — see BATTLE_SWOOP_FRACTION's own
## comment for why one continuous curve, not an add-on offset, is what actually reads as
## natural. Never used by manual scroll-zoom, which calls _apply_zoom directly and stays a
## plain, predictable, player-controlled pan — a curved path would fight the player's own
## scroll input instead of reading as deliberate.
func _apply_battle_zoom(t: float) -> void:
	_apply_zoom(t)
	if _camera == null:
		return
	var home := CAMERA_HOME_POS
	var battle_pos := Vector3(
		_zoom_target_pos.x, _zoom_target_pos.y + BATTLE_CAMERA_Y_LIFT,
		_zoom_target_pos.z + BATTLE_CAMERA_DIST)
	var path := battle_pos - home
	# The curve's own control point: the straight line's midpoint, pushed sideways (whichever
	# direction is perpendicular to the home->battle line and to world-up) by a fraction of
	# that line's own length. Falls back to a fixed side if home and battle_pos ever end up
	# exactly vertically stacked (cross product degenerates to zero) — never actually happens
	# with this map's fixed CAMERA_HOME_POS, but a real fallback costs nothing.
	var side := path.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.0001 else Vector3.RIGHT
	var control := (home + battle_pos) * 0.5 + side * (BATTLE_SWOOP_FRACTION * path.length())
	var tt := clampf(t, 0.0, 1.0)
	var u := 1.0 - tt
	_camera.position = home * (u * u) + control * (2.0 * u * tt) + battle_pos * (tt * tt)
	# The background plate's own repositioning (_apply_zoom, above) used the straight-line
	# position that's just been overwritten — redone here against the real curved position so
	# it doesn't lag/drift relative to the camera during the swoop specifically.
	if _bg_node != null:
		var half_fov := deg_to_rad(_camera.fov * 0.5)
		var dist := _bg_dist_k / maxf(tan(half_fov), 0.001)
		_bg_node.position = Vector3(_camera.position.x, _camera.position.y, _camera.position.z - dist)


## Give every preloaded Futura weight the engine default as a glyph fallback, so symbols
## Futura doesn't carry (✦ in the status line, ⚙ on the gear, → on the force buttons)
## still render instead of showing tofu.
func _init_fonts() -> void:
	var fb: Array[Font] = [ThemeDB.fallback_font]
	for f: FontFile in [Tokens.FONT_HEAVY, Tokens.FONT_BOLD, Tokens.FONT_MEDIUM,
			Tokens.FONT_BOOK, Tokens.FONT_LIGHT]:
		f.fallbacks = fb


## A project-wide `Theme`, applied once on the root Control so every Button and Label
## (topbar, modals, everywhere) picks it up — Futura throughout, and pill-shaped buttons
## instead of Godot's default squares, in the same dark/cool palette as the rest (Tokens).
func _build_button_theme() -> Theme:
	var theme_res := Theme.new()
	theme_res.set_default_font(Tokens.FONT_BOOK)
	theme_res.set_default_font_size(Tokens.FONT_SIZE_BASE)
	theme_res.set_font("font", "Button", Tokens.FONT_MEDIUM)
	theme_res.set_font_size("font_size", "Button", Tokens.FONT_SIZE_BASE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Tokens.SURFACE_EDGE
	# A radius bigger than any button is tall clamps to a half-circle each end — pills.
	normal.set_corner_radius_all(40)
	normal.set_content_margin(SIDE_LEFT, Tokens.SPACE_4)
	normal.set_content_margin(SIDE_RIGHT, Tokens.SPACE_4)
	normal.set_content_margin(SIDE_TOP, Tokens.SPACE_2)
	normal.set_content_margin(SIDE_BOTTOM, Tokens.SPACE_2)
	theme_res.set_stylebox("normal", "Button", normal)
	_theme_button_normal = normal

	var hover := normal.duplicate()
	hover.bg_color = Tokens.SURFACE_EDGE.lightened(0.18)
	theme_res.set_stylebox("hover", "Button", hover)
	_theme_button_hover = hover

	var pressed := normal.duplicate()
	pressed.bg_color = Tokens.SURFACE_EDGE.lightened(0.32)
	theme_res.set_stylebox("pressed", "Button", pressed)

	var disabled := normal.duplicate()
	disabled.bg_color = Tokens.SURFACE
	theme_res.set_stylebox("disabled", "Button", disabled)

	var focus := normal.duplicate()
	focus.bg_color = Tokens.SURFACE_EDGE
	focus.border_color = Tokens.TEXT
	focus.set_border_width_all(2)
	theme_res.set_stylebox("focus", "Button", focus)

	return theme_res


## Frosted glass fill for a bar (blur of what's behind, tinted dark) + a 1px accent edge.
func _bar_glass(bar: Control, edge_at_bottom: bool) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(Tokens.SURFACE, 0.72)
	var shader := load("res://ui/frosted_bar.gdshader")
	if shader != null:
		var smat := ShaderMaterial.new()
		smat.shader = shader
		bg.material = smat
		bg.color = Color.WHITE   # shader ignores it; keep the rect opaque-drawing
	bar.add_child(bg)
	if bar == _topbar:
		_topbar_bg = bg
	var edge := ColorRect.new()
	edge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if edge_at_bottom else Control.PRESET_TOP_WIDE)
	edge.offset_top = -1.0 if edge_at_bottom else 0.0
	edge.offset_bottom = 0.0 if edge_at_bottom else 1.0
	edge.color = Tokens.SURFACE_EDGE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(edge)


## A small faction insignia for the top-bar tally, recoloured to the player-relative owner
## colour (blue for you, red for the enemy) with the same luminance mask the map uses.
func _make_status_icon(size: float = 18.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = INSIGNIA_RECOLOR_SHADER
	mat.set_shader_parameter("use_luminance_mask", true)
	icon.material = mat
	return icon


func _make_status_count(size: int = Tokens.FONT_SIZE_SMALL) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", Tokens.TEXT)
	l.add_theme_font_override("font", Tokens.FONT_HEAVY)
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A plain high-contrast checkbox glyph, generated so it reads on the dark panel instead of
## the theme's very low-contrast default icons. There is no image asset to keep in sync.
func _checkbox_icon(checked: bool) -> ImageTexture:
	var s := 18
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.86, 0.87, 0.90, 1.0)
	for x in range(2, s - 2):
		img.set_pixel(x, 2, col)
		img.set_pixel(x, s - 3, col)
	for y in range(2, s - 2):
		img.set_pixel(2, y, col)
		img.set_pixel(s - 3, y, col)
	if checked:
		for i in 6:
			img.set_pixel(4 + i, 9 + i, col)
			img.set_pixel(4 + i, 10 + i, col)
		for i in 6:
			img.set_pixel(9 + i, 14 - i, col)
			img.set_pixel(9 + i, 15 - i, col)
	return ImageTexture.create_from_image(img)


## Both sides' insignia + worlds-held count. Called from _refresh (state changes) and on
## input-mode changes (hotseat can flip whose side this screen is).
func _update_status_row() -> void:
	if _status_row == null or state == null:
		return
	var me := _current_seat_faction()
	var them := Faction.opponent(me)
	_status_me_icon.texture = FACTION_INSIGNIA.get(me, null)
	_status_them_icon.texture = FACTION_INSIGNIA.get(them, null)
	for pair in [[_status_me_icon, me], [_status_them_icon, them]]:
		var icon: TextureRect = pair[0]
		var mat := icon.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("tint", _owner_color(pair[1]))
	_status_me_count.text = str(state.planets_owned_by(me).size())
	_status_them_count.text = str(state.planets_owned_by(them).size())
	_status_row.tooltip_text = "Worlds held — %s %d, %s %d" % [
		Faction.display_name(me), state.planets_owned_by(me).size(),
		Faction.display_name(them), state.planets_owned_by(them).size()]


## Top strip = centred info / status / message. Bottom strip = centred gameplay buttons.
## Non-gameplay actions live behind the top-right gear (`_build_settings_menu`).
func _build_panel() -> void:
	# --- Top: centred info / status / message ------------------------------
	_topbar = Control.new()
	_topbar.name = "TopBar"
	_topbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_topbar.mouse_filter = Control.MOUSE_FILTER_STOP
	_topbar.clip_contents = true
	add_child(_topbar)
	_bar_glass(_topbar, true)

	var top_center := CenterContainer.new()
	top_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_topbar.add_child(top_center)
	var top_v := VBoxContainer.new()
	top_v.alignment = BoxContainer.ALIGNMENT_CENTER
	top_v.add_theme_constant_override("separation", int(Tokens.SPACE_1))
	top_center.add_child(top_v)

	# Top-left: current faction insignia with the turn number underneath. Replaces the old
	# spelled-out "TURN N — GALACTIC REPUBLIC" headline, freeing the centre for the tally.
	_turn_box = VBoxContainer.new()
	_turn_box.add_theme_constant_override("separation", 2)
	_turn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.add_child(_turn_box)
	_turn_icon = _make_status_icon(36.0)
	_turn_box.add_child(_turn_icon)
	_turn_label = Label.new()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	_turn_label.add_theme_font_override("font", Tokens.FONT_LIGHT)
	_turn_label.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_SMALL)
	_turn_box.add_child(_turn_label)

	# Only shown for VICTORY/DEFEAT (and the two-player "X WINS" variant).
	_panel_title = Label.new()
	_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_title.add_theme_color_override("font_color", Tokens.TEXT)
	_panel_title.add_theme_font_override("font", Tokens.FONT_HEAVY)
	_panel_title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	top_v.add_child(_panel_title)

	# The standing tally — just each side's insignia and worlds held. Bigger than before now
	# that the turn headline no longer competes with it for space.
	_status_row = HBoxContainer.new()
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	top_v.add_child(_status_row)
	_status_me_icon = _make_status_icon(30.0)
	_status_me_count = _make_status_count(22)
	_status_row.add_child(_status_me_icon)
	_status_row.add_child(_status_me_count)
	var versus := Label.new()
	versus.text = "vs"
	versus.add_theme_font_override("font", Tokens.FONT_LIGHT)
	versus.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_SMALL)
	versus.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	_status_row.add_child(versus)
	_status_them_icon = _make_status_icon(30.0)
	_status_them_count = _make_status_count(22)
	_status_row.add_child(_status_them_icon)
	_status_row.add_child(_status_them_count)

	# The contextual message — Futura Book, with Bold for its [b]…[/b] emphasis.
	_panel_body = RichTextLabel.new()
	_panel_body.bbcode_enabled = true
	_panel_body.scroll_active = false
	_panel_body.fit_content = true
	_panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.custom_minimum_size = Vector2(720.0, 0.0)
	_panel_body.add_theme_color_override("default_color", Tokens.TEXT_DIM)
	_panel_body.add_theme_font_override("normal_font", Tokens.FONT_BOOK)
	_panel_body.add_theme_font_override("bold_font", Tokens.FONT_BOLD)
	_panel_body.add_theme_font_size_override("normal_font_size", Tokens.FONT_SIZE_BASE)
	_panel_body.add_theme_font_size_override("bold_font_size", Tokens.FONT_SIZE_BASE)
	top_v.add_child(_panel_body)

	# --- Top-right gear + Settings popup ----------------------------------
	_build_settings_menu()

	# --- Bottom: two centred rows of gameplay buttons -------------------
	# Row 1 movement (Move · End turn · Cancel), row 2 upgrades (Reinforcements · Buy
	# fleet · Training). Each row is a 3-cell balanced layout so the middle button is
	# always dead-centre on screen whether or not its flanking buttons are shown; the
	# flankers hug inward toward it. Row 3 is the battle controls, shown only mid-battle.
	_bottombar = Control.new()
	_bottombar.name = "BottomBar"
	_bottombar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottombar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bottombar.clip_contents = true
	add_child(_bottombar)
	_bar_glass(_bottombar, false)

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", int(Tokens.SPACE_1))
	_bottombar.add_child(rows)

	_end_turn_button = Button.new()
	_end_turn_button.text = "End turn"
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_move_button = Button.new()
	_move_button.text = "Move"
	_move_button.pressed.connect(_on_move_pressed)
	_cancel_button = Button.new()
	_cancel_button.text = "Back"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_buy_button = Button.new()
	_buy_button.text = "Buy fleet (%d)" % TurnResolver.BUY_FLEET_COST
	_buy_button.pressed.connect(_on_buy_pressed)
	_reinforce_button = Button.new()
	_reinforce_button.pressed.connect(_on_reinforce_pressed)
	_training_button = Button.new()
	_training_button.pressed.connect(_on_training_pressed)

	# Mouse mode: one horizontal row, matching the controller bar's footprint. Buttons are
	# shown/hidden by context (Move/Cancel while staging, upgrades while a fleet is
	# selected, End Turn only when no fleet is selected).
	_row_mouse = HBoxContainer.new()
	_row_mouse.alignment = BoxContainer.ALIGNMENT_CENTER
	_row_mouse.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	_row_mouse.add_child(_move_button)
	_row_mouse.add_child(_cancel_button)
	_row_mouse.add_child(_reinforce_button)
	_row_mouse.add_child(_buy_button)
	_row_mouse.add_child(_training_button)
	_row_mouse.add_child(_end_turn_button)
	rows.add_child(_row_mouse)

	# Battle controls — their own centred row, shown only while a battle is live.
	_battle_box = HBoxContainer.new()
	_battle_box.add_theme_constant_override("separation", int(Tokens.SPACE_1))
	_row_battle = CenterContainer.new()
	_row_battle.add_child(_battle_box)
	rows.add_child(_row_battle)

	# Controller-only action bar. Display-only pills: the physical face buttons invoke the
	# actions directly (Cross select, Circle back, Square buy/upgrades, Triangle end turn).
	_pad_bar = HBoxContainer.new()
	_pad_bar.name = "PadBar"
	_pad_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_pad_bar.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	_pad_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad_bar.visible = false
	rows.add_child(_pad_bar)
	_pad_pill_confirm = PadActionPill.new()
	_pad_bar.add_child(_pad_pill_confirm)
	_pad_pill_cancel = PadActionPill.new()
	_pad_bar.add_child(_pad_pill_cancel)
	_pad_pill_west = PadActionPill.new()
	_pad_bar.add_child(_pad_pill_west)
	_pad_pill_north = PadActionPill.new()
	_pad_bar.add_child(_pad_pill_north)

	_pad_upgrade_bar = HBoxContainer.new()
	_pad_upgrade_bar.name = "PadUpgradeBar"
	_pad_upgrade_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_pad_upgrade_bar.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	_pad_upgrade_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad_upgrade_bar.visible = false
	rows.add_child(_pad_upgrade_bar)
	_pad_upgrade_a = PadActionPill.new()
	_pad_upgrade_bar.add_child(_pad_upgrade_a)
	_pad_upgrade_b = PadActionPill.new()
	_pad_upgrade_bar.add_child(_pad_upgrade_b)

	_kyber_play_button = Button.new()
	_kyber_play_button.text = "Play in KYBER"
	_kyber_play_button.pressed.connect(_on_kyber_play_pressed)
	_battle_box.add_child(_kyber_play_button)

	_kyber_connect_button = Button.new()
	_kyber_connect_button.text = "Start KYBER + plugin"
	_kyber_connect_button.pressed.connect(_on_kyber_connect_pressed)
	_battle_box.add_child(_kyber_connect_button)

	_kyber_end_row = HBoxContainer.new()
	_kyber_end_row.add_theme_constant_override("separation", int(Tokens.SPACE_1))
	var end_now := Button.new()
	end_now.text = "End match"
	end_now.tooltip_text = "Tell KYBER to end the round now (the score/kill-based winner still decides it, same as a natural end) — for when the round already finished in SWBF2 but the plugin's confirmation didn't reach GC."
	end_now.pressed.connect(func(): _end_kyber_match(0))
	_kyber_end_row.add_child(end_now)
	_battle_box.add_child(_kyber_end_row)

	_kyber_result_label = Label.new()
	_kyber_result_label.add_theme_color_override("font_color", Tokens.WARNING)
	_kyber_result_label.clip_text = true
	_battle_box.add_child(_kyber_result_label)
	_kyber_apply_button = Button.new()
	_kyber_apply_button.text = "Apply result"
	_kyber_apply_button.pressed.connect(_on_kyber_apply_pressed)
	_battle_box.add_child(_kyber_apply_button)

	_more_button = Button.new()
	_more_button.text = "More…"
	_more_button.tooltip_text = "Manual winner report, for when there's no automatic KYBER result"
	_more_button.pressed.connect(func():
		if _more_popup.visible:
			_sfx_cancel()
			_close_more_menu()
		else:
			_sfx_move()
			_open_more_menu())
	_battle_box.add_child(_more_button)
	_build_more_menu()

	_layout_topbar()


## The "More…" popup: the manual winner-report fallback (two "<side> won" buttons +
## Abandoned) — off to the side rather than crowding the main battle row, since Apply
## result is the button a normal match actually needs. Same click-catcher-scrim shape as
## the settings popup, its own instance since the two can be open independently (in
## practice never both live at once, but nothing should assume that).
func _build_more_menu() -> void:
	_more_scrim = Control.new()
	_more_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_more_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_more_scrim.visible = false
	_more_scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_sfx_cancel()
			_close_more_menu())
	add_child(_more_scrim)

	_more_popup = PanelContainer.new()
	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Tokens.SURFACE
	pop_style.border_color = Tokens.SURFACE_EDGE
	pop_style.set_border_width_all(1)
	pop_style.set_corner_radius_all(8)
	pop_style.set_content_margin_all(int(Tokens.SPACE_2))
	_more_popup.add_theme_stylebox_override("panel", pop_style)
	_more_popup.visible = false
	add_child(_more_popup)

	_more_menu_box = VBoxContainer.new()
	_more_menu_box.add_theme_constant_override("separation", int(Tokens.SPACE_1))
	_more_popup.add_child(_more_menu_box)

	# Two manual winner buttons + Abandoned; _refresh labels the win buttons per campaign and
	# reparents them between the battle row and this popup per situation (Abandoned always
	# stays in the battle row) — see _place_result_buttons.
	_win_buttons.clear()
	for i in 2:
		var win_button := Button.new()
		win_button.pressed.connect(func():
			_close_more_menu()
			_on_victor_reported(_campaign_factions()[i]))
		_win_buttons.append(win_button)
		_more_menu_box.add_child(win_button)
	_abandon_button = Button.new()
	_abandon_button.text = "Abandoned"
	_abandon_button.pressed.connect(func():
		_close_more_menu()
		_on_abandoned())
	_more_menu_box.add_child(_abandon_button)
	# `2026-09-22` (playtest 921, item 13): "Supremacy reported no winner... battle was
	# unable to be played... would be good to have an option to start the battle again."
	# It normally lives here as a KYBER escape hatch, and _place_result_buttons promotes it
	# into the battle row only when KYBER could not read a result.
	_restart_battle_button = Button.new()
	_restart_battle_button.text = "Restart battle"
	_restart_battle_button.tooltip_text = ("Clears GC's own stuck/misfired match state and "
		+ "tells KYBER to restart the current round from scratch — for when a match didn't "
		+ "play out (or GC reported \"no winner\" with nothing actually decided) and there's "
		+ "no other way back to a fresh \"Play in KYBER\".")
	_restart_battle_button.pressed.connect(func():
		_close_more_menu()
		_on_restart_battle_pressed())
	_more_menu_box.add_child(_restart_battle_button)
	_style_result_buttons_for_popup()


## Popup styling: flat, left-aligned, a fixed min-width — reads as a small menu list.
func _style_result_button_popup(b: Button) -> void:
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(160.0, 0.0)


## Inline styling: an ordinary button among _battle_box's other ordinary buttons.
func _style_result_button_inline(b: Button) -> void:
	b.flat = false
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2.ZERO


func _style_result_buttons_for_popup() -> void:
	for b in _win_buttons:
		_style_result_button_popup(b)
	if is_instance_valid(_restart_battle_button):
		_style_result_button_popup(_restart_battle_button)


## Abandoned is never a hidden debug option: it belongs in the battle row in every mode.
func _style_abandon_inline() -> void:
	if is_instance_valid(_abandon_button):
		_style_result_button_inline(_abandon_button)


## Reparents (not duplicates) the same result-button instances each _refresh; only actually
## moves them when the target differs from their current parent. `inline` puts the manual
## winner buttons in the battle row (offline / unreadable / co-op after its hold);
## `restart_inline` is separate because Restart Battle is only promoted out of More… when
## KYBER genuinely could not read a result. Abandoned is always in the battle row.
func _place_result_buttons(inline: bool, restart_inline := false) -> void:
	if not is_instance_valid(_more_menu_box) or not is_instance_valid(_battle_box):
		return
	if is_instance_valid(_abandon_button) and _abandon_button.get_parent() != _battle_box:
		_abandon_button.get_parent().remove_child(_abandon_button)
		_battle_box.add_child(_abandon_button)
	_style_abandon_inline()
	var target: Node = _battle_box if inline else _more_menu_box
	for n: Button in _win_buttons:
		if n.get_parent() != target:
			n.get_parent().remove_child(n)
			target.add_child(n)
		if inline:
			_style_result_button_inline(n)
		else:
			_style_result_button_popup(n)
	if is_instance_valid(_restart_battle_button):
		var rtarget: Node = _battle_box if restart_inline else _more_menu_box
		if _restart_battle_button.get_parent() != rtarget:
			_restart_battle_button.get_parent().remove_child(_restart_battle_button)
			rtarget.add_child(_restart_battle_button)
		if restart_inline:
			_style_result_button_inline(_restart_battle_button)
		else:
			_style_result_button_popup(_restart_battle_button)


## Is the pending battle a CO-OP match (the Clone Wars / sequel capital-ship boarding co-ops,
## Jakku/Takodana/Ajan Kloss held by the Resistance, GCW's Kessel)? KYBER exposes no result
## for those, ever (docs/SUPREMACY_PHASE.md) — the commander logs it by hand.
func _battle_is_coop() -> bool:
	if state == null or not state.has_pending_battle():
		return false
	var req := Battle.Request.from_dict(state.pending_battle)
	var planet := state.get_planet(req.planet_id)
	if planet == null:
		return false
	var r := KyberBridge.resolve_map(req, planet, ContentLoader.load_map_catalog(state.campaign_id), _current_seat_faction(), GcPrefs.offline_mode())
	return String((r["entry"] as Dictionary).get("mode", "")) == "coop"


## True while a co-op's manual winner report is being held back to let the round play out.
func _coop_result_hold_active() -> bool:
	return _coop_result_unlock_ms > Time.get_ticks_msec() and _battle_is_coop()


func _open_more_menu() -> void:
	if not _layer_is_open(_more_popup):
		_push_ui_layer(_more_popup, _close_more_menu)
	_more_scrim.visible = true
	_more_popup.visible = true
	_layout_topbar()   # positions the popup above the More… button


func _close_more_menu() -> void:
	_pop_ui_layer(_more_popup)
	if is_instance_valid(_more_scrim):
		_more_scrim.visible = false
	if is_instance_valid(_more_popup):
		_more_popup.visible = false


## The top-right gear and the popup it toggles: everything that isn't gameplay
## (New Campaign / Display / KYBER Setup / Log / Exit). A click-catcher scrim closes it.
func _build_settings_menu() -> void:
	_settings_scrim = Control.new()
	_settings_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_scrim.visible = false
	_settings_scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_sfx_cancel()
			_close_settings())
	add_child(_settings_scrim)

	_settings_popup = PanelContainer.new()
	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Tokens.SURFACE
	pop_style.border_color = Tokens.SURFACE_EDGE
	pop_style.set_border_width_all(1)
	pop_style.set_corner_radius_all(8)
	pop_style.set_content_margin_all(int(Tokens.SPACE_2))
	_settings_popup.add_theme_stylebox_override("panel", pop_style)
	_settings_popup.visible = false
	add_child(_settings_popup)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", int(Tokens.SPACE_1))
	_settings_popup.add_child(menu)

	menu.add_child(_settings_item("New Campaign", _on_difficulty_pressed))
	menu.add_child(_settings_item("Controls…", _on_controls_pressed))
	_display_toggle_button = _settings_item(_fullscreen_toggle_label(), _on_display_pressed)
	menu.add_child(_display_toggle_button)
	menu.add_child(_settings_item("Save / Load Game", _on_saves_pressed))
	_music_toggle_button = _settings_item(_music_toggle_label(), _on_toggle_music_pressed)
	menu.add_child(_music_toggle_button)
	if OS.get_name() == "Windows":
		_kyber_setup_button = _settings_item("KYBER Setup…", _on_kyber_setup_pressed)
		menu.add_child(_kyber_setup_button)
		_log_button = _settings_item("Debug", _on_log_pressed)
		menu.add_child(_log_button)
	menu.add_child(_settings_item("Exit", func(): get_tree().quit()))

	_gear_button = Button.new()
	_gear_button.text = "⚙"
	_gear_button.tooltip_text = "Settings"
	_gear_button.flat = true
	# Strip the theme's pill stylebox (its wide L/R content margin makes the button ~70px
	# and pushes it off the right edge) — the gear is just the glyph in the corner.
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		_gear_button.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_gear_button.custom_minimum_size = Vector2(GEAR_SIZE, GEAR_SIZE)
	_gear_button.size = Vector2(GEAR_SIZE, GEAR_SIZE)
	_gear_button.add_theme_font_size_override("font_size", 22)
	_gear_button.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	_gear_button.add_theme_color_override("font_hover_color", Tokens.TEXT)
	_gear_button.pressed.connect(func():
		if _settings_popup.visible:
			_sfx_cancel()
			_close_settings()
		else:
			_sfx_move()
			_open_settings())
	add_child(_gear_button)


func _settings_item(label: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.flat = true   # a plain menu list, not a stack of pills
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(180.0, 0.0)
	b.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Tokens.TEXT)
	b.pressed.connect(func():
		_sfx_move()
		_close_settings()
		handler.call())
	return b


func _open_settings() -> void:
	# Opened from the boot menu the start-screen overlay is on top of everything — move the
	# scrim and popup above it (and the gear-less top-right corner is where the popup anchors).
	if not _layer_is_open(_settings_popup):
		_push_ui_layer(_settings_popup, _close_settings)
	move_child(_settings_scrim, get_child_count() - 1)
	move_child(_settings_popup, get_child_count() - 1)
	_settings_scrim.visible = true
	_settings_popup.visible = true
	_layout_topbar()   # positions the popup under the gear


func _close_settings() -> void:
	_pop_ui_layer(_settings_popup)
	if is_instance_valid(_settings_scrim):
		_settings_scrim.visible = false
	if is_instance_valid(_settings_popup):
		_settings_popup.visible = false


# --- Interaction -------------------------------------------------------------

const PAN_DRAG_THRESHOLD_PX := 6.0
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# A modal/wizard owns the wheel while it is open. Its ScrollContainer still scrolls;
		# the map behind it must not zoom at the same time.
		if mb.pressed and _ui_layers.is_empty():
			_handle_scroll_zoom(mb)
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
		_pan_button_down = mb.pressed
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# Clicks resolve on RELEASE so a press-and-drag can pan the zoomed-in view instead.
	if mb.pressed:
		_press_pos = mb.position
		_press_active = true
		_press_moved = false
		return
	var was_drag := _press_moved
	_press_active = false
	_press_moved = false
	if was_drag:
		return
	_handle_map_click(mb.position)


func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	_keyboard_map_nav = false
	# A mouse user should not keep a controller focus ring on whatever they last clicked.
	# A focused LineEdit is left alone so typing does not lose its caret.
	var fo := get_viewport().gui_get_focus_owner()
	if fo is Button and fo.is_visible_in_tree():
		fo.release_focus()
	var left_held := _press_active and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if left_held and not _press_moved:
		if mm.position.distance_to(_press_pos) < PAN_DRAG_THRESHOLD_PX:
			return
		_press_moved = true
	if _pan_button_down or (left_held and _press_moved):
		_pan_view(mm.relative)
		return
	if state == null:
		return
	var h := _planet_at(mm.position)
	var hid: StringName = h.id if h != null else &""
	if hid != _hover_id:
		_hover_id = hid
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover_is_actionable(hid) else Control.CURSOR_ARROW
		queue_redraw()


## Whether hovering `hid` right now would actually DO something on click, for the cursor
## alone. `2026-09-21` (playtest 921): "if you have a fleet selected, you should only be
## able to select places you can go to — confusing to highlight a planet outside of reach."
## No fleet selected, every world is a live target (inspect, or pick up one of your fleets
## there). A fleet selected narrows this to exactly its legal destinations; the fleet's own
## world is not one (Back is the only way to deselect).
func _hover_is_actionable(hid: StringName) -> bool:
	if hid == &"":
		return false
	if selected_fleet == null:
		return true
	return _reachable_ids().has(hid)


## Click-drag pan while zoomed in: shifts the zoom's aim point so the view slides with the
## cursor (grab-the-map feel). No-op at full zoom-out — there's nothing to pan.
func _pan_view(rel: Vector2) -> void:
	if _camera == null or state == null or state.has_pending_battle() or _zoom_t < 0.02:
		return
	var vp_h := maxf(get_viewport_rect().size.y, 1.0)
	var world_per_px := 2.0 * absf(_camera.position.z) * tan(deg_to_rad(_camera.fov * 0.5)) / vp_h
	# The camera only travels `_zoom_t` of the way to the aim point, so the aim point moves
	# 1/_zoom_t as far as the camera should.
	var d := Vector3(-rel.x, rel.y, 0.0) * world_per_px / maxf(_zoom_t, 0.05)
	_zoom_planet_id = &""
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_target_pos_raw = _clamp_pan(_zoom_target_pos_raw + d)
	_zoom_target_pos = _clamp_pan(_zoom_target_pos + d)
	_apply_zoom(_zoom_t)


func _clamp_pan(v: Vector3) -> Vector3:
	# The camera only travels `_zoom_t` of the way from home to the aim point, so bound where the
	# CAMERA ends up (a little past the outermost worlds), then solve back for the aim point —
	# a fixed bound on the aim point itself stopped short of the map's right edge at partial zoom.
	var t := maxf(_zoom_t, 0.05)
	var cam_x := clampf(t * v.x, -MAP_SPREAD.x * 1.1, MAP_SPREAD.x * 1.1)
	var cam_y_min := -MAP_SPREAD.y * 1.1 + MAP_Y_OFFSET
	var cam_y_max := MAP_SPREAD.y * 1.1 + MAP_Y_OFFSET
	var cam_y := clampf(CAMERA_HOME_POS.y * (1.0 - t) + t * (v.y + BATTLE_CAMERA_Y_LIFT), cam_y_min, cam_y_max)
	return Vector3(cam_x / t, (cam_y - CAMERA_HOME_POS.y * (1.0 - t)) / t - BATTLE_CAMERA_Y_LIFT, v.z)


func _handle_map_click(pos: Vector2) -> void:
	var hit := _planet_at(pos)
	_activate_world(hit)


## The shared "a world was chosen" path. Mouse clicks find a planet from a screen point and
## call this; the controller/keyboard map cursor already knows the planet id and calls this
## directly. Keeping one body here means selection, fleet switching, inspect text and
## move-staging can never drift between the two input paths.
func _activate_world(hit: Planet) -> void:
	_notice = ""

	# The board is read-only while a battle is waiting on its result, or once the war ends.
	if state.has_pending_battle() or state.is_over() or _ai_opening_seed >= 0:
		return

	# With a fleet selected, ONLY that fleet's legal destinations accept a click. The fleet's
	# own world and everything else are inert; Back is the only way to deselect. This keeps a
	# mouse selection as simple as the controller's restricted reticle.
	if selected_fleet != null:
		if hit == null or not _reachable_ids().has(hit.id):
			return
		_sfx_confirm()
		_inspect_id = hit.id
		pending_dest = hit.id
		_refresh()
		return

	if hit == null:
		_clear_selection()
		_refresh()
		return
	_sfx_confirm()   # a planet was actually chosen — selecting a fleet or staging a destination
	_inspect_id = hit.id   # whatever it is, say what it is

	# Any world with a fleet of mine that can still move is a direct pick. `2026-09-21`
	# (playtest 921): "Can't switch to another fleet once one is already selected..." — that
	# switching now happens only when nothing is selected; with a fleet active, clicks are
	# destinations.
	for f in state.fleets_at(hit.id):
		# f.owner == _current_seat_faction() alone used to be enough (in single player and
		# local hotseat the two conditions below always coincide by construction — see
		# _current_seat_faction's own doc comment) but an online CLIENT's seat is fixed to
		# their own faction even during the HOST's phase, so it needs its own explicit
		# active_faction check to keep a networked player from selecting their own fleet
		# out of turn (harmless alone, but Move would then send a doomed intent).
		if f.owner == _current_seat_faction() and f.owner == state.active_faction and not f.has_moved:
			selected_fleet = f
			pending_dest = &""
			_refresh()
			return

	_refresh()


## True when this session is an online CLIENT — every action then becomes an intent sent to
## the host instead of a direct TurnResolver call (the host is the sole authority; see
## bridge/gc_net.gd's own header). False for single player, local hotseat, and the host's
## own side of an online game (the host still mutates state directly, exactly as today).
func _is_net_client() -> bool:
	return _gc_net != null and _gc_net.role == GcNet.Role.CLIENT


## True when it's safe for THIS screen to mutate `state` directly right now. Always true
## off-network (single player, local hotseat — there's only one human, and whichever phase
## is showing is the one they're allowed to act in, by construction of _current_seat_
## faction). Online, only the host ever mutates state directly, and only during its OWN
## phase: Move is transitively protected already (_gui_input's fleet-selection gate already
## requires f.owner == state.active_faction, so selected_fleet can never legitimately be an
## out-of-turn fleet), but Buy/End Turn don't go through fleet selection at all — without
## this a host could buy a fleet, or even end the OTHER player's turn out from under them,
## just by clicking their own always-visible buttons, network round-trip or not. Mirrors
## exactly what _apply_remote_intent already checks for the client's side of the same
## actions; Reinforce/Train get it too, for the same "don't lean on UI gating alone" reason
## _apply_remote_intent itself doesn't just trust a client's fleet_id.
func _is_my_turn_to_act() -> bool:
	if _gc_net == null:
		return true
	return _gc_net.role == GcNet.Role.HOST and state.active_faction == _gc_net.my_faction


## Host-side only: push the fresh state to a connected client after any local mutation —
## the host's own move, or an intent it just applied on the client's behalf. A no-op for
## single player, local hotseat, or a client (which never mutates state directly, so it has
## nothing of its own to broadcast).
func _gc_net_broadcast() -> void:
	if _gc_net != null and _gc_net.role == GcNet.Role.HOST and _gc_net.is_peer_connected():
		_gc_net.send_state(state.to_dict())


func _on_move_pressed() -> void:
	if selected_fleet == null or pending_dest == &"":
		return
	_sfx_confirm()
	if _is_net_client():
		_gc_net.send_intent({"type": "move", "fleet_id": String(selected_fleet.id), "dest": String(pending_dest)})
		_clear_selection()
		_notice = "Move sent — waiting for the host…"
		_refresh()
		return
	if not _is_my_turn_to_act():
		_clear_selection()
		return
	_notice = ""
	var outcome := TurnResolver.move_fleet(state, selected_fleet.id, pending_dest)
	if outcome.status == TurnResolver.MoveStatus.INVALID:
		_notice = outcome.reason
		pending_dest = &""
	else:
		# OK or BATTLE_REQUIRED: selection is spent; the battle box (if any) takes over.
		_clear_selection()
	_gc_net_broadcast()
	_refresh()


func _on_cancel_pressed() -> void:
	_sfx_cancel()
	_notice = ""
	_clear_selection()
	_refresh()


func _on_buy_pressed() -> void:
	_sfx_confirm()
	if _is_net_client():
		_gc_net.send_intent({"type": "buy"})
		_clear_selection()
		_notice = "Sent — waiting for the host…"
		_refresh()
		return
	if not _is_my_turn_to_act():
		return
	_notice = ""
	var outcome := TurnResolver.buy_fleet(state, _current_seat_faction())
	if not outcome.ok:
		_notice = outcome.reason
	_clear_selection()
	_gc_net_broadcast()
	_refresh()


func _on_reinforce_pressed() -> void:
	_sfx_confirm()
	if selected_fleet == null:
		return
	if _is_net_client():
		_gc_net.send_intent({"type": "reinforce", "fleet_id": String(selected_fleet.id)})
		_notice = "Sent — waiting for the host…"
		_refresh()
		return
	if not _is_my_turn_to_act():
		return
	_notice = ""
	var outcome := TurnResolver.reinforce_fleet(state, selected_fleet.id)
	if not outcome.ok:
		_notice = outcome.reason
	else:
		GcLog.note("gc", "%s fleet at %s reinforced → tier %d" % [
			Faction.display_name(selected_fleet.owner),
			_planet_name(selected_fleet.location), selected_fleet.reinforcement_tier,
		])
	_gc_net_broadcast()
	_refresh()


func _on_training_pressed() -> void:
	_sfx_confirm()
	if selected_fleet == null:
		return
	if _is_net_client():
		_gc_net.send_intent({"type": "train", "fleet_id": String(selected_fleet.id)})
		_notice = "Sent — waiting for the host…"
		_refresh()
		return
	if not _is_my_turn_to_act():
		return
	_notice = ""
	var outcome := TurnResolver.buy_combat_training(state, selected_fleet.id)
	if not outcome.ok:
		_notice = outcome.reason
	else:
		GcLog.note("gc", "%s fleet at %s reached Combat Training %s" % [
			Faction.display_name(selected_fleet.owner), _planet_name(selected_fleet.location),
			_roman(selected_fleet.combat_training_level),
		])
	_gc_net_broadcast()
	_refresh()


func _clear_selection() -> void:
	selected_fleet = null
	pending_dest = &""
	_inspect_id = &""


func _on_end_turn_pressed() -> void:
	_sfx_cancel()   # closes the player's phase without committing to a further action
	if _is_net_client():
		_gc_net.send_intent({"type": "end_turn"})
		_clear_selection()
		_notice = "Sent — waiting for the host…"
		_refresh()
		return
	if not _is_my_turn_to_act():
		return
	_notice = ""
	if TurnResolver.end_turn(state):
		_clear_selection()
		_gc_net_broadcast()
		_refresh()


## Everything KYBER-side tied to the battle that just ended — cleared before the next one's
## panel renders, since the AI's counter-attack can be pending in the same frame (a stale
## `_kyber_staged` from the last battle then hid the new one's "Play in KYBER" button).
func _reset_kyber_battle_state() -> void:
	_kyber_staged = {}
	_kyber_awaiting = {}
	_kyber_match_live = false
	_coop_result_unlock_ms = 0
	_coop_result_armed = false
	_groundwin_pending_battle_id = ""
	_kyber_watch.disarm()


func _on_victor_reported(victor: StringName) -> void:
	if not state.has_pending_battle():
		return
	_sfx_confirm()
	_notice = ""
	_reset_kyber_battle_state()
	var request := Battle.Request.from_dict(state.pending_battle)
	if _battle_active:
		_exit_battle_view()
	if _is_net_client():
		# A client-side manual report — the fallback when the host isn't around to notice
		# their own KYBER auto-detection landed. The host always drives KYBER itself (see
		# gc_net.gd's header), so this never touches TurnResolver locally; it just tells the
		# host which winner to fold in, same shape as a "move"/"buy" intent.
		_gc_net.send_intent({"type": "battle_result", "victor": String(victor)})
		_clear_selection()
		_notice = "Sent — waiting for the host…"
		_refresh()
		return
	TurnResolver.resolve_player_battle(state, TurnResolver.manual_result(request, victor))
	_clear_selection()
	_gc_net_broadcast()
	_refresh()


## `2026-09-22` (playtest 921, item 13): the host's "something's stuck, try again" escape
## hatch — does NOT touch the campaign (no TurnResolver call, no net broadcast; the battle
## stays pending exactly as it was). Clears GC's own local KYBER bookkeeping for this battle
## (a stale/misfired staged result, an awaiting-load that never confirmed, the log watch)
## and, if KYBER is actually connected, sends the same single `restart` (Console.Execute
## "Restart") the normal end-of-match flow uses — restarts the CURRENT round on the SAME
## map/mode/bots already loaded, not a fresh rotation pick. Host-only: only the host's
## screen ever shows More… with KYBER content at all (see _refresh's client gating).
func _on_restart_battle_pressed() -> void:
	if not state.has_pending_battle():
		return
	_sfx_confirm()
	_notice = ""
	_reset_kyber_battle_state()
	if _kyber_link != null and _kyber_link.is_online():
		_kyber_link.restart_match()
		_notice = "Told KYBER to restart the match — click \"Play in KYBER\" again once it's back at the front end, if it doesn't just reload."
	else:
		_notice = "Cleared the stuck match state — KYBER isn't connected, so click \"Play in KYBER\" again once it is."
	_refresh()


func _on_abandoned() -> void:
	if not state.has_pending_battle():
		return
	_sfx_cancel()
	_notice = ""
	_reset_kyber_battle_state()
	var request := Battle.Request.from_dict(state.pending_battle)
	if _battle_active:
		_exit_battle_view()
	if _is_net_client():
		_gc_net.send_intent({"type": "battle_result", "abandoned": true,
			"abandoned_by": String(_current_seat_faction())})
		_clear_selection()
		_notice = "Sent — waiting for the host…"
		_refresh()
		return
	TurnResolver.resolve_player_battle(state,
		TurnResolver.abandoned_result(request, _current_seat_faction()))
	_clear_selection()
	_gc_net_broadcast()
	_refresh()


# --- KYBER Setup modal (Windows only) --------------------------------------
# Holds no game rules: it only calls KyberPluginInstaller and shows what it returns.

func _on_kyber_setup_pressed() -> void:
	if is_instance_valid(_kyber_modal):
		return
	_kyber_message = ""
	_build_kyber_modal()
	_kyber_refresh()


## A dimmed full-screen overlay with a centred panel that is always fully inside the
## viewport (no dragging). Fill the returned "body" VBox; free the returned "overlay".
## `center_content` (the wizard only, `2026-09-15`) vertically centres "body" within the
## panel instead of top-aligning it — see the comment at its own use below for why that
## needs a different container than every other modal's plain top-aligned ScrollContainer.
func _modal_overlay(title_text: String, want := Vector2(560, 620), center_content: bool = false, fill_height: bool = false, auto_height: bool = false) -> Dictionary:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# Frosted backdrop: blur whatever's behind (the 3D galaxy) so the modal box reads as the
	# thing in focus, matching the top bar's glass. Falls back to a flat dark scrim if the
	# shader fails to compile.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.6)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim_shader := load("res://ui/frosted_bar.gdshader")
	if scrim_shader != null:
		var scrim_mat := ShaderMaterial.new()
		scrim_mat.shader = scrim_shader
		scrim_mat.set_shader_parameter("tint", Color(0.02, 0.02, 0.04, 0.72))
		scrim.material = scrim_mat
		scrim.color = Color.WHITE   # shader ignores it; keep the rect opaque-drawing
	overlay.add_child(scrim)

	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.SURFACE
	style.border_color = Tokens.SURFACE_EDGE
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, int(Tokens.SPACE_4))

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", int(Tokens.SPACE_3))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if center_content:
		# The wizard's own steps are short (a heading + a couple of buttons) inside a tall
		# fixed-size modal — a plain ScrollContainer sizes its child to that child's OWN
		# (small) minimum height and top-aligns it, leaving the rest of the modal empty
		# below, which read as "everything crammed at the top." A CenterContainer centres
		# instead — but it always sizes its child to that child's own minimum size, which
		# would also shrink "body" down to its narrowest content and lose the "spread
		# across the modal" look the faction row's own SIZE_EXPAND_FILL slots rely on, so
		# "body" gets an explicit minimum width first (the ScrollContainer path below gets
		# the same width for free, from its own horizontal-scroll-disabled auto-stretch).
		# Wizard content always fits comfortably in the fixed modal sizes this is used
		# with, so no scrolling fallback is needed here the way the general case below
		# still provides one.
		body.custom_minimum_size.x = want.x - Tokens.SPACE_4 * 2.0
		# `fill_height` (the wizard): body takes the modal's whole height, so the wizard can pin its
		# Back button to the bottom with an expanding spacer and centre the step's content above.
		if fill_height:
			body.custom_minimum_size.y = want.y - Tokens.SPACE_4 * 2.0
		var clip := Control.new()
		clip.clip_contents = true
		clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.add_child(body)
		clip.add_child(center)
		margin.add_child(clip)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# A focused control must be brought into view when D-pad navigation reaches an
		# off-screen row (long KYBER/Debug/Controls panels, especially at 720p).
		scroll.follow_focus = true
		# Disabling horizontal scroll does NOT clamp a child's width to the container's own —
		# a row whose natural (minimum) width is wider than the panel (e.g. a path LineEdit
		# next to a button) just overflows past the modal's edge, uncontained. Force it.
		scroll.clip_contents = true
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(body)
		margin.add_child(scroll)
	panel.add_child(margin)

	var title := Label.new()
	title.text = title_text.to_upper()
	title.add_theme_color_override("font_color", Tokens.TEXT)
	title.add_theme_font_override("font", Tokens.FONT_BOLD)
	title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	body.add_child(title)

	var reclamp := func():
		var vp := get_viewport_rect().size
		var w := minf(want.x, vp.x - 32.0)
		var h := want.y
		if auto_height:
			# Wizard steps differ wildly in height; size the panel to its own content (up to
			# the viewport) instead of leaving a tall empty box or clipping a tall step.
			h = body.get_combined_minimum_size().y + Tokens.SPACE_4 * 2.0
			h = clampf(h, 180.0, vp.y - 32.0)
		var s := Vector2(w, minf(h, vp.y - 32.0))
		panel.size = s
		panel.position = ((vp - s) * 0.5).clamp(Vector2(16, 16), (vp - s - Vector2(16, 16)).max(Vector2(16, 16)))
	reclamp.call()
	get_viewport().size_changed.connect(reclamp)
	if auto_height:
		body.minimum_size_changed.connect(reclamp)
	overlay.tree_exiting.connect(func():
		if get_viewport().size_changed.is_connected(reclamp):
			get_viewport().size_changed.disconnect(reclamp)
		if auto_height and body.minimum_size_changed.is_connected(reclamp):
			body.minimum_size_changed.disconnect(reclamp))

	overlay.set_meta("controller_layer", true)
	add_child(overlay)
	overlay.tree_exiting.connect(func(): _pop_ui_layer(overlay))
	_push_ui_layer(overlay, func(): overlay.queue_free())
	return {"overlay": overlay, "body": body}


func _build_kyber_modal() -> void:
	var shell := _modal_overlay("KYBER Setup")
	var overlay: Control = shell["overlay"]
	var col: VBoxContainer = shell["body"]

	var blurb := Label.new()
	blurb.text = ("Galactic Conquest injects a custom plugin into the KYBER Launcher to "
		+ "enable connectivity. Select your kyber_launcher.exe file in your installation "
		+ "directory below:")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	col.add_child(blurb)

	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	_kyber_path_edit = LineEdit.new()
	_kyber_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kyber_path_edit.placeholder_text = "C:\\path\\to\\kyber_launcher.exe"
	var configured := KyberPluginInstaller.configured_launcher_path()
	_kyber_path_edit.text = configured if not configured.is_empty() else KyberPluginInstaller.detect_launcher()
	_kyber_path_edit.focus_exited.connect(_kyber_refresh)
	path_row.add_child(_kyber_path_edit)
	var detect_button := Button.new()
	detect_button.text = "Detect"
	detect_button.pressed.connect(_on_kyber_detect_pressed)
	path_row.add_child(detect_button)
	col.add_child(path_row)

	_kyber_status_label = Label.new()
	_kyber_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kyber_status_label.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	col.add_child(_kyber_status_label)

	_kyber_launch_button = Button.new()
	_kyber_launch_button.text = "Restart KYBER with GC Plugin"
	_kyber_launch_button.pressed.connect(_on_kyber_launch_pressed)
	col.add_child(_kyber_launch_button)

	var my_id_head := Label.new()
	my_id_head.text = "Online multiplayer — automatic team assignment"
	my_id_head.add_theme_color_override("font_color", Tokens.TEXT)
	col.add_child(my_id_head)

	var my_id_blurb := Label.new()
	my_id_blurb.text = ("Set this once before hosting so Galactic Conquest can automatically "
		+ "put you in the correct faction in online matches. Otherwise, set the teams by "
		+ "hand in KYBER.")
	my_id_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(my_id_blurb)

	var my_id_row := HBoxContainer.new()
	my_id_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	var my_id_edit := LineEdit.new()
	my_id_edit.placeholder_text = "KYBER Player ID"
	my_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var saved_id := GcPrefs.my_kyber_player_id()
	my_id_edit.text = str(saved_id) if saved_id != 0 else ""
	my_id_row.add_child(my_id_edit)
	var my_id_save := Button.new()
	my_id_save.text = "Save"
	my_id_save.pressed.connect(func():
		_sfx_confirm()
		GcPrefs.set_my_kyber_player_id(int(my_id_edit.text.strip_edges()) if my_id_edit.text.is_valid_int() else 0)
		_kyber_message = "Saved." if my_id_edit.text.is_valid_int() else "Cleared — auto team-assignment is off until this is set."
		_kyber_refresh())
	my_id_row.add_child(my_id_save)
	col.add_child(my_id_row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	var uninstall_button := Button.new()
	uninstall_button.text = "Uninstall Plugin"
	uninstall_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uninstall_button.pressed.connect(_on_kyber_uninstall_pressed)
	bottom.add_child(uninstall_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(_on_kyber_close_pressed)
	bottom.add_child(close_button)
	col.add_child(bottom)

	_kyber_modal = overlay
	overlay.set_meta("controller_cancel", _on_kyber_close_pressed)
	_focus_if_valid.call_deferred(_kyber_launch_button)


func _kyber_refresh() -> void:
	if _kyber_status_label == null:
		return
	var s := KyberPluginInstaller.status(_kyber_path_edit.text.strip_edges())
	var running := bool(s["kyber_running"])
	var plugin_online := running and (
		(_kyber_link != null and _kyber_link.is_online()) or KyberLink.plugin_listening())
	var lines: Array[String] = []
	if not bool(s["launcher_found"]):
		lines.append("• Launcher not found — set the path above, or press Detect.")
	lines.append("• KYBER running: %s" % ("yes" if running else "no"))
	lines.append("• Plugin packaged: %s" % ("yes" if bool(s["kbplugin_present"]) else "no"))
	lines.append("• GC plugin connected: %s" % ("yes" if plugin_online else "no"))
	if _kyber_message != "":
		lines.append("")
		lines.append(_kyber_message)
	_kyber_status_label.text = "\n".join(PackedStringArray(lines))
	_kyber_launch_button.text = "Restart KYBER with GC Plugin" if running \
		else "Launch KYBER with GC Plugin"
	_kyber_launch_button.visible = true


func _on_kyber_detect_pressed() -> void:
	var found := KyberPluginInstaller.detect_launcher()
	if found.is_empty():
		_kyber_message = "Couldn't find kyber_launcher.exe automatically — paste the full path."
	else:
		_kyber_path_edit.text = found
		_kyber_message = ""
	_kyber_refresh()


func _on_kyber_launch_pressed() -> void:
	var path := _kyber_path_edit.text.strip_edges()
	if path.is_empty():
		path = KyberPluginInstaller.configured_launcher_path()
	if path.is_empty():
		path = KyberPluginInstaller.detect_launcher()
	if path.is_empty():
		_kyber_message = "Set the path to kyber_launcher.exe first."
		_kyber_refresh()
		return
	_kyber_message = "Restarting KYBER…"
	_kyber_refresh()
	if KyberPluginInstaller.kyber_running():
		KyberPluginInstaller.close_kyber()
		await get_tree().create_timer(1.0).timeout
	var res := KyberPluginInstaller.launch(path)
	if bool(res.get("ok", false)):
		_kyber_message = "KYBER started with the plugin. Host a match, then check the module log for \"[gc_result] listening\"."
	else:
		_kyber_message = String(res.get("reason", "Launch failed."))
	_kyber_refresh()


func _on_kyber_uninstall_pressed() -> void:
	var res := KyberPluginInstaller.uninstall(_kyber_path_edit.text.strip_edges())
	_kyber_message = String(res.get("reason", "Removed."))
	_kyber_refresh()


func _on_kyber_close_pressed() -> void:
	if is_instance_valid(_kyber_modal):
		_kyber_modal.queue_free()
	_kyber_modal = null
	_kyber_path_edit = null
	_kyber_status_label = null
	_kyber_launch_button = null


# --- Activity log modal ----------------------------------------------------

func _on_log_pressed() -> void:
	if is_instance_valid(_log_modal):
		return
	_build_log_modal()


func _build_log_modal() -> void:
	var shell := _modal_overlay("Debug", Vector2(760, 620))
	var overlay: Control = shell["overlay"]
	var col: VBoxContainer = shell["body"]

	# `2026-10-08` (playtest 104, items 6/7): "Log" renamed to "Debug" — this panel already
	# held KYBER protocol-probing buttons more than a plain activity log, so an experimental
	# toggle belongs here too rather than in the normal New Game flow.
	var hotseat_toggle := CheckBox.new()
	hotseat_toggle.text = "Enable 2 Player (hotseat) [experimental]"
	hotseat_toggle.tooltip_text = "Adds \"2 Players (hotseat)\" back to the New Game wizard's player-count step."
	hotseat_toggle.button_pressed = GcPrefs.hotseat_enabled()
	hotseat_toggle.toggled.connect(func(on: bool): GcPrefs.set_hotseat_enabled(on))
	col.add_child(hotseat_toggle)

	var more_toggle := CheckBox.new()
	more_toggle.text = "Show the More… KYBER debug menu [debug]"
	more_toggle.tooltip_text = ("Off by default in every mode. The menu contains only "
		+ "Restart Battle; the normal winner buttons stay in the battle row when needed.")
	more_toggle.button_pressed = GcPrefs.show_online_more_menu()
	more_toggle.toggled.connect(func(on: bool):
		GcPrefs.set_show_online_more_menu(on)
		_refresh())
	col.add_child(more_toggle)

	var autoapply_toggle := CheckBox.new()
	autoapply_toggle.text = "Auto-apply a clear KYBER result [debug]"
	autoapply_toggle.tooltip_text = "Skip the Apply click when KYBER reports a clear winner."
	autoapply_toggle.button_pressed = GcPrefs.auto_apply_results()
	autoapply_toggle.toggled.connect(func(on: bool): GcPrefs.set_auto_apply_results(on))
	col.add_child(autoapply_toggle)

	var verbose_toggle := CheckBox.new()
	verbose_toggle.text = "Verbose KYBER message log [diagnostic]"
	verbose_toggle.tooltip_text = ("Sets KYBER_MESSAGE_DEBUG — logs the name of every engine "
		+ "message KYBER sees, not just the ones it acts on. Takes effect on the next launch; "
		+ "makes the KYBER log much larger.")
	verbose_toggle.button_pressed = GcPrefs.kyber_message_debug()
	verbose_toggle.toggled.connect(func(on: bool): GcPrefs.set_kyber_message_debug(on))
	col.add_child(verbose_toggle)

	_log_text = TextEdit.new()
	_log_text.editable = false
	_log_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log_text.custom_minimum_size = Vector2(0, 380)
	_log_text.add_theme_font_size_override("font_size", 12)
	col.add_child(_log_text)

	if _kyber_link != null:
		var diag_row := HBoxContainer.new()
		diag_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		var settings_button := Button.new()
		settings_button.text = "Dump settings"
		settings_button.tooltip_text = "Ask the plugin to dump the readable Frostbite settings objects (docs/SUPREMACY_PHASE.md)"
		settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		settings_button.pressed.connect(func():
			if _kyber_link.is_online(): _kyber_link.send_line("settings")
			else: GcLog.note("kyber", "not linked — start a match first")
			_sync_log_text(true))
		diag_row.add_child(settings_button)
		var testeor_button := Button.new()
		testeor_button.text = "Test end-of-round"
		testeor_button.tooltip_text = ("Diagnostic only — does NOT report a result. Sends "
			+ "Console.Execute(\"endofround\"), a real native console command found in a "
			+ "KYBER community plugin (GunGame). Only meaningful during a live managed match "
			+ "— check the log after to see what it actually did.")
		testeor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		testeor_button.pressed.connect(func():
			if _kyber_link.is_online(): _kyber_link.send_line("testeor")
			else: GcLog.note("kyber", "not linked — start a match first")
			_sync_log_text(true))
		diag_row.add_child(testeor_button)
		var probe_button := Button.new()
		probe_button.text = "Probe kit limits"
		probe_button.tooltip_text = ("Diagnostic only — does NOT report a result. Dumps the "
			+ "kit-limitations gamemode container's real field names (ResourceManager."
			+ "LookupDataContainer, docs/SUPREMACY_PHASE.md) — runs once per match. Only "
			+ "meaningful during a live managed match — check the log after.")
		probe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		probe_button.pressed.connect(func():
			if _kyber_link.is_online(): _kyber_link.send_line("probe")
			else: GcLog.note("kyber", "not linked — start a match first")
			_sync_log_text(true))
		diag_row.add_child(probe_button)
		col.add_child(diag_row)

		# `groundwin` already exists and already fires Kyber.endgameteam<N> (a DICE
		# ConsoleCommandTrigger, confirmed live to cleanly end a match) — today it's only
		# ever sent reactively, once KyberMatchWatch sees a Clone Wars lane's capital-ship
		# sub-level already streaming in. The user's question (2026-09-11): could the same
		# trigger, fired proactively right at match start on a GENERAL Supremacy map (not
		# just a Clone Wars lane), skip its ground/planetary phase entirely and drop straight
		# into the capital-ship phase — which might carry its own Outro_Team<N> marker, unlike
		# Supremacy's overall match (docs/SUPREMACY_PHASE.md: no ticket/score signal exists at
		# all, only the slow rotation-advance one). Untested in both directions: whether firing
		# this before any real ground fighting happened is safe (`SkipTitanPhase1` crashed on
		# a re-fire; this is a different trigger, but "immediately at load" is a genuinely new
		# situation for it), and whether the resulting phase actually emits Outro_Team<N> at
		# all outside the two Clone Wars lane maps it's been observed on. No plugin change
		# needed — `groundwin` is exactly the lever, just never given a manual UI trigger.
		# Diagnostic only: does not touch match_armed/managing/emit_result (same as the
		# buttons above), it only pulls the same trigger `_skip_capital_ship_phase` does.
		var skip_ground_row := HBoxContainer.new()
		skip_ground_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		var skip_ground_label := Label.new()
		skip_ground_label.text = "Test skip ground phase (CONFIRMED: crashes, 2026-09-11):"
		skip_ground_label.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		skip_ground_row.add_child(skip_ground_label)
		for team: int in [1, 2]:
			var skip_button := Button.new()
			skip_button.text = "Team %d wins ground" % team
			skip_button.tooltip_text = ("CONFIRMED LIVE (2026-09-11): crashed the game — see "
				+ "CLAUDE.md. Sends groundwin %d, declaring team %d the ground-phase winner "
				+ "(fires Kyber.endgameteam%d, the same DICE ConsoleCommandTrigger the natural "
				+ "Clone Wars lane flow fires once boarding starts on its own — but that's only "
				+ "ever been verified safe fired AFTER real ground fighting concluded). Firing "
				+ "it artificially, without the level's own blueprint having run through "
				+ "whatever state it expects first, is not safe — left here only because a "
				+ "narrower follow-up test (fire it later, once real fighting has happened) "
				+ "might behave differently and is worth trying once, deliberately.") % [team, team, team]
			skip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var team_captured: int = team
			skip_button.pressed.connect(func():
				if _kyber_link.is_online(): _kyber_link.send_line("groundwin %d" % team_captured)
				else: GcLog.note("kyber", "not linked — start a match first")
				_sync_log_text(true))
			skip_ground_row.add_child(skip_button)
		col.add_child(skip_ground_row)

		var hero_row := HBoxContainer.new()
		hero_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		_hero_asset_edit = LineEdit.new()
		_hero_asset_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hero_asset_edit.text = "Gameplay/Kits/Hero/DarthVader/Kit_Hero_DarthVader"
		_hero_asset_edit.tooltip_text = ("A hero kit resource path, \"Gameplay/Kits/Hero/<Name>/"
			+ "Kit_Hero_<Name>\" — the Vader path here is the only one confirmed working "
			+ "(found live in a KYBER community plugin). Edit freely to try other names; "
			+ "nothing else confirms they exist.")
		hero_row.add_child(_hero_asset_edit)
		var hero_button := Button.new()
		hero_button.text = "Set hero kit"
		hero_button.tooltip_text = ("Diagnostic only — does NOT report a result. Sends "
			+ "Player:SetCustomizationAsset(path) to the first human found in the match. "
			+ "Only meaningful during a live managed match.")
		hero_button.pressed.connect(func():
			var path := _hero_asset_edit.text.strip_edges()
			if path.is_empty():
				GcLog.note("kyber", "enter a hero asset path first")
			elif _kyber_link.is_online():
				_kyber_link.send_line("hero %s" % path)
			else:
				GcLog.note("kyber", "not linked — start a match first")
			_sync_log_text(true))
		hero_row.add_child(hero_button)
		col.add_child(hero_row)

		var grpc_head := Label.new()
		grpc_head.text = "gRPC (experimental — bypasses the gc_result plugin entirely)"
		grpc_head.add_theme_color_override("font_color", Tokens.TEXT)
		col.add_child(grpc_head)

		var grpc_blurb := Label.new()
		grpc_blurb.text = ("Calls KYBER's own local interface directly (bridge/kyber_grpc.gd,"
			+ " its README has the findings) instead of going through gc_result's Lua plugin"
			+ " — works even if the socket above shows unlinked, needs only a live game with"
			+ " Kyber injected. Needs grpcurl.exe at tools/grpcurl.exe (download it yourself,"
			+ " https://github.com/fullstorydev/grpcurl/releases) — every call fails with a"
			+ " clear message if it's missing.")
		grpc_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grpc_blurb.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		col.add_child(grpc_blurb)

		var grpc_info_button := Button.new()
		grpc_info_button.text = "gRPC: Get info"
		grpc_info_button.tooltip_text = ("Common.GetInfo — current server state: id, level/"
			+ "mode, and a player list (id/name/teamId only — no kills/deaths/score, that "
			+ "field doesn't exist on this interface at all). Dumps the raw response to the "
			+ "log below.")
		grpc_info_button.pressed.connect(func():
			# Async — call_rpc() blocks for up to KyberGrpc.MAX_TIME_S against a dead server
			# (confirmed live: 13s+ before that flag existed at all), which would otherwise
			# freeze the whole window for that long on every click.
			grpc_info_button.disabled = true
			grpc_info_button.text = "gRPC: Get info (waiting...)"
			KyberGrpc.get_info_async(func(res: Dictionary):
				grpc_info_button.disabled = false
				grpc_info_button.text = "gRPC: Get info"
				if res.get("ok", false):
					GcLog.note("grpc", "GetInfo -> %s" % JSON.stringify(res.get("data", {})))
				else:
					GcLog.note("grpc", "GetInfo failed: %s" % String(res.get("reason", "")))
				_sync_log_text(true)))
		col.add_child(grpc_info_button)

		var grpc_cmd_row := HBoxContainer.new()
		grpc_cmd_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		_grpc_cmd_edit = LineEdit.new()
		_grpc_cmd_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grpc_cmd_edit.placeholder_text = "e.g. AutoPlayers.ForceFillGameplayBotsTeam1 20"
		_grpc_cmd_edit.tooltip_text = ("Any console command — Common.RunCommand is the same "
			+ "power as Console.Execute() in the Lua plugin, just issued from outside the "
			+ "game entirely.")
		grpc_cmd_row.add_child(_grpc_cmd_edit)
		var grpc_cmd_button := Button.new()
		grpc_cmd_button.text = "gRPC: Run command"
		grpc_cmd_button.pressed.connect(func():
			var cmd := _grpc_cmd_edit.text.strip_edges()
			if cmd.is_empty():
				GcLog.note("grpc", "enter a console command first")
				_sync_log_text(true)
				return
			# Async — see the Get info button above for why (same dead-server freeze risk).
			grpc_cmd_button.disabled = true
			grpc_cmd_button.text = "gRPC: Run command (waiting...)"
			KyberGrpc.run_command_async(cmd, func(res: Dictionary):
				grpc_cmd_button.disabled = false
				grpc_cmd_button.text = "gRPC: Run command"
				if res.get("ok", false):
					GcLog.note("grpc", "RunCommand(%s) -> ok" % cmd)
				else:
					GcLog.note("grpc", "RunCommand(%s) failed: %s" % [cmd, String(res.get("reason", ""))])
				_sync_log_text(true)))
		grpc_cmd_row.add_child(grpc_cmd_button)
		col.add_child(grpc_cmd_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	var save_button := Button.new()
	save_button.text = "Save last result → fixture"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_log_save_fixture_pressed)
	row.add_child(save_button)
	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(func():
		GcLog.clear()
		_sync_log_text(true))
	row.add_child(clear_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_on_log_close_pressed)
	row.add_child(close_button)
	col.add_child(row)

	_log_modal = overlay
	overlay.set_meta("controller_cancel", _on_log_close_pressed)
	_sync_log_text(true)


func _sync_log_text(force := false) -> void:
	if _log_text == null:
		return
	var count := GcLog.entries().size()
	if not force and count == _log_shown_count:
		return
	_log_shown_count = count
	_log_text.text = GcLog.as_text()
	_log_text.scroll_vertical = _log_text.get_line_count()


func _on_log_save_fixture_pressed() -> void:
	if _kyber_link == null or _kyber_link.last_result.is_empty():
		GcLog.note("gc", "no KYBER result to save yet — finish a match first")
		_sync_log_text(true)
		return
	var f := FileAccess.open("user://gc_result_sample.json", FileAccess.WRITE)
	if f == null:
		GcLog.note("gc", "could not write the result fixture")
	else:
		f.store_string(JSON.stringify(_kyber_link.last_result) + "\n")
		f.close()
		GcLog.note("gc", "saved last result to user://gc_result_sample.json")
	_sync_log_text(true)


func _on_log_close_pressed() -> void:
	if is_instance_valid(_log_modal):
		_log_modal.queue_free()
	_log_modal = null
	_log_text = null
	_log_shown_count = -1
	_hero_asset_edit = null
	_grpc_cmd_edit = null


# --- Display: fullscreen toggle -------------------------------------------
# `2026-09-19`: the resolution picker is gone — playtest noted the window's contents already
# scale to whatever size the window is (project.godot's canvas_items stretch), so picking a
# fixed resolution only ever resized the window, which the player can do by dragging its edge.
# What's left that the OS window chrome doesn't offer as conveniently is fullscreen, so that
# stays as a one-click toggle in the settings menu. DisplaySettings still persists the last
# windowed size (untouched), so a fullscreen round trip returns to the same window.

func _fullscreen_toggle_label() -> String:
	return "Fullscreen: On" if bool(DisplaySettings.load_saved()["fullscreen"]) else "Fullscreen: Off"


func _on_display_pressed() -> void:
	var saved := DisplaySettings.load_saved()
	var now_fullscreen := not bool(saved["fullscreen"])
	var size: Vector2i = saved["size"]
	if now_fullscreen and DisplayServer.get_name() != "headless" 			and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		size = DisplayServer.window_get_size()   # remember the size the player dragged to
	DisplaySettings.save(size, now_fullscreen)
	if DisplayServer.get_name() != "headless":
		DisplaySettings.apply({"size": size, "fullscreen": now_fullscreen})
	if is_instance_valid(_display_toggle_button):
		_display_toggle_button.text = _fullscreen_toggle_label()


func _saved_faction_for(campaign_id: StringName) -> StringName:
	var factions := ContentLoader.campaign_def(campaign_id).factions
	var f := FactionSettings.load_saved()
	if f in factions:
		return f
	return factions[0] if not factions.is_empty() else Faction.REPUBLIC


## The two-faction list for a campaign — for the wizard, the manual winner buttons and the
## KYBER force-winner buttons, none of which should ever offer the other era's sides.
func _campaign_factions() -> Array:
	var f := ContentLoader.campaign_def(state.campaign_id).factions
	return f if f.size() == 2 else [Faction.REPUBLIC, Faction.SEPARATIST]


## The wizard: campaign → players → (1 Player: faction → difficulty) / (2 Players: starts
## immediately, no faction or difficulty to pick) / (Host Online: pick a faction, then wait
## for a join) / (Join Online, from the campaign step itself — the host already decided the
## campaign, so a joiner skips straight past picking one). Rendered into `col`, which it
## clears and rebuilds per step. `allow_close` adds a Close button on every step (New
## Campaign — the boot screen has none: a campaign HAS to be started).
## `on_start(campaign_id, faction, level, two_player)` fires from the difficulty step
## (1 Player) or straight from the players step (2 Players, `level` is just
## Difficulty.DEFAULT — unused, see GalaxyState.two_player). `on_host_online(campaign_id,
## faction)` / `on_join_online(ip, port)` hand off to main.gd's own status overlay
## (_start_online_host / _start_online_join, bridge/gc_net.gd) once the wizard's own job —
## picking a campaign/faction, or decoding a join code — is done; the wizard closes
## immediately either way, since what happens next (waiting for a connection) isn't really
## a wizard step any more.
func _build_campaign_wizard(col: VBoxContainer, allow_close: bool, on_close: Callable, on_start: Callable,
		on_host_online: Callable = Callable(), on_join_online: Callable = Callable()) -> void:
	var pick := {"campaign": CampaignSettings.load_saved(), "faction": &"",
		"after_kyber": Callable(), "kyber_back": Callable()}
	var layer := _layer_ancestor(col)

	var add_spacer := func():
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(sp)

	# Every step starts with an expanding spacer above its content and ends (in add_nav) with
	# one below it + the centred Back/Close row — so the content sits in the middle of the
	# popup and the nav is pinned to the bottom (playtest 920).
	var clear := func():
		for c in col.get_children():
			c.queue_free()
		add_spacer.call()
		# The step's controls are built after this call returns; focus once they exist.
		_focus_first_in.call_deferred(layer)

	# Wizard text is centred (playtest 920): headings, blurbs, notes.
	var add_heading := func(text: String):
		var l := Label.new()
		l.text = text
		l.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)

	# Both faction options side by side, each with its insignia above its button — recoloured
	# flat white (ui/insignia_recolor.gdshader) rather than a player-relative tint, since this
	# step is about picking a side, not reading who currently controls a world.
	# use_luminance_mask matches the galaxy map's own home-world insignia (on): without it, a
	# logo drawn as dark linework over a light disc (Republic/Imperial/CIS) recolours its
	# whole opaque disc flat white — indistinguishable from the wizard's own white panel
	# background, reported live as the icon just "not showing up." With it on, the light disc
	# fades toward transparent and only the linework reads, same as everywhere else it's used.
	var add_faction_row := func(factions: Array, on_pick: Callable):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(Tokens.SPACE_3))
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for f in factions:
			var slot := VBoxContainer.new()
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			if FACTION_INSIGNIA.has(f):
				var icon := TextureRect.new()
				icon.texture = FACTION_INSIGNIA[f]
				icon.custom_minimum_size = Vector2(88, 88)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				var mat := ShaderMaterial.new()
				mat.shader = INSIGNIA_RECOLOR_SHADER
				mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, 1.0))
				mat.set_shader_parameter("use_luminance_mask", true)
				icon.material = mat
				slot.add_child(icon)
			var b := Button.new()
			b.text = Faction.display_name(f)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): on_pick.call(f))
			slot.add_child(b)
			row.add_child(slot)
		col.add_child(row)

	var add_nav := func(back: Callable, show_close := true):
		add_spacer.call()
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		if back.is_valid():
			var b := Button.new()
			b.text = "← Back"
			b.pressed.connect(func():
				_sfx_cancel()
				back.call())
			row.add_child(b)
		if allow_close and show_close:
			var x := Button.new()
			x.text = "Close"
			x.pressed.connect(func():
				_sfx_cancel()
				on_close.call())
			row.add_child(x)
		if row.get_child_count() > 0:
			col.add_child(row)
		if is_instance_valid(layer):
			# B/Circle follows the same step the on-screen Back/Close button does. The boot
			# menu has neither, so B must be a deliberate no-op there (not "free the start
			# screen", which is the generic modal default).
			if back.is_valid():
				layer.set_meta("controller_cancel", func():
					_sfx_cancel()
					back.call())
			elif allow_close:
				layer.set_meta("controller_cancel", func():
					_sfx_cancel()
					on_close.call())
			else:
				layer.set_meta("controller_cancel", Callable())

	# Step callables live in a dict so each captures the others by reference (a GDScript
	# lambda captures plain locals by value at creation, before the later steps exist).
	var step := {}

	# The boot screen's main menu (playtest 920): New Game / Load Game / Join Online Game /
	# Settings. (The mid-campaign New Campaign modal opens straight on "campaign" instead.)
	step["menu"] = func():
		clear.call()
		var t := Label.new()
		t.text = "GALACTIC CONQUEST"
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_color_override("font_color", Tokens.TEXT)
		t.add_theme_font_override("font", Tokens.FONT_TRAJAN)
		t.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
		col.add_child(t)
		var new_b := Button.new()
		new_b.text = "New Game"
		new_b.pressed.connect(func():
			_sfx_confirm()
			step["campaign"].call())
		col.add_child(new_b)
		var load_b := Button.new()
		load_b.text = "Load Game"
		load_b.pressed.connect(func():
			_sfx_confirm()
			_on_saves_pressed())
		col.add_child(load_b)
		if on_join_online.is_valid():
			var join_b := Button.new()
			join_b.text = "Join Online Game"
			join_b.tooltip_text = "Enter a code someone hosting a game gave you — they've already picked the campaign."
			join_b.pressed.connect(func():
				_sfx_confirm()
				step["join_code"].call())
			col.add_child(join_b)
		var settings_b := Button.new()
		settings_b.text = "Settings"
		settings_b.pressed.connect(func():
			_sfx_confirm()
			_open_settings())
		col.add_child(settings_b)
		add_nav.call(Callable())

	# New Game's first step: how GC and KYBER fit together, and a one-click launch of KYBER with
	# the GC plugin (playtest 920). Continue proceeds either way — Offline mode, or KYBER
	# already open, don't need the launch.
	step["kyber"] = func():
		clear.call()
		var t := Label.new()
		t.text = "GALACTIC CONQUEST WORKS THROUGH KYBER"
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.add_theme_color_override("font_color", Tokens.TEXT)
		t.add_theme_font_override("font", Tokens.FONT_BOLD)
		t.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
		col.add_child(t)
		# RichTextLabel so the consequences sentence can be bold while the rest stays body copy.
		var intro := RichTextLabel.new()
		intro.bbcode_enabled = true
		intro.fit_content = true
		intro.scroll_active = false
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro.add_theme_color_override("default_color", Tokens.TEXT_DIM)
		intro.add_theme_font_override("normal_font", Tokens.FONT_BOOK)
		intro.add_theme_font_override("bold_font", Tokens.FONT_BOLD)
		intro.add_theme_font_size_override("normal_font_size", Tokens.FONT_SIZE_BASE)
		intro.add_theme_font_size_override("bold_font_size", Tokens.FONT_SIZE_BASE)
		intro.text = ("[center]Once installed, launch KYBER with the GC plugin using the Launch "
			+ "button below. Then, Host a server on any map or mode with any combination of "
			+ "mods. [b]Galactic Conquest will take control of your hosted server to launch "
			+ "matches[/b], read wins and losses, and modify AI behavior based on your "
			+ "campaign.[/center]")
		col.add_child(intro)
		var mods_note := RichTextLabel.new()
		mods_note.bbcode_enabled = true
		mods_note.fit_content = true
		mods_note.scroll_active = false
		mods_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mods_note.add_theme_color_override("default_color", Tokens.TEXT_DIM)
		mods_note.add_theme_font_override("normal_font", Tokens.FONT_BOOK)
		mods_note.add_theme_font_override("bold_font", Tokens.FONT_BOLD)
		mods_note.add_theme_font_size_override("normal_font_size", Tokens.FONT_SIZE_BASE)
		mods_note.add_theme_font_size_override("bold_font_size", Tokens.FONT_SIZE_BASE)
		mods_note.text = ("[center]Galactic Conquest is [b]STRONGLY[/b] recommended with a mod "
			+ "to improve AI behavior in matches. Galactic Conquest was made with Battlefront+ "
			+ "in mind, but it can also work with Instant Online Improvements.[/center]")
		col.add_child(mods_note)
		# `2026-10-08` (playtest 104, item 5): a first-time player has no idea KYBER is a
		# separate download — one click straight to it, rather than send them off to search.
		var get_kyber_b := Button.new()
		get_kyber_b.text = "Don't have KYBER? Get it at kyber.gg"
		get_kyber_b.flat = true
		get_kyber_b.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		get_kyber_b.pressed.connect(func():
			_sfx_move()
			OS.shell_open("https://kyber.gg"))
		col.add_child(get_kyber_b)
		var battlefront_b := Button.new()
		battlefront_b.text = "Battlefront+ Modpack"
		battlefront_b.flat = true
		battlefront_b.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		battlefront_b.pressed.connect(func():
			_sfx_move()
			OS.shell_open("https://www.nexusmods.com/starwarsbattlefront22017/mods/7592"))
		col.add_child(battlefront_b)
		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_color_override("font_color", Tokens.WARNING)
		col.add_child(status)
		var launch_b := Button.new()
		launch_b.text = "Launch KYBER with GC Plugin"
		var continue_b := Button.new()
		continue_b.text = "Continue without launching"
		continue_b.flat = true
		continue_b.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		continue_b.pressed.connect(func():
			_sfx_confirm()
			pick["after_kyber"].call())
		launch_b.pressed.connect(func():
			_wizard_launch_kyber(status, launch_b, pick["after_kyber"]))
		col.add_child(launch_b)
		col.add_child(continue_b)
		add_nav.call(pick["kyber_back"])

		# The wizard only needs to know whether KYBER is open at all. Internal plugin-link
		# detection is unreliable before a hosted match, so don't claim anything about it;
		# always offer a Restart that reloads KYBER with the GC plugin.
		var refresh_kyber_state := func():
			if not is_instance_valid(status) or not is_instance_valid(launch_b) \
					or not is_instance_valid(continue_b):
				return
			_kyber_running_checked_ms = 0
			if _kyber_running_cached():
				status.text = ("KYBER is already open. Restart KYBER below to enable the GC plugin.\n"
					+ "Settings → KYBER Setup… lets you set the launcher path.")
				status.add_theme_color_override("font_color", Tokens.WARNING)
				launch_b.text = "Restart KYBER with GC Plugin"
			else:
				status.text = ""
				status.add_theme_color_override("font_color", Tokens.WARNING)
				launch_b.text = "Launch KYBER with GC Plugin"
			launch_b.visible = true
			_focus_if_valid.call_deferred(launch_b)
		refresh_kyber_state.call()

	step["campaign"] = func():
		clear.call()
		add_heading.call("Choose a campaign:")
		for cd in ContentLoader.load_campaigns():
			var b := Button.new()
			b.text = cd.display_name
			b.tooltip_text = "%s vs %s" % [
				Faction.display_name(cd.factions[0]), Faction.display_name(cd.factions[1])]
			b.pressed.connect(func():
				_sfx_confirm()
				pick["campaign"] = cd.id
				step["players"].call())
			col.add_child(b)
		# The boot screen has its own main menu (Load Game / Join Online Game live there); the
		# mid-campaign New Campaign modal skips the menu, so it keeps them here.
		if allow_close:
			var load_btn := Button.new()
			load_btn.text = "Load Saved Game"
			load_btn.pressed.connect(func():
				_sfx_confirm()
				_on_saves_pressed())
			col.add_child(load_btn)
		if allow_close and on_join_online.is_valid():
			var sep := Label.new()
			sep.text = "— or —"
			sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sep.add_theme_color_override("font_color", Tokens.TEXT_DIM)
			col.add_child(sep)
			var join_btn := Button.new()
			join_btn.text = "Join Online Game"
			join_btn.tooltip_text = "Enter a code someone hosting a game gave you — they've already picked the campaign."
			join_btn.pressed.connect(func():
				_sfx_confirm()
				step["join_code"].call())
			col.add_child(join_btn)
		add_nav.call(step["menu"] if not allow_close else Callable())

	step["join_code"] = func():
		clear.call()
		add_heading.call("Enter the code your host gave you:")
		# `2026-09-21` (playtest 921): "make join game code copy and paste-able." JoinCode.decode
		# already strips dashes/spaces/case on its own, so max_length only needs to be generous
		# enough that a paste with a little extra whitespace around it doesn't get truncated
		# before that stripping ever runs.
		# `2026-09-24` (playtest 922): "text box is cut off on the left. Doesn't need to be so
		# big/long" — SIZE_EXPAND_FILL stretched it to the full width of this (wide) wizard
		# panel; a fixed, modest width sized to the code itself reads correctly instead.
		var code_row := HBoxContainer.new()
		code_row.alignment = BoxContainer.ALIGNMENT_CENTER
		code_row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		var code_edit := LineEdit.new()
		code_edit.placeholder_text = "XXXXX-XXXXX"
		code_edit.max_length = 20
		code_edit.custom_minimum_size = Vector2(180.0, 0.0)
		code_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		code_row.add_child(code_edit)
		var paste_btn := Button.new()
		paste_btn.text = "Paste"
		paste_btn.tooltip_text = "Paste the code from your clipboard"
		paste_btn.pressed.connect(func():
			_sfx_move()
			code_edit.text = DisplayServer.clipboard_get()
			code_edit.grab_focus())
		code_row.add_child(paste_btn)
		col.add_child(code_row)
		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		col.add_child(status)
		var connect_btn := Button.new()
		connect_btn.text = "Connect"
		connect_btn.pressed.connect(func():
			var decoded := JoinCode.decode(code_edit.text)
			if not bool(decoded.get("ok", false)):
				_sfx_cancel()
				status.text = "That code doesn't look right — check it and try again."
				return
			_sfx_confirm()
			on_join_online.call(String(decoded["ip"]), int(decoded["port"])))
		col.add_child(connect_btn)
		add_nav.call(step["menu"] if not allow_close else step["campaign"])

	# 2 Players (hotseat) skips faction + difficulty entirely — both sides are played, so
	# there's no side to pick, and difficulty only ever tuned the AI, which doesn't exist
	# here. `cd.factions[0]` just names who goes first each round (TurnResolver.end_turn
	# always hands the phase to Faction.opponent(player_faction) then back); it isn't a
	# "your side" choice the way it is for 1 Player.
	step["players"] = func():
		clear.call()
		var cd := ContentLoader.campaign_def(pick["campaign"])
		add_heading.call("%s — how many players?" % cd.display_name)
		var one := Button.new()
		one.text = "1 Player (vs AI)"
		one.pressed.connect(func():
			_sfx_confirm()
			step["faction"].call())
		col.add_child(one)
		# `2026-10-08` (playtest 104, item 8): "need a tooltip or some sort of text that says
		# the 1 Player vs AI option is also the split screen co-op option" — SWBF2's own local
		# split-screen is entirely its own business; Galactic Conquest only ever needs ONE
		# commander driving the campaign regardless of how many people are on that couch.
		var one_caption := Label.new()
		one_caption.text = "Also how to play local split-screen co-op — one commander either way."
		one_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		one_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		one_caption.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		one_caption.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_SMALL)
		col.add_child(one_caption)
		# `2026-10-08` (playtest 104, item 6): hidden from the normal flow — confused more
		# players than it helped. Flip "Enable 2 Player (hotseat)" in the Debug panel to
		# bring it back; the feature itself is unchanged.
		if GcPrefs.hotseat_enabled():
			var two := Button.new()
			two.text = "2 Players (hotseat)"
			two.tooltip_text = ("Both sides are played by hand, one at a time — hand the mouse "
				+ "and keyboard back and forth each turn. Perfectly even: no AI, no starting bonus.")
			two.pressed.connect(func():
				_sfx_confirm()
				on_start.call(cd.id, cd.factions[0], Difficulty.DEFAULT, true))
			col.add_child(two)
		if on_host_online.is_valid():
			var host_btn := Button.new()
			host_btn.text = "Host Online Game"
			host_btn.tooltip_text = ("Play with someone over the internet — you'll get a code "
				+ "to send them. Also perfectly even: no AI, no starting bonus.")
			host_btn.pressed.connect(func():
				_sfx_confirm()
				step["host_faction"].call())
			col.add_child(host_btn)
		add_nav.call(step["campaign"])

	step["host_faction"] = func():
		clear.call()
		var cd := ContentLoader.campaign_def(pick["campaign"])
		add_heading.call("%s online — play as (your opponent joins as the other side):" % cd.display_name)
		add_faction_row.call(cd.factions, func(f: StringName):
			_sfx_confirm()
			pick["after_kyber"] = func(): on_host_online.call(cd.id, f)
			pick["kyber_back"] = func(): step["host_faction"].call()
			step["kyber"].call())
		add_nav.call(step["players"], false)

	step["faction"] = func():
		clear.call()
		var cd := ContentLoader.campaign_def(pick["campaign"])
		add_heading.call("%s — play as:" % cd.display_name)
		add_faction_row.call(cd.factions, func(f: StringName):
			_sfx_confirm()
			pick["faction"] = f
			step["difficulty"].call())
		add_nav.call(step["players"])

	step["difficulty"] = func():
		clear.call()
		# `2026-10-08` (playtest 104, item 9): a real "DIFFICULTY" header (matching the other
		# steps' title treatment, not the small dim caption style) instead of a recap sentence
		# nobody needed ("Galactic Civil War as the Galactic Empire"); and each option's
		# description now sits ABOVE its own button, not below — stacked button/blurb/
		# button/blurb pairs read ambiguously about which blurb belongs to which button once
		# there's more than one on screen.
		var diff_title := Label.new()
		diff_title.text = "DIFFICULTY"
		diff_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		diff_title.add_theme_color_override("font_color", Tokens.TEXT)
		diff_title.add_theme_font_override("font", Tokens.FONT_BOLD)
		diff_title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
		col.add_child(diff_title)
		for level in Difficulty.ALL:
			var blurb := Label.new()
			blurb.text = Difficulty.blurb(level)
			blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			blurb.add_theme_color_override("font_color", Tokens.TEXT_DIM)
			col.add_child(blurb)
			# Button text can't wrap (Godot constraint) — name on the button, blurb above.
			var b := Button.new()
			b.text = Difficulty.display_name(level)
			b.pressed.connect(func():
				_sfx_confirm()
				if GcPrefs.offline_mode():
					on_start.call(pick["campaign"], pick["faction"], level, false)
					return
				pick["after_kyber"] = func():
					on_start.call(pick["campaign"], pick["faction"], level, false)
				pick["kyber_back"] = func(): step["difficulty"].call()
				step["kyber"].call())
			col.add_child(b)
		var offline_check := CheckBox.new()
		offline_check.text = "Offline mode — no KYBER (use Instant Action Overhaul mod)"
		offline_check.flat = true
		offline_check.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		offline_check.add_theme_color_override("font_hover_color", Tokens.TEXT)
		offline_check.add_theme_icon_override("unchecked", _checkbox_icon(false))
		offline_check.add_theme_icon_override("unchecked_disabled", _checkbox_icon(false))
		offline_check.add_theme_icon_override("checked", _checkbox_icon(true))
		offline_check.add_theme_icon_override("checked_disabled", _checkbox_icon(true))
		offline_check.add_theme_constant_override("h_separation", 8)
		offline_check.tooltip_text = ("Each battle shows the settings to recreate in Arcade / "
			+ "Instant Action; you report the winner by hand. Use when KYBER hosting is down.")
		offline_check.button_pressed = GcPrefs.offline_mode()
		offline_check.toggled.connect(func(on: bool): GcPrefs.set_offline_mode(on))
		col.add_child(offline_check)
		add_nav.call(step["faction"])

	(step["campaign"] if allow_close else step["menu"]).call()


## A short launch splash: the custom GC logo wipes in left-to-right behind a soft seam
## (the Star Wars scene-wipe effect), holds, then a second seam wipes the whole overlay away
## to reveal the start screen. It is pushed as a UI layer so the wizard behind it cannot take
## input while it is showing.
func _show_launch_splash() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var overlay := Control.new()
	overlay.name = "LaunchSplash"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# The shader itself paints the opaque dark backdrop, so the exit wipe can make the WHOLE
	# overlay transparent as its seam moves; a separate ColorRect would stay behind and hide
	# the start screen.
	var logo := TextureRect.new()
	logo.texture = SPLASH_LOGO
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SPLASH_WIPE_SHADER
	mat.set_shader_parameter("logo_texture", SPLASH_LOGO)
	mat.set_shader_parameter("logo_size", SPLASH_LOGO.get_size())
	mat.set_shader_parameter("wipe", -0.2)
	mat.set_shader_parameter("exit", -0.2)
	logo.material = mat
	overlay.add_child(logo)

	var fit_viewport := func():
		mat.set_shader_parameter("screen_size", get_viewport_rect().size)
	fit_viewport.call()
	get_viewport().size_changed.connect(fit_viewport)
	overlay.tree_exiting.connect(func():
		if get_viewport().size_changed.is_connected(fit_viewport):
			get_viewport().size_changed.disconnect(fit_viewport))

	overlay.set_meta("controller_cancel", Callable())
	overlay.tree_exiting.connect(func(): _pop_ui_layer(overlay))
	_push_ui_layer(overlay, Callable())

	var tw := create_tween()
	tw.tween_method(_splash_set_wipe.bind(mat), -0.2, 1.2, SPLASH_WIPE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(SPLASH_HOLD_TIME)
	tw.tween_method(_splash_set_exit.bind(mat), -0.2, 1.2, SPLASH_WIPE_OUT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(overlay.queue_free)


func _splash_set_wipe(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("wipe", value)


func _splash_set_exit(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("exit", value)


## Launch — or, when KYBER is already running without our plugin, restart — KYBER from the
## wizard's New Game step. Async because the restart waits for the old process to exit.
func _wizard_launch_kyber(status: Label, launch_b: Button, on_done: Callable) -> void:
	_sfx_confirm()
	var path := KyberPluginInstaller.configured_launcher_path()
	if path.is_empty():
		path = KyberPluginInstaller.detect_launcher()
	if path.is_empty() or not FileAccess.file_exists(path):
		status.text = "KYBER's launcher wasn't found. Set it in Settings → KYBER Setup… first."
		status.add_theme_color_override("font_color", Tokens.WARNING)
		return
	_kyber_running_checked_ms = 0
	if _kyber_running_cached():
		status.text = "Restarting KYBER…"
		status.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		launch_b.disabled = true
		KyberPluginInstaller.close_kyber()
		await get_tree().create_timer(1.0).timeout
	var res := KyberPluginInstaller.launch(path)
	if bool(res.get("ok", false)):
		on_done.call()
	else:
		status.text = String(res.get("reason", "Couldn't launch KYBER."))
		status.add_theme_color_override("font_color", Tokens.WARNING)
		launch_b.disabled = false


## Shown once at launch — there is no save/resume, every run is a fresh war. No Close
## button: a campaign has to be started to proceed at all.
func _show_start_screen() -> void:
	if is_instance_valid(_start_screen):
		return
	var shell := _modal_overlay("Galactic Conquest", Vector2(560, 720), true, false, true)
	_start_screen = shell["overlay"]
	var close_start_screen := func():
		if is_instance_valid(_start_screen):
			_start_screen.queue_free()
		_start_screen = null
		_layout_topbar()
	_build_campaign_wizard(shell["body"], false, Callable(),
		func(campaign_id: StringName, faction: StringName, level: StringName, two_player: bool):
			_start_new_campaign_at(campaign_id, level, faction, two_player)
			close_start_screen.call(),
		func(campaign_id: StringName, faction: StringName):
			_start_online_host(campaign_id, faction),
		func(ip: String, port: int):
			_start_online_join(ip, port))


## A successful online host dismisses whichever setup wizard launched it (the boot start
## screen or the mid-campaign New Campaign modal). Cancelling the hosting screen must leave
## that wizard in place, so this is called only from the host's finalize path.
func _close_setup_overlays() -> void:
	if is_instance_valid(_start_screen):
		_start_screen.queue_free()
		_start_screen = null
	if is_instance_valid(_difficulty_modal):
		_difficulty_modal.queue_free()
		_difficulty_modal = null
	_layout_topbar()


func _on_difficulty_pressed() -> void:
	if is_instance_valid(_difficulty_modal):
		return
	var shell := _modal_overlay("New Campaign", Vector2(560, 720), true, false, true)
	_difficulty_modal = shell["overlay"]
	var close := func():
		if is_instance_valid(_difficulty_modal):
			_difficulty_modal.queue_free()
		_difficulty_modal = null
	_build_campaign_wizard(shell["body"], true, close,
		func(campaign_id: StringName, faction: StringName, level: StringName, two_player: bool):
			_start_new_campaign_at(campaign_id, level, faction, two_player)
			close.call(),
		func(campaign_id: StringName, faction: StringName):
			_start_online_host(campaign_id, faction),
		func(ip: String, port: int):
			_start_online_join(ip, port))


func _start_new_campaign_at(campaign_id: StringName, level: StringName,
		faction: StringName = Faction.REPUBLIC, two_player: bool = false) -> void:
	CampaignSettings.save(campaign_id)
	# Don't clobber the saved 1-Player prefs with a 2-Player game's placeholder values —
	# the next 1-Player campaign should still start on whatever the player last chose.
	if not two_player:
		DifficultySettings.save(level)
		FactionSettings.save(faction)
	# The enemy's coin-flip opening move is deferred (ai_opening := false here, run by
	# _run_ai_opening after a beat) so the player sees the board as it starts and then WATCHES
	# the AI's fleets move, instead of the campaign appearing with them already relocated.
	var campaign_seed := randi()
	state = ContentLoader.new_campaign(campaign_id, faction, campaign_seed, level, false, two_player)
	_ai_opening_seed = campaign_seed if (not two_player and ContentLoader.ai_takes_opening(campaign_seed)) else -1
	_rebuild_map_for_campaign()
	_clear_selection()
	_reset_kyber_battle_state()
	_seen_battle_id = ""
	_battle_intro_end_ms = 0
	if is_instance_valid(_victory_modal):
		_victory_modal.queue_free()
	_victory_modal = null
	_victory_modal_shown_for = &""
	if two_player:
		_notice = "New %s campaign — 2 Player (hotseat). Both sides are played by hand; hand over the mouse and keyboard each turn." % \
			ContentLoader.campaign_def(campaign_id).display_name
	else:
		_notice = "New %s campaign — %s.%s" % [
			ContentLoader.campaign_def(campaign_id).display_name,
			Faction.display_name(faction),
			"  The enemy moves first…" if _ai_opening_seed >= 0 else ""]
	_refresh()
	if _ai_opening_seed >= 0:
		var token := state
		get_tree().create_timer(AI_OPENING_DELAY_S).timeout.connect(func(): _run_ai_opening(token))


## The deferred AI opening (see _start_new_campaign_at). `token` is the GalaxyState it was
## scheduled for — if the player started another campaign in the meantime, do nothing.
func _run_ai_opening(token: GalaxyState) -> void:
	if state != token or _ai_opening_seed < 0:
		return
	var seed := _ai_opening_seed
	_ai_opening_seed = -1
	TurnResolver.run_ai_opening(state, seed + state.turn)
	_notice = "The enemy moved first."
	_refresh()


## Tear down the 3D planet + fleet nodes and rebuild them for the current `state` — the
## planets (and their ids, layout, art) differ between campaigns, so a plain state swap
## isn't enough.
func _rebuild_map_for_campaign() -> void:
	if is_instance_valid(_planets_root):
		_planets_root.queue_free()
	_planet_nodes.clear()
	_planet_body_nodes.clear()
	_planet_glow_base_modulate.clear()
	_atmosphere_tint.clear()
	for id in _atmosphere_glow_nodes:
		var rect: Node = _atmosphere_glow_nodes[id]
		if is_instance_valid(rect):
			rect.queue_free()
	_atmosphere_glow_nodes.clear()
	for id in _insignia_icon_nodes:
		var icon: Node = _insignia_icon_nodes[id]
		if is_instance_valid(icon):
			icon.queue_free()
	_insignia_icon_nodes.clear()
	for id in _insignia_glow_nodes:
		var glow: Node = _insignia_glow_nodes[id]
		if is_instance_valid(glow):
			glow.queue_free()
	_insignia_glow_nodes.clear()
	for id in _fleet_nodes.keys():
		var n: Node = _fleet_nodes[id]
		if is_instance_valid(n):
			n.queue_free()
	_fleet_nodes.clear()
	_fleet_targets.clear()
	_build_map_3d()
	_sync_fleet_nodes()
	_reset_pad_cursor()


# --- Save / load -----------------------------------------------------------------
# `2026-09-20` (playtest 919): the campaign can be saved and reloaded. bridge/save_game.gd
# does the disk work; this is the UI around it — a "Save / Load Game" settings item and a
# "Load Saved Game" button on the start screen, both opening the same slot list, plus an
# automatic save at the start of each of the player's turns (slot "auto").

## Why saving/loading is unavailable right now, or "" if it's fine. Online, only the host holds
## the campaign and a client's copy is a mirror — neither side saves or loads mid-session.
func _saves_blocked_reason() -> String:
	if _gc_net != null:
		return "Saving and loading aren't available in an online game."
	return ""


func _on_saves_pressed() -> void:
	if is_instance_valid(_saves_modal):
		return
	var shell := _modal_overlay("Saved Games", Vector2(680, 440))
	_saves_modal = shell["overlay"]
	_saves_modal.set_meta("controller_cancel", _close_saves_modal)
	var col: VBoxContainer = shell["body"]
	var blocked := _saves_blocked_reason()
	if blocked != "":
		var l := Label.new()
		l.text = blocked
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		col.add_child(l)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	col.add_child(rows)
	if blocked == "":
		_fill_save_rows(rows)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func():
		_sfx_cancel()
		_close_saves_modal())
	col.add_child(close)


func _close_saves_modal() -> void:
	if is_instance_valid(_saves_modal):
		_saves_modal.queue_free()
	_saves_modal = null


func _fill_save_rows(rows: VBoxContainer) -> void:
	for c in rows.get_children():
		c.queue_free()
	# A campaign only exists once the start screen is gone.
	var can_save := not is_instance_valid(_start_screen)
	for slot in SaveGame.SLOTS:
		var desc := SaveGame.describe(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
		var label := Label.new()
		label.text = "%s
%s" % ["Autosave" if slot == "auto" else "Slot %s" % slot,
			desc if desc != "" else "— empty —"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Tokens.TEXT if desc != "" else Tokens.TEXT_DIM)
		row.add_child(label)
		if slot != "auto":
			var save_b := Button.new()
			save_b.text = "Save"
			save_b.disabled = not can_save
			save_b.pressed.connect(func():
				_save_to_slot(slot)
				_fill_save_rows(rows))
			row.add_child(save_b)
		var load_b := Button.new()
		load_b.text = "Load"
		load_b.disabled = desc == ""
		load_b.pressed.connect(func(): _load_saved_game(slot))
		row.add_child(load_b)
		rows.add_child(row)
	if _controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD:
		_set_mouse_ui_enabled(false)


func _save_to_slot(slot: String) -> void:
	if state == null or is_instance_valid(_start_screen) or _saves_blocked_reason() != "":
		return
	if SaveGame.save(slot, state):
		_sfx_confirm()
		_notice = "Game saved (slot %s)." % slot
		GcLog.note("save", "saved slot %s — turn %d" % [slot, state.turn])
	else:
		_sfx_cancel()
		_notice = "Couldn't write the save file."
	_refresh()


func _load_saved_game(slot: String) -> void:
	if _saves_blocked_reason() != "":
		return
	var loaded := SaveGame.load_state(slot)
	if loaded == null:
		_sfx_cancel()
		_notice = "That save couldn't be loaded (missing, damaged, or from a newer version)."
		_refresh()
		return
	_sfx_confirm()
	_close_saves_modal()
	if is_instance_valid(_start_screen):
		_start_screen.queue_free()
		_start_screen = null
	if is_instance_valid(_difficulty_modal):
		_difficulty_modal.queue_free()
		_difficulty_modal = null
	# Same reset a new campaign does (_start_new_campaign_at), minus picking anything.
	state = loaded
	_ai_opening_seed = -1
	CampaignSettings.save(state.campaign_id)
	_rebuild_map_for_campaign()
	_clear_selection()
	_reset_kyber_battle_state()
	_seen_battle_id = ""
	_battle_intro_end_ms = 0
	if is_instance_valid(_victory_modal):
		_victory_modal.queue_free()
	_victory_modal = null
	_victory_modal_shown_for = &""
	_autosave_key = "%d:%d" % [state.campaign_seed, state.turn]   # don't immediately overwrite "auto" with what was just loaded
	_notice = "Loaded — turn %d." % state.turn
	GcLog.note("save", "loaded slot %s — turn %d" % [slot, state.turn])
	_layout_topbar()
	_refresh()


## Slot "auto": written once at the start of each of the player's turns. Not while a battle is
## pending or the war is over, not before a campaign exists, not online, and not mid-way
## through the enemy's deferred opening move.
func _autosave_if_due() -> void:
	if state == null or is_instance_valid(_start_screen) or _gc_net != null or _ai_opening_seed >= 0:
		return
	if state.is_over() or state.has_pending_battle() or state.active_faction != state.player_faction:
		return
	var key := "%d:%d" % [state.campaign_seed, state.turn]
	if key == _autosave_key:
		return
	_autosave_key = key
	SaveGame.save("auto", state)


# --- Online multiplayer (GcNet, bridge/gc_net.gd) -----------------------------

## Auto-detects this machine's public IPv4 via a plain outbound HTTP GET (api.ipify.org —
## no key, no auth; a common pattern for exactly this, and the same "external check with a
## graceful fallback" shape Offline mode already uses for KYBER outages) so the host doesn't
## have to go look their own address up. Calls `on_done("")` on any failure (no internet,
## the service down, a timeout) — the caller falls back to a manual/local address; this is a
## convenience, never a hard dependency for hosting to work.
func _detect_public_ip(on_done: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 5.0
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var ip := body.get_string_from_utf8().strip_edges()
			if ip.split(".").size() == 4:
				on_done.call(ip)
				return
		on_done.call(""))
	if req.request("https://api.ipify.org") != OK:
		req.queue_free()
		on_done.call("")


## The first plausible private-LAN IPv4 address on this machine (192.168.x, 10.x, or
## 172.16-31.x — the ranges routers actually hand out; loopback and link-local excluded), or
## "" if none is found. Synchronous, no network round trip — used for a same-network join
## code shown immediately alongside the public one, which needs one. Also the whole reason
## testing two-player online on a single PC (or with someone else in the house) is practical
## at all: a public-IP code often can't even be dialled from the SAME network it was
## detected on (not every router supports NAT hairpin/loopback), and a real over-the-internet
## test needs a second machine regardless — this sidesteps that entirely.
func _local_lan_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.count(".") != 3:
			continue   # skip IPv6
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		if addr.begins_with("172."):
			var parts := addr.split(".")
			if parts.size() >= 2 and parts[1].is_valid_int():
				var second := int(parts[1])
				if second >= 16 and second <= 31:
					return addr
	return ""


## Host side: start listening, show the join code once the host's address is known, and
## create the campaign the instant a client actually connects (not before — there is no
## reason to run a live campaign nobody else has joined yet). `_apply_remote_intent` handles
## everything the client sends from here on; `_gc_net_broadcast` (called from every local
## action handler already) is what keeps the client's screen in sync with the host's own
## moves.
## A join code the host can hand to a friend: a read-only, SELECTABLE field (a plain Label
## has no text-selection UI at all, so there was no way to copy one out except retyping it)
## plus an explicit one-click Copy button for anyone who doesn't know Ctrl+C works on it.
## Added to `body`; returns the field so the caller can still just assign `.text` later,
## exactly like the Label it replaces.
func _join_code_row(body: Control, font_size: int) -> LineEdit:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(Tokens.SPACE_2))
	body.add_child(row)
	var field := LineEdit.new()
	field.editable = false
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", font_size)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.pressed.connect(func():
		_sfx_confirm()
		DisplayServer.clipboard_set(field.text))
	row.add_child(copy_btn)
	return field


## Both KYBER player ids GC's automatic team assignment can use (bridge/kyber_ea_id.gd,
## GcPrefs) — shown right on the Hosting screen itself, not only buried in KYBER Setup…, so
## it's part of starting an online game rather than something a first-time host has to
## already know to go looking for. `2026-09-21` (playtest 921): "make player type in KYBER
## ID before hosting/joining match so that we put them on correct team each time." Only the
## HOST'S own log can ever see either player's authentication (kyber_ea_id.gd's header), so
## both fields live here on the host's screen, not the joiner's — the friend just tells the
## host their own number once (it's in KYBER's log, or its admin/allow-list files).
func _kyber_ids_row(body: Control) -> void:
	var heading := Label.new()
	heading.text = "KYBER team auto-assignment (optional, but recommended)"
	heading.add_theme_color_override("font_color", Tokens.TEXT)
	body.add_child(heading)
	var blurb := Label.new()
	blurb.text = "Enter both your own and your friend's KYBER Player ID so every battle puts you on your own GC factions' teams automatically — skip this and you'll set teams by hand in KYBER instead."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(blurb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(Tokens.SPACE_2))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var my_edit := LineEdit.new()
	my_edit.placeholder_text = "Your KYBER Player ID"
	my_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_edit.custom_minimum_size.x = 180.0
	var my_saved := GcPrefs.my_kyber_player_id()
	my_edit.text = str(my_saved) if my_saved != 0 else ""
	grid.add_child(my_edit)
	var friend_edit := LineEdit.new()
	friend_edit.placeholder_text = "Friend's KYBER Player ID"
	friend_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friend_edit.custom_minimum_size.x = 180.0
	var friend_saved := GcPrefs.friend_kyber_player_id()
	friend_edit.text = str(friend_saved) if friend_saved != 0 else ""
	grid.add_child(friend_edit)
	var save_btn := Button.new()
	save_btn.text = "Save IDs"
	save_btn.pressed.connect(func():
		_sfx_confirm()
		GcPrefs.set_my_kyber_player_id(int(my_edit.text.strip_edges()) if my_edit.text.strip_edges().is_valid_int() else 0)
		GcPrefs.set_friend_kyber_player_id(int(friend_edit.text.strip_edges()) if friend_edit.text.strip_edges().is_valid_int() else 0))
	body.add_child(save_btn)


func _start_online_host(campaign_id: StringName, faction: StringName) -> void:
	if _gc_net != null:
		_gc_net.close()
	if _gc_net_udp_fallback != null:
		_gc_net_udp_fallback.close()
		_gc_net_udp_fallback = null
	_gc_net = GcNet.new()
	if not _gc_net.host(GcNet.DEFAULT_PORT, faction):
		_gc_net = null
		_notice = "Couldn't open port %d for hosting — is another copy of GC already hosting on this machine?" % GcNet.DEFAULT_PORT
		_refresh()
		return

	var shell := _modal_overlay("Hosting Online Game", Vector2(480, 700))
	var overlay: Control = shell["overlay"]
	var body: VBoxContainer = shell["body"]

	_kyber_ids_row(body)

	# A same-network code is shown immediately (no round trip needed) alongside the public
	# one — this is also what makes testing the whole feature on one PC, or with someone in
	# the same house, practical: the public-IP code often can't even be used from the SAME
	# network it was detected on (NAT hairpin/loopback isn't supported by every router), and
	# a real remote test needs a second machine anyway. `127.0.0.1` covers literally the same
	# PC; the LAN address (if one's found) covers a second PC on the same Wi-Fi/router.
	var lan_ip := _local_lan_ip()
	var local_heading := Label.new()
	local_heading.text = "Same computer or network:"
	local_heading.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(local_heading)
	var local_code_label := _join_code_row(body, 22)
	local_code_label.text = JoinCode.encode(lan_ip if lan_ip != "" else "127.0.0.1", GcNet.DEFAULT_PORT)

	var waiting := Label.new()
	waiting.text = "Waiting for a player to join…"
	waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(waiting)

	var internet_heading := Label.new()
	internet_heading.text = "Over the internet:"
	internet_heading.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(internet_heading)
	var status := Label.new()
	status.text = "Detecting your address…"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var code_label := _join_code_row(body, 28)
	var hint := Label.new()
	hint.text = "Send the matching code to whoever is joining."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(hint)

	# Port forwarding is the one step that used to require the host to log into their own
	# router — UPnP (bridge/gc_upnp.gd) automates it on most home routers, which already
	# support it for things like game consoles opening their own ports with no manual setup.
	# `2026-09-22` (playtest 921: "I don't want users to have to download a program or mess
	# with forwarding ports"): when UPnP fails, GC now ALSO tries a UDP hole-punch fallback
	# automatically (see _try_holepunch_fallback below) — best-effort, not a guaranteed fix
	# (bridge/gc_net.gd's own header spells out exactly which NAT types it can/can't get
	# through), with the manual/VPN-mesh instructions as the last-resort fallback under that.
	var port_status := Label.new()
	port_status.text = "Setting up automatic port forwarding (UPnP)…"
	port_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	port_status.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(port_status)
	# A Dictionary, not separate Node locals plus a plain bool: closures below need to share
	# "are we done" and several Labels, but GDScript lambdas capture a plain local BY VALUE at
	# creation (same caveat _build_campaign_wizard's own `step` dict works around), so a bare
	# bool would give each closure its own frozen copy. A Dictionary is captured by reference,
	# so `ui["done"]` is genuinely shared. It also sidesteps a second, separate problem: the
	# host can connect (peer_joined) well before the async IP lookup below ever returns, and a
	# Node held as a lambda's OWN direct capture gets forcibly nulled with a logged "Lambda
	# capture was freed" engine error the instant it's freed — checked or not, before the
	# closure body even runs — whereas a Node reached indirectly through a Dictionary the
	# closure captures is never treated as one of the closure's own captures at all, so
	# freeing it elsewhere logs nothing (the `ui["done"]` guard still has to run first, though
	# — the reference itself would otherwise dangle just as it would through any other
	# indirection).
	var ui := {"done": false, "status": status, "code_label": code_label, "port_status": port_status, "body": body}
	var cancel := Button.new()
	cancel.text = "Back"
	cancel.pressed.connect(func():
		_sfx_cancel()
		ui["done"] = true
		if _gc_net != null:
			_gc_net.close()
			_gc_net = null
		if _gc_net_udp_fallback != null:
			_gc_net_udp_fallback.close()
			_gc_net_udp_fallback = null
		GcUpnp.remove_mapping(GcNet.DEFAULT_PORT)   # best-effort — never blocks Cancel on it
		overlay.queue_free())
	body.add_child(cancel)
	overlay.set_meta("controller_cancel", func(): cancel.pressed.emit())

	# Shared by whichever transport actually gets a peer first (see _try_holepunch_fallback) —
	# TCP if UPnP worked (or a LAN/same-PC joiner used the code above regardless of UPnP), the
	# UDP fallback otherwise. Only ever runs once (`ui["done"]` guard); a mid-game disconnect
	# afterward is a known v1 limitation either way (see gc_net.gd).
	var finalize := func(net: GcNet) -> void:
		if ui["done"]:
			return
		ui["done"] = true
		if net != _gc_net:
			_gc_net.close()
			_gc_net = net
		if _gc_net_udp_fallback != null and _gc_net_udp_fallback != net:
			_gc_net_udp_fallback.close()
		_gc_net_udp_fallback = null
		overlay.queue_free()
		_close_setup_overlays()
		_gc_net.intent_received.connect(_apply_remote_intent)
		_gc_net.disconnected.connect(_on_gc_net_disconnected)
		# From this instant on, this machine's own KYBER log is the ONLY place either
		# player's authentication can ever be recorded (KYBER's plugin runs in the
		# server realm, i.e. on the HOST — see bridge/kyber_ea_id.gd's header). Marking
		# the offset here, not earlier, is what keeps a stale identity from some
		# unrelated match today from ever being mistaken for one of this campaign's
		# two players.
		_kyber_auth_scan_offset = KyberEaId.current_log_length()
		state = ContentLoader.new_campaign(campaign_id, faction, randi(), Difficulty.DEFAULT, false, true)
		_gc_net.host_send_hello(faction, campaign_id, state.to_dict())
		_rebuild_map_for_campaign()
		_clear_selection()
		_reset_kyber_battle_state()
		_seen_battle_id = ""
		_battle_intro_end_ms = 0
		_notice = "A player joined! New %s campaign — online, you play %s." % [
			ContentLoader.campaign_def(campaign_id).display_name, Faction.display_name(faction)]
		_refresh()
		# `2026-09-24` (playtest 922, item 7): a persistent (NOT one-shot) listener from here on
		# — the host's TCP socket keeps accepting a fresh connection after a drop (GcNet's own
		# `_poll_host` comment says so), so a later peer_joined IS a genuine reconnect, not the
		# first join `finalize` above already handled. Resends the CURRENT campaign state rather
		# than creating a new one. Known gap: this only actually fires for the TCP transport —
		# the UDP hole-punch fallback has no way yet to notice a mid-game drop at all (see
		# gc_net.gd's own header), so a UDP-connected game can't reconnect today.
		_gc_net.peer_joined.connect(func():
			if not is_instance_valid(self):
				return
			GcLog.note("net", "player reconnected — resending current state")
			_dismiss_disconnect_modal()
			_notice = "%s reconnected." % Faction.display_name(Faction.opponent(_current_seat_faction()))
			# Reuses the exact same `hello` message the FIRST join sends, deliberately — the
			# client's own `_start_online_join` already knows how to turn one into a working
			# session (assign faction, load `state`) with no reconnect-specific code needed
			# there at all; a bare `send_state` would need the client to already have a
			# `state_received` listener wired up, which only `joined`/`hello` sets up.
			_gc_net.host_send_hello(_gc_net.my_faction, state.campaign_id, state.to_dict())
			_refresh())
	_gc_net.peer_joined.connect(func(): finalize.call(_gc_net), CONNECT_ONE_SHOT)

	GcUpnp.try_map_port_async(GcNet.DEFAULT_PORT, func(result: Dictionary):
		if ui["done"]:
			return   # cancelled or already joined before this came back
		if bool(result.get("ok", false)):
			ui["port_status"].text = "Port forwarding: done automatically (UPnP) ✓"
		else:
			ui["port_status"].text = ("Automatic port forwarding didn't work (%s) — trying a "
				+ "direct connection instead (no port forwarding needed)…") % String(result.get("reason", "unknown reason"))
			_try_holepunch_fallback(ui, body, faction, finalize))

	_detect_public_ip(func(ip: String):
		if ui["done"]:
			return   # already joined, or cancelled
		if ip == "":
			ui["status"].text = "Couldn't auto-detect it — use the same-network code above instead."
			return
		ui["status"].text = "Your address:"
		var code := JoinCode.encode(ip, GcNet.DEFAULT_PORT)
		ui["code_label"].text = code if code != "" else "(couldn't build a code for %s)" % ip)


## Client side: dial the host directly, wait for `hello` (assigns our faction and hands over
## the freshly-created campaign in one message), then behave exactly like the host's own
## screen from then on — same map, same panel, same buttons — except every action becomes
## an intent instead of a direct TurnResolver call (see _is_net_client / _on_move_pressed
## etc.) and the state itself only ever changes when the host says so.
## `2026-09-22` (playtest 921): UPnP just failed, so a plain TCP listen isn't reachable from
## outside this network. Tries a UDP hole-punch instead (bridge/gc_stun.gd + GcNet's own
## UDP transport) — no download, no router login, but genuinely best-effort: it cannot get
## through a symmetric NAT or CGNAT on either end (see gc_net.gd's header for exactly what
## that means). `_gc_net_udp_fallback` races `_gc_net`'s own still-listening TCP socket;
## `finalize` is shared, so whichever one actually gets a peer first wins outright.
func _try_holepunch_fallback(ui: Dictionary, body: VBoxContainer, faction: StringName, finalize: Callable) -> void:
	_gc_net_udp_fallback = GcNet.new()
	var bound := _gc_net_udp_fallback.host_udp(GcNet.DEFAULT_PORT, faction)
	if not bool(bound.get("ok", false)):
		_gc_net_udp_fallback = null
		_show_holepunch_gave_up(ui, body, "couldn't open a local UDP socket (%s)" % String(bound.get("reason", "unknown reason")))
		return

	var punch_heading := Label.new()
	punch_heading.text = "Trying a direct connection (no port forwarding)…"
	punch_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	punch_heading.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(punch_heading)
	ui["punch_heading"] = punch_heading

	GcStun.discover_async(_gc_net_udp_fallback.udp_socket(), func(result: Dictionary):
		if ui["done"] or _gc_net_udp_fallback == null:
			return   # cancelled, or the TCP side already won while STUN was in flight
		if not bool(result.get("ok", false)):
			_gc_net_udp_fallback = null
			_show_holepunch_gave_up(ui, body, String(result.get("reason", "couldn't reach a STUN server")))
			return
		var code := JoinCode.encode(String(result["ip"]), int(result["port"]))
		(ui["punch_heading"] as Label).text = "No port forwarding needed — give your friend THIS code instead:"
		var punch_code_label := _join_code_row(body, 22)
		punch_code_label.text = code if code != "" else "(couldn't build a code for %s)" % String(result["ip"])
		var punch_hint := Label.new()
		punch_hint.text = "Best-effort — works for most home routers, but not every one. Still stuck? Use the manual options below."
		punch_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		punch_hint.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		body.add_child(punch_hint)
		_show_manual_fallback(ui, body)
		if _gc_net_udp_fallback != null:
			_gc_net_udp_fallback.peer_joined.connect(func(): finalize.call(_gc_net_udp_fallback), CONNECT_ONE_SHOT))


func _show_holepunch_gave_up(ui: Dictionary, body: VBoxContainer, reason: String) -> void:
	if ui.has("punch_heading") and is_instance_valid(ui["punch_heading"]):
		(ui["punch_heading"] as Label).text = "Direct connection didn't work (%s)." % reason
	_show_manual_fallback(ui, body)


## The last-resort text, shown once UPnP AND the hole-punch attempt have both given up (or
## the hole-punch code above is showing but might still not get through) — named once, not
## repeated per failure branch.
func _show_manual_fallback(ui: Dictionary, body: VBoxContainer) -> void:
	if ui.has("manual_fallback_shown"):
		return
	ui["manual_fallback_shown"] = true
	# A VPN-style mesh tool (Tailscale, ZeroTier, Hamachi, Radmin) puts both PCs on one virtual
	# LAN with no router login at all — not something GC can set up FOR them (a real relay
	# server is the built-in fix and is deliberately not built, see gc_net.gd's header), but a
	# real, concrete second option worth naming rather than leaving port forwarding as the
	# only answer.
	var manual := Label.new()
	manual.text = ("Still no luck? Forward TCP port %d to this PC in your router settings and "
		+ "use the address code above, or install a free VPN-style tool like Tailscale, ZeroTier "
		+ "or Hamachi on both PCs — it puts you on one virtual network with no router setup at "
		+ "all, then build a join code by hand from the IP it gives you instead of your real one.") % GcNet.DEFAULT_PORT
	manual.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manual.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	body.add_child(manual)


func _start_online_join(ip: String, port: int) -> void:
	_last_join_ip = ip
	_last_join_port = port
	if _gc_net != null:
		_gc_net.close()
	if _gc_net_udp_fallback != null:
		_gc_net_udp_fallback.close()
		_gc_net_udp_fallback = null
	_gc_net = GcNet.new()

	var shell := _modal_overlay("Joining Online Game", Vector2(440, 260))
	var overlay: Control = shell["overlay"]
	var body: VBoxContainer = shell["body"]
	var status := Label.new()
	status.text = "Connecting to %s:%d…" % [ip, port]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	# A one-element array, not a plain bool — see the matching comment in _start_online_host
	# for why: three separate closures need to share this flag, and a plain local would give
	# each of them its own frozen copy instead.
	var overlay_done := [false]
	var cancel := Button.new()
	cancel.text = "Back"
	cancel.pressed.connect(func():
		_sfx_cancel()
		overlay_done[0] = true
		if _gc_net != null:
			_gc_net.close()
			_gc_net = null
		if _gc_net_udp_fallback != null:
			_gc_net_udp_fallback.close()
			_gc_net_udp_fallback = null
		overlay.queue_free())
	body.add_child(cancel)
	overlay.set_meta("controller_cancel", func(): cancel.pressed.emit())

	# A shared Dictionary (not a plain String local) for the same reason as overlay_done
	# above — the disconnected closure below needs whatever the LAST error said, e.g. "This
	# game already has two players" (GcNet.ALREADY_FULL_REASON) rather than the generic
	# guess, and a bare local would give each closure its own frozen copy.
	var join_status := {"last_error": ""}

	# Shared by whichever transport actually connects first — `2026-09-22` (playtest 921): the
	# code we were given could be a plain TCP/UPnP address OR a hole-punch one (see
	# _start_online_host's own _try_holepunch_fallback) and there's no way to tell which just
	# from the code text, so BOTH are always tried at once against the same ip:port; whichever
	# one is reachable wins outright and the other is closed.
	var finalize := func(net: GcNet, host_faction: StringName, my_faction: StringName,
			campaign_id: StringName, initial_state: Dictionary) -> void:
		if overlay_done[0]:
			return
		overlay_done[0] = true
		if net != _gc_net:
			_gc_net.close()
			_gc_net = net
		if _gc_net_udp_fallback != null and _gc_net_udp_fallback != net:
			_gc_net_udp_fallback.close()
		_gc_net_udp_fallback = null
		overlay.queue_free()
		_close_setup_overlays()
		_gc_net.state_received.connect(_on_gc_net_state_received)
		_gc_net.error_received.connect(_on_gc_net_error_received)
		_gc_net.disconnected.connect(_on_gc_net_disconnected)
		# Only the host ever drives a real KYBER match (see gc_net.gd's header) — a client's
		# own local _kyber_link would at best be inert (nothing local for it to connect to)
		# and at worst, if the player also happened to have KYBER + our plugin running on
		# their OWN machine, could stage and apply a battle result straight into this
		# client's local `state` outside the host's authority entirely. Closing it here,
		# the instant a join succeeds, is the active fix — not just documenting the risk.
		if _kyber_link != null:
			_kyber_link.close_link()
		state = GalaxyState.from_dict(initial_state)
		_rebuild_map_for_campaign()
		_clear_selection()
		_reset_kyber_battle_state()
		_seen_battle_id = ""
		_battle_intro_end_ms = 0
		_notice = "Connected! New %s campaign — online, you play %s." % [
			ContentLoader.campaign_def(campaign_id).display_name, Faction.display_name(my_faction)]
		_refresh()

	var tcp_ok := _gc_net.join(ip, port)
	if tcp_ok:
		_gc_net.joined.connect(func(hf, mf, cid, st): finalize.call(_gc_net, hf, mf, cid, st), CONNECT_ONE_SHOT)
		_gc_net.error_received.connect(func(reason: String): join_status["last_error"] = reason)
		_gc_net.disconnected.connect(func():
			if not overlay_done[0]:
				_gc_net = null   # this attempt failed; the UDP one (if any) is still live
				_update_join_status_if_both_failed(status, join_status))
	else:
		_gc_net = null

	# The UDP hole-punch attempt, in parallel — uses an ephemeral local port (0 asks the OS
	# to pick one; nothing else needs to know it, unlike the host's fixed DEFAULT_PORT which
	# has to appear in the code the host shows).
	_gc_net_udp_fallback = GcNet.new()
	var udp_bound := _gc_net_udp_fallback.join_udp(0, ip, port)
	if bool(udp_bound.get("ok", false)):
		var udp_net := _gc_net_udp_fallback
		udp_net.joined.connect(func(hf, mf, cid, st): finalize.call(udp_net, hf, mf, cid, st), CONNECT_ONE_SHOT)
		udp_net.error_received.connect(func(reason: String): join_status["last_error"] = reason)
		udp_net.disconnected.connect(func():
			if not overlay_done[0]:
				if _gc_net_udp_fallback == udp_net:
					_gc_net_udp_fallback = null   # this attempt failed; the TCP one (if any) is still live
				_update_join_status_if_both_failed(status, join_status))
	else:
		_gc_net_udp_fallback = null

	if not tcp_ok and _gc_net_udp_fallback == null:
		status.text = "Couldn't reach %s:%d." % [ip, port]
		return
	status.text = "Connecting to %s:%d… (trying a direct connection too — this can take up to 15s)" % [ip, port]


## Both the TCP and UDP join attempts failed (each nulls its own field on the way out — see
## _start_online_join) — say so, preferring whichever attempt's error actually explained why
## (e.g. GcNet.ALREADY_FULL_REASON) over a generic guess. No-op while either one is still live.
func _update_join_status_if_both_failed(status: Label, join_status: Dictionary) -> void:
	if _gc_net != null or _gc_net_udp_fallback != null:
		return
	status.text = String(join_status["last_error"]) if String(join_status["last_error"]) != "" \
		else "Couldn't connect — the host may not be running yet, or the port isn't forwarded."


## Client side: the host sent a fresh snapshot after applying either its own move or one of
## our intents — this is the ONLY place a network client's `state` ever changes. Clears the
## local selection rather than trying to preserve it across a state we didn't produce
## ourselves (a stale fleet/planet reference is a needless risk for a cheap-to-redo click).
func _on_gc_net_state_received(state_dict: Dictionary) -> void:
	state = GalaxyState.from_dict(state_dict)
	_clear_selection()
	_refresh()


## Client side: the host rejected our last intent (out of turn, an invalid move, a fleet
## that wasn't ours…) — surfaced the same way every other rejected action already is.
func _on_gc_net_error_received(reason: String) -> void:
	_notice = reason
	_refresh()


## `2026-09-24` (playtest 922, item 7): "should have pop up window with message if one player
## leaves or crashes." The old plain `_notice` line was easy to miss — this is a real modal,
## and (client only) a real way back in: the host's own TCP listener never actually stopped
## (`GcNet._poll_host`'s own comment: "keep listening — the server itself stays open for a
## rejoin") and, for the UDP transport, nothing stops binding a fresh socket and punching
## again either — so a client that dials back in mid-game genuinely can reconnect. The HOST
## side has nothing to dial (it's the one being reconnected TO), so its modal is just the
## notice; _start_online_host's own persistent (non-one-shot) peer_joined listener, wired up
## once the game actually starts, is what resends state and dismisses this when they're back.
func _on_gc_net_disconnected() -> void:
	if _gc_net != null and _gc_net.role == GcNet.Role.CLIENT:
		_show_disconnect_modal("Connection to the host was lost.", true)
	else:
		_show_disconnect_modal("The other player disconnected. Still hosting — GC will resume the moment they reconnect.", false)
	_notice = ""
	_refresh()


func _show_disconnect_modal(message: String, offer_reconnect: bool) -> void:
	if is_instance_valid(_disconnect_modal):
		_disconnect_modal.queue_free()
	var shell := _modal_overlay("Connection Lost", Vector2(420, 220))
	_disconnect_modal = shell["overlay"]
	_disconnect_modal.set_meta("controller_cancel", _dismiss_disconnect_modal)
	var body: VBoxContainer = shell["body"]
	var msg := Label.new()
	msg.text = message
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(msg)
	if offer_reconnect:
		var reconnect_btn := Button.new()
		reconnect_btn.text = "Try to reconnect"
		reconnect_btn.pressed.connect(func():
			_sfx_confirm()
			var ip := _last_join_ip
			var port := _last_join_port
			_dismiss_disconnect_modal()
			_start_online_join(ip, port))
		body.add_child(reconnect_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func():
		_sfx_cancel()
		_dismiss_disconnect_modal())
	body.add_child(close_btn)


func _dismiss_disconnect_modal() -> void:
	if is_instance_valid(_disconnect_modal):
		_disconnect_modal.queue_free()
	_disconnect_modal = null


## Host side: apply an intent from the network client through the exact same TurnResolver
## entry points the local UI already uses (see gc_net.gd's header for the intent shapes),
## then push the result back. Rejects anything that isn't actually the client's turn, or
## names a fleet that isn't theirs, rather than silently letting the two sides' states
## diverge — core/ has no such check built in on purpose (AiCommander and plenty of tests
## call these functions directly with no "whose turn" gate at all), so it belongs here, at
## the one boundary that actually has to distrust its input.
func _apply_remote_intent(action: Dictionary) -> void:
	if _gc_net == null:
		return
	var client_faction := Faction.opponent(_gc_net.my_faction)
	var kind := String(action.get("type", ""))
	if kind != "battle_result" and state.active_faction != client_faction:
		_gc_net.host_send_error("Not your turn yet.")
		return
	match kind:
		"move":
			var fleet := state.get_fleet(StringName(action.get("fleet_id", &"")))
			if fleet == null or fleet.owner != client_faction:
				_gc_net.host_send_error("That fleet isn't yours.")
			else:
				var outcome := TurnResolver.move_fleet(state, fleet.id, StringName(action.get("dest", &"")))
				if outcome.status == TurnResolver.MoveStatus.INVALID:
					_gc_net.host_send_error(outcome.reason)
		"buy":
			var bo := TurnResolver.buy_fleet(state, client_faction)
			if not bo.ok:
				_gc_net.host_send_error(bo.reason)
		"reinforce":
			var rf := state.get_fleet(StringName(action.get("fleet_id", &"")))
			if rf == null or rf.owner != client_faction:
				_gc_net.host_send_error("That fleet isn't yours.")
			else:
				var ro := TurnResolver.reinforce_fleet(state, rf.id)
				if not ro.ok:
					_gc_net.host_send_error(ro.reason)
		"train":
			var tf := state.get_fleet(StringName(action.get("fleet_id", &"")))
			if tf == null or tf.owner != client_faction:
				_gc_net.host_send_error("That fleet isn't yours.")
			else:
				var to_ := TurnResolver.buy_combat_training(state, tf.id)
				if not to_.ok:
					_gc_net.host_send_error(to_.reason)
		"end_turn":
			TurnResolver.end_turn(state)
		"battle_result":
			if not state.has_pending_battle():
				_gc_net.host_send_error("No battle is pending.")
			else:
				var request := Battle.Request.from_dict(state.pending_battle)
				var result := TurnResolver.abandoned_result(request, client_faction) \
					if bool(action.get("abandoned", false)) \
					else TurnResolver.manual_result(request, StringName(action.get("victor", &"")))
				TurnResolver.resolve_player_battle(state, result)
		_:
			_gc_net.host_send_error("Unrecognised action.")
			return
	_gc_net_broadcast()
	_refresh()


# --- Offline mode ------------------------------------------------------

## The battle-panel card for offline mode: what to set up in Arcade / Instant Action.
func _offline_briefing_text() -> String:
	if not state.has_pending_battle():
		return ""
	var request := Battle.Request.from_dict(state.pending_battle)
	var planet := state.get_planet(request.planet_id)
	var b := KyberBridge.offline_briefing(request, planet, ContentLoader.load_map_catalog(state.campaign_id),
		_current_seat_faction(), state.difficulty)
	var lane := not planet.capturable
	var lines := PackedStringArray()
	lines.append("[b]Offline battle[/b] — recreate this in Arcade / Instant Action:")
	lines.append("Map: %s — %s. Bots ~%d allied vs ~%d enemy. AI: %s. You play: %s. Report the winner below." % [
		String(b["map_name"]) if lane else planet.display_name, b["mode_name"],
		int(b["your_bots"]), int(b["enemy_bots"]), b["ai_difficulty"], b["your_side"]])
	if lane and _is_gcw():
		lines.append("[i]Set Era to \"Original\" (cross-era); this Sequel ship co-op needs it.[/i]")
	return "\n".join(lines)


# --- KYBER match flow ----------------------------------------------------

func _pending_team_one() -> StringName:
	if not state.has_pending_battle():
		return Faction.REPUBLIC
	var request := Battle.Request.from_dict(state.pending_battle)
	var planet := state.get_planet(request.planet_id)
	var catalog := ContentLoader.load_map_catalog(state.campaign_id)
	var params := KyberBridge.match_params(request, planet, catalog, _current_seat_faction(), false, GcPrefs.offline_mode())
	var entry := ContentLoader.find_map(catalog, String(params["map_key"]))
	return StringName(entry.get("team_one_faction", Faction.REPUBLIC))


## A short description of one side's force, for the plugin's team labels / logs.
func _force_label(request: Battle.Request, is_attacker: bool) -> String:
	if is_attacker:
		return "fleet s%d t%d%s" % [request.attacker_strength, request.attacker_reinforcement,
			" ct%d" % request.attacker_training if request.attacker_training > 0 else ""]
	if request.defender_fleet_strength <= 0:
		return "garrison only"
	return "fleet s%d t%d%s" % [request.defender_fleet_strength, request.defender_reinforcement,
		" ct%d" % request.defender_training if request.defender_training > 0 else ""]


## 0 -> "", 1 -> "I", 2 -> "II", 3 -> "III".
func _roman(n: int) -> String:
	return ["", "I", "II", "III"][clampi(n, 0, 3)]


func _stage_kyber_result(result: Dictionary) -> void:
	if not state.has_pending_battle():
		GcLog.note("battle", "KYBER sent a result but no battle is pending — ignored")
		return
	# Don't let a later undetermined result (the plugin's rotation-advance winner_team:0,
	# or a re-emit) clobber a determinate one already staged — e.g. the KYBER-log winner.
	if not _kyber_staged.is_empty() \
			and int(_kyber_staged.get("winner_team", 0)) != 0 \
			and int(result.get("winner_team", 0)) == 0:
		GcLog.note("battle", "kept the staged winner — later result was undetermined")
		return
	_kyber_staged = result
	_kyber_awaiting = {}
	_kyber_watch.disarm()
	GcLog.note("battle", "KYBER result is ready to apply")
	# Replace the stale "waiting for the match to load" / "play the round" line so the panel
	# actually says the battle is over. Auto-apply / the Apply button clear it again.
	if int(result.get("winner_team", 0)) == 0:
		if _battle_is_coop() and _coop_result_hold_active():
			_notice = ("KYBER can't read co-op results — the result buttons unlock after the "
				+ "round has had time to play out.")
		else:
			_notice = "KYBER can't read co-op match results — log the match result below." if _battle_is_coop() 			else "KYBER match over — no automatic winner. Report it with the buttons below."
	else:
		_notice = "KYBER match over — %s.  Click \"Apply result\"." % _describe_staged_result()
	# The outcome, into match chat — this is the earliest point GC actually knows it
	# (Level:Complete already fired for the plugin to have sent this at all, so the round
	# is ending or just has; best-effort, may or may not still be visible in time).
	if _kyber_link != null and _kyber_link.is_online():
		_gc_chat(_result_chat_line())
		_schedule_match_restart(result)
	# Bring GC back to the front — the battle is over.
	_exit_battle_view()
	# Optionally fold a determinate result straight in, no click.
	if GcPrefs.auto_apply_results() and int(result.get("winner_team", 0)) != 0:
		if _apply_staged_result():
			GcLog.note("battle", "auto-applied the KYBER result")
	_refresh()


## The KYBER log named a round winner that the plugin couldn't read (Supremacy / GA).
## Stage it like a plugin result — unless the plugin already gave a determinate one.
func _stage_log_winner(team: int) -> void:
	if not state.has_pending_battle():
		return
	if not _kyber_staged.is_empty() and int(_kyber_staged.get("winner_team", 0)) != 0:
		return
	GcLog.note("battle", "KYBER log named team %d the round winner — plugin had no score" % team)
	_stage_kyber_result({
		"type": "gc_result",
		"winner_team": team,
		"teams": {},
		"reason": "read from the KYBER log",
		"source": "kyber_log",
	})


## KYBER's log shows the Clone Wars capital-ship sub-level streaming in — a team just won
## the ground phase. `boarded_faction` owns the ship that loaded, so they LOST the ground
## phase; the other side won. `Kyber.endgameteam<N>` is deliberately NOT used: its EOR /
## outro listener cleanup crashes the game ~4.8 s later with the same bad 0x100597302
## pointer, even after the capital-ship sub-level has fully loaded. Instead, stage the
## ground winner in GC and let the normal result restart switch maps.
func _skip_capital_ship_phase(boarded_faction: StringName) -> void:
	if _is_gcw() or not state.has_pending_battle() or _kyber_link == null:
		return
	var pb := state.get_planet(StringName(state.pending_battle.get("planet_id", &"")))
	if pb != null and not pb.capturable:
		return   # a space-lane battle IS the capital-ship co-op — there's no ground phase
	var battle_id := String(state.pending_battle.get("id", ""))
	if _groundwin_pending_battle_id == battle_id:
		return   # already staged for this battle
	_groundwin_pending_battle_id = battle_id
	var ground_winner := Faction.opponent(boarded_faction)
	var winner_team := 1 if _pending_team_one() == ground_winner else 2
	GcLog.note("battle", "ground phase ended — staging %s (team %d) and switching maps without Kyber.endgameteam" % [
		Faction.display_name(ground_winner), winner_team])
	_stage_kyber_result({
		"type": "gc_result",
		"winner_team": winner_team,
		"teams": {},
		"reason": "ground phase ended - ship phase skipped",
		"source": "ground_phase",
	})


func _on_kyber_play_pressed() -> void:
	if not state.has_pending_battle() or _kyber_link == null:
		return
	if _is_net_client():
		return   # only the host ever drives a real KYBER match — see _refresh()'s kyber_ui gate
	_sfx_confirm()
	var request := Battle.Request.from_dict(state.pending_battle)
	var planet := state.get_planet(request.planet_id)
	var params := KyberBridge.match_params(request, planet, ContentLoader.load_map_catalog(state.campaign_id), _current_seat_faction(), state.two_player)
	if not bool(params["ok"]):
		_notice = String(params["reason"])
		_refresh()
		return

	if bool(params.get("fallback", false)):
		_notice = String(params["reason"])
	# match_params returns per-role values; map attacker/defender onto teams 1/2 by which
	# faction team 1 is on that map. Reinforcement → bot count + per-team aim.
	var one := String(params["team_one_faction"])
	var attacker_is_one := one == String(request.attacker)
	var bots_t1 := int(params["attacker_bots"]) if attacker_is_one else int(params["defender_bots"])
	var bots_t2 := int(params["defender_bots"]) if attacker_is_one else int(params["attacker_bots"])
	# The human(s) take a slot an AI would have had, so a 24v24 is really 23 AI + you vs 24 AI.
	# Online: a real human on each team. Otherwise: the one person at the controls, on the seat's team.
	var seat_team := 1 if one == String(_current_seat_faction()) else 2
	var coop_role := String(params.get("coop_role", ""))
	# `2026-09-24` (playtest 922, item 5): "co-op needs to put opposing player on opposite
	# team... this has been tested and is known to work" — overturns the 2026-09-21 guess
	# that co-op only has one human-eligible side. It has two, exactly like GA/Blast/Supremacy;
	# what was actually broken was GC not reliably SENDING the per-id `teamid` pin (see the
	# auto-assign rewrite below) that puts a specific human on co-op's normally-AI-only side.
	var humans_t1 := 1 if (_gc_net != null or seat_team == 1) else 0
	var humans_t2 := 1 if (_gc_net != null or seat_team == 2) else 0
	var reserved := KyberBridge.reserve_human_slots(bots_t1, bots_t2, humans_t1, humans_t2)
	bots_t1 = reserved[0]
	bots_t2 = reserved[1]
	var aim_t1 := float(params["aim_t1"])
	var aim_t2 := float(params["aim_t2"])
	# Which team the human is on: SWBF2's fixed layout is Team 1 = light side, Team 2 =
	# dark side, so this is by faction, never by the map's team_one_faction. In two-player
	# there's a human on BOTH teams — forcibly holding just one onto its team (the plugin's
	# enforce_human_team) would fight the OTHER human's own team every few seconds, so send
	# 0 ("don't touch") instead of picking a side.
	var human_team := 0 if state.two_player else Faction.team_side(_current_seat_faction())
	var defender_team := Faction.team_side(request.defender)

	# Online two-player, hosting: try to automatically pin each real human to their own team
	# by EA account id, so neither player has to open KYBER's own team menu and set it by
	# hand every single match. Only possible from the host's own machine — KYBER's plugin
	# runs in the "server realm," i.e. only the HOST's own log can ever show either player's
	# authentication (see bridge/kyber_ea_id.gd's header).
	#
	# Which of the (at most two) ids found is the HOST is decided by GcPrefs.my_kyber_player_id
	# — a value the host sets once (KYBER Setup… → "My KYBER Player ID") — NEVER by which one
	# authenticated first. An earlier version of this guessed "first since hosting began ==
	# host" reasoning from the architecture (the host must click Host before a friend can
	# join) — correct as far as it went, but NOT something GC can afford to get wrong here:
	# a wrong guess wouldn't just fail loudly, it would swap BOTH players onto the opposite
	# team from their actual GC faction and still look plausible (still two different teams,
	# just backwards) — exactly the failure mode the user asked to be sure couldn't happen.
	# Matching against a known id sidesteps the guess entirely: whichever of the (up to two)
	# ids found matches the host's own saved id IS the host, full stop; the other, if there's
	# exactly one other, is the friend. Unset, or a saved id that matches neither, or a count
	# other than 1-2 found — skip auto-assignment and fall back to the existing humanteam 0
	# behaviour rather than ever guessing.
	if state.two_player and _gc_net != null and _gc_net.role == GcNet.Role.HOST:
		var my_id := GcPrefs.my_kyber_player_id()
		var friend_id := GcPrefs.friend_kyber_player_id()
		if my_id == 0:
			GcLog.note("kyber", "auto team-assign skipped — set \"My KYBER Player ID\" before hosting to enable it")
		elif friend_id != 0:
			# `2026-09-24` (playtest 922, item 5): both ids were typed in by hand on the Hosting
			# screen — trust them directly rather than ALSO requiring the log-scan below to have
			# already seen them. Requiring that was the actual bug: co-op (unlike GA/Blast, whose
			# own matchmaking often separates two humans anyway) NEEDS this pin to put a human on
			# its normally-AI-only side at all, so a scan hiccup (log rotation, timing, an offset
			# a hair off) silently meant "nobody's team gets pinned, everyone piles onto team 1"
			# — exactly the report ("co-op puts both players on same team," confirmed fixable via
			# `teamid`). Pre-configured ids no longer depend on the scan succeeding.
			var host_faction: StringName = _gc_net.my_faction
			var client_faction: StringName = Faction.opponent(host_faction)
			var host_team := 1 if one == String(host_faction) else 2
			var client_team := 1 if one == String(client_faction) else 2
			_kyber_link.send_teamid(my_id, host_team)
			_kyber_link.send_teamid(friend_id, client_team)
			GcLog.note("kyber", "auto team-assign (configured ids): host %d -> team %d, friend %d -> team %d" % [my_id, host_team, friend_id, client_team])
		else:
			# Fallback: the friend's id was never entered — the old heuristic, which DOES need
			# the log scan to actually find them (there's no other way to learn an id nobody
			# typed in). Silently skips (falls back to plain `humanteam 0`) on anything but
			# exactly "myself plus one other" since hosting began, rather than ever guessing.
			var idents := KyberEaId.find_identities_since(KyberLogReader.log_path(), _kyber_auth_scan_offset)
			var found_self := false
			var others: Array[int] = []
			for ident in idents:
				var pid := int(ident["player_id"])
				if pid == my_id:
					found_self = true
				else:
					others.append(pid)
			if found_self and others.size() == 1:
				var host_faction: StringName = _gc_net.my_faction
				var client_faction: StringName = Faction.opponent(host_faction)
				var host_team := 1 if one == String(host_faction) else 2
				var client_team := 1 if one == String(client_faction) else 2
				_kyber_link.send_teamid(my_id, host_team)
				_kyber_link.send_teamid(others[0], client_team)
				GcLog.note("kyber", "auto team-assign (discovered): host %d -> team %d, friend %d -> team %d" % [my_id, host_team, others[0], client_team])
			else:
				GcLog.note("kyber", "auto team-assign skipped — found %d id(s) since hosting began (self %s), expected self + exactly 1 other; enter \"Friend's KYBER Player ID\" on the Hosting screen to skip this scan entirely" % [idents.size(), "seen" if found_self else "NOT seen"])

	# Forget the previous battle's "level" message so it can't be mistaken for this one
	# loading (two battles can share a level_path).
	_kyber_link.clear_level()
	_kyber_match_live = false
	_groundwin_pending_battle_id = ""
	var level_path := String(params["level_path"])

	if _kyber_link.load_level(level_path, String(params["frostbite_mode"]),
			bots_t1, bots_t2, aim_t1, aim_t2, 0, 0,
			int(params["match_max_s"]), int(params["match_margin"])):
		# Follow KYBER's own log for the winner — the plugin can't read one for Supremacy / GA.
		# A space lane IS a capital-ship co-op from the start, so don't treat the ship's own
		# bundle load as a "ground phase won" signal (that fires groundwin → crashy endgame).
		_kyber_watch.arm(level_path, planet.capturable)
		var atk_label := "%s attacker %s" % [String(request.attacker), _force_label(request, true)]
		var def_label := "%s defender %s" % [String(request.defender), _force_label(request, false)]
		_kyber_link.send_line("label 1 %s" % (atk_label if attacker_is_one else def_label))
		_kyber_link.send_line("label 2 %s" % (def_label if attacker_is_one else atk_label))
		_kyber_link.send_line("humanteam %d" % human_team)
		_kyber_link.send_line("heroprob %s" % str(snappedf(float(params["hero_probability"]), 0.01)))
		if String(params["frostbite_mode"]) in ["Mode9", "ModeDefend"]:
			_kyber_link.send_line("coopdef %d" % defender_team)
		# Not "playing" yet — the plugin only acts once a match is running (Host, or an
		# offline Arcade / Instant Action match). _poll_kyber_await() turns this into
		# "battle live" on the plugin's "level" message, or guidance if it never comes.
		_kyber_awaiting = {
			"level": level_path,
			"planet": String(params.get("map_name", planet.display_name)),
			"mode_name": String(params["mode_name"]),
			"deadline_ms": Time.get_ticks_msec() + 16000,
		}
		_notice = "Sent \"%s\" to SWBF2 — waiting for the match to load…" % \
			_battle_headline(request, planet, String(params.get("map_name", "")))
		GcLog.note("battle", "requested %s — %s / %s | bots t1/t2 %d/%d | aim t1/t2 %.2f/%.2f | human T%d" % [
			planet.display_name, params["frostbite_mode"], level_path,
			bots_t1, bots_t2, aim_t1, aim_t2, human_team
		])
		# A one-line campaign briefing into the match chat, so the stakes are visible
		# without alt-tabbing back to GC.
		_gc_chat(_battle_briefing_line(request, planet))
		# Safety: nudge the round to start even if the lobby is short a player.
		get_tree().create_timer(13.0).timeout.connect(func():
			if is_instance_valid(self) and _kyber_link != null and _kyber_link.is_online():
				_kyber_link.start_match())
		# Window choreography waits for the battle to actually load — see _poll_kyber_await().
	else:
		_notice = "KYBER link is not connected yet."
	_refresh()


## Between "Play in KYBER" and the battle actually loading in SWBF2. Drains the plugin's
## control messages and watches for the "level" confirmation:
##  - plugin's "level" message for our map  → battle is live, hand the screen over
##  - load_failed                           → SWBF2 didn't switch; the plugin's reason says
##    what to do (usually: if hosting, click Play again). Bots/aim were still applied.
##  - load_ack running=false                → no match at all; start one first
##  - deadline with no word                 → same guidance
func _poll_kyber_await() -> void:
	if _kyber_link == null:
		return
	var want := String(_kyber_awaiting.get("level", ""))
	var target := _kyber_await_target()

	# A real "level" message for our map wins over anything queued — recover even if a
	# premature load_failed arrived a beat earlier (online loads land a few seconds after
	# the LoadLevel echo).
	if want != "" and String(_kyber_link.last_level.get("map", "")) == want and not _kyber_awaiting.is_empty():
		_kyber_battle_is_live(want)
		return

	var evt := _kyber_link.take_event()
	while not evt.is_empty():
		match String(evt.get("type", "")):
			"load_ack":
				if not bool(evt.get("running", true)):
					_kyber_await_failed("SWBF2 isn't in a match. Start it as %s, then click Play in KYBER again." % target)
			"load_failed":
				_kyber_await_failed(String(evt.get("reason",
					"SWBF2 didn't switch to %s. If you're hosting, click Play again." % target)))
		evt = _kyber_link.take_event()

	if _kyber_awaiting.is_empty():
		return
	if want != "" and String(_kyber_link.last_level.get("map", "")) == want:
		_kyber_battle_is_live(want)
	elif Time.get_ticks_msec() >= int(_kyber_awaiting.get("deadline_ms", 0)):
		_kyber_await_failed("No word from SWBF2. Start the match as %s, play it, then report the winner below." % target)


func _kyber_battle_is_live(map: String) -> void:
	_kyber_awaiting = {}
	_kyber_match_live = true
	if _battle_is_coop():
		_coop_result_armed = true
		_coop_result_unlock_ms = Time.get_ticks_msec() + COOP_RESULT_HOLD_MS
	_notice = "Battle live in SWBF2 — play the round."
	GcLog.note("battle", "KYBER switched to %s — battle is live" % map)
	if DisplayServer.get_name() != "headless":
		_enter_battle_view()
	_refresh()


## "Felucia — Supremacy" for the pending battle, for the offline guidance messages.
func _kyber_await_target() -> String:
	var p := String(_kyber_awaiting.get("planet", "the target world"))
	var m := String(_kyber_awaiting.get("mode_name", ""))
	return "%s — %s" % [p, m] if m != "" else p


func _kyber_await_failed(msg: String) -> void:
	if _kyber_awaiting.is_empty():
		return
	_kyber_awaiting = {}
	_notice = msg
	GcLog.note("battle", "battle did not start — %s" % msg)
	_refresh()


## The battle's headline. A normal world: "Battle for <world>". A Clone Wars space lane: a
## capital-ship boarding co-op — "Board the Separatist Dreadnought" if the player's fleet is
## attacking, "Defend the Republic Venator" if it's the one being boarded. `map_name` is the
## resolved co-op entry's display_name ("Republic Venator — Co-Op Attack").
func _battle_headline(request: Battle.Request, planet: Planet, map_name: String) -> String:
	if planet.capturable:
		return "Battle for %s" % planet.display_name
	var ship := map_name.split(" — ")[0].strip_edges()   # drop the "— Co-Op Attack/Defense" tail
	if ship == "" or ship == map_name:
		ship = "%s capital ship" % Faction.short_name(request.defender)
	return ("Defend the %s" % ship) if _current_seat_faction() == request.defender else "Board the %s" % ship


## A line for the in-match chat: who is fighting for what, what a loss costs, and each
## side's force — strength, reinforcement tier, Combat Training — so the match has context
## without alt-tabbing back to GC to check. Kept short: Frostbite's chat truncates a long
## broadcast, and the original "GALACTIC CONQUEST - Turn N - ..." phrasing (with full
## "strength N, reinforcement N, training N" per side) ran ~190 characters and was getting
## cut off mid-sentence in-game. The essentials — turn, who/what/stake — come first so
## they survive even if this still gets clipped somewhere; the force breakdown is last.
func _battle_briefing_line(request: Battle.Request, planet: Planet) -> String:
	# `2026-09-19` playtest 919: the old line (turn, "you attack", strength + R/T tiers per side)
	# was too long. Now just who attacks what, plus the fleets as plain levels:
	# "First Order attacks Crait, the Resistance homeworld (Level 2 vs Level 1)".
	var atk_level := "Level %d" % (request.attacker_reinforcement + 1)
	var def_level := "Level %d" % (request.defender_reinforcement + 1) 		if request.defender_fleet_strength > 0 else "garrison"
	var levels := " (%s vs %s)" % [atk_level, def_level]
	if not planet.capturable:
		# A space lane — a capital-ship boarding co-op. The map is the defender's ship.
		var brief := KyberBridge.build_briefing(request, planet, ContentLoader.load_map_catalog(state.campaign_id), _current_seat_faction())
		return _battle_headline(request, planet, String(brief["map_name"])) + levels
	var stake := ""
	if planet.capital_faction != &"":
		stake = ", the %s homeworld" % _faction_adjective(planet.capital_faction)
	return "%s attacks %s%s%s" % [Faction.short_name(request.attacker), planet.display_name, stake, levels]


## The word that goes before "homeworld" / "fleet" — Faction.short_name reads wrong there for
## the Rebels ("the Rebels homeworld") and the CIS.
func _faction_adjective(faction: StringName) -> String:
	match faction:
		Faction.REPUBLIC:
			return "Republic"
		Faction.SEPARATIST:
			return "Separatist"
		Faction.EMPIRE:
			return "Imperial"
		Faction.REBELLION:
			return "Rebel"
	return Faction.short_name(faction)


## `2026-09-24` (playtest 922, item 6): the whole "minimize GC, raise SWBF2, restore GC"
## hand-off (and the `RenderingServer.render_loop_enabled = false` throttle that went with
## it) is REMOVED outright, per the user's own call — "host client program visuals froze
## after co-op match defeat... does this have to do with the handing over to SWBF2 option?
## If so, let's remove it completely." Exactly the suspected mechanism: co-op has no
## automatic winner signal at all, so a co-op defeat never calls _exit_battle_view() on its
## own — the ONLY thing that used to undo the render-loop-off throttle before the player
## clicked back into GC was the FOCUS_IN safety net below, and evidently that path (or some
## other edge in it) still left the window looking frozen (input still worked — "could hear
## noises as if I was selecting things" — nothing repainted). Rather than keep chasing which
## exact edge case that was, the whole risky mechanism is gone; GC's window is never
## minimized, resized or throttled around a battle anymore. `_battle_active` itself stays —
## it still drives battle-music ducking and a couple of "are we mid-match" checks elsewhere —
## just with nothing left that can leave the window unusable if a result never arrives.
func _enter_battle_view() -> void:
	if not is_instance_valid(self) or _kyber_link == null or not _kyber_link.is_online():
		return
	_battle_active = true
	_update_music()


func _exit_battle_view() -> void:
	_battle_active = false
	_update_music()


func _end_kyber_match(winner_team: int) -> void:
	if _kyber_link == null or not _kyber_link.is_online():
		return
	_kyber_link.end_match(winner_team)
	_notice = "Told KYBER to end the match."
	GcLog.note("battle", "end match requested (winner %s)" % ("by score" if winner_team == 0 else str(winner_team)))
	_refresh()


func _on_kyber_apply_pressed() -> void:
	_sfx_confirm()
	if _apply_staged_result():
		_clear_selection()
	_refresh()


## Parse + fold the staged KYBER result into the campaign. Returns true on success.
## Shared by the Apply button and the auto-apply path.
func _apply_staged_result() -> bool:
	if _kyber_staged.is_empty() or not state.has_pending_battle():
		return false
	if _is_net_client():
		return false   # the host alone calls TurnResolver online — see gc_net.gd's header
	var request := Battle.Request.from_dict(state.pending_battle)
	var report := BattleResultParser.parse(JSON.stringify(_kyber_staged), request, _pending_team_one())
	if report.result == null:
		_notice = "Couldn't read the KYBER result: %s" % report.note
		return false
	GcLog.note("battle", "applied — %s won" % Faction.display_name(report.result.victor))
	_notice = ""
	_reset_kyber_battle_state()   # clear it before the AI's counter-attack renders this same frame
	if _battle_active:
		_exit_battle_view()
	TurnResolver.resolve_player_battle(state, report.result)
	# `2026-09-21` (playtest 921): missing on both callers — a KYBER auto-detected result
	# (Play in KYBER, not the manual buttons) applied fine on the HOST's own state but never
	# reached the client at all, leaving its screen stuck on the old pending battle forever.
	_gc_net_broadcast()
	return true


## Kept short for the same reason as _battle_briefing_line — this also goes into the
## in-match chat and was getting clipped as "KYBER: couldn't read the winner (score ...".
## Every line GC puts into the SWBF2 match chat: one prefix, and trimmed so the game's chat
## doesn't clip it mid-word (`2026-09-19` playtest: messages must start "GALACTIC CONQUEST:"
## and not get cut off). Trims at a word boundary, ellipsis if it had to.
const CHAT_PREFIX := "GALACTIC CONQUEST: "
const CHAT_MAX_LEN := 112
func _gc_chat(body: String) -> void:
	if _kyber_link == null or not _kyber_link.is_online():
		return
	var line := CHAT_PREFIX + body.strip_edges()
	if line.length() > CHAT_MAX_LEN:
		var cut := line.left(CHAT_MAX_LEN - 1)
		var sp := cut.rfind(" ")
		line = (cut.left(sp) if sp > CHAT_PREFIX.length() + 10 else cut) + "…"
	_kyber_link.send_line("say " + line)


## "CIS wins and now controls Felucia" / "Republic holds Geonosis" / a lane's "…wins the space
## battle" — what the staged result MEANS for the campaign, thematically, not just the score.
func _result_chat_line() -> String:
	var winner_team := int(_kyber_staged.get("winner_team", 0))
	if winner_team == 0:
		return "KYBER can't read co-op results — log the winner in GC." if _battle_is_coop() 			else "No winner detected — the commander reports it in GC."
	var req := Battle.Request.from_dict(state.pending_battle)
	var planet := state.get_planet(req.planet_id)
	var winner: StringName = _pending_team_one() if winner_team == 1 else Faction.opponent(_pending_team_one())
	var who := Faction.short_name(winner)
	var place := planet.display_name if planet != null else "the system"
	if planet != null and not planet.capturable:
		return "%s wins the space battle over %s." % [who, place]
	if winner == req.attacker:
		return "%s wins and now controls %s!" % [who, place]
	return "%s holds %s — the assault is repelled." % [who, place]


const MATCH_RESTART_DELAY_S := 2.5
## `2026-10-08` (playtest 104, item 14): Blast has no round-end signal at all — the plugin's
## `emit_result` fires the INSTANT a team's 100th kill lands (__init__.lua, BLAST_KILL_TARGET),
## while players are still actively fighting. Hitting it with the same short delay as a
## Supremacy/GA round — which by then has already finished and is mid-Outro — forces a hard
## `Restart` on a match that's still fully live. Likely why a live Blast match on Bespin
## crashed (item 14) and why the "back to GC" chat line was reported as not appearing for
## Blast (item 12) — the restart may be landing too close to the final kill for either to
## register before teardown. Giving Blast specifically the old, longer pre-921 delay lets the
## chat line land and the round settle before the forced restart. Identified from the
## plugin's own `reason` field (`"blast kills %d-%d"`, __init__.lua's emit_result) — not a new
## schema, just reading the one the plugin already sends. Unverified live; if Blast still
## crashes or still eats the chat line, the next thing to try is a real KYBER log capture from
## that exact match (Hard Rule 5 — no schema beyond what's already read here should be guessed).
const BLAST_LIVE_RESTART_DELAY_S := 6.0
## `2026-09-19` playtest: "still crashes after a Supremacy match — just skip map/restart after
## triggering end of match." KYBER's own natural end-of-round (LoadNextLevel of an empty
## rotation) is what crashes (docs/SUPREMACY_PHASE.md); once GC has a determinate winner there's
## nothing left to wait for, so a beat later (long enough for the chat line above to land) it
## tells the plugin to `restart`. Skipped if a NEW battle has been started in the meantime — a
## late restart must never hit the next match.
## `2026-09-21` (playtest 921): "Game crashes after supremacy ending still. Stop ending round.
## Just do restart." The 6s delay this used to be gave KYBER's OWN crash-prone round end
## plenty of time to fire first — shortened so `restart` races ahead of it instead. Live-
## unverified past this point (needs a real KYBER capture) — if it still crashes, the next
## thing to try is cutting this further or sending `restart` the instant a winner is staged,
## with the chat line reordered to go out AFTER it rather than before.
func _schedule_match_restart(result: Dictionary) -> void:
	if int(result.get("winner_team", 0)) == 0 or _kyber_link == null:
		return
	var battle_id := String(state.pending_battle.get("id", ""))
	var is_blast_live_kill := String(result.get("reason", "")).begins_with("blast kills")
	var delay := BLAST_LIVE_RESTART_DELAY_S if is_blast_live_kill else MATCH_RESTART_DELAY_S
	get_tree().create_timer(delay).timeout.connect(func():
		if not is_instance_valid(self) or _kyber_link == null or not _kyber_link.is_online():
			return
		if not _kyber_awaiting.is_empty():
			return   # a fresh Play in KYBER is in flight — never restart THAT
		if state.has_pending_battle() and String(state.pending_battle.get("id", "")) != battle_id:
			return
		# `2026-09-21` (playtest 921): "Need a server message to wait for next match... imagine
		# some players aren't seeing the GC screen." One last line before the map cycles.
		_gc_chat("Back to Galactic Conquest for the next move — watch here for the next match.")
		_kyber_link.restart_match())


func _describe_staged_result() -> String:
	var teams: Dictionary = _kyber_staged.get("teams", {})
	var t1: Dictionary = teams.get("1", {})
	var t2: Dictionary = teams.get("2", {})
	var s1 := int(t1.get("score", 0))
	var s2 := int(t2.get("score", 0))
	var k1 := int(t1.get("kills", 0))
	var k2 := int(t2.get("kills", 0))
	# Blast reports kills, never a ticket score (always 0–0) — show whichever tally is real.
	var tally := ""
	if s1 != 0 or s2 != 0:
		tally = "%d–%d" % [s1, s2]
	elif k1 != 0 or k2 != 0:
		tally = "%d–%d kills" % [k1, k2]
	var winner_team := int(_kyber_staged.get("winner_team", 0))
	if winner_team == 0:
		return "no clear winner%s — use the manual buttons" % ((" (%s)" % tally) if tally != "" else "")
	var who := Faction.short_name(_pending_team_one()) if winner_team == 1 		else Faction.short_name(Faction.opponent(_pending_team_one()))
	if String(_kyber_staged.get("source", "")) == "kyber_log" or tally == "":
		return "%s won" % who
	return "%s won (%s)" % [who, tally]


func _on_kyber_connect_pressed() -> void:
	if _kyber_link == null:
		return
	_notice = ""
	if not KyberPluginInstaller.kyber_running():
		var res := KyberPluginInstaller.launch(KyberPluginInstaller.configured_launcher_path())
		if bool(res.get("ok", false)):
			_notice = "KYBER is starting with the GC plugin. Click Host in KYBER — GC will connect."
		else:
			_notice = String(res.get("reason", "Couldn't start KYBER — use KYBER Setup…"))
	else:
		_kyber_link.connect_to()
		# Can't tell from here whether the plugin is actually loaded (only "is KYBER running")
		# — a KYBER opened any way other than GC's own launch has no plugin at all and this
		# will just keep failing to connect no matter how many times it's retried. Say both
		# things plainly rather than implying "click Host" is always the missing step.
		_notice = ("Reconnecting… Make sure you are Hosting an active server through KYBER. "
			+ "If you already are, restart KYBER with the GC plugin under Settings → KYBER Setup…")
	_refresh()


# --- small view helpers ----------------------------------------------------

## What a world is and who is stationed there — shown when it's clicked, in reach or not.
## Two lines, at most: what was selected, then one strength/presence line. Planets show the
## garrison only when no fleet is parked there; a parked fleet's strength replaces it (never
## both). Hyperlanes are unaligned and show fleet presence, not strength.
func _inspect_text(p: Planet) -> String:
	var me := _current_seat_faction()
	var holder := "Unaligned"
	if p.capturable:
		holder = "Unoccupied" if p.owner == Faction.NEUTRAL else "Held by %s" % Faction.display_name(p.owner)
	var fleets: Array = state.fleets_at(p.id)
	var line := ""
	if not fleets.is_empty():
		var parts := PackedStringArray()
		for f: Fleet in fleets:
			var who := "Your fleet" if f.owner == me else "%s fleet" % Faction.short_name(f.owner)
			if p.capturable:
				parts.append("%s — strength %d · %s" % [who, f.strength, _reinf_label(f.reinforcement_tier)])
			else:
				parts.append("%s at %s" % [who, p.display_name])
		line = " · ".join(parts)
	elif p.capturable and p.garrison > 0:
		line = "Garrison %d" % p.garrison
	var head := "[b]%s[/b] — %s" % [p.display_name, holder]
	return head if line == "" else head + "\n" + line


## Can the player pick this fleet up right now? (what the ▼ hint in _draw marks)
func _fleet_selectable(f: Fleet) -> bool:
	return f.owner == _current_seat_faction() and f.owner == state.active_faction and not f.has_moved \
		and not state.has_pending_battle() and not state.is_over() and _ai_opening_seed < 0


## Big, always-visible treasury badge, now on the bottom (buying) bar rather than the top.
## (playtest 920v2: "hard to tell how much you have").
func _build_credits_badge() -> void:
	_credits_badge = VBoxContainer.new()
	_credits_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_badge.position = Vector2(Tokens.SPACE_4, 0.0)
	if is_instance_valid(_bottombar):
		_bottombar.add_child(_credits_badge)
	else:
		add_child(_credits_badge)
	var cap := Label.new()
	cap.text = "CREDITS"
	cap.add_theme_font_override("font", Tokens.FONT_MEDIUM)
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	_credits_badge.add_child(cap)
	_credits_value = Label.new()
	_credits_value.add_theme_font_override("font", Tokens.FONT_HEAVY)
	_credits_value.add_theme_font_size_override("font_size", 30)
	_credits_value.add_theme_color_override("font_color", Tokens.WARNING)
	_credits_badge.add_child(_credits_value)
	_credits_income = Label.new()
	_credits_income.add_theme_font_override("font", Tokens.FONT_BOOK)
	_credits_income.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_SMALL)
	_credits_income.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	_credits_badge.add_child(_credits_income)


func _update_credits_badge() -> void:
	if _credits_badge == null or state == null:
		return
	var me := _current_seat_faction()
	_credits_value.text = str(int(state.credits.get(me, 0)))
	_credits_income.text = "+%d / turn" % state.income_for(me)


## Top-left turn block: the ACTIVE side's insignia (so online/hotseat can never be misread)
## tinted player-relative blue/red, with "TURN N" underneath. Online, a warning-coloured turn
## number means it is this screen's move.
func _set_turn_title() -> void:
	var active := state.active_faction
	if _turn_icon != null:
		_turn_icon.texture = FACTION_INSIGNIA.get(active, null)
		var mat := _turn_icon.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("tint", _owner_color(active))
	if _turn_label != null:
		_turn_label.text = "TURN %d" % state.turn
		var yours := active == _current_seat_faction()
		var col := Tokens.WARNING if _gc_net != null and yours else Tokens.TEXT_DIM
		_turn_label.add_theme_color_override("font_color", col)
	if _turn_box != null:
		_turn_box.tooltip_text = "Turn %d — %s" % [state.turn, Faction.display_name(active)]
	_panel_title.visible = false
	_update_window_title()


## "Galactic Conquest — Republic — Turn 4" (playtest notes 104: the bare project name told
## a player nothing at a glance, e.g. alt-tabbing back during a KYBER match). "[team]" is
## this screen's OWN side (_current_seat_faction — fixed in single player/online, the
## seat-in-control in local hotseat), not necessarily whoever's turn it actually is.
func _update_window_title() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var title := "Galactic Conquest — %s — Turn %d" % [Faction.display_name(_current_seat_faction()), state.turn]
	if get_window().title != title:
		get_window().title = title


## "no training" / "training level 2" — a fleet's Combat Training as the player bought it.
func _training_label(level: int) -> String:
	return "training level %d" % level if level > 0 else "no training"


func _planet_name(planet_id: StringName) -> String:
	var p := state.get_planet(planet_id)
	if p == null:
		return String(planet_id)
	return p.display_name if p.capturable else "%s (hyperlane)" % p.display_name


func _reinf_label(tier: int) -> String:
	return "no reinforcements" if tier <= 0 else "reinforcements tier %d" % tier


## (The old `_status_line` — difficulty, fleet counts, planets, neutrals in one sentence —
## was removed 2026-10-28. The top bar now shows only both factions' insignia and worlds held,
## via _update_status_row.)


func _planet_at(point: Vector2) -> Planet:
	var best: Planet = null
	var best_d := INF
	for p: Planet in state.planets.values():
		var d := point.distance_to(_screen_position(p))
		if d <= _screen_radius(p) + 6.0 and d < best_d:
			best = p
			best_d = d
	return best


## Where a world's 3D node projects onto the screen — the anchor for every 2D overlay.
func _screen_position(planet: Planet) -> Vector2:
	if _camera == null or not _planet_nodes.has(planet.id):
		return Vector2.ZERO
	return _camera.unproject_position((_planet_nodes[planet.id] as Node3D).global_position)


## On-screen radius of a world's glow — the overlay ring and the click target hug it.
func _screen_radius(planet: Planet) -> float:
	if _camera == null or not _planet_nodes.has(planet.id):
		return 12.0
	var node: Node3D = _planet_nodes[planet.id]
	# node.scale accounts for _planet_depth_scale's north-of-the-core shrink (a lane star
	# never gets that scale applied, but its scale is always 1 regardless, so this is safe
	# unconditionally) — without it this over-reported the radius for a shrunk world, since
	# span is otherwise added in world space with no regard to the node's own scale at all.
	var span := (PLANET_GLOW if planet.capturable else STAR_GLOW) * 0.42 * node.scale.x
	var edge := node.global_position + _camera.global_transform.basis.x * span
	var r := _screen_position(planet).distance_to(_camera.unproject_position(edge))
	# `2026-09-13`: upper bound raised from 40 — that was fine at the old, farther battle-zoom
	# distance, but the closer BATTLE_CAMERA_DIST this session's cinematic-zoom work settled
	# on genuinely projects a much bigger on-screen radius, and the old clamp silently capped
	# it well below the planet body's own actual size, leaving the ownership ring (drawn at
	# this radius + a few px) rendering INSIDE the visible planet instead of around it.
	return clampf(r, 5.0, 400.0)


## The campaign's end — a real popup (not just the top-bar banner swap _refresh also does)
## with a stat summary and a New Campaign button, per live playtest feedback that the old
## inline banner needed to be a proper screen. `_victory_modal_shown_for` guards against
## _refresh (called on all sorts of unrelated clicks, not just once) reopening this every
## time after the player closes it — it only rebuilds when the winner actually changes,
## which in practice means only once per campaign, at the moment it ends.
func _show_victory_modal(winner: StringName, title_text: String, body_text: String) -> void:
	if _victory_modal_shown_for == winner:
		return   # already shown for this outcome — including if the player has since closed it
	if is_instance_valid(_victory_modal):
		_victory_modal.queue_free()
	_victory_modal_shown_for = winner

	var shell := _modal_overlay(title_text, Vector2(520, 600), true)
	_victory_modal = shell["overlay"]
	var victory_overlay: Control = shell["overlay"]
	victory_overlay.set_meta("controller_cancel", func():
		if is_instance_valid(victory_overlay):
			victory_overlay.queue_free()
		if _victory_modal == victory_overlay:
			_victory_modal = null)
	var col: VBoxContainer = shell["body"]
	# The modal's own title label (VICTORY / DEFEAT) is left-aligned by default — centre it.
	if col.get_child_count() > 0 and col.get_child(0) is Label:
		(col.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var summary := Label.new()
	summary.text = body_text
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(summary)

	var turns := Label.new()
	turns.text = "%d turn%s" % [state.turn, "" if state.turn == 1 else "s"]
	turns.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	turns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(turns)

	var stats := GridContainer.new()
	stats.columns = 3
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats.add_theme_constant_override("h_separation", int(Tokens.SPACE_4))
	stats.add_theme_constant_override("v_separation", int(Tokens.SPACE_1))
	col.add_child(stats)

	var add_cell := func(text: String, dim: bool = false):
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if dim:
			l.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		stats.add_child(l)

	add_cell.call("", true)
	for f in _campaign_factions():
		add_cell.call(Faction.short_name(f).to_upper(), true)

	add_cell.call("Battles won", true)
	for f in _campaign_factions():
		add_cell.call(str(state.battles_won_by(f)))

	add_cell.call("Battles lost", true)
	for f in _campaign_factions():
		add_cell.call(str(state.battles_lost_by(f)))

	add_cell.call("Worlds captured", true)
	for f in _campaign_factions():
		add_cell.call(str(state.worlds_captured_by(f)))

	add_cell.call("Worlds held", true)
	for f in _campaign_factions():
		add_cell.call(str(state.planets_owned_by(f).size()))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", int(Tokens.SPACE_3))
	col.add_child(buttons)

	var new_campaign_button := Button.new()
	new_campaign_button.text = "New Campaign"
	new_campaign_button.pressed.connect(func():
		_sfx_confirm()
		if is_instance_valid(_victory_modal):
			_victory_modal.queue_free()
		_victory_modal = null
		_on_difficulty_pressed())
	buttons.add_child(new_campaign_button)


# --- Controller / gamepad ---------------------------------------------------
# Additive input layer. The existing mouse handlers and Button signals are untouched;
# this section owns (a) the focused-planet map cursor, (b) the gamepad/keyboard gameplay
# actions, and (c) the modal/focus stack that lets a controller drive the same Buttons a
# mouse does. Pure helpers live in ui/controller_*.gd and ui/map_cursor.gd.

func _on_input_mode_changed(new_mode: int) -> void:
	if new_mode == ControllerDevice.Mode.GAMEPAD:
		# Hand-off from mouse: if the pointer is over a world, start the pad cursor there
		# instead of at wherever it was left last time. If the pointer is over the bars or
		# empty space, leave the previous pad position alone.
		if _ui_layers.is_empty() and state != null and _window_focused:
			var hovered := get_viewport().gui_get_hovered_control()
			if hovered == null or hovered == self:
				var hover := _planet_at(get_global_mouse_position())
				if hover != null:
					_pad_cursor_id = hover.id
					_map_cursor.set_current(hover.id)
					_inspect_id = hover.id
		_hover_id = &""
		_keyboard_map_nav = false
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		_set_mouse_ui_enabled(false)
		if not _ui_layers.is_empty():
			var layer: Control = _ui_layers.back()["control"]
			var focus := get_viewport().gui_get_focus_owner()
			if focus == null or not layer.is_ancestor_of(focus) or not focus.is_visible_in_tree():
				_focus_first_in(layer)
		elif state != null and state.has_pending_battle():
			_pad_last_region = "bar"
		else:
			_pad_last_region = "map"
			_pad_menu = "main"
			_pad_upgrade_index = 0
			_focus_map()
		_pad_sync_battle_focus.call_deferred()
		queue_redraw()
	else:
		_reset_pad_state()
		_set_mouse_ui_enabled(true)
		_pad_menu = "main"
		_pad_upgrade_index = 0
		queue_redraw()
	_apply_cursor_visibility()
	_refresh()


## Hide the OS pointer while the controller owns the UI; show it again the moment mouse or
## keyboard input takes over (ControllerDevice's mode switch calls this).
func _apply_cursor_visibility() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var pad := _controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if pad else Input.MOUSE_MODE_VISIBLE


func _on_controller_family_changed(_family: int) -> void:
	_refresh_controls_modal()
	_refresh()


func _on_controller_connection_changed(_connected: bool, _device: int, _device_name: String) -> void:
	_refresh_controls_modal()
	_refresh()


## While the controller is active, mouse hover/click is disabled across the UI and the
## Button hover style is flattened. A mouse *button* event switches mode before Godot's
## GUI sees it, so the filters are restored in time for the click to work normally.
func _set_mouse_ui_enabled(enabled: bool) -> void:
	if enabled:
		for c in _mouse_filters.keys():
			if is_instance_valid(c):
				(c as Control).mouse_filter = int(_mouse_filters[c])
		_mouse_filters.clear()
		for b in _mouse_hover_colors.keys():
			if is_instance_valid(b):
				(b as Button).add_theme_color_override("font_hover_color", _mouse_hover_colors[b])
		_mouse_hover_colors.clear()
		if theme != null and _theme_button_hover != null:
			theme.set_stylebox("hover", "Button", _theme_button_hover)
		return
	if theme != null and _theme_button_normal != null:
		theme.set_stylebox("hover", "Button", _theme_button_normal)
	var all: Array[Control] = []
	_collect_all_controls(get_tree().root, all)
	for c: Control in all:
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and not _mouse_filters.has(c):
			_mouse_filters[c] = c.mouse_filter
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if c is Button and not _mouse_hover_colors.has(c):
			var b := c as Button
			_mouse_hover_colors[b] = b.get_theme_color("font_hover_color")
			var normal_col := b.get_theme_color("font_disabled_color") if b.disabled \
				else b.get_theme_color("font_color")
			b.add_theme_color_override("font_hover_color", normal_col)


## Per-frame analog handling: left stick/D-pad cursor repeat, triggers for zoom, right
## stick for pan. Only runs while the map has input focus; a focused menu/button keeps the
## normal Godot focus behavior.
func _pad_process(delta: float) -> void:
	if _controller == null or _controller.mode != ControllerDevice.Mode.GAMEPAD:
		return
	if not _window_focused or state == null or _controller.active_device < 0:
		return
	if DisplayServer.get_name() != "headless" and not get_window().has_focus():
		return
	if not _ui_layers.is_empty() or state.has_pending_battle():
		return
	if _pad_menu == "upgrades":
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus.is_visible_in_tree():
		return
	_pad_handle_stick(delta)
	if not _ui_layers.is_empty():
		return
	_pad_handle_triggers(delta)
	_pad_handle_right_stick(delta)


func _pad_sync_battle_focus() -> void:
	if _controller == null or _controller.mode != ControllerDevice.Mode.GAMEPAD:
		return
	if state == null or not state.has_pending_battle():
		_pad_auto_focused_battle = ""
		return
	if not _ui_layers.is_empty() or _battle_intro_playing():
		return
	var battle_id := String(state.pending_battle.get("id", ""))
	if battle_id == _pad_auto_focused_battle:
		return
	if _focus_bar_first():
		_pad_auto_focused_battle = battle_id


func _pad_handle_stick(delta: float) -> void:
	var device := _controller.active_device
	var raw := Vector2.ZERO
	var dpad := Vector2.ZERO
	if device >= 0:
		raw = Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
			dpad.x -= 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
			dpad.x += 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
			dpad.y -= 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
			dpad.y += 1.0
	var dpad_pressed := dpad != Vector2.ZERO
	if dpad_pressed and not _pad_dpad_held:
		# A fresh D-pad press is always a deliberate step, even if the stick was held a
		# moment ago and left the axis "unarmed".
		_pad_axis_armed = true
		_pad_repeat_wait = 0.0
	_pad_dpad_held = dpad_pressed
	var active := raw.length() >= 0.55 or dpad != Vector2.ZERO
	if not active:
		# Hysteresis: the stick must come back near centre before another step, so a light
		# flick does not skip three worlds.
		if raw.length() < 0.45:
			_pad_repeat_dir = Vector2.ZERO
			_pad_axis_armed = true
		_pad_repeat_wait = 0.0
		return
	var dir := dpad if dpad != Vector2.ZERO else raw
	if absf(dir.x) >= absf(dir.y):
		dir = Vector2(signf(dir.x), 0.0)
	else:
		dir = Vector2(0.0, signf(dir.y))
	if _pad_axis_armed:
		_pad_move_cursor(dir)
		_pad_axis_armed = false
		_pad_repeat_dir = dir
		_pad_repeat_wait = 0.35
		return
	if dir.dot(_pad_repeat_dir) < 0.9:
		if dpad_pressed:
			_pad_move_cursor(dir)
			_pad_repeat_dir = dir
			_pad_repeat_wait = 0.35
			return
		# The stick rolled into a new direction while held: wait out the same short delay,
		# then step that way without requiring a full centre return.
		_pad_repeat_wait -= delta
		if _pad_repeat_wait <= 0.0:
			_pad_move_cursor(dir)
			_pad_repeat_dir = dir
			_pad_repeat_wait = 0.18
		return
	_pad_repeat_wait -= delta
	if _pad_repeat_wait <= 0.0:
		_pad_move_cursor(dir)
		_pad_repeat_wait = 0.12


func _pad_handle_triggers(delta: float) -> void:
	var device := _controller.active_device
	if device < 0:
		return
	var rt := maxf(0.0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT))
	var lt := maxf(0.0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT))
	if rt < 0.08:
		rt = 0.0
	if lt < 0.08:
		lt = 0.0
	var change := (rt - lt) * PAD_ZOOM_RATE * delta
	if absf(change) < 0.00001:
		return
	var new_target := clampf(_view_zoom_target + change, 0.0, 1.0)
	if is_equal_approx(new_target, _view_zoom_target):
		return
	if change > 0.0 and _pad_cursor_id != &"":
		var p := state.get_planet(_pad_cursor_id) if state != null else null
		if p != null:
			_zoom_target_pos_raw = _planet_world_pos(p)
	_view_zoom_target = new_target
	_zoom_planet_id = &""   # a free/manual zoom, not the battle camera
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()


func _pad_handle_right_stick(delta: float) -> void:
	if _zoom_t < 0.02:
		return
	var device := _controller.active_device
	if device < 0:
		return
	var v := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if v.length() < 0.20:
		return
	# Negative because _pan_view's mouse convention is "drag the map"; the player expects
	# the right stick to push the camera the way they push it.
	_pan_view(Vector2(-v.x, -v.y) * 900.0 * delta)


func _pad_move_cursor(direction: Vector2) -> void:
	if state == null or state.has_pending_battle():
		return
	var allowed := _pad_allowed_ids()
	var positions := {}
	for p: Planet in state.planets.values():
		if not allowed.is_empty() and not allowed.has(p.id):
			continue
		var wp := _planet_world_pos(p)
		# MapCursor works in screen convention (up = -Y); world Y is up, so flip it.
		positions[p.id] = Vector2(wp.x, -wp.y)
	var next := _map_cursor.step(positions, direction)
	if next == &"" or next == _pad_cursor_id:
		return
	_pad_cursor_id = next
	_inspect_id = next
	_pad_last_region = "map"
	_notice = ""
	_center_camera_on_cursor()
	_refresh()


## While a fleet is selected the reticle may only visit that fleet's world and the worlds
## directly connected to it. An empty dictionary means "everything is allowed".
func _pad_allowed_ids() -> Dictionary:
	var out := _reachable_ids()
	if selected_fleet != null:
		out[selected_fleet.location] = true
	return out


func _selected_fleet_reaches(id: StringName) -> bool:
	if selected_fleet == null or state == null:
		return false
	var origin := state.get_planet(selected_fleet.location)
	if origin == null or not origin.is_connected_to(id):
		return false
	return state.fleet_at(id, selected_fleet.owner) == null


func _center_camera_on_cursor() -> void:
	if _camera == null or _zoom_t < 0.02 or state == null or state.has_pending_battle():
		return
	var p := state.get_planet(_pad_cursor_id)
	if p == null:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_planet_id = &""
	_zoom_target_pos_raw = _planet_world_pos(p)


func _pad_zoom(direction: int) -> void:
	if state == null or _camera == null or state.has_pending_battle():
		return
	var new_target := clampf(_view_zoom_target + VIEW_ZOOM_STEP * direction, 0.0, 1.0)
	if is_equal_approx(new_target, _view_zoom_target):
		return
	if direction > 0 and _pad_cursor_id != &"":
		var p := state.get_planet(_pad_cursor_id)
		if p != null:
			_zoom_target_pos_raw = _planet_world_pos(p)
	_view_zoom_target = new_target
	_zoom_planet_id = &""   # a free/manual zoom, not the battle camera
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()


func _pad_reset_camera() -> void:
	if state == null or state.has_pending_battle():
		return
	_view_zoom_target = 0.0
	_zoom_planet_id = &""
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()


func _pad_confirm() -> void:
	if _pad_menu == "upgrades":
		_pad_buy_upgrade()
		return
	if state == null or not _is_map_region():
		return
	if state.has_pending_battle():
		_focus_bar_first()
		return
	if selected_fleet != null:
		if _pad_cursor_id == selected_fleet.location:
			return
		if _selected_fleet_reaches(_pad_cursor_id):
			pending_dest = _pad_cursor_id
			_on_move_pressed()
		return
	if _pad_can_select_fleet_at(_pad_cursor_id):
		var p := state.get_planet(_pad_cursor_id)
		if p != null:
			_activate_world(p)


func _pad_can_select_fleet_at(id: StringName) -> bool:
	if state == null:
		return false
	for f: Fleet in state.fleets_at(id):
		if _fleet_selectable(f):
			return true
	return false


## Last-resort A/Cross activation if Godot's `ui_accept` joypad event is missing. Normally
## the focused Button handles A itself and this never runs.
func _pad_accept_button() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BaseButton and focus.is_visible_in_tree() and not (focus as BaseButton).disabled:
		(focus as BaseButton).pressed.emit()
		return
	if _is_map_region():
		_pad_confirm()


func _pad_confirm_label() -> String:
	if state == null or state.has_pending_battle():
		return ""
	if selected_fleet != null:
		var dest := state.get_planet(_pad_cursor_id)
		if dest == null or dest.id == selected_fleet.location:
			return "Move"
		var hostile := Faction.is_playable(dest.owner) and dest.owner != selected_fleet.owner
		return "Attack" if hostile else "Move"
	return "Select" if _pad_can_select_fleet_at(_pad_cursor_id) else ""


func _pad_confirm_enabled() -> bool:
	if state == null or state.has_pending_battle():
		return false
	if selected_fleet != null:
		return _pad_cursor_id != selected_fleet.location and _selected_fleet_reaches(_pad_cursor_id)
	return _pad_can_select_fleet_at(_pad_cursor_id)


## Square/X: Buy Fleet when nothing is selected, Upgrades when a fleet is selected.
func _pad_west_action() -> void:
	if state == null or _pad_menu != "main" or not _is_map_region():
		return
	if state.has_pending_battle():
		return
	if selected_fleet != null:
		_pad_menu = "upgrades"
		_pad_upgrade_index = 0
		_update_pad_bar()
		_refresh()
		return
	if _buy_button != null and (not _buy_button.visible or _buy_button.disabled):
		return
	_on_buy_pressed()


## Triangle/Y: End Turn.
func _pad_north_action() -> void:
	if state == null or _pad_menu != "main" or not _is_map_region():
		return
	if state.has_pending_battle() or selected_fleet != null:
		return
	if _end_turn_button != null and (not _end_turn_button.visible or _end_turn_button.disabled):
		return
	_on_end_turn_pressed()


func _pad_choose_upgrade(direction: int) -> void:
	if _pad_menu != "upgrades":
		return
	_pad_upgrade_index = (_pad_upgrade_index + direction + 2) % 2
	_sfx_move()
	_update_pad_bar()


func _pad_buy_upgrade() -> void:
	if _pad_menu != "upgrades" or selected_fleet == null:
		return
	var btn: Button = _reinforce_button if _pad_upgrade_index == 0 else _training_button
	if btn != null and btn.disabled:
		return
	if _pad_upgrade_index == 0:
		_on_reinforce_pressed()
	else:
		_on_training_pressed()
	_update_pad_bar()


func _pad_cancel() -> bool:
	if not _ui_layers.is_empty():
		_layer_cancel()
		return true
	if _pad_menu == "upgrades":
		_pad_menu = "main"
		_pad_upgrade_index = 0
		_update_pad_bar()
		_refresh()
		return true
	if state != null and state.has_pending_battle():
		# Keep the battle row focused; don't drop back to the (read-only) map.
		return true
	if selected_fleet != null or pending_dest != &"":
		_clear_selection()
		_notice = ""
		_pad_menu = "main"
		_refresh()
		return true
	return true


func _focus_bar_first() -> bool:
	if not _ui_layers.is_empty():
		return false
	var candidates: Array = [
		_end_turn_button, _buy_button, _move_button, _cancel_button,
		_reinforce_button, _training_button,
		_kyber_play_button, _kyber_connect_button, _kyber_apply_button,
		_more_button, _abandon_button, _restart_battle_button,
	]
	candidates.append_array(_win_buttons)
	for b in candidates:
		if not is_instance_valid(b):
			continue
		var btn := b as Button
		if btn.is_visible_in_tree() and not btn.disabled and btn.focus_mode != Control.FOCUS_NONE:
			btn.grab_focus()
			_pad_last_region = "bar"
			_update_pad_bar()
			return true
	# Fallback for controls built inline and not stored in a member (the KYBER "End match"
	# button, for example): the first visible bar button in tree order.
	for btn in _visible_bar_buttons():
		if btn.focus_mode != Control.FOCUS_NONE:
			btn.grab_focus()
			_pad_last_region = "bar"
			_update_pad_bar()
			return true
	return false


func _focus_map() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus):
		focus.release_focus()
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_pad_last_region = "map"
	_update_pad_bar()
	queue_redraw()


func _is_map_region() -> bool:
	if state == null or not _ui_layers.is_empty():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus.is_visible_in_tree():
		return false
	return true


func _reset_pad_state() -> void:
	_pad_repeat_dir = Vector2.ZERO
	_pad_repeat_wait = 0.0
	_pad_axis_armed = true
	_pad_dpad_held = false


func _pad_cursor_drawn() -> bool:
	var active := _keyboard_map_nav or (_controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD)
	return active and _is_map_region() and _pad_cursor_id != &"" and state != null \
		and not state.has_pending_battle()


func _validate_pad_cursor() -> void:
	if state == null:
		return
	if _pad_cursor_id == &"" or state.get_planet(_pad_cursor_id) == null:
		_reset_pad_cursor()
	elif selected_fleet != null and not _pad_allowed_ids().has(_pad_cursor_id):
		_pad_cursor_id = selected_fleet.location
		_map_cursor.set_current(_pad_cursor_id)
	else:
		_map_cursor.set_current(_pad_cursor_id)


func _reset_pad_cursor() -> void:
	if state == null:
		return
	var id: StringName = &""
	var cap := state.capital_for(_current_seat_faction())
	if cap != null:
		id = cap.id
	if id == &"":
		var fleets: Array[Fleet] = state.fleets_owned_by(_current_seat_faction())
		if not fleets.is_empty():
			id = fleets[0].location
	if id == &"":
		for p: Planet in state.planets.values():
			if p.capturable:
				id = p.id
				break
	if id == &"" and not state.planets.is_empty():
		id = StringName(state.planets.keys()[0])
	_pad_cursor_id = id
	_map_cursor.set_current(id)


# --- Controller input events -------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _controller == null:
		return
	# Belt-and-braces: ControllerDevice already swallows joypad events while the window is
	# unfocused, but never let a delayed/direct event drive the map or a focused button.
	var focused := _window_focused
	if DisplayServer.get_name() != "headless":
		focused = focused and get_window().has_focus()
	if not focused and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.is_action_pressed("ui_cancel"):
		if _pad_cancel():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		if _is_map_region():
			_pad_confirm()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		if jb.button_index == JOY_BUTTON_START:
			if _ui_layers.is_empty():
				_open_settings()
			get_viewport().set_input_as_handled()
			return
		if jb.button_index == JOY_BUTTON_BACK:
			if _ui_layers.is_empty():
				_on_controls_pressed()
			get_viewport().set_input_as_handled()
			return
		# Fallback in case a future engine/project change removes the joypad binding added
		# by ControllerDevice._ensure_ui_joy_bindings(). With the binding present, a focused
		# button consumes A before this runs and B goes through the ui_cancel branch above.
		if jb.button_index == JOY_BUTTON_A:
			_pad_accept_button()
			get_viewport().set_input_as_handled()
			return
		if jb.button_index == JOY_BUTTON_B:
			if _pad_cancel():
				get_viewport().set_input_as_handled()
			return
		if not _ui_layers.is_empty():
			return
		# Left/right on the D-pad chooses the highlighted upgrade in the Upgrades submenu.
		if _pad_menu == "upgrades":
			if jb.button_index == JOY_BUTTON_DPAD_LEFT:
				_pad_choose_upgrade(-1)
				get_viewport().set_input_as_handled()
				return
			if jb.button_index == JOY_BUTTON_DPAD_RIGHT:
				_pad_choose_upgrade(1)
				get_viewport().set_input_as_handled()
				return
		if jb.button_index == JOY_BUTTON_Y:
			if _is_map_region() and _pad_menu == "main":
				_pad_north_action()
			get_viewport().set_input_as_handled()
			return
		if jb.button_index == JOY_BUTTON_X:
			if _is_map_region() and _pad_menu == "main":
				_pad_west_action()
			get_viewport().set_input_as_handled()
			return
		if not _is_map_region():
			return
		match jb.button_index:
			JOY_BUTTON_RIGHT_STICK:
				_pad_reset_camera()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if not _is_map_region():
			return
		if _pad_menu == "upgrades":
			match key.physical_keycode:
				KEY_LEFT, KEY_A:
					_pad_choose_upgrade(-1)
				KEY_RIGHT, KEY_D:
					_pad_choose_upgrade(1)
				KEY_M:
					if _ui_layers.is_empty():
						_open_settings()
				KEY_H:
					if _ui_layers.is_empty():
						_on_controls_pressed()
				_:
					return
			get_viewport().set_input_as_handled()
			return
		_keyboard_map_nav = true
		match key.physical_keycode:
			KEY_LEFT, KEY_A:
				_pad_move_cursor(Vector2.LEFT)
			KEY_RIGHT, KEY_D:
				_pad_move_cursor(Vector2.RIGHT)
			KEY_UP, KEY_W:
				_pad_move_cursor(Vector2.UP)
			KEY_DOWN, KEY_S:
				_pad_move_cursor(Vector2.DOWN)
			KEY_F:
				_pad_west_action()
			KEY_T:
				_pad_north_action()
			KEY_M:
				if _ui_layers.is_empty():
					_open_settings()
			KEY_H:
				if _ui_layers.is_empty():
					_on_controls_pressed()
			KEY_EQUAL, KEY_KP_ADD:
				_pad_zoom(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_pad_zoom(-1)
			KEY_HOME:
				_pad_reset_camera()
			_:
				return
		get_viewport().set_input_as_handled()


# --- UI focus / modal layer stack ---------------------------------------------

func _layer_is_open(control: Control) -> bool:
	for entry: Dictionary in _ui_layers:
		if entry["control"] == control:
			return true
	return false


func _push_ui_layer(control: Control, cancel: Callable) -> void:
	if control == null or not is_inside_tree() or _layer_is_open(control):
		return
	var previous_focus := get_viewport().gui_get_focus_owner()
	# Focus trap: anything outside this layer stops accepting focus while it is open, so
	# D-pad/Tab cannot wander into the map or command bar behind the scrim. Each layer
	# keeps its own snapshot, which makes nesting (Settings → Controls) safe.
	var disabled_focus := {}
	var all: Array[Control] = []
	_collect_all_controls(get_tree().root, all)
	for c: Control in all:
		if c == control or control.is_ancestor_of(c):
			continue
		if c.focus_mode != Control.FOCUS_NONE:
			disabled_focus[c] = c.focus_mode
			c.focus_mode = Control.FOCUS_NONE
	_ui_layers.append({
		"control": control,
		"cancel": cancel,
		"previous_focus": previous_focus,
		"previous_region": _pad_last_region,
		"disabled_focus": disabled_focus,
	})
	_pad_last_region = "layer"
	_focus_first_in.call_deferred(control)
	_update_pad_bar()


func _pop_ui_layer(control: Control) -> void:
	if not is_inside_tree():
		return
	for i in range(_ui_layers.size() - 1, -1, -1):
		if _ui_layers[i]["control"] != control:
			continue
		var entry: Dictionary = _ui_layers[i]
		_ui_layers.remove_at(i)
		var disabled_focus: Dictionary = entry.get("disabled_focus", {})
		for c in disabled_focus.keys():
			if is_instance_valid(c):
				(c as Control).focus_mode = int(disabled_focus[c])
		_wire_focus_chain()
		if not _ui_layers.is_empty():
			_pad_last_region = "layer"
			_focus_first_in.call_deferred(_ui_layers.back()["control"])
			_update_pad_bar()
			return
		_pad_last_region = String(entry.get("previous_region", "map"))
		var previous = entry.get("previous_focus")
		if is_instance_valid(previous) and previous is Control and (previous as Control).is_visible_in_tree():
			(previous as Control).grab_focus()
		elif _pad_last_region == "bar":
			if not _focus_bar_first():
				_focus_map()
		else:
			_focus_map()
		_update_pad_bar()
		return


func _layer_cancel() -> bool:
	if _ui_layers.is_empty():
		return false
	var top: Dictionary = _ui_layers.back()
	var control: Control = top["control"]
	if not is_instance_valid(control):
		return true
	var cancel_v: Variant = control.get_meta("controller_cancel", top.get("cancel", Callable()))
	if cancel_v is Callable and (cancel_v as Callable).is_valid():
		(cancel_v as Callable).call()
	return true


func _layer_ancestor(node: Node) -> Control:
	var n: Node = node
	while n != null:
		if n is Control and n.has_meta("controller_layer"):
			return n as Control
		n = n.get_parent()
	return null


func _focus_first_in(layer: Control) -> void:
	if not is_instance_valid(layer):
		return
	var controls := _collect_focusable(layer)
	for c: Control in controls:
		if c is BaseButton:
			c.grab_focus()
			return
	for c: Control in controls:
		if not (c is LineEdit):
			c.grab_focus()
			return
	if not controls.is_empty():
		controls[0].grab_focus()
	if _controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD:
		_set_mouse_ui_enabled(false)


func _focus_if_valid(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree() and not control.is_queued_for_deletion():
		control.grab_focus()


func _collect_focusable(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect_focusable_into(root, out)
	return out


func _collect_all_controls(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			out.append(child as Control)
		_collect_all_controls(child, out)


func _collect_focusable_into(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if not c.is_visible_in_tree() or c.is_queued_for_deletion():
				continue
			if c.focus_mode != Control.FOCUS_NONE:
				if c is BaseButton and (c as BaseButton).disabled:
					pass
				else:
					out.append(c)
		_collect_focusable_into(child, out)


func _ensure_valid_focus() -> void:
	if _controller == null or _controller.mode != ControllerDevice.Mode.GAMEPAD:
		return
	if not _ui_layers.is_empty():
		var layer: Control = _ui_layers.back()["control"]
		if not is_instance_valid(layer):
			return
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not layer.is_ancestor_of(focus) or not focus.is_visible_in_tree():
			_focus_first_in(layer)
		return
	if state != null and state.has_pending_battle() and not _battle_intro_playing():
		var focus := get_viewport().gui_get_focus_owner()
		var in_battle_row := focus != null and is_instance_valid(_row_battle) \
			and _row_battle.is_ancestor_of(focus) and focus.is_visible_in_tree()
		if not in_battle_row:
			_focus_bar_first()
		return
	# The controller bottom bar is display-only; it is never a focus target.
	_focus_map()


func _wire_focus_chain() -> void:
	var buttons := _visible_bar_buttons()
	if buttons.size() < 2:
		return
	for i in buttons.size():
		var b := buttons[i]
		b.focus_next = b.get_path_to(buttons[(i + 1) % buttons.size()])
		b.focus_previous = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])


func _visible_bar_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _bottombar == null:
		return out
	for c: Control in _collect_focusable(_bottombar):
		if c is Button:
			var b := c as Button
			if b.is_visible_in_tree() and not b.disabled:
				out.append(b)
	return out


# --- Controller bottom bar ------------------------------------------------------

func _current_glyph_style() -> int:
	var family := _controller.family if _controller != null else ControllerDevice.Family.GENERIC
	return ControllerGlyphs.style_for(family, GcPrefs.glyph_style())


## (The old `_input_hint` copy helper was removed 2026-10-28 with the top-bar control tips —
## the strings are parked in agent-docs/controller-support/PARKED_HINTS.md.)


## Rebuild the display-only controller bar. In controller mode the ordinary mouse rows are
## hidden; this is the only bottom-bar UI, and its pills mirror the direct face buttons.
func _update_pad_bar() -> void:
	if _pad_bar == null:
		return
	var pad_mode := _controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD
	if not pad_mode or state == null or state.is_over() or not _ui_layers.is_empty():
		_pad_bar.visible = false
		_pad_upgrade_bar.visible = false
		return
	if state.has_pending_battle():
		_pad_bar.visible = false
		_pad_upgrade_bar.visible = false
		return
	var style := _current_glyph_style()
	if _pad_menu == "upgrades" and selected_fleet != null:
		_pad_bar.visible = false
		_pad_upgrade_bar.visible = true
		var r_enabled := _reinforce_button != null and not _reinforce_button.disabled
		var t_enabled := _training_button != null and not _training_button.disabled
		var r_text := _reinforce_button.text.split(" · ")[0]
		var t_text := _training_button.text.split(" · ")[0]
		# Only the two choices. The highlighted pill itself is the instruction: left/right
		# moves the highlight, Cross buys the highlighted one, Circle backs out.
		_pad_upgrade_a.setup("", r_text, style, r_enabled, _pad_upgrade_index == 0, false)
		_pad_upgrade_b.setup("", t_text, style, t_enabled, _pad_upgrade_index == 1, false)
		return
	if _pad_menu == "upgrades":
		_pad_menu = "main"
		_pad_upgrade_index = 0
	_pad_upgrade_bar.visible = false
	_pad_bar.visible = true

	var confirm_label := _pad_confirm_label()
	_pad_pill_confirm.visible = confirm_label != ""
	if confirm_label != "":
		_pad_pill_confirm.setup(ControllerGlyphs.ACTION_CONFIRM, confirm_label, style,
			_pad_confirm_enabled(), false)
	_pad_pill_cancel.visible = selected_fleet != null or pending_dest != &""
	if _pad_pill_cancel.visible:
		_pad_pill_cancel.setup(ControllerGlyphs.ACTION_CANCEL, "Back", style, true, false)
	var west_label := "Upgrades" if selected_fleet != null else "Buy Fleet (%d)" % TurnResolver.BUY_FLEET_COST
	var west_enabled := true
	if selected_fleet == null:
		west_enabled = _buy_button != null and _buy_button.visible and not _buy_button.disabled
	_pad_pill_west.setup(ControllerGlyphs.ACTION_WEST, west_label, style, west_enabled, false)
	_pad_pill_north.visible = selected_fleet == null
	if _pad_pill_north.visible:
		_pad_pill_north.setup(ControllerGlyphs.ACTION_NORTH, "End Turn", style,
			_end_turn_button != null and _end_turn_button.visible and not _end_turn_button.disabled, false)


# --- Controls / help modal ----------------------------------------------------

func _on_controls_pressed() -> void:
	if is_instance_valid(_controls_modal):
		return
	_build_controls_modal()


func _build_controls_modal() -> void:
	var shell := _modal_overlay("Controls", Vector2(720, 840))
	_controls_modal = shell["overlay"]
	var col: VBoxContainer = shell["body"]
	_controls_legend_icons.clear()

	_controls_status_label = Label.new()
	_controls_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_status_label.add_theme_color_override("font_color", Tokens.TEXT)
	col.add_child(_controls_status_label)

	_controls_style_button = Button.new()
	_controls_style_button.text = _glyph_style_button_text()
	_controls_style_button.pressed.connect(func():
		_cycle_glyph_style())
	col.add_child(_controls_style_button)

	var vibration := CheckBox.new()
	vibration.text = "Vibration"
	vibration.button_pressed = GcPrefs.vibration()
	vibration.toggled.connect(func(on: bool): GcPrefs.set_vibration(on))
	col.add_child(vibration)

	col.add_child(HSeparator.new())
	_add_controls_legend(col, "Map", [
		[ControllerGlyphs.ACTION_CONFIRM, "Select fleet / Move to the highlighted world"],
		[ControllerGlyphs.ACTION_CANCEL, "Back / deselect fleet"],
		[ControllerGlyphs.ACTION_WEST, "Buy Fleet / Upgrades"],
		[ControllerGlyphs.ACTION_NORTH, "End Turn"],
		[ControllerGlyphs.ACTION_DPAD, "Move cursor; in Upgrades, choose an option"],
		[ControllerGlyphs.ACTION_RIGHT_STICK, "Right stick — pan when zoomed in"],
		[ControllerGlyphs.ACTION_ZOOM_OUT, "Zoom out (smooth while held)"],
		[ControllerGlyphs.ACTION_ZOOM_IN, "Zoom in (smooth while held)"],
		[ControllerGlyphs.ACTION_CENTER, "Reset camera"],
	])
	_add_controls_legend(col, "Menus", [
		[ControllerGlyphs.ACTION_CONFIRM, "Select"],
		[ControllerGlyphs.ACTION_CANCEL, "Back / close"],
		[ControllerGlyphs.ACTION_MENU, "Settings"],
		[ControllerGlyphs.ACTION_HELP, "Controls"],
	])

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_controls_modal)
	col.add_child(close)
	_controls_modal.set_meta("controller_cancel", _close_controls_modal)
	_refresh_controls_modal()


func _add_controls_legend(parent: VBoxContainer, heading: String, rows: Array) -> void:
	var title := Label.new()
	title.text = heading.to_upper()
	title.add_theme_color_override("font_color", Tokens.TEXT)
	title.add_theme_font_override("font", Tokens.FONT_BOLD)
	title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_SMALL)
	parent.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(Tokens.SPACE_3))
	grid.add_theme_constant_override("v_separation", int(Tokens.SPACE_1))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: Array in rows:
		var icon := GlyphIcon.new()
		icon.setup(String(row[0]), _current_glyph_style(), 22.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(icon)
		_controls_legend_icons.append(icon)
		var label := Label.new()
		label.text = String(row[1])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Tokens.TEXT_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
	parent.add_child(grid)


func _close_controls_modal() -> void:
	if is_instance_valid(_controls_modal):
		_controls_modal.queue_free()
	_controls_modal = null
	_controls_status_label = null
	_controls_style_button = null
	_controls_legend_icons.clear()


func _refresh_controls_modal() -> void:
	if not is_instance_valid(_controls_modal):
		return
	if is_instance_valid(_controls_status_label):
		if _controller != null and _controller.has_controller():
			_controls_status_label.text = "Connected: %s — %s" % [
				_controller.device_name(), ControllerGlyphs.family_name(_controller.family)]
		else:
			_controls_status_label.text = "No controller connected — keyboard and mouse still work."
	if is_instance_valid(_controls_style_button):
		_controls_style_button.text = _glyph_style_button_text()
	for icon: GlyphIcon in _controls_legend_icons:
		if is_instance_valid(icon):
			icon.setup(icon.action, _current_glyph_style(), icon.glyph_px)


func _glyph_style_button_text() -> String:
	var auto := GcPrefs.glyph_style() == "auto"
	return "Glyph style: %s" % ControllerGlyphs.style_label(_current_glyph_style(), auto)


func _cycle_glyph_style() -> void:
	var styles := GcPrefs.GLYPH_STYLES
	var i := styles.find(GcPrefs.glyph_style())
	GcPrefs.set_glyph_style(String(styles[(i + 1) % styles.size()]))
	_refresh_controls_modal()
	_refresh()




# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	_sync_fleet_nodes()
	_sync_planet_glow_colors()
	_check_battle_intro()
	_update_battle_zoom()
	_update_status_row()
	_update_credits_badge()

	var winner := state.victor()
	if winner != Faction.NEUTRAL:
		_panel_title.visible = true
		var lost := state.capital_for(Faction.opponent(winner))
		var cap := lost.display_name if lost != null else "the enemy capital"
		if state.two_player:
			# Both sides are human — "VICTORY"/"DEFEAT" would be ambiguous about whose. The
			# winning move was just made on whichever screen is showing this (end_turn is
			# blocked once state.is_over(), so active_faction never advances past it), but
			# naming the winner outright reads better for two people who just played it out
			# together than a one-sided "you win" framing would.
			_panel_title.text = "%s WINS" % Faction.short_name(winner).to_upper()
			_panel_body.text = "%s has fallen. The %s campaign ends here." % [
				cap, Faction.display_name(Faction.opponent(winner))]
		elif winner == _current_seat_faction():
			_panel_title.text = "VICTORY"
			_panel_body.text = "%s has fallen. The %s war machine is broken." % [
				cap, Faction.display_name(Faction.opponent(_current_seat_faction()))]
		else:
			_panel_title.text = "DEFEAT"
			_panel_body.text = "%s has fallen. The %s campaign is lost." % [
				cap, Faction.display_name(_current_seat_faction())]
		_row_mouse.visible = false
		_row_battle.visible = false
		_pad_bar.visible = false
		_pad_upgrade_bar.visible = false
		# The top bar keeps its one-line summary; the popup gets the full epilogue
		# (ui/campaign_endings.gd) — themed to the faction that won, or, on a DEFEAT, told from
		# the loser's side. Two-player always shows the winner's story.
		_show_victory_modal(winner, _panel_title.text, CampaignEndings.epilogue(
			winner, state.two_player or winner == _current_seat_faction(), cap))
		_end_turn_button.disabled = true
		_center_body()
		_layout_topbar()
		queue_redraw()
		return

	_set_turn_title()

	if not state.has_pending_battle():
		_kyber_staged = {}
		_kyber_awaiting = {}
		_kyber_match_live = false
		_coop_result_unlock_ms = 0
		_coop_result_armed = false
		_groundwin_pending_battle_id = ""
		_kyber_watch.disarm()

	if state.has_pending_battle():
		var request := Battle.Request.from_dict(state.pending_battle)
		var planet := state.get_planet(request.planet_id)
		var brief := KyberBridge.build_briefing(request, planet, ContentLoader.load_map_catalog(state.campaign_id), _current_seat_faction(), GcPrefs.offline_mode())
		var mp := KyberBridge.match_params(request, planet, ContentLoader.load_map_catalog(state.campaign_id), _current_seat_faction(), state.two_player, GcPrefs.offline_mode())
		var headline := _battle_headline(request, planet, String(brief["map_name"]))
		var line: String
		if planet.capturable:
			line = "[b]%s[/b] · %s · bots %d/%d · %s def" % [
				headline, brief["map_name"],
				int(brief["attacker_bots"]), int(brief["defender_bots"]),
				Faction.short_name(request.defender),
			]
		else:
			line = "[b]%s[/b] · %s · bots %d/%d" % [
				headline, brief["map_name"],
				int(brief["attacker_bots"]), int(brief["defender_bots"]),
			]
		if not bool(mp["ok"]):
			line += "  [color=#%s](no verified map — use the manual buttons)[/color]" % Tokens.WARNING.to_html(false)
		elif bool(mp.get("fallback", false)):
			line += "  [color=#%s](%s)[/color]" % [Tokens.TEXT_DIM.to_html(false), String(mp["reason"])]
		_panel_body.text = line
	elif selected_fleet != null and pending_dest != &"":
		var dest := state.get_planet(pending_dest)
		var hostile := Faction.is_playable(dest.owner) and dest.owner != selected_fleet.owner
		if hostile:
			# The campaign's "strength" stat doesn't set bot count any more — only
			# reinforcement tier + Combat Training do (KyberBridge.fleet_bots / team_aim) —
			# so show the real match numbers here instead of a Strength comparison that
			# would not match what KYBER actually runs.
			var preview_req := TurnResolver.build_battle_request(state, selected_fleet, dest.id, dest.owner)
			var preview_mp := KyberBridge.match_params(preview_req, dest, ContentLoader.load_map_catalog(state.campaign_id), _current_seat_faction(), state.two_player)
			# Aim is shown as the Combat Training LEVEL bought (playtest 919: "levels purchased,
			# not actual values") — the raw aim-noise number means nothing to a player.
			_panel_body.text = "Attack [b]%s[/b] (%s)? %d bots (%s) vs %d bots (%s) defending — this starts a battle." % [
				dest.display_name, Faction.display_name(dest.owner),
				int(preview_mp["attacker_bots"]), _training_label(preview_req.attacker_training),
				int(preview_mp["defender_bots"]), _training_label(preview_req.defender_training)]
		else:
			_panel_body.text = "Move to [b]%s[/b] (%s)." % [
				dest.display_name, Faction.display_name(dest.owner)]
	elif selected_fleet != null and _pad_menu == "upgrades":
		_panel_body.text = "Upgrades for fleet at [b]%s[/b]." % _planet_name(selected_fleet.location)
	elif selected_fleet != null:
		var sel_planet := state.get_planet(selected_fleet.location)
		if sel_planet != null:
			_panel_body.text = _inspect_text(sel_planet)
		else:
			_panel_body.text = "[b]%s[/b]" % _planet_name(selected_fleet.location)
	else:
		var inspected := state.get_planet(_inspect_id) if _inspect_id != &"" else null
		if inspected != null:
			_panel_body.text = _inspect_text(inspected)
		elif _gc_net != null and state.active_faction != _current_seat_faction():
			# `2026-09-24` (playtest 922): "remove End Turn and Buy Fleet from screen when not
			# player turn... say Waiting for (faction) to end turn." — online only; hotseat's
			# whole perspective already flips with the seat, so there's nothing to wait for there.
			_panel_body.text = "Waiting for %s to end their turn…" % Faction.display_name(state.active_faction)
		elif state.turn == 1 and not state.fleets_owned_by(_current_seat_faction()).is_empty():
			# `2026-09-21` (playtest 921): "unclear if you have one or need to buy one" — a
			# first-turn-only callout naming the starting fleet's own world. Kept short: the
			# old sentence included a click/press instruction, which is parked in
			# agent-docs/controller-support/PARKED_HINTS.md for future tooltip use.
			var starter: Fleet = state.fleets_owned_by(_current_seat_faction())[0]
			_panel_body.text = "Your first fleet is at [b]%s[/b]." % _planet_name(starter.location)
		else:
			_panel_body.text = ""

	if _notice != "":
		_panel_body.text = "[color=#%s]%s[/color]" % [Tokens.WARNING.to_html(false), _notice]

	var battling := state.has_pending_battle()
	var at_fleet_cap := state.fleets_owned_by(_current_seat_faction()).size() >= TurnResolver.MAX_FLEETS
	var too_poor := int(state.credits.get(_current_seat_faction(), 0)) < TurnResolver.BUY_FLEET_COST

	# Label the manual winner buttons for the current campaign's two sides.
	var factions := _campaign_factions()
	for i in mini(2, factions.size()):
		var short := Faction.short_name(factions[i])
		_win_buttons[i].text = "%s won" % short
		_win_buttons[i].tooltip_text = "Report %s as the winner by hand" % Faction.display_name(factions[i])

	var battle_row := battling and not _battle_intro_playing()   # the map beat plays first
	if not battle_row:
		_close_more_menu()
	var pad_mode := _controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD
	_row_battle.visible = battle_row
	_battle_box.visible = battle_row
	if selected_fleet == null or battling:
		_pad_menu = "main"
		_pad_upgrade_index = 0
	var fleet_selected := selected_fleet != null and not battling
	# Mouse bar mirrors the controller's fleet actions: Move stays visible (greyed until a
	# legal destination is picked), Back is the only way to deselect, and Buy Fleet is hidden
	# while a fleet is selected.
	_move_button.visible = fleet_selected
	_move_button.disabled = not fleet_selected or pending_dest == &""
	_cancel_button.visible = fleet_selected
	# `2026-09-24` (playtest 922): online, not-your-turn hides these two entirely (rather than
	# just disabling them) — the panel body already says "Waiting for X…" above; a live but
	# greyed-out End Turn/Buy Fleet on a screen that can't legally act on them read as broken.
	var my_turn_or_offline := _gc_net == null or state.active_faction == _current_seat_faction()
	_buy_button.visible = my_turn_or_offline and selected_fleet == null
	_buy_button.disabled = too_poor or at_fleet_cap or _ai_opening_seed >= 0
	_end_turn_button.visible = my_turn_or_offline and selected_fleet == null
	_end_turn_button.disabled = battling or _ai_opening_seed >= 0

	# Reinforce + Combat Training act on the selected fleet only.
	var can_reinforce := selected_fleet != null and not battling
	_reinforce_button.visible = can_reinforce
	_training_button.visible = can_reinforce
	if can_reinforce:
		var credits := int(state.credits.get(selected_fleet.owner, 0))
		var tier := selected_fleet.reinforcement_tier
		var r_max := tier >= TurnResolver.MAX_REINFORCEMENTS
		var r_cost := TurnResolver.reinforcement_cost(tier)
		_reinforce_button.text = "Reinforcements maxed" if r_max else "Reinforce (%d) · +bots" % r_cost
		_reinforce_button.tooltip_text = "" if r_max else "Fleet bots tier %d → %d" % [tier, tier + 1]
		_reinforce_button.disabled = r_max or credits < r_cost
		var t_level := selected_fleet.combat_training_level
		if t_level >= TurnResolver.MAX_COMBAT_TRAINING:
			_training_button.text = "Combat Training %s (max)" % _roman(t_level)
			_training_button.disabled = true
		else:
			var t_cost := TurnResolver.combat_training_cost(t_level)
			_training_button.text = "Combat Training %s (%d) · sharper aim" % [_roman(t_level + 1), t_cost]
			_training_button.tooltip_text = "This fleet's team gets sharper bot aim in KYBER matches (level %d → %d)" % [t_level, t_level + 1]
			_training_button.disabled = credits < t_cost

	var offline := GcPrefs.offline_mode()

	# Manual win buttons are a result path, not an always-on battle control. They appear
	# inline only when KYBER genuinely cannot supply a result (offline, undetermined staged
	# result, or co-op after its hold), or in the debug More… menu if enabled. A normal
	# battle shows only Play/Reconnect + Abandoned.
	var result_unreadable := not _kyber_staged.is_empty() \
		and int(_kyber_staged.get("winner_team", 0)) == 0
	var coop_ready := _battle_is_coop() and _coop_result_armed and not _coop_result_hold_active()
	var manual_visible := offline or result_unreadable or coop_ready
	var result_inline := battle_row and manual_visible
	_place_result_buttons(result_inline, battle_row and result_unreadable)
	for b in _win_buttons:
		b.visible = true
	if is_instance_valid(_restart_battle_button):
		_restart_battle_button.visible = true
	if is_instance_valid(_abandon_button):
		_abandon_button.visible = battle_row
	if _more_button != null:
		# More… is the debug home for the win/restart fallback, and disappears when those
		# actions are already inline or when a result is still on its way.
		var show_more := battle_row and GcPrefs.show_online_more_menu() and not result_inline
		_more_button.visible = show_more
		if not show_more:
			_close_more_menu()
	if battle_row and not manual_visible and _is_net_client():
		_panel_body.text += "\n\n[color=#%s]Waiting for the host to start the match in KYBER — this updates on its own once it lands.[/color]" % Tokens.TEXT_DIM.to_html(false)

	if _kyber_setup_button != null:
		# Only the host ever drives KYBER for an online match — hide the whole setup path on
		# the client's screen rather than leaving it merely inert if clicked.
		_kyber_setup_button.visible = not offline and not _is_net_client()

	var have_staged := not _kyber_staged.is_empty()
	var awaiting := not _kyber_awaiting.is_empty()
	var linked := _kyber_link != null and _kyber_link.is_online()

	# Offline mode replaces the whole KYBER flow: the setup briefing goes in the centred
	# message area, and the manual winner buttons below are the result path.
	if battling and offline:
		_panel_body.text += "\n\n" + _offline_briefing_text()

	# A net client never drives KYBER at all — the host is the sole authority (gc_net.gd's
	# header). Hiding this whole block for a client, rather than leaving it present-but-inert,
	# is what actually prevents a client's own local KYBER Setup / Play / Apply from ever
	# touching this client's local `state` outside the host's control (see the matching
	# _kyber_link.close_link() call in _start_online_join, and the defensive early-returns in
	# _on_kyber_play_pressed / _apply_staged_result below).
	var kyber_ui := battling and not offline and not _is_net_client()
	if _kyber_play_button != null:
		# While a `load` is in flight, hide Play (no double-send). End match is likewise
		# hidden until KYBER confirms the requested level actually loaded — it is only a
		# meaningful escape hatch while a round is live in SWBF2.
		# Supremacy / GA / Blast give no end-of-round score in this KYBER build (verified — see
		# docs/SUPREMACY_PHASE.md), so winner_team is 0 for those. When we DID read a winner
		# (Supremacy outro bundle), show the result + Apply. When we didn't, don't crowd the
		# bar with a disabled Apply and a wrapping hint — the "no automatic winner" message is
		# already in `_notice`; just leave the manual winner buttons below.
		var undetermined := have_staged and int(_kyber_staged.get("winner_team", 0)) == 0
		var show_apply := kyber_ui and have_staged and not undetermined
		_kyber_play_button.visible = kyber_ui and linked and not have_staged and not awaiting
		_kyber_end_row.visible = kyber_ui and linked and _kyber_match_live and not have_staged
		_kyber_result_label.visible = show_apply
		_kyber_apply_button.visible = show_apply
		if show_apply:
			_kyber_result_label.text = _describe_staged_result()
			_kyber_apply_button.disabled = false
			_kyber_apply_button.text = "Apply result"
	if _restart_battle_button != null:
		# Restart is a normal debug/popup action while a result is on its way, but when
		# KYBER could not read a result it is the recovery path and shows inline by default.
		_restart_battle_button.visible = result_unreadable or (kyber_ui and linked)
	if _kyber_connect_button != null:
		var need_connect := kyber_ui and not linked and not have_staged and OS.get_name() == "Windows"
		_kyber_connect_button.visible = need_connect
		if need_connect:
			_kyber_connect_button.text = "Reconnect to KYBER" if _kyber_running_cached() \
				else "Start KYBER + plugin"

	_row_mouse.visible = not battling and not pad_mode and _mouse_row_has_action()
	_pad_sync_battle_focus()
	_update_pad_bar()
	_center_body()
	_layout_topbar()
	_validate_pad_cursor()
	_wire_focus_chain()
	_ensure_valid_focus.call_deferred()
	queue_redraw()
	_autosave_if_due()


## Wrap the message area's text so it renders centred (RichTextLabel has no align property).
func _center_body() -> void:
	if _panel_body != null and not _panel_body.text.begins_with("[center]"):
		_panel_body.text = "[center]%s[/center]" % _panel_body.text


## kyber_running() but cached — the raw call blocks on `tasklist`. Only re-checked while a
## battle is pending and the link is down (the one moment the answer changes what to show).
func _kyber_running_cached() -> bool:
	var now := Time.get_ticks_msec()
	if now - _kyber_running_checked_ms > 3000:
		_kyber_running_checked_ms = now
		_kyber_running_cache = KyberPluginInstaller.kyber_running()
	return _kyber_running_cache


## Fresh launcher/plugin state for the wizard: `running` = kyber_launcher.exe exists,
## `plugin_online` = the gc_result plugin is actually listening (our link may still be
## OFFLINE before a hosted match, so an independent port check is the reliable signal).
## Forces one tasklist refresh so opening the step is accurate.
func _kyber_runtime_state() -> Dictionary:
	_kyber_running_checked_ms = 0
	var running := _kyber_running_cached()
	var online := running and _kyber_link != null and _kyber_link.is_online()
	if running and not online:
		if _kyber_link != null:
			_kyber_link.retry_now()
		# The plugin binds its socket at load even if its accept loop only runs once a
		# hosted match exists, so the independent port check is the reliable signal here.
		online = KyberLink.plugin_listening()
	return {"running": running, "plugin_online": online}


func _draw() -> void:
	# The galaxy image stack and the glowing worlds render in 3D behind this canvas. This
	# pass is only the overlay: constellation lines, ownership rings, selection, fleet pips.
	if _galaxy_root == null:
		draw_rect(Rect2(Vector2.ZERO, size), Tokens.VOID)
	if state == null or _camera == null:
		return

	var reachable := _reachable_ids()

	# `2026-09-13`: this whole 2D overlay (constellation lines, ownership rings, reachable/
	# pending-dest rings, fleet pips) is sized and designed for the galaxy-view scale — at
	# full battle zoom the screen is often just one planet and up to two ships, and these
	# elements ended up reading as clutter drawn on top of (or, for the ownership ring
	# specifically, actually INSIDE — see _screen_radius's own comment on the clamp that used
	# to cause that) the now much-larger world instead of tastefully around it. Rather than
	# trying to keep every one of these correctly sized at every zoom level, they simply fade
	# out as the camera moves in, gone well before full battle zoom — matching how the 3D
	# galaxy backdrop / sky layers / planet glow already fade with _zoom_t elsewhere.
	var overlay_fade := _overlay_fade()

	# The focus world keeps full-strength reticle treatment while everything else fades.
	# On pad/keyboard it's the cursor; on mouse it's the hovered (or last inspected) world.
	var pad_active := _keyboard_map_nav or (_controller != null and _controller.mode == ControllerDevice.Mode.GAMEPAD)
	var focus_id: StringName = &""
	if pad_active:
		focus_id = _pad_cursor_id
	elif _is_map_region() and not state.has_pending_battle():
		focus_id = _hover_id if _hover_id != &"" else _inspect_id
	var persistent_label := focus_id != &"" and overlay_fade < 0.6 \
		and _is_map_region() and not state.has_pending_battle()

	# Hyperlanes first, drawn once per pair, trimmed back to each end's glow radius (see
	# _line_between) so a line reads as passing BEHIND a planet/node instead of straight
	# through its centre and over the top of it — this is a 2D overlay compositing on top of
	# the whole 3D scene underneath (planet bodies, glows, ships all render in 3D first), so
	# true depth occlusion isn't available here; stopping the line at the glow's own edge
	# gets the same visual result for anything reasonably round, without needing to rebuild
	# hyperlanes as real depth-tested 3D geometry.
	var drawn := {}
	var origin_id: StringName = selected_fleet.location if selected_fleet != null else &""
	for p: Planet in state.planets.values():
		for other_id in p.connections:
			var other: Planet = state.get_planet(other_id)
			if other == null:
				continue
			var a := String(p.id)
			var b := String(other_id)
			var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
			if drawn.has(key):
				continue
			drawn[key] = true
			var lit := reachable.has(other_id) or reachable.has(p.id)
			# Constellation lines: hairline-thin and faint, except a selected fleet's legal
			# outgoing lanes, which are thick and carry a travelling pulse below.
			var lane_col := Color(0.66, 0.80, 1.0, 0.80) if lit else Color(0.60, 0.72, 0.98, 0.32)
			var width := 1.0
			var outgoing := false
			var from_planet := p
			var to_planet := other
			if selected_fleet != null and (p.id == origin_id or other_id == origin_id):
				var dest_id: StringName = other_id if p.id == origin_id else p.id
				if reachable.has(dest_id):
					outgoing = true
					lane_col = Tokens.LANE_ACTIVE
					width = 3.0
					if p.id != origin_id:
						from_planet = other
						to_planet = p
			_line_between(p, other, _faded(lane_col, overlay_fade), width)
			if outgoing:
				_draw_move_pulse(from_planet, to_planet, overlay_fade)

	# The staged destination: a line from the selected fleet's world.
	if selected_fleet != null and pending_dest != &"":
		var from_planet: Planet = state.get_planet(selected_fleet.location)
		var to_planet: Planet = state.get_planet(pending_dest)
		if from_planet != null and to_planet != null:
			_line_between(from_planet, to_planet, _faded(Tokens.LANE_ACTIVE, overlay_fade), 3.0)

	for p: Planet in state.planets.values():
		var centre := _screen_position(p)
		var r := _screen_radius(p)

		# Ownership: a faction-coloured ring hugging a held world's glow. Lanes are owned by
		# nobody, so no ring.
		if p.capturable and Faction.is_playable(p.owner):
			draw_arc(centre, r + 4.0, 0, TAU, 48, _faded(_owner_color(p.owner), overlay_fade), 2.0, true)

		if reachable.has(p.id):
			draw_arc(centre, r + 7.0, 0, TAU, 40, _faded(Tokens.LANE_ACTIVE, overlay_fade), 1.0, true)

		if p.id == pending_dest:
			draw_arc(centre, r + 7.0, 0, TAU, 40, _faded(Tokens.LANE_ACTIVE, overlay_fade), 2.5, true)

		var stationed := state.fleets_at(p.id)
		for i in stationed.size():
			var f: Fleet = stationed[i]
			var pip := centre + Vector2(-9.0 + i * 9.0, r + 13.0)
			var pip_colour := _owner_color(f.owner)
			if f == selected_fleet:
				draw_circle(pip, 6.0, _faded(Tokens.LANE_ACTIVE, overlay_fade))
			draw_circle(pip, 4.0, _faded(pip_colour, overlay_fade))

		# Selection feedback (playtest 920v2: "not sure what is selected"): the selected fleet's
		# world gets a bold double gold ring and a tag; a fleet that COULD be selected gets a ▼.
		if selected_fleet != null and p.id == selected_fleet.location:
			draw_arc(centre, r + 12.0, 0, TAU, 56, _faded(Tokens.WARNING, overlay_fade), 3.5, true)
			draw_arc(centre, r + 18.0, 0, TAU, 56, _faded(Tokens.WARNING, overlay_fade * 0.4), 1.5, true)
		elif selected_fleet == null:
			for f: Fleet in stationed:
				if _fleet_selectable(f):
					var top := centre + Vector2(0.0, -r - 12.0)
					draw_colored_polygon(PackedVector2Array([top + Vector2(-6, -7), top + Vector2(6, -7), top]),
						_faded(Tokens.LANE_ACTIVE, overlay_fade))
					break
		if p.id == _inspect_id and not (selected_fleet != null and p.id == selected_fleet.location):
			draw_arc(centre, r + 9.0, 0, TAU, 48, _faded(Tokens.TEXT, overlay_fade * 0.7), 1.5, true)
		# Names: every world always (dim), lanes only when hovered or picked.
		var named := p.capturable or p.id == _hover_id or p.id == _inspect_id
		if named and overlay_fade > 0.05 and not (persistent_label and p.id == focus_id):
			var strong := p.id == _hover_id or p.id == _inspect_id
			var col := Tokens.TEXT if strong else Tokens.TEXT_DIM
			# Name sits below the world, clear of a parked fleet's own downward offset.
			_draw_map_label(centre + Vector2(0.0, r + 44.0), p.display_name,
				Tokens.FONT_MEDIUM if strong else Tokens.FONT_BOOK, 13 if strong else 12, _faded(col, overlay_fade))

	# The gamepad/keyboard planet cursor: a bright double ring around the focused world.
	# Unlike the rest of the galaxy-scale overlay it does NOT fade with zoom — zooming in
	# keeps the reticle readable while everything else thins out. Its radius tracks the
	# planet's own projected size, so it becomes an outline of the zoomed world rather than
	# a small fixed ring floating inside it.
	if _pad_cursor_drawn():
		var cursor_planet := state.get_planet(_pad_cursor_id)
		if cursor_planet != null:
			var cursor_centre := _screen_position(cursor_planet)
			var cursor_r := _screen_body_radius(cursor_planet)
			var ring_r := maxf(cursor_r + 10.0, 26.0)
			draw_arc(cursor_centre, ring_r, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.55), 6.0, true)
			draw_arc(cursor_centre, ring_r, 0.0, TAU, 64, Tokens.LANE_ACTIVE, 3.0, true)
			draw_arc(cursor_centre, ring_r + 5.0, 0.0, TAU, 64, _faded(Tokens.LANE_ACTIVE, 0.35), 1.5, true)
			if persistent_label:
				_draw_map_label(cursor_centre + Vector2(0.0, ring_r + 24.0), cursor_planet.display_name,
					Tokens.FONT_MEDIUM, 13, Tokens.TEXT)

	# Mouse mode has no persistent planet cursor, but while zoomed in the world under the
	# pointer (or the last inspected world) keeps the same full-strength reticle.
	if not pad_active and focus_id != &"" and overlay_fade < 0.9:
		var mouse_planet := state.get_planet(focus_id)
		if mouse_planet != null:
			var mouse_centre := _screen_position(mouse_planet)
			var mouse_r := maxf(_screen_body_radius(mouse_planet) + 10.0, 26.0)
			draw_arc(mouse_centre, mouse_r, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.45), 5.0, true)
			draw_arc(mouse_centre, mouse_r, 0.0, TAU, 64, Tokens.TEXT, 2.5, true)
			if persistent_label:
				_draw_map_label(mouse_centre + Vector2(0.0, mouse_r + 24.0), mouse_planet.display_name,
					Tokens.FONT_MEDIUM, 13, Tokens.TEXT)


## Centred text with a 1px dark drop shadow so it reads over any nebula/planet behind it.
func _draw_map_label(at: Vector2, text: String, font: Font, font_size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var w := 240.0
	var pos := at - Vector2(w if align == HORIZONTAL_ALIGNMENT_RIGHT else w * 0.5, 0.0)
	draw_string(font, pos + Vector2(1, 1), text, align, w, font_size, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, pos, text, align, w, font_size, col)


## `c` with its own alpha scaled by `mult` — the shared helper behind _draw()'s overlay_fade.
static func _faded(c: Color, mult: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * mult)


## How much every galaxy-view-scale 2D overlay element (constellation lines, ownership
## rings, reachable/pending-dest rings, fleet pips, and — _update_insignia_icons — home-world
## insignia) should fade by, as the camera moves into battle zoom. Shared so _draw() and
## _update_insignia_icons (a real per-frame Node update, not an immediate-mode draw call, so
## it can't just read _draw()'s own local) always agree.
func _overlay_fade() -> float:
	return 1.0 - smoothstep(0.3, 0.75, _zoom_t)


## A constellation-line segment trimmed back at both ends to sit just outside each planet's
## own glow radius (+ LANE_EDGE_MARGIN, matching the ownership ring's own "+4.0" hug) instead
## of running straight through its centre — see the comment above this function's call site
## in _draw() for why a screen-space trim, not real 3D depth-testing. Silently draws nothing
## if the two glows already overlap (adjacent nodes placed unusually close) rather than a
## backwards/negative-length segment.
const LANE_EDGE_MARGIN := 4.0

func _line_between(a: Planet, b: Planet, col: Color, width: float) -> void:
	var pa := _screen_position(a)
	var pb := _screen_position(b)
	var seg := pb - pa
	var dist := seg.length()
	if dist < 0.01:
		return
	var dir := seg / dist
	var ra := _screen_radius(a) + LANE_EDGE_MARGIN
	var rb := _screen_radius(b) + LANE_EDGE_MARGIN
	if ra + rb >= dist:
		return
	draw_line(pa + dir * ra, pb - dir * rb, col, width, true)


## A looping light streak travelling along the already-trimmed lane segment, from `from`
## toward `to`. The tail fades to nothing behind the head (a light streak, not a solid dash),
## and the head has no dot or rounded tip. The lane's planet glows mask both ends: a streak
## enters from behind `from`, and after its head passes `to` the remaining trail slides out
## of sight behind `to` instead of snapping off. A second pulse is already entering at the
## origin by then, so the loop is continuous.
const MOVE_PULSE_TRAVEL_S := 1.35  ## seconds for the head to go origin → destination
const MOVE_PULSE_TAIL := 0.55      ## tail length as a fraction of the whole lane

func _draw_move_pulse(from: Planet, to: Planet, alpha: float) -> void:
	if alpha <= 0.01:
		return
	var pa := _screen_position(from)
	var pb := _screen_position(to)
	var seg := pb - pa
	var dist := seg.length()
	if dist < 0.01:
		return
	var dir := seg / dist
	var ra := _screen_radius(from) + LANE_EDGE_MARGIN
	var rb := _screen_radius(to) + LANE_EDGE_MARGIN
	if ra + rb >= dist:
		return
	var start := pa + dir * ra
	var end := pb - dir * rb
	if start.distance_to(end) < 6.0:
		return
	# One shared clock for every outgoing lane. Spacing between pulses is one lane plus one
	# tail, so the previous trail leaves exactly as the next pulse enters.
	var span := 1.0 + MOVE_PULSE_TAIL
	var cycle_s := MOVE_PULSE_TRAVEL_S * span
	var phase := fmod(Time.get_ticks_msec() * 0.001 / cycle_s, 1.0)
	var base_head := phase * span - MOVE_PULSE_TAIL
	_draw_pulse_streak(start, end, base_head, alpha)
	_draw_pulse_streak(start, end, base_head + span, alpha)


## Draw one streak, clipped to the lane's 0..1 range. The gradient is computed from the
## pulse's own tail→head position, so clipping at either end never changes its shape.
func _draw_pulse_streak(start: Vector2, end: Vector2, head_f: float, alpha: float) -> void:
	var tail_f := head_f - MOVE_PULSE_TAIL
	var lo := maxf(tail_f, 0.0)
	var hi := minf(head_f, 1.0)
	if hi - lo < 0.002:
		return
	var steps := 24
	var pts := PackedVector2Array()
	var core_cols := PackedColorArray()
	var glow_cols := PackedColorArray()
	var core := Color(0.82, 0.97, 1.0)
	var glow := Color(0.30, 0.72, 1.0)
	for i in steps + 1:
		var s := lerpf(lo, hi, float(i) / float(steps))
		pts.append(start.lerp(end, s))
		var along := clampf((s - tail_f) / MOVE_PULSE_TAIL, 0.0, 1.0)
		var a := pow(along, 1.15) * alpha
		core_cols.append(Color(core, a))
		glow_cols.append(Color(glow, a * 0.24))
	draw_polyline_colors(pts, glow_cols, 11.0, true)
	draw_polyline_colors(pts, core_cols, 3.6, true)


func _reachable_ids() -> Dictionary:
	var out := {}
	if selected_fleet == null:
		return out
	var origin: Planet = state.get_planet(selected_fleet.location)
	if origin == null:
		return out
	for c in origin.connections:
		# Match TurnResolver: a world already holding a friendly fleet is not a legal move
		# destination, so it should not glow/read as reachable either.
		if state.fleet_at(c, selected_fleet.owner) == null:
			out[c] = true
	return out
