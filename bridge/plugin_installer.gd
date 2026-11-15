class_name KyberPluginInstaller
extends RefCounted

## Packages bridge/kyber_plugin/gc_result/ as a .kbplugin and launches the KYBER
## Launcher with KYBER_SERVER_PLUGINS_PATH pointing at it.
##
## KYBER's module loads a server Lua plugin ONLY from getenv("KYBER_SERVER_PLUGINS_PATH")
## (or KYBER_DEV_PLUGIN_PATH) — the desktop Launcher scans no folder and its own plugin
## manager only loads one built-in DLL. So GC sets that variable in ITS OWN process
## (OS.set_environment — in memory, nothing persisted to the registry or user profile,
## exactly how KYBER sets its own variables) and starts kyber_launcher.exe as a child,
## which inherits it. A KYBER the user opened themselves will NOT have the variable.
##
## Windows only. Everything here returns a plain result dict; ui/ shows the strings.

const PLUGIN_SRC := "res://bridge/kyber_plugin/gc_result"
const PLUGIN_FILES: Array[String] = ["plugin.json", "server/__init__.lua"]
const ENV_VAR := "KYBER_SERVER_PLUGINS_PATH"
## KYBER defaults to `info`-level logging, which is enough for the winner markers already
## in use (`Outro_Team<N>` is `[info]`) but hides the BF+/BXL `[PrintDebugText]` lines that
## are the ONLY way anything about co-op's actual mission state (not just its win/loss,
## which has no signal at all yet, verified live) has ever been discovered — that's exactly
## how the Clone Wars capital-ship-phase winner and the boarding-faction name were found for
## Supremacy. Set unconditionally so every future KYBER session started from GC captures at
## the higher verbosity without the player needing to know this env var exists.
const LOG_LEVEL_VAR := "KYBER_LOG_LEVEL"
const LOG_LEVEL := "debug"
## KYBER's module hooks the engine's raw message dispatcher and, with this set, logs the
## name of EVERY engine message it sees ("Dispatched message <TypeName>") — not just the
## dozen names the module currently acts on (Module/Source/Core/Program.cpp). This is the
## only way to see whatever internal message actually corresponds to a match/mission ending
## that no Lua-side reflection can reach (KYBER's own Lua bindings don't expose the game's
## own BXL/gamemode logic at all — this hook sits a layer below that, on the engine itself).
## Verified opt-in on purpose: this can be VERY verbose (every dispatched message, every
## frame) — set only while actively hunting a new signal, not as a permanent default the way
## LOG_LEVEL above is. Toggle via GcPrefs.kyber_message_debug(), off by default.
const MESSAGE_DEBUG_VAR := "KYBER_MESSAGE_DEBUG"
const CONFIG_PATH := "user://kyber_setup.cfg"
const LAUNCHER_EXE := "kyber_launcher.exe"
const PLUGIN_SUBDIR := "GalacticConquest"
const KBPLUGIN_NAME := "gc_result.kbplugin"

## Vendored, unmodified KYBER community plugin (bridge/kyber_plugin/playtest_gungame/,
## MIT — see its README.md) the user can playtest live, separately from gc_result — see
## launch_gungame_playtest(). Not part of GC's own campaign flow at all.
const PLAYTEST_GUNGAME_SRC := "res://bridge/kyber_plugin/playtest_gungame"
const PLAYTEST_GUNGAME_FILES: Array[String] = [
	"plugin.json", "common/sdk.lua", "server/__init__.lua", "server/admins.lua",
	"server/bfplus_gun_list.lua", "server/input_blocks.lua", "server/vanilla_gun_list.lua",
]
const PLAYTEST_SUBDIR := "GalacticConquestPlaytest"
const GUNGAME_KBPLUGIN_NAME := "gungame.kbplugin"


# --- paths ------------------------------------------------------------------
#
# The .kbplugin goes in GC's own user data dir, NOT next to kyber_launcher.exe:
# KYBER installed under C:\Program Files\ can't be written there without admin rights.
# KYBER_SERVER_PLUGINS_PATH is an absolute path and can point anywhere.

static func plugin_dir() -> String:
	return OS.get_user_data_dir().replace("\\", "/").path_join(PLUGIN_SUBDIR)


static func kbplugin_path() -> String:
	return plugin_dir().path_join(KBPLUGIN_NAME)


## A SEPARATE directory from gc_result's — KYBER_SERVER_PLUGINS_PATH only ever points at
## one directory, so switching it to this one for a playtest means gc_result does NOT load
## alongside it (deliberate: GunGame's own team/gamemode management would fight ours).
static func gungame_plugin_dir() -> String:
	return OS.get_user_data_dir().replace("\\", "/").path_join(PLAYTEST_SUBDIR)


