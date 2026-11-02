class_name BattleResultParser
extends RefCounted

## Turns the bundled GC result plugin's payload into a Battle.Result.
##
## KYBER itself has no match-result RPC, event, or round-end log line — confirmed from
## the Module source. The result comes instead from `bridge/kyber_plugin/gc_result/`,
## a server-realm Lua plugin that tallies per-team score on `Level:Complete` and pushes
## a small JSON object over a localhost TCP socket. That JSON is OUR contract, documented
## in tests/fixtures/gc_result_sample.json.
##
## PLUGIN_CONTRACT_VERIFIED stays false until a real emission from a real server has been
## captured into that fixture. While it is false, `parse` still parses (we own the
## format) but marks the report unverified so callers know not to trust it yet.

const PLUGIN_CONTRACT_VERIFIED := false

## The heuristic winner uses each team's score as a stand-in for tickets — the Lua API
## does not surface the game's real ticket/objective counters.
const RESULT_TYPE := "gc_result"


class ParseReport extends RefCounted:
	var verified: bool = false
	var result: Battle.Result = null
	var note: String = ""


## payload: the raw JSON string from the plugin (one object, optional trailing newline).
## request: the pending Battle.Request this result answers.
## team_one_faction: which campaign faction is team id 1 on this map (from data/maps.json).
static func parse(payload: String, request: Battle.Request, team_one_faction: StringName) -> ParseReport:
	var report := ParseReport.new()

	# Instance form (not JSON.parse_string) so malformed input returns an error code
	# instead of pushing to the engine log.
	var json := JSON.new()
	if json.parse(payload.strip_edges()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		report.note = "Plugin payload was not a JSON object."
		return report
	var data: Dictionary = json.data
	if String(data.get("type", "")) != RESULT_TYPE:
		report.note = "Payload is not a '%s' object." % RESULT_TYPE
		return report
	if not data.has("winner_team"):
		report.note = "Payload has no 'winner_team'."
		return report

	var teams: Dictionary = data.get("teams", {})
	var one_score := _team_score(teams, "1")
	var two_score := _team_score(teams, "2")
	var winner_team := int(data.get("winner_team", 0))

	# winner_team is the whole answer: 1 or 2, or 0 = "the game gave no end-of-round score".
	# We do NOT guess from kills or fall back to "defender holds" — a real Supremacy fight
	# was being mis-reported that way. 0 → no result; the caller shows the manual buttons.
	if winner_team != 1 and winner_team != 2:
		report.note = (
			"KYBER reported no winner (%s) — Supremacy / GA give no end-of-round score, so "
			+ "the campaign can't read this one. Use the \"won\" / Abandoned buttons."
		) % String(data.get("reason", "no score"))
		return report

	var result := Battle.Result.new()
	result.request_id = request.id
	result.completed = true
	result.victor = team_one_faction if winner_team == 1 else Faction.opponent(team_one_faction)

	# Losses scale with how close the score was: the side that held more of the score
	# pool takes fewer. Score stands in for tickets, which the Lua API does not expose.
	var attacker_score := one_score if team_one_faction == request.attacker else two_score
	var defender_score := two_score if team_one_faction == request.attacker else one_score
	var pool := attacker_score + defender_score
	if pool <= 0:
		# We know who won but the mode gave no score (Supremacy / GA — the winner was read
		# from the KYBER log, not a ticket count). Use the same deterministic split as a
		# hand-reported result: the winner is bloodied by one, the loser by half its
		# strength rounded up. See TurnResolver.manual_result.
		var winner_is_attacker := result.victor == request.attacker
		result.attacker_losses = 1 if winner_is_attacker else int(ceil(request.attacker_strength / 2.0))
		result.defender_losses = int(ceil(request.defender_strength / 2.0)) if winner_is_attacker else 1
		report.result = result
		report.verified = false
		report.note = "Winner known, no end-of-round score — losses use the default split."
		return report
	result.attacker_losses = losses_from_ticket_ratio(attacker_score, pool, request.attacker_strength)
	result.defender_losses = losses_from_ticket_ratio(defender_score, pool, request.defender_strength)

	report.result = result
	report.verified = PLUGIN_CONTRACT_VERIFIED
	if not report.verified:
		report.note = (
			"Parsed, but the plugin contract is unverified. Capture a real gc_result "
			+ "emission, then set PLUGIN_CONTRACT_VERIFIED."
		)
	return report


static func _team_score(teams: Dictionary, key: String) -> int:
	var t: Variant = teams.get(key, {})
	if typeof(t) != TYPE_DICTIONARY:
		return 0
	return int(t.get("score", 0))


## Losses are derived from the campaign side, not read out of the match — Battlefront has
## no notion of fleet strength, so a ticket (here, score) differential is the only honest
## input. Keeping this in bridge/ means the rule can change without the campaign rules
## changing. A side that held all the score takes nothing; one that was shut out takes
## its whole strength.
static func losses_from_ticket_ratio(loser_tickets: int, starting_tickets: int, max_losses: int) -> int:
	if starting_tickets <= 0:
		return 0
	var remaining := clampf(float(loser_tickets) / float(starting_tickets), 0.0, 1.0)
	return int(round((1.0 - remaining) * float(max_losses)))
