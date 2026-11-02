class_name GalaxyState
extends RefCounted

## The entire campaign. Serialises to JSON and back with no loss, which is what makes
## save files, test fixtures and crash recovery all the same problem.

## 2: reinforcements moved from a faction-wide tier to a per-fleet Fleet.reinforcement_tier.
## 3: fleets carried a unit roster (vehicles / specials / heroes) + dead_heroes tracking.
## 4: the unit-buying system was removed — fleets are just strength + reinforcement_tier.
## 5: multi-campaign — `campaign_id` names which era's map this state belongs to.
## 6: `two_player` — a local hotseat war with no AI at all; see TurnResolver.
## 7: `battles_won` / `battles_lost` / `worlds_captured` — lifetime per-faction counters,
##    for the victory/defeat screen. Missing on an old save loads as empty (all zero),
##    same as a fresh campaign — there is no way to reconstruct history retroactively, and
##    that's fine: the numbers are a nice-to-have on top of an otherwise-working save, not
##    load-bearing campaign state.
const SAVE_VERSION := 7

var version: int = SAVE_VERSION
var turn: int = 1
var campaign_id: StringName = &"clone_wars"   ## Which campaign (data/campaigns.json).
var player_faction: StringName = Faction.REPUBLIC
var active_faction: StringName = Faction.REPUBLIC  ## Whose phase it is right now.
## A local two-human hotseat war: `player_faction`'s opponent is also human-controlled
## (TurnResolver.end_turn hands the phase back and forth instead of running AiCommander),
## and no AI-only starting bonus / per-round income bonus is ever paid — both sides equal.
var two_player: bool = false
var planets: Dictionary = {}    ## StringName -> Planet
var fleets: Dictionary = {}     ## StringName -> Fleet
var credits: Dictionary = {}    ## StringName -> int
var pending_battle: Dictionary = {}  ## Serialised Battle.Request, or empty.
var ai_plan: Array = []         ## Queued AI actions, drained during the AI phase. Plain dicts.
var campaign_seed: int = 0      ## Fixed at campaign creation; drives AI determinism.
var difficulty: StringName = Difficulty.DEFAULT   ## easy / normal / hard; set at campaign creation.
var ai_opened: bool = false     ## The 50/50 coin flip gave the enemy the opening move.
## Lifetime per-faction stats for the victory/defeat screen — StringName faction -> int.
## Updated by TurnResolver alone (_fold_battle_result, move_fleet's neutral-occupation
## branch); nothing here computes them, this just holds the running totals. An abandoned
## battle decides nothing, so it increments neither battles_won nor battles_lost.
var battles_won: Dictionary = {}
var battles_lost: Dictionary = {}
var worlds_captured: Dictionary = {}   ## Capturable worlds only — neutral occupation + conquest.
var _fleet_serial: int = 0


func _init() -> void:
	# Per-faction credit balances are filled by ContentLoader.new_campaign for the
	# campaign's two sides; every read goes through `.get(faction, 0)` so an empty map
	# before then is fine.
	credits = {}


# --- Queries -----------------------------------------------------------------

func get_planet(planet_id: StringName) -> Planet:
	return planets.get(planet_id, null)


func get_fleet(fleet_id: StringName) -> Fleet:
	return fleets.get(fleet_id, null)


## The planet a faction calls its capital, whoever currently holds it, or null.
func capital_for(faction: StringName) -> Planet:
	for p: Planet in planets.values():
		if p.capital_faction == faction:
			return p
	return null


func planets_owned_by(faction: StringName) -> Array[Planet]:
	var out: Array[Planet] = []
	for p: Planet in planets.values():
		if p.owner == faction:
			out.append(p)
	return out


func fleets_owned_by(faction: StringName) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f: Fleet in fleets.values():
		if f.owner == faction:
			out.append(f)
	return out


func fleets_at(planet_id: StringName) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f: Fleet in fleets.values():
		if f.location == planet_id:
			out.append(f)
	return out


## The one fleet a faction has at a planet, or null. One fleet per planet is a rule
## (see TurnResolver.move_fleet), so this is unambiguous.
func fleet_at(planet_id: StringName, faction: StringName) -> Fleet:
	for f: Fleet in fleets.values():
		if f.location == planet_id and f.owner == faction:
			return f
	return null


## Beyond this many owned worlds, extra worlds still add their own income to the
## base below, but no longer also raise the multiplier (playtest 104, item 13: an
## uncapped base * owned was quadratic in world count — a faction with many worlds
## snowballed, each new conquest multiplying an already-growing base).
const INCOME_MULTIPLIER_CAP := 4
## Hard ceiling on the ordinary planet-income total. Past it, extra worlds add only
## INCOME_EXTRA_PER_WORLD each instead of their full multiplied income — four rich worlds
## were paying ~1500/turn and deciding games by themselves.
const INCOME_CAP := 1200
const INCOME_EXTRA_PER_WORLD := 50

