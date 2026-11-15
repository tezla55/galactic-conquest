class_name TurnResolver
extends RefCounted

## All campaign rules. Pure functions over GalaxyState — nothing here reads a file,
## touches the scene tree, or knows that Battlefront exists.

enum MoveStatus {
	OK,                ## Fleet relocated (into own or neutral territory), no fighting.
	BATTLE_REQUIRED,   ## Destination is enemy held; a match must be played.
	INVALID,           ## Rejected. See MoveOutcome.reason.
}

const BUY_FLEET_COST := 1000
const BUY_FLEET_STRENGTH := 5
const MAX_FLEETS := 3           ## A faction may field at most this many fleets.

## The reinforcement fund: bought per fleet. Raising a fleet one tier costs
## COST × (tier+1) and adds bots to that fleet's KYBER match — nothing else.
## MAX_REINFORCEMENTS must match Fleet.MAX_REINFORCEMENT_TIER.
const REINFORCEMENT_COST := 400
const MAX_REINFORCEMENTS := 3

## Combat Training: a per-fleet aim upgrade with MAX_COMBAT_TRAINING levels. Each level
## sharpens this side's bot aim in the fleet's KYBER matches (KyberBridge.team_aim).
## Independent of reinforcements. Level L→L+1 costs COMBAT_TRAINING_COST × (L+1), except the
## top level, priced steeper still (see combat_training_cost) — `2026-09-21` (playtest 921):
## "make it more accurate but much more expensive".
## MAX_COMBAT_TRAINING must match Fleet.MAX_COMBAT_TRAINING.
const COMBAT_TRAINING_COST := 500
const MAX_COMBAT_TRAINING := 3
## The final level (MAX_COMBAT_TRAINING - 1 -> MAX_COMBAT_TRAINING) costs this many times
## the plain linear rate — deliberately a bigger jump than every level below it.
const COMBAT_TRAINING_TOP_TIER_MULTIPLIER := 3


class MoveOutcome extends RefCounted:
	var status: int = MoveStatus.INVALID
	var reason: String = ""
	var request: Battle.Request = null


class BuyOutcome extends RefCounted:
	var ok: bool = false
	var reason: String = ""
	var fleet: Fleet = null


static func _reject(reason: String) -> MoveOutcome:
	var o := MoveOutcome.new()
	o.status = MoveStatus.INVALID
	o.reason = reason
	return o


## Attempt to move a fleet along a hyperlane. Mutates `state` only when the move is
## uncontested; a contested move parks a pending battle and waits for a result.
static func move_fleet(state: GalaxyState, fleet_id: StringName, dest_id: StringName) -> MoveOutcome:
	if state.is_over():
		return _reject("The war is over.")
	if state.has_pending_battle():
		return _reject("A battle is already awaiting its result.")

	var fleet: Fleet = state.get_fleet(fleet_id)
	if fleet == null:
		return _reject("No such fleet: %s" % fleet_id)
	if fleet.has_moved:
		return _reject("%s has already moved this turn." % fleet_id)

	var origin: Planet = state.get_planet(fleet.location)
	var dest: Planet = state.get_planet(dest_id)
	if origin == null or dest == null:
		return _reject("Unknown planet in move %s -> %s" % [fleet.location, dest_id])
	if not origin.is_connected_to(dest_id):
		return _reject("%s is not on a hyperlane from %s." % [dest.display_name, origin.display_name])

	var outcome := MoveOutcome.new()

	if state.fleet_at(dest_id, fleet.owner) != null:
		return _reject("%s already has a fleet stationed there." % dest.display_name)

	# A space lane is a transit node nobody owns. A parked enemy fleet is fought (the
	# lane itself never changes hands); an empty one is just moved onto.
	if not dest.capturable:
		var blocker := _enemy_fleet_at(state, dest_id, fleet.owner)
		if blocker == null:
			fleet.location = dest_id
			fleet.has_moved = true
			outcome.status = MoveStatus.OK
			return outcome
		return _start_battle(state, fleet, dest_id, blocker.owner, outcome)

	# Own territory is a plain relocation; a neutral world is occupied without a fight.
	if dest.owner == fleet.owner or dest.owner == Faction.NEUTRAL:
		if dest.owner == Faction.NEUTRAL:
			dest.owner = fleet.owner
			dest.garrison = fleet.strength
			state.record_world_captured(fleet.owner)
		fleet.location = dest_id
		fleet.has_moved = true
		outcome.status = MoveStatus.OK
		return outcome

	return _start_battle(state, fleet, dest_id, dest.owner, outcome)


