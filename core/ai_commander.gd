class_name AiCommander
extends RefCounted

## A deterministic opponent. Given a GalaxyState, the faction to act for, and a seed, it
## returns an ordered list of action dicts for TurnResolver to execute:
##
##   {"type": "buy"}
##   {"type": "move", "fleet_id": <fleet id>, "dest": <planet id>}
##
## Same inputs, same list, every time. Randomness enters only through `seed` — to break
## ties, and to pick among options the heuristic rates *nearly* equally (SCORE_TIE_TOLERANCE
## / DEFENCE_TIE_TOLERANCE), so two campaigns with different seeds don't play out
## identically move-for-move while a fixed seed still always replays the same way.
##
## The heuristic: grow when it can afford to, take undefended neutral worlds, press an
## attack on any adjacent enemy world it is not badly outmatched at, guard its own exposed
## worlds, and otherwise march toward the most valuable reachable target.

## The AI attacks only when it is genuinely ahead. With a human on the defending team an
## even fight is an easy win for the player, so the AI needs a real edge — more bots, a
## higher reinforcement tier, or sharper Combat Training — before it commits. An even or
## losing matchup → it holds and keeps investing. How big that required edge is scales with
## difficulty: Hard presses an even fight, Easy waits for a clearer one.
const AI_ATTACK_EDGE_BY_DIFFICULTY := {
	Difficulty.EASY: 2,
	Difficulty.NORMAL: 1,
	Difficulty.HARD: 0,
}
const FIGHT_SIZE_CAP := 7   ## KYBER caps match size, so defence past this doesn't make the fight harder.


static func _attack_edge_for(difficulty: StringName) -> int:
	return int(AI_ATTACK_EDGE_BY_DIFFICULTY.get(Difficulty.normalise(difficulty), AI_ATTACK_EDGE_BY_DIFFICULTY[Difficulty.NORMAL]))

## Reinforcement tier → +4 bots. Combat Training level → deadlier bot aim for the AI side
## (1.75 → 1.25 → 0.75). Both weighted here so the AI treats a kitted fleet as a real
## deterrent, values its own investment, and presses harder once its aim is sharp.
const TIER_WEIGHT := 2
const TRAINING_WEIGHT := 2

## A little variety between otherwise-identical campaigns: a candidate scored within this
## much of the best is treated as an effective tie and picked among at random (via the
## passed seed) instead of the AI always taking the literal single best option. Kept
## small on purpose — this should only ever swap between comparably good choices, never
## pick something meaningfully worse.
const SCORE_TIE_TOLERANCE := 0.08   ## _best_reachable: fraction of the top score
const DEFENCE_TIE_TOLERANCE := 1    ## _adjacent_attack: absolute defence+edge points


## A fleet's edge in a match beyond raw numbers — reinforcement tier plus Combat Training.
static func _kit_edge(fleet: Fleet) -> int:
	return fleet.reinforcement_tier * TIER_WEIGHT + fleet.combat_training_level * TRAINING_WEIGHT


## The kit edge of every enemy fleet dug in at a world (or parked on a lane).
static func _defence_kit_edge(state: GalaxyState, planet_id: StringName, attacker: StringName) -> int:
	var edge := 0
	for f in state.fleets_at(planet_id):
		if f.owner != attacker and Faction.is_playable(f.owner):
			edge += _kit_edge(f)
	return edge


## Would this fleet take on that defence? Bot counts are compared at the capped fight size;
## reinforcement and roster edges are added on top for both sides. Against a fleet the AI
## must EXCEED the defence by `edge` (an even fight is an easy player win, at Normal's
## default edge of 1) — see AI_ATTACK_EDGE_BY_DIFFICULTY. Against a garrison only — no
## defending fleet — the bot-count maths favour the attacker, so the AI presses even when it
## looks a couple of points behind on paper.
static func _worth_attacking(fleet: Fleet, defence: int, defence_edge: int, garrison_only := false, edge := AI_ATTACK_EDGE_BY_DIFFICULTY[Difficulty.NORMAL]) -> bool:
	var attack := mini(fleet.strength, FIGHT_SIZE_CAP) + _kit_edge(fleet)
	var defend := mini(defence, FIGHT_SIZE_CAP) + defence_edge
	# A trained fleet's bots out-shoot the player's defenders, so it commits on a lower bar.
	var required := (-2 if garrison_only else edge) - fleet.combat_training_level
	return attack >= defend + maxi(required, -3)


