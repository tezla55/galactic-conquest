class_name GcPrefs
extends RefCounted

## Small persisted user preferences that are not display / difficulty / KYBER-path.
## One flat ConfigFile at user://gc_prefs.cfg. All getters have a safe default.

const PATH := "user://gc_prefs.cfg"
const SECTION := "kyber"


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PATH)   # missing file is fine — everything falls back to a default
	return c


static func _read(key: String, default: Variant) -> Variant:
	return _cfg().get_value(SECTION, key, default)


static func _write(key: String, value: Variant) -> void:
	var c := _cfg()
	c.set_value(SECTION, key, value)
	c.save(PATH)


## Fold a determinate KYBER result into the campaign automatically (no "Apply" click).
static func auto_apply_results() -> bool:
	return bool(_read("auto_apply_results", false))

static func set_auto_apply_results(v: bool) -> void:
	_write("auto_apply_results", v)


## Play with no KYBER at all: each battle shows the settings to recreate in Arcade /
## Instant Action, and the winner is reported by hand. Chosen on the start screen; for
## when KYBER's hosting backend is unavailable.
static func offline_mode() -> bool:
	return bool(_read("offline_mode", false))

static func set_offline_mode(v: bool) -> void:
	_write("offline_mode", v)


## Sets KYBER_MESSAGE_DEBUG when launching KYBER (KyberPluginInstaller) — logs the name of
## EVERY engine message KYBER's module sees, not just the ones it currently acts on. The
## only way to see a signal (e.g. a real co-op mission-end message) that no Lua reflection
## can reach. Off by default — this can be very verbose (every message, every frame) — meant
## to be switched on for one diagnostic KYBER session, not left on permanently.
static func kyber_message_debug() -> bool:
	return bool(_read("kyber_message_debug", false))

static func set_kyber_message_debug(v: bool) -> void:
	_write("kyber_message_debug", v)


## The host's own EA/KYBER player id (bridge/kyber_ea_id.gd's "[Server] <name> (<id>)
## successfully authenticated" number, from KYBER's own log) — set once, persists across
## campaigns/relaunches. This is what lets online two-player team auto-assignment
## (main.gd::_on_kyber_play_pressed) tell the host's own identity apart from a joining
## friend's WITHOUT guessing from the order they authenticated in — see kyber_ea_id.gd's
## header for why order alone isn't trustworthy. 0 = not set; auto-assignment then skips
## itself entirely rather than falling back to a guess.
static func my_kyber_player_id() -> int:
	return int(_read("my_kyber_player_id", 0))

static func set_my_kyber_player_id(id: int) -> void:
	_write("my_kyber_player_id", id)


## The FRIEND's KYBER player id, same source, set on the HOST's machine alongside its own —
## `2026-09-21` (playtest 921: "make player type in KYBER ID before hosting/joining match so
## that we put them on correct team each time"). With both ids known, auto-assignment matches
## two SPECIFIC identities instead of "exactly two people authenticated, the other one must be
## the friend" — a heuristic that silently breaks the instant a third person (or a returning
## player from an earlier session) shows up in the same KYBER log window. 0 = not set; the
## host's own id alone still works the old ("exactly one other") way.
static func friend_kyber_player_id() -> int:
	return int(_read("friend_kyber_player_id", 0))

static func set_friend_kyber_player_id(id: int) -> void:
	_write("friend_kyber_player_id", id)


## Mute the galaxy-map music (galaxy_music.gd, GalaxyMusic). Independent of the window-focus
## / battle-active ducking in main.gd::_update_music — this is a flat "never play" the user
## sets once from the settings menu, not a transient duck, so it has its own section (not
## "kyber" — nothing here is KYBER-specific) and survives across campaigns/relaunches.
const SOUND_SECTION := "sound"

static func music_muted() -> bool:
	return bool(_cfg().get_value(SOUND_SECTION, "music_muted", false))

static func set_music_muted(v: bool) -> void:
	var c := _cfg()
	c.set_value(SOUND_SECTION, "music_muted", v)
	c.save(PATH)


## `2026-10-08` (playtest 104, item 6): local hotseat confused more players than it helped
## ("what is this, why would I share a keyboard") — hidden from the normal New Game wizard,
## surfaced only as an experimental toggle in the Debug panel (`main.gd::_build_log_modal`).
## Off by default; the feature itself (`GalaxyState.two_player`) is unchanged either way.
const DEBUG_SECTION := "debug"

static func hotseat_enabled() -> bool:
	return bool(_cfg().get_value(DEBUG_SECTION, "hotseat_enabled", false))

static func set_hotseat_enabled(v: bool) -> void:
	var c := _cfg()
	c.set_value(DEBUG_SECTION, "hotseat_enabled", v)
	c.save(PATH)


## Debug-only: show the "More…" KYBER escape-hatch menu. Off by default in every mode;
## its only visible action is Restart Battle. The normal winner buttons stay inline.
static func show_online_more_menu() -> bool:
	return bool(_cfg().get_value(DEBUG_SECTION, "show_online_more_menu", false))


static func set_show_online_more_menu(v: bool) -> void:
	var c := _cfg()
	c.set_value(DEBUG_SECTION, "show_online_more_menu", v)
	c.save(PATH)


## Controller/gamepad preferences (ui/controller_*.gd, main.gd). `glyph_style` is one of
## "auto", "xbox360", "xbox", "ps4", "ps5", "generic" — "auto" follows the detected
## controller, the rest are a manual override for Steam Input / DS4Windows, which often
## disguise a DualSense or DualShock 4 as an Xbox pad. `vibration` is a plain on/off.
const INPUT_SECTION := "input"
const GLYPH_STYLES := ["auto", "xbox360", "xbox", "ps4", "ps5", "generic"]

static func glyph_style() -> String:
	var v := String(_cfg().get_value(INPUT_SECTION, "glyph_style", "auto"))
	return v if GLYPH_STYLES.has(v) else "auto"

static func set_glyph_style(v: String) -> void:
	var c := _cfg()
	c.set_value(INPUT_SECTION, "glyph_style", v if GLYPH_STYLES.has(v) else "auto")
	c.save(PATH)

static func vibration() -> bool:
	return bool(_cfg().get_value(INPUT_SECTION, "vibration", true))

static func set_vibration(v: bool) -> void:
	var c := _cfg()
	c.set_value(INPUT_SECTION, "vibration", v)
	c.save(PATH)
