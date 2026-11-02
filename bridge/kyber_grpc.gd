class_name KyberGrpc
extends RefCounted

## EXPERIMENTAL. Talks to KYBER's own LOCAL gRPC interface — the one the injected Kyber.dll
## module hosts inside the running game (Module/Source/RPC/InterfaceService.cpp) — directly,
## bypassing bridge/kyber_plugin/gc_result/'s Lua plugin entirely for the handful of things
## it exposes. See bridge/kyber_grpc/README.md for the full writeup, including a real
## limitation found from KYBER's own .proto files before writing a line of this: there is no
## event-subscription RPC on this interface anywhere, so it can issue commands and poll state
## but cannot replace EventManager.Listen(...) for anything event-driven (kills, spawns,
## round-end) — the Lua plugin stays necessary for that regardless of what this proves out.
##
## Plaintext (grpc::InsecureServerCredentials — no TLS). No server reflection is registered,
## so a caller must supply the .proto schema itself — bridge/kyber_grpc/Proto/, vendored
## verbatim from KYBER's own repo.
##
## Port 3005 is KYBER's OWN documented default (`ver/beta10` source,
## `Module/Source/RPC/InterfaceService.cpp`), overridable via KYBER_INTERFACE_PORT —
## `KyberPluginInstaller` sets that env var on every launch. **But the installed build is
## v2.0.0-beta8** (confirmed from the KYBER log's own `[Engine] Initializing KYBER
## v2.0.0-beta8` line, 2026-09-11), an older/different build than that source, and it does
## NOT honor either the fixed default or the env var: every real session's own
## `"[RPC] Started interface server on port <N>"` log line names a different, ephemeral-range
## port (55680, 65474, 63581, 58147, 51797, 59134, 58281, 52048, 61967 — nine different
## sessions, one 2026-09-11 log, KYBER_INTERFACE_PORT=3005 set every single time) — dialing
## 3005 there was never going to hit anything real. So `discover_port()` reads the actual
## port straight out of KYBER's own log instead of trusting any fixed number, the same log
## `KyberLogReader` already tails (its `KEEP` list already includes `"[RPC]"`, so these lines
## were visible in GC's own Log panel the whole time). `DEFAULT_PORT` (3005) is now only a
## last-resort fallback if the log can't be read at all.
##
## No native gRPC client in Godot, so every call here shells out to `grpcurl`
## (https://github.com/fullstorydev/grpcurl, MIT) — the user must download it once and place
## it at tools/grpcurl.exe. Same OS.execute-a-small-external-tool pattern already used by
## KyberPluginInstaller for powershell/tasklist; nothing persistent, one process per call.

const GRPCURL_REL_PATH := "res://tools/grpcurl.exe"
## The parent of Proto/, NOT Proto/ itself — the vendored files' own `import
## "Proto/kyber_common.proto"` statements (copied verbatim from KYBER's Module/Proto/ layout)
## are resolved AS "<import-path>/Proto/...", so import-path has to be one level up or grpcurl
## looks for Proto/Proto/kyber_common.proto and fails (confirmed live: exactly that error).
const PROTO_DIR_REL := "res://bridge/kyber_grpc"
const PROTO_FILE := "Proto/kyber_interface.proto"
const DEFAULT_PORT := 3005
const INTERFACE_PORT_VAR := "KYBER_INTERFACE_PORT"
## Bounds on the grpcurl child process itself, NOT just a nicety — a dead/unreachable
## server produced a live "context deadline exceeded" after 13s with neither flag set
## (2026-09-11), and since call_rpc() runs synchronously (see call_rpc_async() below for
## why that alone isn't enough), an unbounded dial is an unbounded UI freeze. -connect-timeout
## bounds the TCP dial; -max-time bounds the whole call in case a server accepts the
## connection but never answers the RPC.
const CONNECT_TIMEOUT_S := 3
const MAX_TIME_S := 6

## call_rpc_async() keeps every in-flight Thread referenced here until it's joined —
## Godot requires wait_to_finish() before a Thread object can be freed, and a local var
## going out of scope the moment start() returns would leak/error on exactly that.
static var _threads: Array[Thread] = []


static func grpcurl_path() -> String:
	return ProjectSettings.globalize_path(GRPCURL_REL_PATH)


static func proto_dir() -> String:
	return ProjectSettings.globalize_path(PROTO_DIR_REL)


static func grpcurl_present() -> bool:
	return FileAccess.file_exists(grpcurl_path())


## Two earlier "fixes" for the same underlying bug both turned out wrong before this one —
## see the class doc's history. The actual root cause, found by testing directly against
## grpcurl.exe rather than guessing further: `OS.execute()` on Windows does NOT escape
## embedded `"` characters when it wraps a spaced argument in quotes for the child process's
## command line — confirmed live (2026-09-11) that a value with a space but NO quote
## characters passes through fine (a real dial attempt happens), while the identical value
## WITH JSON's own quote characters reliably produces grpcurl's "Too many arguments" (the
## embedded quotes toggle Windows' own "am I inside a quoted region" parsing, so the space
## ends up unprotected and splits the argument). Backslash-escaping each embedded `"` as `\"`
## before handing the string to OS.execute — the standard Windows/CRT argv convention — fixed
## it (confirmed live: the same "Too many arguments" case became a real dial attempt).
## **Known limitation, not exercised by anything GC actually sends today**: this does not
## also double a literal backslash that precedes a quote, which the full MS quoting algorithm
## requires for round-trip correctness — fine for plain console-command strings like
## "AutoPlayers.ForceFillGameplayBotsTeam1 20", but a command value containing a literal
## backslash right before a quote (e.g. a Windows path) is not guaranteed correct.
static func _win_arg_escape(s: String) -> String:
	return s.replace("\"", "\\\"")