static func gungame_kbplugin_path() -> String:
	return gungame_plugin_dir().path_join(GUNGAME_KBPLUGIN_NAME)


## Where earlier builds wrote the package (next to the launcher) — checked so an upgrade
## can clean it up. "" when the launcher path is unknown.
static func legacy_plugin_dir_for(launcher_path: String) -> String:
	if launcher_path.is_empty():
		return ""
	return launcher_path.get_base_dir().path_join(PLUGIN_SUBDIR)


static func configured_launcher_path() -> String:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	return String(cf.get_value("kyber", "launcher_path", ""))


static func _save_launcher_path(p: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value("kyber", "launcher_path", p)
	cf.save(CONFIG_PATH)


# --- detection --------------------------------------------------------------

## Resolve kyber_launcher.exe from a shortcut, then from the official install locations.
## Checks the per-machine AND per-user Start Menu plus desktop shortcuts: the old build only
## looked at ProgramData, so a per-user install (or one where the shortcut was declined)
## could never be auto-detected and the player had to paste the path by hand.
static func detect_launcher() -> String:
	if OS.get_name() != "Windows":
		return ""
	var lnks: Array[String] = []
	for raw in [OS.get_environment("ProgramData"), OS.get_environment("APPDATA")]:
		var base := String(raw)
		if base.is_empty():
			continue
		lnks.append(base.replace("\\", "/").path_join(
			"Microsoft/Windows/Start Menu/Programs/KYBER Launcher.lnk"))
	for raw in [OS.get_environment("USERPROFILE"), OS.get_environment("PUBLIC")]:
		var base := String(raw)
		if base.is_empty():
			continue
		lnks.append(base.replace("\\", "/").path_join("Desktop/KYBER Launcher.lnk"))
	for lnk in lnks:
		var target := _shortcut_target(lnk)
		if not target.is_empty():
			return target
	# Default installer locations, checked only after the shortcuts so a custom install's
	# shortcut still wins.
	var candidates: Array[String] = []
	for base in [OS.get_environment("ProgramFiles(x86)"), OS.get_environment("ProgramFiles"),
			OS.get_environment("LOCALAPPDATA")]:
		var base_str := String(base)
		if base_str.is_empty():
			continue
		var root: String = base_str.replace("\\", "/")
		candidates.append(root.path_join("KYBER Launcher/kyber_launcher.exe"))
		candidates.append(root.path_join("Programs/KYBER Launcher/kyber_launcher.exe"))
	for p in candidates:
		if FileAccess.file_exists(p):
			return p
	return ""


## The real path a .lnk points at, or "" if it is missing / unreadable / points nowhere.
static func _shortcut_target(lnk: String) -> String:
	if not FileAccess.file_exists(lnk):
		return ""
	var out: Array = []
	var code := OS.execute("powershell", [
		"-NoProfile", "-NonInteractive", "-Command",
		"(New-Object -ComObject WScript.Shell).CreateShortcut('%s').TargetPath" % lnk.replace("/", "\\"),
	], out, false)
	if code != 0 or out.is_empty():
		return ""
	var target := String(out[0]).strip_edges().replace("\\", "/")
	return target if not target.is_empty() and FileAccess.file_exists(target) else ""


static func kyber_running() -> bool:
	if OS.get_name() != "Windows":
		return false
	var out: Array = []
	OS.execute("tasklist", ["/FI", "IMAGENAME eq %s" % LAUNCHER_EXE, "/NH", "/FO", "CSV"], out, false)
	return not out.is_empty() and String(out[0]).to_lower().contains(LAUNCHER_EXE)


## True if the user has a persistent KYBER_DEV_PLUGIN_PATH user env var (my earlier
## advice). GC no longer needs it, and leaving it set makes KYBER load the plugin twice
## — the second copy fails to bind the socket. GC clears it in the child on launch, but
## the Setup modal nudges the user to delete it for good.
static func dev_plugin_path_set() -> bool:
	if OS.get_name() != "Windows":
		return false
	var out: Array = []
	OS.execute("reg", ["query", "HKCU\\Environment", "/v", "KYBER_DEV_PLUGIN_PATH"], out, false)
	return not out.is_empty() and String(out[0]).contains("KYBER_DEV_PLUGIN_PATH")


static func status(launcher_path := "") -> Dictionary:
	if launcher_path.is_empty():
		launcher_path = configured_launcher_path()
	var found := not launcher_path.is_empty() and FileAccess.file_exists(launcher_path)
	return {
		"on_windows": OS.get_name() == "Windows",
		"launcher_path": launcher_path,
		"launcher_found": found,
		"kbplugin_present": FileAccess.file_exists(kbplugin_path()),
		"kyber_running": kyber_running(),
		"dev_plugin_path_set": dev_plugin_path_set(),
	}


# --- packaging --------------------------------------------------------------

## Zip `files` (relative to `src_dir`) into a .kbplugin, plugin.json at the archive root
## (KYBER requires it). Defaults to GC's own gc_result source, so existing callers are
## unaffected; pass PLAYTEST_GUNGAME_SRC / PLAYTEST_GUNGAME_FILES for the playtest package.
static func build_kbplugin(dest_kbplugin_path: String, src_dir: String = PLUGIN_SRC,
		files: Array[String] = PLUGIN_FILES) -> Dictionary:
	var dir := dest_kbplugin_path.get_base_dir()
	var derr := DirAccess.make_dir_recursive_absolute(dir)
	if derr != OK and derr != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "Cannot create %s (%s). Pick a writable folder — a path under Program Files needs admin rights." % [dir, error_string(derr)]}
	if FileAccess.file_exists(dest_kbplugin_path):
		DirAccess.remove_absolute(dest_kbplugin_path)

	var packer := ZIPPacker.new()
	var oerr := packer.open(dest_kbplugin_path, ZIPPacker.APPEND_CREATE)
	if oerr != OK:
		return {"ok": false, "reason": "Cannot write %s (%s). A path under Program Files needs admin rights." % [dest_kbplugin_path, error_string(oerr)]}

	for rel in files:
		var bytes := FileAccess.get_file_as_bytes("%s/%s" % [src_dir, rel])
		if bytes.is_empty():
			packer.close()
			return {"ok": false, "reason": "Missing plugin source file: %s" % rel}
		packer.start_file(rel)
		packer.write_file(bytes)
		packer.close_file()

	packer.close()
	return {"ok": true, "path": dest_kbplugin_path}


