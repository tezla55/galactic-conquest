class_name KyberEaId
extends RefCounted

## Finds the CURRENT player's own EA account id from KYBER's own daily log — the same
## number the log's own
##   [Server] <name> (<id>) successfully authenticated
## line shows. Confirmed against a real capture
## (logs_2026-09-11_10-03-30/kyber_2026-09-11.log:
##   "[2026-09-11 07:36:17.002] [KYBER] [info] [Server] DrTezla (2755533100) successfully
##   authenticated"
## — used verbatim in this file's own test) and against `player.playerId` being that exact
## field: the vendored GunGame plugin's `admins.lua` already checks `player.playerId`
## against a hardcoded EA id list, live, successfully (the user's own id was added there for
## the GunGame playtest) — so this is the right number for GC's own `teamid <playerId>
## <team>` command (bridge/kyber_link.gd) to use.
##
## NOT the "[Client] Joining server authenticated as <id> <name> 0" line's own id — the same
## real capture shows those are two DIFFERENT numbers for the same person at the same
## instant (827489137 vs 2755533100) — that one is some other session/join-token value, not
## `player.playerId`. This class only ever matches the "[Server] ... successfully
## authenticated" wording.

const _MARKER := "] [Server] "
const _SUFFIX := ") successfully authenticated"


## {"ok": bool, "name": String, "player_id": int} for whoever most recently authenticated on
## this machine's KYBER TODAY — not a live tail (KyberLogReader already owns that for other
## purposes), a one-shot scan, since this is only ever needed once, right before sending a
## `teamid` for a battle. {"ok": false} if KYBER hasn't logged an authentication today (never
## started, or started after this log file's last rotation) — the caller falls back to
## leaving that side's team unpinned (the existing `humanteam` / manual behaviour), never a
## hard requirement for hosting or joining to work.
static func find_own_identity(path: String = "") -> Dictionary:
	var log_path := path if path != "" else KyberLogReader.log_path()
	if log_path.is_empty() or not FileAccess.file_exists(log_path):
		return {"ok": false}
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return {"ok": false}
	var best := {"ok": false}
	while not f.eof_reached():
		var line := f.get_line()
		var parsed := _parse_line(line)
		if bool(parsed.get("ok", false)):
			best = parsed   # last occurrence wins — same "most recent" convention discover_port() uses
	f.close()
	return best


## Every DISTINCT player (by id, first occurrence kept) that authenticated at or after byte
## `offset` in today's log — for online multiplayer, where the HOST's own KYBER log is the
## only one either player's connection ever gets recorded in at all (a listen server logs
## every client that authenticates INTO it, host's own local client included — a joining
## remote player's own separate machine never independently produces this line for anyone,
## since they're not the one running the server realm this plugin lives in). Order is
## "first authenticated since `offset`" — since the host has to click Host before a friend
## can join at all, the host's own entry is expected to come first, the friend's second;
## this ordering assumption is REASONED from the architecture, not yet confirmed against an
## actual two-human capture (see this class's own header) — main.gd falls back to the
## existing manual/`humanteam` behaviour whenever this doesn't yield a confident answer.
static func find_identities_since(path: String, offset: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	if offset > 0 and offset <= f.get_length():
		f.seek(offset)
	var seen_ids := {}
	while not f.eof_reached():
		var parsed := _parse_line(f.get_line())
		if bool(parsed.get("ok", false)):
			var pid: int = parsed["player_id"]
			if not seen_ids.has(pid):
				seen_ids[pid] = true
				out.append(parsed)
	f.close()
	return out


## The current length of today's KYBER log, or 0 if it doesn't exist yet — call this the
## moment online hosting begins and pass the result as `find_identities_since`'s `offset`,
## so only identities that authenticated during THIS session are ever considered (a long
## day's log can carry plenty of stale entries from earlier, unrelated matches).
static func current_log_length(path: String = "") -> int:
	var log_path := path if path != "" else KyberLogReader.log_path()
	if log_path.is_empty() or not FileAccess.file_exists(log_path):
		return 0
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return 0
	var length := f.get_length()
	f.close()
	return length


## The test seam: parses one raw log line, or {"ok": false} if it isn't this exact line
## shape. Assumes the display name itself has no literal "(" in it — true of every real
## capture seen so far, and the normal EA/Origin display-name convention.
static func _parse_line(line: String) -> Dictionary:
	if not line.ends_with(_SUFFIX):
		return {"ok": false}
	var marker := line.find(_MARKER)
	if marker == -1:
		return {"ok": false}
	var rest := line.substr(marker + _MARKER.length())
	var paren := rest.find(" (")
	if paren == -1:
		return {"ok": false}
	var name := rest.substr(0, paren)
	var id_start := paren + 2
	var id_len := rest.length() - id_start - _SUFFIX.length()
	if id_len <= 0:
		return {"ok": false}
	var id_str := rest.substr(id_start, id_len)
	if name.is_empty() or not id_str.is_valid_int():
		return {"ok": false}
	return {"ok": true, "name": name, "player_id": int(id_str)}
