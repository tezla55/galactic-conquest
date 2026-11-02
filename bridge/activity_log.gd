class_name GcLog
extends RefCounted

## A process-wide activity log the UI can show: KYBER launch, plugin link state, the
## match GC asked for, the result that came back. Plain static buffer — no Node, no
## autoload. bridge/ and ui/ both write to it; nothing reads it as game state.

const MAX_ENTRIES := 500

static var _entries: Array[Dictionary] = []


## tag is a short source label ("kyber", "setup", "battle", "gc").
static func note(tag: String, text: String) -> void:
	_entries.append({
		"time": Time.get_time_string_from_system(),
		"tag": tag,
		"text": text,
	})
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)


static func entries() -> Array:
	return _entries


static func as_text() -> String:
	var lines := PackedStringArray()
	for e in _entries:
		lines.append("%s  [%s]  %s" % [e["time"], e["tag"], e["text"]])
	return "\n".join(lines)


static func clear() -> void:
	_entries.clear()