static func _enemy_fleet_at(state: GalaxyState, planet_id: StringName, faction: StringName) -> Fleet:
	for f in state.fleets_at(planet_id):
		if f.owner != faction:
			return f
	return null


## The Battle.Request a move from `fleet` onto `dest_id` would create — pure, no mutation.
## Shared by _start_battle (which commits it to state.pending_battle) and callers that only
## want to preview the real match numbers (bot count, aim) before committing to an attack.
static func build_battle_request(state: GalaxyState, fleet: Fleet, dest_id: StringName, defender: StringName) -> Battle.Request:
	var req := Battle.Request.new()
	req.id = Battle.make_request_id(state.turn, dest_id, fleet.id)
	req.planet_id = dest_id
	req.attacker = fleet.owner
	req.defender = defender
	req.attacker_fleet_id = fleet.id
	req.attacker_strength = fleet.strength
	req.defender_strength = defender_strength(state, dest_id)
	req.attacker_reinforcement = fleet.reinforcement_tier
	req.attacker_training = fleet.combat_training_level
	var def_fleet: Fleet = state.fleet_at(dest_id, defender)
	req.defender_reinforcement = def_fleet.reinforcement_tier if def_fleet != null else 0
	req.defender_fleet_strength = def_fleet.strength if def_fleet != null else 0
	req.defender_training = def_fleet.combat_training_level if def_fleet != null else 0
	req.turn = state.turn
	return req


static func _start_battle(state: GalaxyState, fleet: Fleet, dest_id: StringName, defender: StringName, outcome: MoveOutcome) -> MoveOutcome:
	var req := build_battle_request(state, fleet, dest_id, defender)
	state.pending_battle = req.to_dict()
	outcome.status = MoveStatus.BATTLE_REQUIRED
	outcome.request = req
	return outcome


static func _friendly_fleet_strength(state: GalaxyState, planet_id: StringName, faction: StringName) -> int:
	var total := 0
	for f in state.fleets_at(planet_id):
		if f.owner == faction:
			total += f.strength
	return total


## What an attacker has to beat to take this world: its garrison plus every fleet its
## current owner has stationed there. Shared by move_fleet and the AI so both agree.
## A space lane has no garrison and no owner — its defence is just the fleet parked there.
static func defender_strength(state: GalaxyState, planet_id: StringName) -> int:
	var planet: Planet = state.get_planet(planet_id)
	if planet == null:
		return 0
	if not planet.capturable:
		var total := 0
		for f in state.fleets_at(planet_id):
			total += f.strength
		return total
	return planet.garrison + _friendly_fleet_strength(state, planet_id, planet.owner)


## Muster a new fleet at the faction's capital for a flat price. Returns ok = false with
## a reason when the treasury is short or the capital is in enemy hands.
static func buy_fleet(state: GalaxyState, faction: StringName) -> BuyOutcome:
	var o := BuyOutcome.new()
	if state.fleets_owned_by(faction).size() >= MAX_FLEETS:
		o.reason = "You already command the maximum of %d fleets." % MAX_FLEETS
		return o
	if int(state.credits.get(faction, 0)) < BUY_FLEET_COST:
		o.reason = "Not enough credits — a fleet costs %d." % BUY_FLEET_COST
		return o
	var capital: Planet = state.capital_for(faction)
	if capital == null or capital.owner != faction:
		o.reason = "Your capital has been lost; there is nowhere to muster a fleet."
		return o
	if state.fleet_at(capital.id, faction) != null:
		o.reason = "A fleet is already stationed at %s — move it out first." % capital.display_name
		return o
	state.credits[faction] = int(state.credits.get(faction, 0)) - BUY_FLEET_COST
	o.fleet = state.spawn_fleet(faction, capital.id, BUY_FLEET_STRENGTH)
	o.ok = true
	return o


static func reinforcement_cost(tier: int) -> int:
	return REINFORCEMENT_COST * (tier + 1)