# --- launch / uninstall ----------------------------------------------------

static func launch(launcher_path: String) -> Dictionary:
	var built := build_kbplugin(kbplugin_path())
	if not built.get("ok", false):
		return {"ok": false, "reason": built.get("reason", "Could not package the plugin.")}
	var result := _launch_process(launcher_path, plugin_dir())
	if result.get("ok", false):
		GcLog.note("setup", "launched KYBER with the gc_result plugin (%s)" % plugin_dir())
		GcLog.note("setup", "now click Host in KYBER — GC will connect when the match starts")
	return result


## Packages and launches the vendored GunGame playtest plugin (bridge/kyber_plugin/
## playtest_gungame/, README.md there) INSTEAD of gc_result — KYBER_SERVER_PLUGINS_PATH
## only ever points at one directory, so GC's own campaign reporting does nothing while
## this is active. Launch KYBER normally (launch()) again afterward to go back to it.
static func launch_gungame_playtest(launcher_path: String) -> Dictionary:
	var built := build_kbplugin(gungame_kbplugin_path(), PLAYTEST_GUNGAME_SRC, PLAYTEST_GUNGAME_FILES)
	if not built.get("ok", false):
		return {"ok": false, "reason": built.get("reason", "Could not package GunGame.")}
	var result := _launch_process(launcher_path, gungame_plugin_dir())
	if result.get("ok", false):
		GcLog.note("setup", "launched KYBER with the GunGame playtest plugin (%s) — gc_result is NOT active" % gungame_plugin_dir())
		GcLog.note("setup", "click Host in KYBER, then pick any multiplayer map/mode yourself — GunGame doesn't load one for you")
	return result


