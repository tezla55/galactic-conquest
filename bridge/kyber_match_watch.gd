class_name KyberMatchWatch
extends RefCounted

## Follows KYBER's daily module log across ONE battle and reports:
##   1. the round winner (Supremacy / GA give the gc_result plugin nothing to read), and
##   2. the Clone Wars capital-ship ("Titan") phase starting, so GC can end the match on
##      the ground result and skip the bot-broken ship phase.
##
## Why (1) exists: the Lua end-of-round `score` is 0 for both teams, `_G` has no ticket
## global, `Level:Complete` never fires, no Lua event carries the victor. But KYBER's log
## does, in lines GC already tails via KyberLogReader:
##
##   [info]  [Server] Loading level '<level>' with mode '<mode>'      -- our match loaded
##   [info]  … Loading bundle <level>/Venator … into compartment 12   -- capital ship phase (see below)
##   [info]  … Loading bundle <level>/Outro_Team<N> …                 -- N = winning team, THE END
##   [debug] [PrintDebugText] In_VictoryDeclarationTeam<N>Won …       -- N = winning team, THE END
##   [info]  [Server] Game ended, moving to next level                -- ~30 s later; rotation advance
##
## The winner's outro bundle / victory declaration IS the end of the round — it only ever
## loads once, at the true finish (the ground→ship→ground "lose twice" transitions load no
## Outro bundle). GC reports on it immediately rather than waiting for "Game ended", which
## lands ~30 s later and may never arrive if KYBER shuts down first (rotation stalls, the
## player alt-F4s out). So the result is applyable whether or not the game is still open.
##
## Why (2): in Clone Wars Capital Supremacy, when a team wins the ground phase the enemy's
## capital-ship sub-level streams in (`<level>/Venator` for the Republic ship, `<level>/
## Dreadnought` for the Separatist one). Verified in-game 2026-09-09: **the ship that loads
## belongs to the team that LOST the ground phase** (they're the ones being boarded). That
## `… into compartment 12` line is `[info]` level — no debug logging needed — and appears
## exactly once per match, 7-15 min in, never near a match start. GCW Supremacy ships no
## capital-ship sub-level, so this never fires there.
##
## External contract we don't control (CLAUDE.md rule 5) — but a READ of real KYBER + BF+
## log output, not an invented schema. It stays advisory: `main.gd` still offers the manual
## winner buttons, and a determinate plugin `gc_result` wins over the log-read winner.
##
## State machine, one battle: arm() → see our level load → (see a capital ship stream in →
## report the boarded faction, once) → see the winner line → report the winner, once.

enum State { IDLE, WAIT_LOAD, IN_MATCH, DONE }

## Capital-ship sub-level bundle name → the faction that owns that ship. The ship that
## streams in belongs to the team that LOST the ground phase (they're being boarded).
## Verified in-game 2026-09-09: Venator = Republic, Dreadnought = Separatist.
## Verified in-game 2026-10-08 (playtest 104, item 15): MC85 = Resistance (the same Mon
## Calamari cruiser asset the lane co-op uses, per CLAUDE.md's "fleets reuse GCW's ISD/Mon
## Cal") — a live Jakku Supremacy match streamed it in right after First Order took the
## ground phase. First Order's own ship bundle name is still unseen in a real log.
static func _ship_owner(ship_name: String) -> StringName:
	match ship_name:
		"Venator":
			return Faction.REPUBLIC
		"Dreadnought", "Providence":
			return Faction.SEPARATIST
		"MC85":
			return Faction.RESISTANCE
	return &""

var state: int = State.IDLE
var _target: String = ""
var _winner: int = 0
var _load_confirmed: bool = false            ## our match's real load has been seen (latched for the match)
var _load_confirmed_pending: bool = false    ## the once-signal for GC; take_load_confirmed() consumes it
var _ship_faction_seen: StringName = &""     ## latched once a capital ship streams in
var _ship_faction_pending: StringName = &""  ## take_capital_ship_boarded() returns this once
var _watch_capital_ship: bool = true         ## false for a lane co-op — the ship IS the map, not a phase


## Begin following a fresh battle on `level_path` (the same string GC sent in `load` and
## that KYBER echoes in "Loading level '<level_path>'"). Pass `watch_capital_ship = false`
## for a Clone Wars space-lane battle: that match is a capital-ship boarding co-op from the
## start, so a "Loading bundle …/Venator…" line is the MAP loading, not a ground-phase win
## — treating it as one fires `groundwin` and abruptly (crashily) ends the match.
func arm(level_path: String, watch_capital_ship: bool = true) -> void:
	state = State.WAIT_LOAD
	_target = level_path.strip_edges()
	_winner = 0
	_load_confirmed = false
	_load_confirmed_pending = false
	_ship_faction_seen = &""
	_ship_faction_pending = &""
	_watch_capital_ship = watch_capital_ship


