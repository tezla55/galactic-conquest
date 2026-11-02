class_name Battle
extends RefCounted

## The two objects that cross the boundary between the campaign and KYBER.
##
## A Request says "these forces are contesting this world." It carries no knowledge
## of maps, modes, bot counts or Docker. Turning it into something Battlefront can
## run is the bridge's job, and turning the outcome back into a Result is the
## bridge's job too. Keep it that way: core/ must never learn what a map rotation is.


class Request extends RefCounted:
	var id: String = ""
	var planet_id: StringName = &""
	var attacker: StringName = Faction.NEUTRAL
	var defender: StringName = Faction.NEUTRAL
	var attacker_fleet_id: StringName = &""
	var attacker_strength: int = 0
	var defender_strength: int = 0
	## The reinforcement tier of the fleet on each side, and the defending fleet's own
	## strength (0 when only a garrison defends). The bridge turns these into each side's
	## bot count and aim — a side with no fleet gets the bare minimum and the basic aim.
	var attacker_reinforcement: int = 0
	var defender_reinforcement: int = 0
	var defender_fleet_strength: int = 0
	## Combat Training level on each side's fleet (0..2) — the bridge turns it into that
	## team's bot aim.
	var attacker_training: int = 0
	var defender_training: int = 0
	var turn: int = 0
	## For a GCW space-lane battle only: which of the two adjacent planets' Blast maps the
	## player chose to fight on (a `maps.json` key). Empty until picked / not a lane battle.
	var lane_map_key: String = ""

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"planet_id": String(planet_id),
			"attacker": String(attacker),
			"defender": String(defender),
			"attacker_fleet_id": String(attacker_fleet_id),
			"attacker_strength": attacker_strength,
			"defender_strength": defender_strength,
			"attacker_reinforcement": attacker_reinforcement,
			"defender_reinforcement": defender_reinforcement,
			"defender_fleet_strength": defender_fleet_strength,
			"attacker_training": attacker_training,
			"defender_training": defender_training,
			"turn": turn,
			"lane_map_key": lane_map_key,
		}

	static func from_dict(d: Dictionary) -> Request:
		var r := Request.new()
		r.id = String(d.get("id", ""))
		r.planet_id = StringName(d.get("planet_id", ""))
		r.attacker = StringName(d.get("attacker", Faction.NEUTRAL))
		r.defender = StringName(d.get("defender", Faction.NEUTRAL))
		r.attacker_fleet_id = StringName(d.get("attacker_fleet_id", ""))
		r.attacker_strength = int(d.get("attacker_strength", 0))
		r.defender_strength = int(d.get("defender_strength", 0))
		r.attacker_reinforcement = int(d.get("attacker_reinforcement", 0))
		r.defender_reinforcement = int(d.get("defender_reinforcement", 0))
		r.defender_fleet_strength = int(d.get("defender_fleet_strength", 0))
		r.attacker_training = int(d.get("attacker_training", int(bool(d.get("attacker_has_training", false)))))
		r.defender_training = int(d.get("defender_training", int(bool(d.get("defender_has_training", false)))))
		r.turn = int(d.get("turn", 0))
		r.lane_map_key = String(d.get("lane_map_key", ""))
		return r


class Result extends RefCounted:
	var request_id: String = ""
	var victor: StringName = Faction.NEUTRAL
	var attacker_losses: int = 0
	var defender_losses: int = 0
	var completed: bool = false   ## False if the match was abandoned or never finished.
	## Which side walked away, when `completed` is false. That side's fleet is destroyed —
	## abandoning is a forfeit, not a free reposition. NEUTRAL means "nobody in particular"
	## (an unreadable/stuck match), which spends the turn without destroying anything.
	var abandoned_by: StringName = Faction.NEUTRAL

	func to_dict() -> Dictionary:
		return {
			"request_id": request_id,
			"victor": String(victor),
			"attacker_losses": attacker_losses,
			"defender_losses": defender_losses,
			"completed": completed,
			"abandoned_by": String(abandoned_by),
		}

	static func from_dict(d: Dictionary) -> Result:
		var r := Result.new()
		r.request_id = String(d.get("request_id", ""))
		r.victor = StringName(d.get("victor", Faction.NEUTRAL))
		r.attacker_losses = int(d.get("attacker_losses", 0))
		r.defender_losses = int(d.get("defender_losses", 0))
		r.completed = bool(d.get("completed", false))
		r.abandoned_by = StringName(d.get("abandoned_by", Faction.NEUTRAL))
		return r


## Deterministic identifier. Same campaign situation always yields the same id, so a
## result parsed out of a log can be matched back to the request that caused it.
static func make_request_id(turn: int, planet_id: StringName, fleet_id: StringName) -> String:
	return "t%d-%s-%s" % [turn, String(planet_id), String(fleet_id)]
