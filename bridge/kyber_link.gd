class_name KyberLink
extends RefCounted

## Persistent, bidirectional link to the gc_result plugin's TCP socket.
##
## GC → plugin: newline-delimited text commands ("load <level> <mode>", "ping") — the
## plugin has a JSON writer but no parser, so keep this side plain.
## plugin → GC: newline-delimited JSON ({"type":"gc_result"|"level"|"hello"|"pong",…}).
##
## RefCounted. Poll it every frame. Auto-reconnects while it wants a connection, so it
## links up whenever the plugin starts listening (i.e. once the user hosts a match).

enum Status { OFFLINE, CONNECTING, ONLINE }

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 45702
const RECONNECT_INTERVAL_MS := 3000

## Must match PLUGIN_BUILD in bridge/kyber_plugin/gc_result/server/__init__.lua. If the
## connected plugin reports a different build the user is running a stale copy — KYBER was
## not (re)launched from GC after the plugin changed. Bump both together.
const EXPECTED_PLUGIN_BUILD := "2026-11-03a"

var status: int = Status.OFFLINE
var last_level: Dictionary = {}
var last_result: Dictionary = {}   ## Most recent gc_result seen (diagnostics).
## The build string the connected plugin reported in its `hello`, or "" before one arrives.
## A mismatch means KYBER is still running a plugin packaged by an older GC build.
var plugin_build: String = ""

## Non-result control messages from the plugin (load_ack / load_failed), FIFO. main.gd
## drains this each frame to drive the "did the battle actually load in SWBF2?" flow.
var _events: Array[Dictionary] = []

var _peer := StreamPeerTCP.new()
var _host := DEFAULT_HOST
var _port := DEFAULT_PORT
var _in_buf := ""
var _results: Array[Dictionary] = []
var _last_seq := 0
var _next_retry_ms := 0
var _want := false


func connect_to(host := DEFAULT_HOST, port := DEFAULT_PORT) -> void:
	_host = host
	_port = port
	_want = true
	_open()


func close_link() -> void:
	_want = false
	_peer.disconnect_from_host()
	_set_status(Status.OFFLINE)


func is_online() -> bool:
	return status == Status.ONLINE


## Independent check of whether a gc_result plugin is listening on the default port.
## Unlike is_online(), this does not require THIS GC process's own link to have connected
## yet — the plugin binds its socket at load, while its accept loop may not run until a
## hosted match, so the link can legitimately still be OFFLINE in the wizard.
static func plugin_listening() -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(DEFAULT_HOST, DEFAULT_PORT) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if st == StreamPeerTCP.STATUS_ERROR:
			break
		OS.delay_msec(5)
	peer.disconnect_from_host()
	return false


## Skip the reconnect back-off and try immediately. Used when the UI is about to tell the
## player a running KYBER has no plugin — the first attempt may have happened before KYBER's
## plugin started listening.
func retry_now() -> void:
	if not _want:
		return
	_next_retry_ms = 0
	if status == Status.OFFLINE:
		_open()


func poll() -> void:
	if not _want:
		return
	if status == Status.OFFLINE:
		if Time.get_ticks_msec() >= _next_retry_ms:
			_open()
		return

	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if status == Status.CONNECTING:
				_set_status(Status.ONLINE)
			var available := _peer.get_available_bytes()
			if available > 0:
				var chunk := _peer.get_data(available)
				if chunk[0] == OK:
					_ingest((chunk[1] as PackedByteArray).get_string_from_utf8())
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			_set_status(Status.OFFLINE)
			_next_retry_ms = Time.get_ticks_msec() + RECONNECT_INTERVAL_MS


## "load <level> <mode> [botsT1 botsT2 [aimT1 aimT2 [bpT1 bpT2 [maxSec margin]]]]"
static func compose_load(level_path: String, frostbite_mode: String,
		bots_t1 := 0, bots_t2 := 0, aim_t1 := -1.0, aim_t2 := -1.0, bp_t1 := 0, bp_t2 := 0,
		max_s := 0, margin := 0) -> String:
	var line := "load %s %s" % [level_path, frostbite_mode]
	if bots_t1 > 0 and bots_t2 > 0:
		line += " %d %d" % [bots_t1, bots_t2]
		if aim_t1 >= 0.0 and aim_t2 >= 0.0:
			line += " %s %s" % [aim_t1, aim_t2]
			if bp_t1 > 0 and bp_t2 > 0:
				line += " %d %d" % [bp_t1, bp_t2]
				line += " %d %d" % [maxi(0, max_s), maxi(0, margin)]
	return line


func load_level(level_path: String, frostbite_mode: String,
		bots_t1 := 0, bots_t2 := 0, aim_t1 := -1.0, aim_t2 := -1.0, bp_t1 := 0, bp_t2 := 0,
		max_s := 0, margin := 0) -> bool:
	return send_line(compose_load(level_path, frostbite_mode, bots_t1, bots_t2, aim_t1, aim_t2, bp_t1, bp_t2, max_s, margin))


func start_match() -> bool:
	return send_line("start")


static func compose_end(winner := 0) -> String:
	return "end" if winner == 0 else "end %d" % winner


## End the running match now. winner 0 = let the kill tally decide; 1 / 2 = force a
## team (for testing the win/loss round-trip without playing 20 minutes).
func end_match(winner := 0) -> bool:
	return send_line(compose_end(winner))