## Reads the real port out of KYBER's own daily log — the LAST "[RPC] Started interface
## server on port <N>" line wins, since a session that's been restarted logs one such line
## per launch and only the most recent one describes the currently-running process. `path`
## defaults to KyberLogReader.log_path() (today's real log); overridable for tests.
##
## The log can be very large with KYBER_LOG_LEVEL=debug on (189 MB observed) and this is
## called on every gRPC call, so this does NOT read the whole file: it reads a tail window,
## doubling it until the marker turns up or the window covers the whole file. In the common
## case (the marker is from the session currently running, so recent) this reads one small
## chunk; correctness for an old/buried marker doesn't depend on the window logic at all —
## it just costs more.
static func discover_port(path: String = "") -> int:
	if path.is_empty():
		path = KyberLogReader.log_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return DEFAULT_PORT
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return DEFAULT_PORT
	const NEEDLE := "[RPC] Started interface server on port "
	var length := f.get_length()
	var window: int = 1 << 19   # 512 KiB
	var found := -1
	while true:
		var start: int = maxi(0, length - window)
		f.seek(start)
		var chunk := f.get_buffer(length - start).get_string_from_utf8()
		var idx := chunk.rfind(NEEDLE)
		if idx >= 0:
			var tail := chunk.substr(idx + NEEDLE.length())
			var end := 0
			while end < tail.length() and tail[end] >= "0" and tail[end] <= "9":
				end += 1
			var num := tail.substr(0, end)
			if not num.is_empty():
				found = num.to_int()
			break
		if start == 0:
			break
		window *= 2
	f.close()
	return found if found > 0 else DEFAULT_PORT


## <service>/<method> against 127.0.0.1:<port>, `body` as the JSON request — e.g.
## call_rpc("Common/RunCommand", {"command": "Kyber.startgame"}). `port` <= 0 (the default)
## means "look it up via discover_port()" — see the class doc for why that's necessary now.
## Returns {"ok": true, "data": Dictionary} or {"ok": false, "reason": String}.
static func call_rpc(service_method: String, body: Dictionary, port: int = -1) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "reason": "grpcurl calls are Windows-only here (untested elsewhere)."}
	if not grpcurl_present():
		return {"ok": false, "reason": "grpcurl.exe not found at %s — download it from https://github.com/fullstorydev/grpcurl/releases and place it there." % grpcurl_path()}
	if port <= 0:
		port = discover_port()

	var args := PackedStringArray([
		"-plaintext",
		"-connect-timeout", str(CONNECT_TIMEOUT_S),
		"-max-time", str(MAX_TIME_S),
		"-import-path", proto_dir(),
		"-proto", PROTO_FILE,
		"-d", _win_arg_escape(JSON.stringify(body)),
		"127.0.0.1:%d" % port,
		"kyber_interface.%s" % service_method,
	])

	var out: Array = []
	var code := OS.execute(grpcurl_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out)).strip_edges()
	if code != 0:
		return {"ok": false, "reason": text if not text.is_empty() else "grpcurl exited %d" % code}
	if text.is_empty():
		return {"ok": true, "data": {}}

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "grpcurl output wasn't JSON: %s" % text.left(200)}
	return {"ok": true, "data": parsed}


## Common.RunCommand — the same power as Console.Execute() in the Lua plugin (e.g.
## "Kyber.SetTeamById <id> <team>", "AutoPlayers.ForceFillGameplayBotsTeam1 20",
## "Kyber.startgame"), issued from entirely outside the game. No response body beyond an ack.
static func run_command(command: String, port: int = -1) -> Dictionary:
	return call_rpc("Common/RunCommand", {"command": command}, port)


## Common.GetInfo — current server/client state: id, current level/mode, and a player list.
## kyber_common.ServerPlayer only carries id/name/teamId — no kills/deaths/score field exists
## on it at all (confirmed in the .proto, not an oversight on our end).
static func get_info(port: int = -1) -> Dictionary:
	return call_rpc("Common/GetInfo", {}, port)


## Same as call_rpc(), but off the main thread — `on_done` (Dictionary -> void) runs on
## the MAIN thread (via Callable.call_deferred(), so it's safe to touch nodes/UI from it)
## once grpcurl exits. Use this from any UI button: call_rpc() blocking the caller for the
## whole -connect-timeout/-max-time window (a real dead server hit the full 13s+ before
## those flags existed, 2026-09-11) freezes the entire game window for that long — CLAUDE.md's
## "never call a blocking OS.execute from _refresh()" rule for the same reason applies here
## even harder, since this can be a genuine multi-second wait, not a sub-frame tasklist call.
static func call_rpc_async(service_method: String, body: Dictionary, on_done: Callable, port: int = -1) -> void:
	var thread := Thread.new()
	_threads.append(thread)
	thread.start(func() -> void:
		var result := call_rpc(service_method, body, port)
		on_done.call_deferred(result)
		_join_thread.call_deferred(thread)
	)


static func _join_thread(thread: Thread) -> void:
	thread.wait_to_finish()
	_threads.erase(thread)


static func run_command_async(command: String, on_done: Callable, port: int = -1) -> void:
	call_rpc_async("Common/RunCommand", {"command": command}, on_done, port)


static func get_info_async(on_done: Callable, port: int = -1) -> void:
	call_rpc_async("Common/GetInfo", {}, on_done, port)
