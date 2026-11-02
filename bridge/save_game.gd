class_name SaveGame
extends RefCounted

## Saved campaigns: `GalaxyState.to_dict()` (already the full serialisation the online host
## sends its client) wrapped in a small header, written as JSON under user://saves/.
## Not a game rule — core/ owns what a state IS; this only moves it to and from disk.
##
## Slots: "auto" (written by main.gd at the start of each of the player's turns — never by
## the player) plus three manual ones. `load_state` returns null for a missing, unreadable, or
## NEWER-than-this-build save rather than guessing at a format it doesn't know.

const DIR := "user://saves"
const SLOTS: Array[String] = ["auto", "1", "2", "3"]
const FORMAT := 1


static func path_for(slot: String) -> String:
	return "%s/slot_%s.json" % [DIR, slot]


static func save(slot: String, state: GalaxyState, dir := DIR) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var payload := {
		"gc_save": FORMAT,
		"saved_at": int(Time.get_unix_time_from_system()),
		"campaign_id": String(state.campaign_id),
		"player_faction": String(state.player_faction),
		"turn": state.turn,
		"two_player": state.two_player,
		"state": state.to_dict(),
	}
	var f := FileAccess.open("%s/slot_%s.json" % [dir, slot], FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload))
	return true


static func _read(slot: String, dir: String) -> Dictionary:
	var p := "%s/slot_%s.json" % [dir, slot]
	if not FileAccess.file_exists(p):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(p)) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parser.data
	if int(d.get("gc_save", 0)) != FORMAT or typeof(d.get("state")) != TYPE_DICTIONARY:
		return {}
	return d


static func exists(slot: String, dir := DIR) -> bool:
	return not _read(slot, dir).is_empty()


## The state in `slot`, or null (missing / corrupt / written by a newer build).
static func load_state(slot: String, dir := DIR) -> GalaxyState:
	var d := _read(slot, dir)
	if d.is_empty():
		return null
	var sd: Dictionary = d["state"]
	if int(sd.get("version", GalaxyState.SAVE_VERSION)) > GalaxyState.SAVE_VERSION:
		return null
	var s := GalaxyState.from_dict(sd)
	if s.planets.is_empty():
		return null
	return s


## One line for the slot list: "Clone Wars · Republic · Turn 5 · 2026-09-20 14:30", or "".
static func describe(slot: String, dir := DIR) -> String:
	var d := _read(slot, dir)
	if d.is_empty():
		return ""
	var cid := StringName(d.get("campaign_id", ""))
	var cname := String(cid)
	for c in ContentLoader.load_campaigns():
		if c.id == cid:
			cname = c.display_name
	var who := "2 Players" if bool(d.get("two_player", false)) \
		else Faction.display_name(StringName(d.get("player_faction", "")))
	var when := Time.get_datetime_string_from_unix_time(int(d.get("saved_at", 0)), true)
	return "%s · %s · Turn %d · %s" % [cname, who, int(d.get("turn", 1)), when.left(16)]


static func delete(slot: String, dir := DIR) -> void:
	var p := "%s/slot_%s.json" % [dir, slot]
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