## Raise one fleet's reinforcement tier by one, paid from its owner's treasury. That
## fleet then fields more bots in its KYBER match and, from tier 1, its side's bots get
## the sharper aim. Returns ok = false with a reason.
static func reinforce_fleet(state: GalaxyState, fleet_id: StringName) -> BuyOutcome:
	var o := BuyOutcome.new()
	if state.is_over():
		o.reason = "The war is over."
		return o
	var fleet: Fleet = state.get_fleet(fleet_id)
	if fleet == null:
		o.reason = "No such fleet: %s" % fleet_id
		return o
	if fleet.reinforcement_tier >= MAX_REINFORCEMENTS:
		o.reason = "This fleet's reinforcements are already at the maximum tier."
		return o
	var cost := reinforcement_cost(fleet.reinforcement_tier)
	if int(state.credits.get(fleet.owner, 0)) < cost:
		o.reason = "Not enough credits — the next reinforcement tier costs %d." % cost
		return o
	state.credits[fleet.owner] = int(state.credits.get(fleet.owner, 0)) - cost
	fleet.reinforcement_tier += 1
	o.fleet = fleet
	o.ok = true
	return o


static func combat_training_cost(level: int) -> int:
	var lvl := maxi(0, level)
	var linear := COMBAT_TRAINING_COST * (lvl + 1)
	return linear * COMBAT_TRAINING_TOP_TIER_MULTIPLIER if lvl == MAX_COMBAT_TRAINING - 1 else linear


## Raise one fleet's Combat Training by one level (max MAX_COMBAT_TRAINING) — a per-fleet
## aim upgrade, paid from its owner's treasury. Returns ok = false with a reason.
static func buy_combat_training(state: GalaxyState, fleet_id: StringName) -> BuyOutcome:
	var o := BuyOutcome.new()
	if state.is_over():
		o.reason = "The war is over."
		return o
	var fleet: Fleet = state.get_fleet(fleet_id)
	if fleet == null:
		o.reason = "No such fleet: %s" % fleet_id
		return o
	if fleet.combat_training_level >= MAX_COMBAT_TRAINING:
		o.reason = "This fleet's Combat Training is already at the maximum level."
		return o
	var cost := combat_training_cost(fleet.combat_training_level)
	if int(state.credits.get(fleet.owner, 0)) < cost:
		o.reason = "Not enough credits — the next Combat Training level costs %d." % cost
		return o
	state.credits[fleet.owner] = int(state.credits.get(fleet.owner, 0)) - cost
	fleet.combat_training_level += 1
	o.fleet = fleet
	o.ok = true
	return o


## Fold a completed battle back into the campaign. Returns true if it was applied.
## When the battle belonged to the AI's turn, draining the rest of its plan resumes here.
static func apply_battle_result(state: GalaxyState, result: Battle.Result) -> bool:
	if not state.has_pending_battle():
		return false
	var req := Battle.Request.from_dict(state.pending_battle)
	if req.id != result.request_id:
		return false

	var applied := _fold_battle_result(state, req, result)
	state.pending_battle = {}
	_resume_ai_phase(state)
	return applied


## The player has reported the outcome of a battle they started. Fold it in, then end
## their phase: pressing an attack is the player's decisive act for the turn and it is
## spent whether they won, lost, or walked away. Battles the AI started are left to the
## AI phase and just fall through to apply_battle_result.
##
## In `two_player` mode there is no AI — both sides play this way. Whichever faction is
## currently active is the one who can have initiated the pending battle (only the active
## side ever moves a fleet), so `acting_faction` is `active_faction` there instead of the
## fixed `player_faction`, and the same "attacking spends your phase" rule applies to both
## humans symmetrically.
static func resolve_player_battle(state: GalaxyState, result: Battle.Result) -> bool:
	var acting_faction := state.active_faction if state.two_player else state.player_faction
	var player_attack := (
		state.has_pending_battle()
		and StringName(state.pending_battle.get("attacker", &"")) == acting_faction
	)
	var applied := apply_battle_result(state, result)
	if applied and player_attack and not state.has_pending_battle() \
			and state.active_faction == acting_faction:
		end_turn(state)
	return applied


