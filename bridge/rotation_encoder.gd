class_name RotationEncoder
extends RefCounted

## Encodes a KYBER map rotation for the KYBER_MAP_ROTATION environment variable.
##
## The format is NOT a JSON array. KYBER's CLI decodes it like this
## (CLI/lib/commands/start_server_command.dart):
##
##   data  = utf8.decode(base64.decode(env['KYBER_MAP_ROTATION'])).split('\n');
##   // '#' and blank lines skipped
##   split = line.split(';');
##   rotation.add(LevelSetup(map: split[1], mode: split[0]));
##
## So each line is "<frostbite_mode>;<level_path>" and the whole thing is base64. There
## is no bot count anywhere in a rotation entry — bots are a separate console command.
##
## `decode` mirrors the Dart parser exactly so a round-trip test is meaningful.


## entries: Array of { "mode": String, "map": String }. Returns the base64 string that
## goes straight into KYBER_MAP_ROTATION.
static func encode(entries: Array) -> String:
	var lines := PackedStringArray()
	for entry in entries:
		var mode := String(entry.get("mode", ""))
		var map := String(entry.get("map", ""))
		lines.append("%s;%s" % [mode, map])
	return Marshalls.utf8_to_base64("\n".join(lines))


## Reverse of `encode`, following KYBER's own parsing rules: split on newlines, drop
## blank lines and comment lines (leading '#'), split each on the first ';'.
## Returns Array of { "mode": String, "map": String }.
static func decode(b64: String) -> Array:
	var text := Marshalls.base64_to_utf8(b64)
	var out: Array = []
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var sep := line.find(";")
		if sep == -1:
			continue
		out.append({
			"mode": line.substr(0, sep),
			"map": line.substr(sep + 1),
		})
	return out


## Build the rotation string from map-catalog keys. Each key is resolved through
## ContentLoader.find_map and its `frostbite_mode` / `level_path` fields are used.
## Keys that are missing, or whose entry has no real strings, are skipped.
static func from_catalog(catalog: Dictionary, map_keys: Array) -> String:
	var entries: Array = []
	for key in map_keys:
		var entry := ContentLoader.find_map(catalog, String(key))
		if entry.is_empty():
			continue
		var mode := String(entry.get("frostbite_mode", ""))
		var path := String(entry.get("level_path", ""))
		if mode.is_empty() or path.is_empty():
			continue
		entries.append({"mode": mode, "map": path})
	return encode(entries)