## Match over and GC has the result: tell the plugin to skip KYBER's own (crash-prone) end-of-round
## sequence with a single Restart. See the plugin's `restart` verb.
func restart_match() -> bool:
	return send_line("restart")


## Tell the plugin whether to suppress the natural end-of-round. Only the Clone Wars /
## Sequel Era capital-ship Supremacy does; send it before `load` so the plugin applies it
## with the rest of the start commands. `auto` hands the decision back to the plugin's mode.
static func compose_stop_eor(on: bool) -> String:
	return "stopeor %d" % (1 if on else 0)


func set_stop_eor(on: bool) -> bool:
	return send_line(compose_stop_eor(on))


static func compose_teamid(player_id: int, team: int) -> String:
	return "teamid %d %d" % [player_id, team]


## Pin one specific human (by EA player id, from the "<name> (<id>) successfully
## authenticated" line in KYBER's own log — see bridge/kyber_ea_id.gd) to a team. Used for
## online two-player, where two real humans need two different teams and the plain
## `humanteam` (a single shared value) can't express that; `team` 0 un-pins that one id.
func send_teamid(player_id: int, team: int) -> bool:
	return send_line(compose_teamid(player_id, team))


func ping() -> bool:
	return send_line("ping")


func send_line(text: String) -> bool:
	if status != Status.ONLINE:
		GcLog.note("kyber", "not connected — dropped command: %s" % text)
		return false
	var err := _peer.put_data((text + "\n").to_utf8_buffer())
	if err != OK:
		GcLog.note("kyber", "send failed: %s" % error_string(err))
		return false
	GcLog.note("kyber", "→ %s" % text)
	return true


func take_result() -> Dictionary:
	return _results.pop_front() if not _results.is_empty() else {}


## A load_ack / load_failed message from the plugin, or {} if none pending.
func take_event() -> Dictionary:
	return _events.pop_front() if not _events.is_empty() else {}


## Forget the last "level" message. Call before a fresh `load` so a stale last_level from
## the previous battle isn't mistaken for the new one having loaded (two battles can pick
## the same level_path).
func clear_level() -> void:
	last_level = {}


# --- internals (also the test seam: _ingest takes raw text) ------------------

func _open() -> void:
	_peer = StreamPeerTCP.new()
	_in_buf = ""
	var err := _peer.connect_to_host(_host, _port)
	if err == OK:
		_set_status(Status.CONNECTING)
	else:
		_set_status(Status.OFFLINE)
		_next_retry_ms = Time.get_ticks_msec() + RECONNECT_INTERVAL_MS


func _ingest(text: String) -> void:
	_in_buf += text
	while true:
		var nl := _in_buf.find("\n")
		if nl == -1:
			break
		var line := _in_buf.substr(0, nl).strip_edges()
		_in_buf = _in_buf.substr(nl + 1)
		if not line.is_empty():
			_handle_line(line)


func _handle_line(line: String) -> void:
	var parser := JSON.new()
	if parser.parse(line) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		GcLog.note("kyber", "unparsable line: %s" % line.left(120))
		return
	var msg: Dictionary = parser.data
	match String(msg.get("type", "")):
		"gc_result":
			var seq := int(msg.get("seq", 0))
			if seq > 0 and seq <= _last_seq:
				GcLog.note("kyber", "duplicate result (seq %d) ignored" % seq)
				return
			_last_seq = seq
			_results.append(msg)
			last_result = msg
			GcLog.note("kyber", "result received (seq %d)" % seq)
		"level":
			last_level = msg
			GcLog.note("kyber", "match running: %s / %s" % [msg.get("mode", "?"), msg.get("map", "?")])
		"load_ack":
			_events.append(msg)
			if bool(msg.get("running", true)):
				GcLog.note("kyber", "plugin got the load — waiting for SWBF2 to switch maps")
			else:
				GcLog.note("kyber", "plugin got the load but NO match is running — start one in SWBF2 first")
		"load_failed":
			_events.append(msg)
			GcLog.note("kyber", "load failed: %s" % msg.get("reason", "SWBF2 did not switch maps"))
		"hello":
			# A fresh plugin session restarts its seq at 1, so a stale _last_seq from a
			# previous KYBER run would drop the new session's first result as a duplicate.
			_last_seq = 0
			var build := String(msg.get("build", "unknown"))
			plugin_build = build
			if build == EXPECTED_PLUGIN_BUILD:
				GcLog.note("kyber", "plugin connected (build %s)" % build)
			else:
				GcLog.note("kyber", "STALE PLUGIN: build %s, GC expects %s — close KYBER and relaunch from KYBER Setup" % [build, EXPECTED_PLUGIN_BUILD])
		"pong":
			GcLog.note("kyber", "pong")
		_:
			GcLog.note("kyber", "message: %s" % line.left(120))


func _set_status(s: int) -> void:
	if s == status:
		return
	var was := status
	status = s
	# Only the meaningful transitions — the connect/offline retry churn would flood the log.
	if s == Status.ONLINE:
		GcLog.note("kyber", "plugin link established")
	elif s == Status.OFFLINE and was == Status.ONLINE:
		GcLog.note("kyber", "plugin link lost — retrying")