## Shared by launch() and launch_gungame_playtest() — everything past "which .kbplugin".
static func _launch_process(launcher_path: String, plugins_dir: String) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "reason": "Launching KYBER from GC is Windows only."}
	launcher_path = launcher_path.strip_edges().replace("\\", "/")
	if launcher_path.is_empty() or not FileAccess.file_exists(launcher_path):
		return {"ok": false, "reason": "Set the path to kyber_launcher.exe first."}
	_save_launcher_path(launcher_path)

	if kyber_running():
		return {
			"ok": false,
			"already_running": true,
			# Spelled out deliberately, not just "close it and relaunch" — KYBER_SERVER_PLUGINS_PATH
			# is process-scoped (Module/Source/Script/ScriptManager.cpp reads it once, via a plain
			# getenv(), at that KYBER process's own startup) and nothing GC does afterward can
			# change it for an already-running process — there is no supported way for one Windows
			# process to inject an environment variable into another. So a KYBER opened any other
			# way (double-clicked, a shortcut, already running from earlier) genuinely has NO
			# plugin loaded and CANNOT pick one up without a real relaunch — this isn't caution,
			# it's the literal mechanism.
			"reason": "KYBER is already open WITHOUT the GC plugin loaded (it can only load at "
				+ "KYBER's own startup — nothing can inject it into an already-running KYBER). "
				+ "Without the plugin, GC cannot see match results, apply bot counts or aim, "
				+ "enforce your team, or send the in-match briefing — you'd be limited to the "
				+ "manual winner buttons for every battle. Close KYBER now and launch it from "
				+ "here instead.",
		}

	OS.set_environment(ENV_VAR, plugins_dir)
	OS.set_environment(LOG_LEVEL_VAR, LOG_LEVEL)
	# Harmless best-effort, not load-bearing: KYBER's `ver/beta10` SOURCE reads this to pick
	# its local gRPC interface port (Module/Source/RPC/InterfaceService.cpp), but the actually
	# installed build is v2.0.0-beta8 (confirmed from the KYBER log's own version line,
	# 2026-09-11) and does NOT honor it — nine separate sessions with this env var set to 3005
	# each logged a different real port anyway ("[RPC] Started interface server on port <N>").
	# KyberGrpc.discover_port() reads the real port from that same log line instead of trusting
	# this. Left set in case a future/different KYBER build does respect it.
	OS.set_environment(KyberGrpc.INTERFACE_PORT_VAR, str(KyberGrpc.DEFAULT_PORT))
	if GcPrefs.kyber_message_debug():
		OS.set_environment(MESSAGE_DEBUG_VAR, "1")
		GcLog.note("setup", "KYBER_MESSAGE_DEBUG is ON — the log will be much larger than usual")
	else:
		OS.unset_environment(MESSAGE_DEBUG_VAR)
	# A leftover persistent KYBER_DEV_PLUGIN_PATH would load the plugin a second time
	# (second SocketManager.Create fails). Clear it for the child we're about to start.
	OS.unset_environment("KYBER_DEV_PLUGIN_PATH")
	var pid := OS.create_process(launcher_path, [])
	if pid <= 0:
		GcLog.note("setup", "could not start %s" % launcher_path)
		return {"ok": false, "reason": "Could not start %s." % launcher_path}
	return {"ok": true, "pid": pid, "plugin_dir": plugins_dir}


static func close_kyber() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "reason": "Windows only."}
	var out: Array = []
	var code := OS.execute("taskkill", ["/IM", LAUNCHER_EXE, "/F"], out, true)
	return {"ok": code == 0, "reason": "\n".join(PackedStringArray(out)).strip_edges()}


static func uninstall(launcher_path := "") -> Dictionary:
	if launcher_path.is_empty():
		launcher_path = configured_launcher_path()

	var removed: Array[String] = []
	# The current location, plus any legacy package next to the launcher from an old build.
	var dirs: Array[String] = [plugin_dir()]
	var legacy := legacy_plugin_dir_for(launcher_path)
	if not legacy.is_empty():
		dirs.append(legacy)
	for pdir in dirs:
		var kb := pdir.path_join(KBPLUGIN_NAME)
		if FileAccess.file_exists(kb):
			DirAccess.remove_absolute(kb)
			removed.append(kb)
		var da := DirAccess.open(pdir)
		if da != null:
			da.list_dir_begin()
			var is_empty := da.get_next() == ""
			da.list_dir_end()
			if is_empty:
				DirAccess.remove_absolute(pdir)

	# The GunGame playtest package (its own directory, own filename — see launch_gungame_playtest).
	var gg_kb := gungame_kbplugin_path()
	if FileAccess.file_exists(gg_kb):
		DirAccess.remove_absolute(gg_kb)
		removed.append(gg_kb)
		var gda := DirAccess.open(gungame_plugin_dir())
		if gda != null:
			gda.list_dir_begin()
			var gg_empty := gda.get_next() == ""
			gda.list_dir_end()
			if gg_empty:
				DirAccess.remove_absolute(gungame_plugin_dir())

	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	if cf.has_section("kyber"):
		cf.erase_section("kyber")
		cf.save(CONFIG_PATH)
	GcLog.note("setup", "removed the gc_result plugin")
	if removed.is_empty():
		return {"ok": true, "reason": "Nothing to remove."}
	return {"ok": true, "reason": "Removed %s. Nothing else was changed." % ", ".join(removed)}