static func _fold_battle_result(state: GalaxyState, req: Battle.Request, result: Battle.Result) -> bool:
	var fleet: Fleet = state.get_fleet(req.attacker_fleet_id)
	var planet: Planet = state.get_planet(req.planet_id)
	if fleet == null or planet == null:
		return false

	if not result.completed:
		# Abandoned match = forfeit. The side that walked away loses the battle and its
		# fleet, and the other side is credited with the win. An abandoned DEFENCE also
		# hands the world (or the lane position) to the attacker - walking away must never
		# work as a free way to push an attack back. A NEUTRAL `abandoned_by` (a
		# stuck/unreadable match nobody forfeited) only spends the turn.
		fleet.has_moved = true
		if result.abandoned_by == req.attacker:
			state.record_battle_result(req.defender, req.attacker)
			state.remove_fleet(fleet.id)
		elif result.abandoned_by == req.defender:
			state.record_battle_result(req.attacker, req.defender)
			for f in state.fleets_at(req.planet_id):
				if f.owner == req.defender:
					state.remove_fleet(f.id)
			_take_planet(state, req, fleet, planet)
		return true

	fleet.apply_losses(result.attacker_losses)
	planet.garrison = maxi(0, planet.garrison - result.defender_losses)
	state.record_battle_result(result.victor,
		req.defender if result.victor == req.attacker else req.attacker)

	if result.victor == req.attacker and not fleet.is_destroyed():
		_take_planet(state, req, fleet, planet)
	else:
		# A failed assault (or a pyrrhic one that wiped the fleet) costs the whole force.
		state.remove_fleet(fleet.id)

	return true


## Move the winning attacker onto the contested world/lane and sweep the defender's ships
## out of it. A capturable world changes hands; a space lane stays unowned and only the
## position changes hands.
static func _take_planet(state: GalaxyState, req: Battle.Request, fleet: Fleet, planet: Planet) -> void:
	if planet.capturable:
		planet.owner = req.attacker
		planet.garrison = fleet.strength
		state.record_world_captured(req.attacker)
	fleet.location = req.planet_id
	for f in state.fleets_at(req.planet_id):
		if f.owner == req.defender:
			state.remove_fleet(f.id)
	fleet.has_moved = true


## Build a result from nothing but a reported winner. Used when a human plays the match
## in Battlefront and tells the campaign who won, before log parsing exists.
##
## The loss curve is deliberately simple and deterministic: the winner is bloodied by
## one, the loser by half its strength rounded up. It is not meant to be realistic, only
## consistent, so that the campaign behaves the same way whether a person or a parser
## reported the outcome. Replace it with ticket-derived losses once the log fixture lands.
static func manual_result(request: Battle.Request, victor: StringName) -> Battle.Result:
	var r := Battle.Result.new()
	r.request_id = request.id
	r.victor = victor
	r.completed = true
	if victor == request.attacker:
		r.attacker_losses = 1
		r.defender_losses = int(ceil(request.defender_strength / 2.0))
	else:
		r.attacker_losses = int(ceil(request.attacker_strength / 2.0))
		r.defender_losses = 1
	return r


## A result for a match nobody finished. The turn is spent, and the `abandoned_by` side (if
## given) forfeits the battle and its fleet - the opponent gets the win, and an abandoned
## defence hands the planet/lane to the attacker. Leave it NEUTRAL for a stuck match where
## nobody walked away.
static func abandoned_result(request: Battle.Request, abandoned_by: StringName = Faction.NEUTRAL) -> Battle.Result:
	var r := Battle.Result.new()
	r.request_id = request.id
	r.completed = false
	r.abandoned_by = abandoned_by
	return r


## End the active side's phase. Blocked while a battle is pending.
##
## **Single player**: hands the turn to the AI. The AI plan is run straight away; if it
## queues a battle against the player, this returns with that battle pending and the rest
## of the plan parked in state.ai_plan — apply_battle_result picks it back up. Once the
## plan is exhausted the round advances: income is paid, movement refreshes, and control
## returns to the player.
##
## **Two player** (`state.two_player`): there is no AI plan to run — this just hands the
## phase to the other human (`_end_turn_two_player`), or, once BOTH sides have had their
## phase, advances the round exactly like single player's does.
##
## `seed` is normally derived from the campaign; pass a value >= 0 to force it (tests).
static func end_turn(state: GalaxyState, seed: int = -1) -> bool:
	if state.has_pending_battle() or state.is_over():
		return false
	if state.two_player:
		return _end_turn_two_player(state)
	if state.active_faction != state.player_faction:
		# Already inside the AI phase (e.g. re-entered): keep draining it.
		_run_ai_plan(state)
		return true
	var resolved_seed := seed if seed >= 0 else state.campaign_seed + state.turn
	state.active_faction = Faction.opponent(state.player_faction)
	state.ai_plan = AiCommander.plan(state, state.active_faction, resolved_seed)
	_run_ai_plan(state)
	return true