static func plan(state: GalaxyState, faction: StringName, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var edge := _attack_edge_for(state.difficulty)

	var actions: Array = []
	var credits := int(state.credits.get(faction, 0))

	var owned_fleets := state.fleets_owned_by(faction).size()
	var capital: Planet = state.capital_for(faction)
	var capital_ready := (
		capital != null
		and capital.owner == faction
		and state.fleet_at(capital.id, faction) == null
	)
	var best_tier := 0
	for f in state.fleets_owned_by(faction):
		best_tier = maxi(best_tier, f.reinforcement_tier)

	# A small reserve only — the AI is meant to keep upgrading, not hoard.
	const RESERVE := 150

	# 1. Grow to a WORKING PAIR of fleets, then stop expanding and pour money into upgrades.
	var growing := owned_fleets < 2 and capital_ready and credits >= TurnResolver.BUY_FLEET_COST
	if growing:
		actions.append({"type": "buy"})
		credits -= TurnResolver.BUY_FLEET_COST
		owned_fleets += 1

	# 2. Reinforcement is the AI's main investment — front-line fleet first.
	var reinforce_target := _fleet_to_reinforce(state, faction)
	if reinforce_target != null:
		var reinforce_cost := TurnResolver.reinforcement_cost(reinforce_target.reinforcement_tier)
		if credits - reinforce_cost >= RESERVE:
			actions.append({"type": "reinforce", "fleet_id": String(reinforce_target.id)})
			credits -= reinforce_cost

	# 3. Combat Training for the front-line fleet — a high-value aim upgrade the AI keeps
	#    climbing (deadlier bots = it can attack on a lower numeric edge). One level a turn.
	if reinforce_target != null \
			and reinforce_target.combat_training_level < TurnResolver.MAX_COMBAT_TRAINING:
		var train_cost := TurnResolver.combat_training_cost(reinforce_target.combat_training_level)
		if credits - train_cost >= RESERVE:
			actions.append({"type": "train", "fleet_id": String(reinforce_target.id)})
			credits -= train_cost

	# 4. A second reinforcement in the same turn when the treasury is deep — keep pouring
	#    credits into the front-line fleet rather than hoarding.
	if reinforce_target != null:
		var next_cost := TurnResolver.reinforcement_cost(reinforce_target.reinforcement_tier + 1)
		if reinforce_target.reinforcement_tier + 1 < TurnResolver.MAX_REINFORCEMENTS \
				and credits - next_cost >= RESERVE + 300:
			actions.append({"type": "reinforce", "fleet_id": String(reinforce_target.id)})
			credits -= next_cost

	# 5. A third fleet only once the pair is well-reinforced and the treasury is deep.
	if not growing and capital_ready and owned_fleets == 2 and best_tier >= 2 \
			and owned_fleets < TurnResolver.MAX_FLEETS \
			and credits >= TurnResolver.BUY_FLEET_COST + 500:
		actions.append({"type": "buy"})
		credits -= TurnResolver.BUY_FLEET_COST

	# One order per un-moved fleet, fleets considered in a stable id order.
	var fleets := state.fleets_owned_by(faction)
	fleets.sort_custom(func(a: Fleet, b: Fleet) -> bool: return String(a.id) < String(b.id))

	var claimed := {}   # planet id -> true, so two fleets never chase the same world

	# 6. Guard the capital, unconditionally. Losing it ends the war, so an empty capital is
	# never an acceptable risk just because a richer target is elsewhere — the ordinary
	# threat check (step 0 in _choose_destination) only reacts once an enemy fleet is
	# within reach, which can be too late for a fleet that then has to travel home from
	# further away. Only fires with a spare fleet (owned_fleets > 1): a lone fleet stays on
	# the normal per-world logic below, since recalling its only fleet could cost the AI a
	# world it could otherwise actually hold.
	var recalled_fleet_id := &""
	if capital_ready and owned_fleets > 1:
		var best_dist := -1
		var best_fleet: Fleet = null
		var best_hop := &""
		for f in fleets:
			if f.has_moved or f.location == capital.id:
				continue
			var bfs := _bfs(state, f.location)
			if not bfs.has(capital.id):
				continue
			var dist := int((bfs[capital.id] as Dictionary)["dist"])
			if best_fleet == null or dist < best_dist \
					or (dist == best_dist and String(f.id) < String(best_fleet.id)):
				best_dist = dist
				best_fleet = f
				best_hop = (bfs[capital.id] as Dictionary)["hop"]
		if best_fleet != null and best_hop != &"":
			recalled_fleet_id = best_fleet.id
			claimed[best_hop] = true
			actions.append({
				"type": "move",
				"fleet_id": String(best_fleet.id),
				"dest": String(best_hop),
			})

	for fleet in fleets:
		if fleet.has_moved or fleet.id == recalled_fleet_id:
			continue
		var dest := _choose_destination(state, faction, fleet, claimed, rng, edge)
		if dest == &"":
			continue
		claimed[dest] = true
		actions.append({
			"type": "move",
			"fleet_id": String(fleet.id),
			"dest": String(dest),
		})
	return actions


static func _choose_destination(
	state: GalaxyState,
	faction: StringName,
	fleet: Fleet,
	claimed: Dictionary,
	rng: RandomNumberGenerator,
	edge: int
) -> StringName:
	var origin: Planet = state.get_planet(fleet.location)
	if origin == null:
		return &""
	var enemy := Faction.opponent(faction)

	# 0. An enemy fleet is close enough to take this world of ours next turn if we vacate it
	#    (adjacent for an ordinary world, two hops for our capital) and no other fleet
	#    guards it — pre-empt with an adjacent attack if we can, otherwise stay and hold.
	if _only_friendly_fleet_here(state, fleet, faction) \
			and _threatened_by_fleet(state, fleet.location, faction):
		return _adjacent_attack(state, faction, fleet, claimed, rng, edge)

	# 1. Adjacent undefended neutral world: walk straight in. Prefer the richest.
	var best_income := -1
	var richest_neutrals: Array = []
	for n in _sorted_ids(origin.connections):
		if claimed.has(n) or state.fleet_at(n, faction) != null:
			continue
		var p: Planet = state.get_planet(n)
		if p == null or p.owner != Faction.NEUTRAL or not p.capturable:
			continue
		if p.income > best_income:
			best_income = p.income
			richest_neutrals = [n]
		elif p.income == best_income:
			richest_neutrals.append(n)
	if not richest_neutrals.is_empty():
		return _pick(richest_neutrals, rng)

	# 2. Adjacent enemy world (or an enemy fleet caught on a hyperlane) we outmatch.
	var strike := _adjacent_attack(state, faction, fleet, claimed, rng, edge)
	if strike != &"":
		return strike

	# 3. Sitting on one of our own worlds that borders enemy territory: hold the line rather
	#    than wander off. An interior world — every neighbour ours — is safe to leave.
	if _is_exposed(state, fleet.location, faction):
		return &""

	# 4. Nothing adjacent is worth doing. Score every reachable world by value over
	#    distance — undefended neutrals, soft enemy garrisons this fleet can take, and our
	#    own exposed unguarded worlds — and take the first hop toward the best.
	var scan := _best_reachable(state, faction, fleet, claimed, rng, edge)
	if scan != &"":
		return scan

	# 5. Otherwise just advance one hop toward the nearest enemy world.
	var hop := _step_toward_enemy(state, fleet.location, enemy, claimed)
	if hop != &"" and state.fleet_at(hop, faction) != null:
		return &""   # the road ahead is blocked by our own fleet; wait
	return hop


## Attack the softest adjacent enemy world (or an enemy fleet caught on a lane) this fleet
## outmatches — "soft" counts the defenders' reinforcement / Combat Training edge. &"" if
## nothing adjacent is worth the fight.
static func _adjacent_attack(
	state: GalaxyState,
	faction: StringName,
	fleet: Fleet,
	claimed: Dictionary,
	rng: RandomNumberGenerator,
	edge: int
) -> StringName:
	var origin: Planet = state.get_planet(fleet.location)
	if origin == null:
		return &""
	var enemy := Faction.opponent(faction)
	var candidates: Array = []   ## [id, effective defence]
	for n in _sorted_ids(origin.connections):
		if claimed.has(n):
			continue
		var p: Planet = state.get_planet(n)
		if p == null:
			continue
		var is_target := p.owner == enemy or (not p.capturable and _has_enemy_fleet(state, n, faction))
		if not is_target:
			continue
		var defence := TurnResolver.defender_strength(state, n)
		var defence_edge := _defence_kit_edge(state, n, faction)
		var garrison_only := p.capturable and not _has_enemy_fleet(state, n, faction)
		if not _worth_attacking(fleet, defence, defence_edge, garrison_only, edge):
			continue
		candidates.append([n, defence + defence_edge])
	if candidates.is_empty():
		return &""
	var softest := 0x7FFFFFFF
	for c in candidates:
		softest = mini(softest, int(c[1]))
	var soft_targets: Array = []
	for c in candidates:
		if int(c[1]) <= softest + DEFENCE_TIE_TOLERANCE:
			soft_targets.append(c[0])
	return _pick(soft_targets, rng)


static func _only_friendly_fleet_here(state: GalaxyState, fleet: Fleet, faction: StringName) -> bool:
	var count := 0
	for f in state.fleets_at(fleet.location):
		if f.owner == faction:
			count += 1
	return count <= 1


## Could a mobile enemy force take this world of ours next turn? True if an enemy fleet is
## within one hop (two for our capital) of it.
static func _threatened_by_fleet(state: GalaxyState, planet_id: StringName, faction: StringName) -> bool:
	var p: Planet = state.get_planet(planet_id)
	if p == null or not p.capturable:
		return false
	var enemy := Faction.opponent(faction)
	var reach := 2 if p.capital_faction == faction else 1
	var bfs := _bfs(state, planet_id)
	for f in state.fleets.values():
		if f.owner == enemy and bfs.has(f.location) and int(bfs[f.location]["dist"]) <= reach:
			return true
	return false


## BFS over the hyperlane graph. Returns id -> { dist, hop } where `hop` is the first step
## on a shortest path from `from_id` to that world (&"" for `from_id` itself).
static func _bfs(state: GalaxyState, from_id: StringName) -> Dictionary:
	var out := {from_id: {"dist": 0, "hop": &""}}
	var frontier: Array = [from_id]
	while not frontier.is_empty():
		var cur: StringName = frontier.pop_front()
		var cp: Planet = state.get_planet(cur)
		if cp == null:
			continue
		var cur_info: Dictionary = out[cur]
		for n in _sorted_ids(cp.connections):
			if out.has(n) or state.get_planet(n) == null:
				continue
			out[n] = {
				"dist": int(cur_info["dist"]) + 1,
				"hop": n if cur == from_id else cur_info["hop"],
			}
			frontier.append(n)
	return out


## Does this world of ours border the front? True if a neighbour is an enemy-held world or
## holds an enemy fleet. An all-friendly interior world is not, and is safe to leave.
static func _is_exposed(state: GalaxyState, planet_id: StringName, faction: StringName) -> bool:
	var p: Planet = state.get_planet(planet_id)
	if p == null or not p.capturable:
		return false
	var enemy := Faction.opponent(faction)
	for n in p.connections:
		var np: Planet = state.get_planet(n)
		if np == null:
			continue
		if np.capturable and np.owner == enemy:
			return true
		if _has_enemy_fleet(state, n, faction):
			return true
	return false


## Score every reachable world by value / (distance + 1) and return the first hop toward
## the best: undefended neutrals, soft enemy garrisons this fleet can actually take, and
## our own exposed unguarded worlds (march a fleet home to hold them).
static func _best_reachable(
	state: GalaxyState,
	faction: StringName,
	fleet: Fleet,
	claimed: Dictionary,
	rng: RandomNumberGenerator,
	edge: int
) -> StringName:
	var enemy := Faction.opponent(faction)
	var reach := _bfs(state, fleet.location)
	var scored: Array = []   ## [hop, score], score > 0 only
	for id in _sorted_ids(reach.keys()):
		var info: Dictionary = reach[id]
		var hop: StringName = info["hop"]
		if hop == &"" or claimed.has(hop) or state.fleet_at(hop, faction) != null:
			continue
		var tp: Planet = state.get_planet(id)
		if tp == null or not tp.capturable:
			continue
		var dist := int(info["dist"])
		var score := 0.0
		if tp.owner == faction:
			if _is_exposed(state, id, faction) and state.fleet_at(id, faction) == null:
				score = float(tp.income + 60) / float(dist + 1)
		elif tp.owner == Faction.NEUTRAL:
			if state.fleet_at(id, faction) == null:
				score = float(tp.income + 40) / float(dist + 1)
		elif tp.owner == enemy:
			var garrison_only := not _has_enemy_fleet(state, id, faction)
			var defence := TurnResolver.defender_strength(state, id)
			var d_edge := _defence_kit_edge(state, id, faction)
			if _worth_attacking(fleet, defence, d_edge, garrison_only, edge):
				var undef := 45 if garrison_only else 0
				score = float(tp.income + undef - defence * 5 - d_edge * 4) / float(dist + 1)
		if score > 0.0:
			scored.append([hop, score])
	if scored.is_empty():
		return &""
	var best := 0.0
	for pair in scored:
		best = maxf(best, float(pair[1]))
	var picks: Array = []
	for pair in scored:
		if float(pair[1]) >= best * (1.0 - SCORE_TIE_TOLERANCE) and not picks.has(pair[0]):
			picks.append(pair[0])
	return _pick(picks, rng)


## Breadth-first search for the first hop on a shortest path to any enemy-held world.
static func _step_toward_enemy(
	state: GalaxyState,
	from_id: StringName,
	enemy: StringName,
	claimed: Dictionary
) -> StringName:
	var came_from := {from_id: from_id}
	var frontier: Array = [from_id]
	var goal := &""
	while not frontier.is_empty():
		var cur: StringName = frontier.pop_front()
		var cp: Planet = state.get_planet(cur)
		if cp == null:
			continue
		if cur != from_id and cp.owner == enemy:
			goal = cur
			break
		for n in _sorted_ids(cp.connections):
			if not came_from.has(n) and state.get_planet(n) != null:
				came_from[n] = cur
				frontier.append(n)
	if goal == &"":
		return &""

	var step: StringName = goal
	while came_from[step] != from_id:
		step = came_from[step]
	if claimed.has(step):
		return &""
	return step


static func _has_enemy_fleet(state: GalaxyState, planet_id: StringName, faction: StringName) -> bool:
	for f in state.fleets_at(planet_id):
		if f.owner != faction:
			return true
	return false


## Which fleet to pour reinforcements into: a front-line fleet (one poised to fight an
## enemy) first, so the AI kits up where the battle will be, otherwise its strongest fleet.
## Both skip fleets already at the cap; ties break on fleet id for determinism.
static func _fleet_to_reinforce(state: GalaxyState, faction: StringName) -> Fleet:
	var enemy := Faction.opponent(faction)
	var frontline: Fleet = null
	var strongest: Fleet = null
	for f in state.fleets_owned_by(faction):
		if f.reinforcement_tier >= TurnResolver.MAX_REINFORCEMENTS:
			continue
		if strongest == null or f.strength > strongest.strength \
				or (f.strength == strongest.strength and String(f.id) < String(strongest.id)):
			strongest = f
		if _is_frontline(state, f, enemy) and (frontline == null or f.strength > frontline.strength \
				or (f.strength == frontline.strength and String(f.id) < String(frontline.id))):
			frontline = f
	return frontline if frontline != null else strongest


## Is this fleet sitting next to an enemy world, or a lane an enemy fleet is on?
static func _is_frontline(state: GalaxyState, fleet: Fleet, enemy: StringName) -> bool:
	var origin: Planet = state.get_planet(fleet.location)
	if origin == null:
		return false
	for n in origin.connections:
		var p: Planet = state.get_planet(n)
		if p == null:
			continue
		if p.owner == enemy:
			return true
		if not p.capturable and _has_enemy_fleet(state, n, fleet.owner):
			return true
	return false


static func _pick(options: Array, rng: RandomNumberGenerator) -> StringName:
	if options.size() == 1:
		return options[0]
	return options[rng.randi() % options.size()]


static func _sorted_ids(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		out.append(i)
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return out