## Credits paid to a faction each turn. The base is the sum of its owned worlds'
## income; that total is then multiplied by the number of capturable worlds it
## holds, up to INCOME_MULTIPLIER_CAP, so early expansion still pays off 1:1 per
## world but a faction well past the cap stops compounding. The result is capped at
## INCOME_CAP; once over it, each world beyond INCOME_MULTIPLIER_CAP adds only
## INCOME_EXTRA_PER_WORLD. Space lanes (capturable == false) are never owned and never
## count. A faction with no worlds earns nothing.
func income_for(faction: StringName) -> int:
	var base := 0
	var owned := 0
	for p: Planet in planets.values():
		if p.owner == faction and p.capturable:
			base += p.income
			owned += 1
	if owned == 0:
		return 0
	var total := base * mini(owned, INCOME_MULTIPLIER_CAP)
	if total <= INCOME_CAP:
		return total
	return INCOME_CAP + maxi(0, owned - INCOME_MULTIPLIER_CAP) * INCOME_EXTRA_PER_WORLD


## The war is decided by capitals: take the enemy's and you win. Returns the winning
## faction, or Faction.NEUTRAL while both capitals still stand with their owners.
func victor() -> StringName:
	for p: Planet in planets.values():
		if p.capital_faction == &"":
			continue
		if Faction.is_playable(p.owner) and p.owner != p.capital_faction:
			return p.owner
	return Faction.NEUTRAL


func is_over() -> bool:
	return victor() != Faction.NEUTRAL


func has_pending_battle() -> bool:
	return not pending_battle.is_empty()


func battles_won_by(faction: StringName) -> int:
	return int(battles_won.get(faction, 0))


func battles_lost_by(faction: StringName) -> int:
	return int(battles_lost.get(faction, 0))


func worlds_captured_by(faction: StringName) -> int:
	return int(worlds_captured.get(faction, 0))


# --- Mutation ----------------------------------------------------------------

func add_planet(planet: Planet) -> void:
	planets[planet.id] = planet


func spawn_fleet(owner: StringName, location: StringName, strength: int) -> Fleet:
	_fleet_serial += 1
	var f := Fleet.new()
	f.id = StringName("fleet_%d" % _fleet_serial)
	f.owner = owner
	f.location = location
	f.strength = clampi(strength, Fleet.MIN_STRENGTH, Fleet.MAX_STRENGTH)
	fleets[f.id] = f
	return f


func remove_fleet(fleet_id: StringName) -> void:
	fleets.erase(fleet_id)


func record_battle_result(winner: StringName, loser: StringName) -> void:
	battles_won[winner] = battles_won_by(winner) + 1
	battles_lost[loser] = battles_lost_by(loser) + 1


func record_world_captured(faction: StringName) -> void:
	worlds_captured[faction] = worlds_captured_by(faction) + 1


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var planet_list: Array = []
	for p: Planet in planets.values():
		planet_list.append(p.to_dict())
	var fleet_list: Array = []
	for f: Fleet in fleets.values():
		fleet_list.append(f.to_dict())
	var credit_map := {}
	for k: StringName in credits:
		credit_map[String(k)] = int(credits[k])
	return {
		"version": version,
		"turn": turn,
		"campaign_id": String(campaign_id),
		"player_faction": String(player_faction),
		"active_faction": String(active_faction),
		"two_player": two_player,
		"planets": planet_list,
		"fleets": fleet_list,
		"credits": credit_map,
		"pending_battle": pending_battle,
		"difficulty": String(difficulty),
		"ai_opened": ai_opened,
		"ai_plan": ai_plan.duplicate(true),
		"campaign_seed": campaign_seed,
		"fleet_serial": _fleet_serial,
		"battles_won": _stringify_faction_map(battles_won),
		"battles_lost": _stringify_faction_map(battles_lost),
		"worlds_captured": _stringify_faction_map(worlds_captured),
	}


static func _stringify_faction_map(m: Dictionary) -> Dictionary:
	var out := {}
	for k: StringName in m:
		out[String(k)] = int(m[k])
	return out


static func _faction_map_from_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k)] = int(d[k])
	return out


static func from_dict(d: Dictionary) -> GalaxyState:
	var s := GalaxyState.new()
	s.version = int(d.get("version", SAVE_VERSION))
	s.turn = int(d.get("turn", 1))
	s.campaign_id = StringName(d.get("campaign_id", "clone_wars"))
	s.player_faction = StringName(d.get("player_faction", Faction.REPUBLIC))
	s.active_faction = StringName(d.get("active_faction", d.get("player_faction", Faction.REPUBLIC)))
	s.two_player = bool(d.get("two_player", false))
	s.campaign_seed = int(d.get("campaign_seed", 0))
	s.ai_opened = bool(d.get("ai_opened", false))
	s._fleet_serial = int(d.get("fleet_serial", 0))
	for pd in d.get("planets", []):
		var p := Planet.from_dict(pd)
		s.planets[p.id] = p
	for fd in d.get("fleets", []):
		var f := Fleet.from_dict(fd)
		s.fleets[f.id] = f
	var credit_map: Dictionary = d.get("credits", {})
	for k in credit_map:
		s.credits[StringName(k)] = int(credit_map[k])
	s.pending_battle = d.get("pending_battle", {})
	s.difficulty = Difficulty.normalise(StringName(d.get("difficulty", Difficulty.DEFAULT)))
	s.ai_plan = (d.get("ai_plan", []) as Array).duplicate(true)
	s.battles_won = _faction_map_from_dict(d.get("battles_won", {}))
	s.battles_lost = _faction_map_from_dict(d.get("battles_lost", {}))
	s.worlds_captured = _faction_map_from_dict(d.get("worlds_captured", {}))
	return s


func copy() -> GalaxyState:
	return GalaxyState.from_dict(to_dict())