## Stop following — the battle resolved, was abandoned, or the campaign moved on.
func disarm() -> void:
	state = State.IDLE
	_target = ""
	_winner = 0
	_load_confirmed = false
	_load_confirmed_pending = false
	_ship_faction_seen = &""
	_ship_faction_pending = &""


## True ONCE, right after our target level loaded (KYBER's own log line) — GC can go
## "battle live" off this even if the plugin's `level` message never comes (its echo
## heuristic misjudges small/fast maps).
func take_load_confirmed() -> bool:
	var v := _load_confirmed_pending
	_load_confirmed_pending = false   # `_load_confirmed` stays latched so it can't re-fire this match
	return v


func is_armed() -> bool:
	return state == State.WAIT_LOAD or state == State.IN_MATCH


## The winning team seen so far (1 / 2), or 0 if none yet. For diagnostics / UI.
func winner_so_far() -> int:
	return _winner


## Feed one KYBER log line (raw, as KyberLogReader yields it). Returns the winning team
## (1 or 2) EXACTLY ONCE — when the match we're following ends with a known winner (its
## outro / victory-declaration line). Returns 0 every other time. Call
## take_capital_ship_boarded() right after to pick up a mid-match "the ship phase is
## starting" signal.
func feed(line: String) -> int:
	match state:
		State.WAIT_LOAD:
			if _is_load_of_target(line):
				state = State.IN_MATCH
		State.IN_MATCH:
			# "Server level loaded" fires only on a REAL switch (not the LoadLevel echo, and
			# not in Instant Action with no server) — that's when GC can safely go live.
			if not _load_confirmed and _is_server_level_loaded(line):
				_load_confirmed = true
				_load_confirmed_pending = true
			if _watch_capital_ship and _ship_faction_seen == &"":
				var ship_faction := KyberMatchWatch.capital_ship_faction(line)
				if ship_faction != &"":
					_ship_faction_seen = ship_faction
					_ship_faction_pending = ship_faction
					return 0
			var w := KyberMatchWatch.winner_in_line(line)
			if w != 0:
				_winner = w
				state = State.DONE
				return w
			if _is_match_end(line):
				# The level switched but we never saw a winner line — 0 → GC's manual buttons.
				state = State.DONE
				return _winner
	return 0


## Set once, when a capital-ship sub-level streamed in: the faction whose ship it is —
## i.e. the faction that LOST the ground phase. Returned ONCE, then cleared. &"" otherwise.
## `main.gd` hands the win to the opponent (Faction.opponent) via `groundwin`.
func take_capital_ship_boarded() -> StringName:
	var f := _ship_faction_pending
	_ship_faction_pending = &""
	return f


func _is_load_of_target(line: String) -> bool:
	return line.contains("Loading level") and _target != "" and line.contains(_target)


## A real level switch finished (host / Arcade) — NOT the bare LoadLevel console echo, and
## never in Instant Action with no server.
func _is_server_level_loaded(line: String) -> bool:
	return line.contains("[Server] Server level loaded") \
		or line.contains("[Server] Level loaded, executing startup commands")


## Match-end with no winner line: KYBER moving on to a DIFFERENT level than ours, or its
## explicit "Game ended" marker.
func _is_match_end(line: String) -> bool:
	if line.contains("Game ended, moving to next level"):
		return true
	if line.contains("Loading level") and _target != "" and not line.contains(_target):
		return true
	return false


static var _winner_re: RegEx = null

## The winning team named in a round-end log line, or 0 if the line names none.
##   ".../Outro_Team2 ..."                       -> 2   (BF+ loads the winner's outro bundle)
##   "In_VictoryDeclarationTeam2Won has been..." -> 2   (BF+ / BXL blueprint, debug level)
## Deliberately NOT matched: "In_StartOutroTeam2" / "Out_StartOutroTeam2" (no underscore
## between Outro and Team — those fire for both sides' outro sequencing).
static func winner_in_line(line: String) -> int:
	if _winner_re == null:
		_winner_re = RegEx.new()
		_winner_re.compile("(?:Outro_Team|VictoryDeclarationTeam)([12])")
	var m := _winner_re.search(line)
	if m == null:
		return 0
	return m.get_string(1).to_int()


static var _ship_re: RegEx = null

## If `line` is a bundle load for a capital-ship sub-level, the faction that owns that ship;
## &"" otherwise. Matches "Loading bundle …/<Ship>" or "…/<Ship>_<Room>" as a path segment
## (e.g. ".../Venator (…) into compartment 12", ".../Venator_ReactorCore").
static func capital_ship_faction(line: String) -> StringName:
	if not line.contains("Loading bundle"):
		return &""
	if _ship_re == null:
		_ship_re = RegEx.new()
		_ship_re.compile("/(Venator|Dreadnought|Providence|MC85)(?:_[A-Za-z]+)?(?:[ /]|$)")
	var m := _ship_re.search(line)
	if m == null:
		return &""
	return KyberMatchWatch._ship_owner(m.get_string(1))
