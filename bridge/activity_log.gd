class_name GcLog
extends RefCounted

## A process-wide activity log the UI can show: KYBER launch, plugin link state, the
## match GC asked for, the result that came back. Plain static buffer (no Node, no autoload).
## bridge/ and ui/ both write to it; nothing reads it as game state.
##
## When main.gd calls `enable_file_logging()`, every note is ALSO appended to
## `user://logs/gc.log`. That file is the one thing a player can send after something goes
## wrong on their machine — the in-memory buffer dies with the process, and the release exe
## has no console. Off by default so the unit suite never touches the user's disk.

const MAX_ENTRIES := 500
const LOG_DIR := "user://logs"
const LOG_PATH := LOG_DIR + "/gc.log"
## Keep the support log from growing without bound across a long campaign. Only checked at
## session start; a single session stays far below this.
const MAX_FILE_BYTES := 2 * 1024 * 1024

static var _entries: Array[Dictionary] = []
static var _file_logging := false


## Start appending to user://logs/gc.log. Idempotent.
static func enable_file_logging() -> void:
	if _file_logging:
		return
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var existing := FileAccess.open(LOG_PATH, FileAccess.READ)
	if existing != null:
		var size := existing.get_length()
		existing.close()
		if size > MAX_FILE_BYTES:
			DirAccess.remove_absolute(LOG_PATH)
	_file_logging = true
	note("gc", "session started")


static func log_path() -> String:
	return LOG_PATH


## tag is a short source label ("kyber", "setup", "battle", "gc").
static func note(tag: String, text: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_entries.append({
		"time": stamp,
		"tag": tag,
		"text": text,
	})
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	if _file_logging:
		_append_to_file("%s  [%s]  %s" % [Time.get_datetime_string_from_system(), tag, text])


static func _append_to_file(line: String) -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return   # unwritable user dir: keep the in-memory log and carry on
	f.seek_end()
	f.store_line(line)
	f.close()


static func entries() -> Array:
	return _entries


static func as_text() -> String:
	var lines := PackedStringArray()
	for e in _entries:
		lines.append("%s  [%s]  %s" % [e["time"], e["tag"], e["text"]])
	return "\n".join(lines)


static func clear() -> void:
	_entries.clear()