## Hotseat hand-off: `player_faction`'s phase ending flips control to the other human;
## the other human's phase ending advances the round (paying both sides equally — see
## _advance_round's `two_player` guard) and hands the first phase of the new round back to
## `player_faction`, same order every round.
static func _end_turn_two_player(state: GalaxyState) -> bool:
	if state.active_faction == state.player_faction:
		state.active_faction = Faction.opponent(state.player_faction)
	else:
		_advance_round(state)
	return true


## Apply one queued AI action. Returns true if the plan must pause here (a battle the
## player has to play). `faction` is who is acting.
static func _apply_ai_action(state: GalaxyState, action: Dictionary, faction: StringName) -> bool:
	match String(action.get("type", "")):
		"buy":
			buy_fleet(state, faction)
		"reinforce":
			reinforce_fleet(state, StringName(action.get("fleet_id", "")))
		"train":
			buy_combat_training(state, StringName(action.get("fleet_id", "")))
		"move":
			var res := move_fleet(
				state,
				StringName(action.get("fleet_id", "")),
				StringName(action.get("dest", ""))
			)
			if res.status == MoveStatus.BATTLE_REQUIRED:
				return true
	return false


## Drain state.ai_plan. Stops early (leaving the rest queued) when a move needs a battle
## the player must play; otherwise advances the round once the queue is empty.
static func _run_ai_plan(state: GalaxyState) -> void:
	if state.is_over():
		state.ai_plan = []
		return
	while not state.ai_plan.is_empty():
		if state.has_pending_battle():
			return
		if _apply_ai_action(state, state.ai_plan.pop_front(), state.active_faction):
			return
	_advance_round(state)


## An optional AI "opening move" before the player's very first turn. A seeded coin flip at
## campaign start (`ContentLoader.new_campaign`) hands the enemy the first move ~half the
## time — more agency for the AI, a bit more difficulty. Runs the AI's plan once WITHOUT
## advancing the round: no income is paid and `turn` stays 1. If the opening queues a
## battle against the player it is left pending — the player resolves it as their first act
## (`apply_battle_result` then drains the rest, exactly like any AI-started battle).
static func run_ai_opening(state: GalaxyState, seed: int) -> void:
	if state.is_over() or state.has_pending_battle():
		return
	var ai := Faction.opponent(state.player_faction)
	state.ai_opened = true
	state.active_faction = ai
	state.ai_plan = AiCommander.plan(state, ai, seed)
	while not state.ai_plan.is_empty():
		if state.has_pending_battle():
			return
		if _apply_ai_action(state, state.ai_plan.pop_front(), ai):
			return
	state.active_faction = state.player_faction
	for f: Fleet in state.fleets.values():
		f.has_moved = false


## No-op in `two_player` — there is no `ai_plan` to drain there; resolve_player_battle's own
## explicit end_turn call (in main.gd's terms: whichever human just fought) is what advances
## a hotseat phase. Without this guard, `active_faction != player_faction` is also just
## "the second human's phase" in two_player mode, and draining an always-empty ai_plan would
## advance the round the instant their FIRST battle resolved instead of ending only their
## own phase.
static func _resume_ai_phase(state: GalaxyState) -> void:
	if state.two_player:
		return
	if state.active_faction != state.player_faction:
		_run_ai_plan(state)


static func _advance_round(state: GalaxyState) -> void:
	var ai_faction := Faction.opponent(state.player_faction)
	for faction in Faction.ALL:
		var pay := state.income_for(faction)
		if faction == ai_faction and not state.two_player:
			pay += Difficulty.ai_income_bonus(state.difficulty)
		state.credits[faction] = int(state.credits.get(faction, 0)) + pay
	for f: Fleet in state.fleets.values():
		f.has_moved = false
	state.turn += 1
	state.active_faction = state.player_faction
	state.ai_plan = []
