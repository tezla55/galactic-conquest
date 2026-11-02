class_name KyberLogReader
extends RefCounted

## Tails KYBER's daily module log so GC can surface "plugin listening", "loading level",
## "game ended" without the user opening a file. Windows only; silent elsewhere.
##
## Path from Module source (Program.cpp): <ProgramData>/Logs/kyber_<yyyy-mm-dd>.log,
## where ProgramData for the Launcher is %APPDATA%/ArmchairDevelopers/Kyber.

const KEEP: Array[String] = [
	"[gc_result]",
	"[Server] Loading level",
	"[Server] Server level loaded",
	"[Server] Game ended",
	"[Server] Level loaded",
	"[Plugin]",
	"[RPC]",
	# A gRPC RunCommand's result is NOT returned in the gRPC response at all (kyber_common.Empty
	# — checked directly, Module/Source/RPC/Interface/Common.cpp) — it only ever reaches
	# "[Console] Result: <text>" in this log. Same "[Console] " prefix a Lua Console.Execute()
	# result uses (Core/Console.cpp's EnqueueCommand). Needed for real research use of
	# KyberGrpc.run_command() (e.g. trying "help"-style list commands to hunt for co-op winner
	# leads, 2026-09-11) — without this, any output a fired command produces is invisible to GC.
	"[Console]",
	# Round-winner markers — KyberMatchWatch reads the team number out of these. The Outro
	# bundle load is logged at KYBER's default level; the PrintDebugText line (BF+ / BXL)
	# only with debug logging on.
	"Outro_Team",
	"VictoryDeclarationTeam",
	# Capital-ship sub-level streaming in = a team won the ground phase. KyberMatchWatch
	# keys "the ship phase is starting" off these ([info] level). Clone Wars ships first;
	# `/MC85` is the Sequel era's Resistance cruiser (`2026-10-08`, playtest 104 item 15 —
	# a live Jakku Supremacy match streamed it in but nothing recognized the line, so the
	# ground-phase win was never caught and the match ran on into the full ship phase).
	# First Order's own ship bundle name is still unseen in a real log — Resistance has
	# never yet lost a ground phase with a capture running.
	"/Venator",
	"/Dreadnought",
	"/Providence",
	"/MC85",
]

var _offset: int = 0
var _path: String = ""


static func log_path() -> String:
	if OS.get_name() != "Windows":
		return ""
	var appdata := OS.get_environment("APPDATA")
	if appdata.is_empty():
		return ""
	var day := Time.get_date_string_from_system()  # yyyy-mm-dd
	return appdata.replace("\\", "/").path_join(
		"ArmchairDevelopers/Kyber/Logs/kyber_%s.log" % day
	)


## New interesting lines since the last poll. Resets its cursor if the file rotated.
func poll() -> Array[String]:
	var path := log_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	if path != _path:
		_path = path
		_offset = 0

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var length := f.get_length()
	if length < _offset:
		_offset = 0   # rotated / truncated
	f.seek(_offset)

	var out: Array[String] = []
	while f.get_position() < length:
		var line := f.get_line()
		for needle in KEEP:
			if line.contains(needle):
				out.append(line.strip_edges())
				break
	_offset = f.get_position()
	f.close()
	return out
