class_name KyberModCheck
extends RefCounted

## Read-only checks for the Instant Online Improvements (IOI) Nexus mod, which is what
## makes the Supremacy / Galactic Assault server AI actually field special units and
## heroes — stock KYBER has no cvar or plugin hook for that (verified against the module
## source). GC cannot install it: the listen-server module receives mods only over gRPC
## from the Launcher's *hosting collection*, and the collection store is a Flutter Hive
## binary DB we will not risk writing. So GC detects and guides instead.
##
## Everything here is best-effort and never throws — a missing folder or an unreadable
## Hive blob degrades to "unknown", it never blocks a match.

const IOI_NEXUS_URL := "https://www.nexusmods.com/starwarsbattlefront22017/mods/3658?tab=files"
const KYBER_APPDATA_SUBDIR := "ArmchairDevelopers/Kyber"
const MODS_SUBDIR := "ArmchairDevelopers/Kyber/Mods"
const LAUNCHER_SUBDIR := "ArmchairDevelopers/Kyber/Launcher"
const HOSTING_KEY := "hostingCollection"
const NO_MODS_SENTINEL := "no-mods"

## Filename fragments (lower-case) that identify the IOI .fbmod.
const IOI_NEEDLES: Array[String] = ["ioi", "instant online"]


static func _appdata() -> String:
	return OS.get_environment("APPDATA").replace("\\", "/")


static func mods_dir() -> String:
	var base := _appdata()
	if base.is_empty():
		return ""
	return base.path_join(MODS_SUBDIR)


## Names of .fbmod files in the KYBER Mods folder that look like IOI. Empty when none /
## the folder is absent.
static func fbmod_matches() -> Array[String]:
	var hits: Array[String] = []
	var dir := mods_dir()
	if dir.is_empty():
		return hits
	var da := DirAccess.open(dir)
	if da == null:
		return hits
	da.list_dir_begin()
	while true:
		var name := da.get_next()
		if name == "":
			break
		if da.current_is_dir():
			continue
		if not name.to_lower().ends_with(".fbmod"):
			continue
		if _name_is_ioi(name):
			hits.append(name)
	da.list_dir_end()
	return hits


static func _name_is_ioi(name: String) -> bool:
	var low := name.to_lower()
	for needle in IOI_NEEDLES:
		if low.contains(needle):
			return true
	return false


static func _launcher_bytes(filename: String) -> PackedByteArray:
	var base := _appdata()
	if base.is_empty():
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(base.path_join(LAUNCHER_SUBDIR).path_join(filename))


static var _uuid_re: RegEx = null

static func _looks_like_uuid(s: String) -> bool:
	if _uuid_re == null:
		_uuid_re = RegEx.create_from_string("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
	return _uuid_re.search(s) != null


## Every run of printable ASCII (len >= min_len) in `bytes`, in order.
static func _printable_runs(bytes: PackedByteArray, min_len := 2) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for b in bytes:
		if _is_printable(b):
			cur += char(b)
		else:
			if cur.length() >= min_len:
				out.append(cur)
			cur = ""
	if cur.length() >= min_len:
		out.append(cur)
	return out


## Best-effort: which collection the Launcher hosts with, and whether IOI is in it.
## `hostingCollection` in data.hive is a UUID; the title + mod list live in collections.hive
## keyed by it. Returns {readable, name, has_ioi}. readable = false when a file couldn't be
## read (KYBER mid-write / missing); name = "" when hosting with no mods.
static func hosting_collection() -> Dictionary:
	var miss := {"readable": false, "name": "", "has_ioi": false}
	var data := _launcher_bytes("data.hive")
	if data.is_empty():
		return miss

	var text := data.get_string_from_ascii()
	var at := text.rfind(HOSTING_KEY)
	if at == -1:
		return {"readable": true, "name": "", "has_ioi": false}   # never set -> no mods
	var host_id := _printable_run(data, at + HOSTING_KEY.length())
	if host_id.is_empty() or host_id == NO_MODS_SENTINEL or host_id == HOSTING_KEY:
		return {"readable": true, "name": "", "has_ioi": false}

	var col := _launcher_bytes("collections.hive")
	if col.is_empty():
		# A collection is set but we can't inspect it.
		return {"readable": false, "name": host_id, "has_ioi": false}

	var runs := _printable_runs(col)
	# Slice the region belonging to host_id: from its first mention to the next UUID that
	# isn't host_id (or the end).
	var start := -1
	for i in runs.size():
		if runs[i].contains(host_id):
			start = i
			break
	var region: Array[String] = []
	if start != -1:
		for i in range(start + 1, runs.size()):
			var r := runs[i]
			if _looks_like_uuid(r) and not r.contains(host_id):
				break
			region.append(r)
	else:
		region = runs   # host_id not found as a run — scan the whole blob

	var title := ""
	for r in region:
		if not _looks_like_uuid(r) and not r.contains(host_id) and r != NO_MODS_SENTINEL:
			title = r
			break
	var has_ioi := false
	for r in region:
		if _name_is_ioi(r):
			has_ioi = true
			break

	return {"readable": true, "name": title, "has_ioi": has_ioi}


## The first run of printable ASCII (len 1..64) at or after `from` in `bytes`.
static func _printable_run(bytes: PackedByteArray, from: int) -> String:
	var i := from
	while i < bytes.size() and not _is_printable(bytes[i]):
		i += 1
	var out := ""
	while i < bytes.size() and _is_printable(bytes[i]) and out.length() < 64:
		out += char(bytes[i])
		i += 1
	return out.strip_edges()


static func _is_printable(b: int) -> bool:
	return b >= 0x20 and b <= 0x7E


static func status() -> Dictionary:
	var matches := fbmod_matches()
	var hosting := hosting_collection()
	var readable := bool(hosting["readable"])
	var name := String(hosting["name"])
	return {
		"on_windows": OS.get_name() == "Windows",
		"mods_dir": mods_dir(),
		"ioi_fbmod": matches,
		"ioi_present": not matches.is_empty(),
		"hosting_readable": readable,
		"hosting_collection": name,
		"hosting_has_mods": readable and not name.is_empty(),
		"hosting_has_ioi": bool(hosting["has_ioi"]),
		"nexus_url": IOI_NEXUS_URL,
	}


static func open_nexus() -> void:
	OS.shell_open(IOI_NEXUS_URL)
