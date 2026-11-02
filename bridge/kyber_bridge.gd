class_name KyberBridge
extends RefCounted

## Turns a Battle.Request into something KYBER can run, and nothing else. It does not
## decide who wins, it does not touch GalaxyState, and it does not guess at formats it
## has not seen.
##
## KYBER's server is configured through environment variables. The one that matters here
## is KYBER_MAP_ROTATION: base64 of newline-delimited "<frostbite_mode>;<level_path>"
## lines ('#' and blank lines skipped), per KYBER's CLI source
## (CLI/lib/commands/start_server_command.dart). RotationEncoder builds it.
##
## The FORMAT is known, but the real mode/level strings for our five planets are not —
## data/maps.json still holds PLACEHOLDER values, so `build_launch_spec` refuses to
## produce a rotation until `schema_verified` is set. See docs/KYBER_MAPPING.md.

const IMAGE := "ghcr.io/armchairdevelopers/kyber-server:latest"

## Campaign strength (1-10) maps onto bot counts. KYBER_SERVER_MAX_PLAYERS accepts
## 1-64; the game's own default limit is 40, so keep both sides inside that.
const BOTS_BASE := 4
const BOTS_PER_STRENGTH := 2
const BOTS_MAX := 20

## Bot counts are per MODE (each mode has a real headcount; more bots just crowd the map).
## `MODE_BOTS[mode] = [floor, per_tier, cap]`. A side's count is
## `clamp(floor + reinforcement_tier * per_tier, floor, cap)` — a garrison (no fleet) is
## `floor`. **Home worlds get NO bonus**: the count reflects the force present, so a
## more-upgraded attacker out-bots a lightly-held home instead of the home always winning
## the count. (A home falling still ends the war — that's the stakes, not a thumb on the
## headcount.) Caps the user asked for: GA 24v24, Blast 20v20, Extraction ~8→12.
##
## `coop` is the human-eligible team's real 8-slot ceiling (`2026-10-29`): 8 requested
## slots minus the human matches the live 8-slot cap, so the player gets 7 AI teammates
## instead of the old flat 4v4's 3. A single-player co-op's AI-only enemy team scales
## 8 / 10 / 12 / 14 by the enemy fleet's reinforcement tier, via `coop_enemy_bots` — see
## the balance comment on that helper.
const MODE_BOTS := {
	"galactic_assault": [20, 4, 24],
	"blast": [14, 3, 20],
	"extraction": [8, 2, 12],
	"coop": [8, 0, 8],
	"supremacy": [20, 4, 32],
	"capital_supremacy": [20, 4, 32],
}
const MODE_BOTS_DEFAULT := [20, 4, 32]
const KYBER_BOTS_PER_TIER := 4        ## kept for the legacy LaunchSpec path only

## Single-player CO-OP balance (`2026-10-30` playtest): the human-eligible team keeps its
## real 8-slot ceiling (7 AI + you after the human slot is reserved). The AI-only enemy
## team now scales 8 / 10 / 12 / 14 for reinforcement levels 1-4, so upgrading the enemy
## fleet is felt as a real headcount advantage (the old 6 / 7 / 8 / 8 was too easy).
## Two-player co-op (a human on each side) stays symmetric 8/8.
const COOP_PLAYER_BOTS := 8
const COOP_ENEMY_BOTS: Array[int] = [8, 10, 12, 14]

## Bot aim-noise (AutoPlayers.AimNoiseScaleTeam1 / Team2 — LOWER is deadlier; the plugin
## sends a per-team value). Indexed by that fleet's Combat Training level (0..3,
## TurnResolver.buy_combat_training):
##   * the PLAYER's team  — 2.5 / 2.0 / 1.5 / 1.0   (sloppier: the human is carrying the fight)
##   * the ENEMY AI team  — 1.75 / 1.25 / 0.75 / 0.25 (deadlier, to even out a bot-vs-bot side)
## Level 3 (`2026-09-21`, playtest 921) keeps the same 0.5-per-level step as the levels below it.
const KYBER_AIM_PLAYER := [2.5, 2.0, 1.5, 1.0]
const KYBER_AIM_ENEMY := [1.75, 1.25, 0.75, 0.25]
## Single-player CO-OP's human side cannot use special units or heroes, and its bot
## teammates were losing every trade even after Combat Training. They get a separate,
## much deadlier curve (lower = more accurate), sharper than the AI enemy at equal tiers
## until both reach the floor at the top level.
const KYBER_AIM_COOP_PLAYER := [1.1, 0.8, 0.5, 0.25]

## Bot HERO spawn probability (`AutoPlayers.HeroSpawnProbability_Gameplay`, 0..1 — the plugin's
## `heroprob` verb). `2026-09-19` playtest: "no heroes currently spawn as AI". It starts LOW
## and climbs with each reinforcement tier the AI's fleet has bought (so upgrading the enemy
## is felt as tougher opposition, not just more bots); a two-player war has no AI fleet to
## key off, so it sits at a fixed, reasonably high value for both humans' bot teammates/foes.
const HERO_PROB_BASE := 0.04
const HERO_PROB_PER_TIER := 0.10
const HERO_PROB_TWO_PLAYER := 0.30


## The AI side's reinforcement tier in this battle: the attacker's if the AI attacks, else the
## defending fleet's (0 for a garrison-only defence, which has no fleet to upgrade).
static func hero_spawn_probability(ai_reinforcement_tier: int, two_player: bool = false) -> float:
	if two_player:
		return HERO_PROB_TWO_PLAYER
	return clampf(HERO_PROB_BASE + HERO_PROB_PER_TIER * maxi(0, ai_reinforcement_tier), 0.0, 1.0)


## Battle-Point manipulation does not work in this KYBER build (verified in-game). The
## campaign reaches a match only through bot COUNT (reinforcement tier) and per-team bot
## AIM (reinforcement tier again). There is no unit-buying system any more.

## No time / kill-margin auto-end — every battle runs to the game's own finish.
const KYBER_MATCH_MAX_S := 0
const KYBER_MATCH_MARGIN := 0


class LaunchSpec extends RefCounted:
	var ok: bool = false
	var reason: String = ""
	var request_id: String = ""
	var map_key: String = ""
	var mode: String = ""
	var attacker_bots: int = 0
	var defender_bots: int = 0
	var max_players: int = 40
	var rotation_base64: String = ""
	var env: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"reason": reason,
			"request_id": request_id,
			"map_key": map_key,
			"mode": mode,
			"attacker_bots": attacker_bots,
			"defender_bots": defender_bots,
			"max_players": max_players,
			"rotation_base64": rotation_base64,
			"env": env,
		}


static func bots_for_strength(strength: int) -> int:
	return clampi(BOTS_BASE + strength * BOTS_PER_STRENGTH, BOTS_BASE, BOTS_MAX)


static func _mode_bots(mode: String) -> Array:
	return MODE_BOTS.get(mode, MODE_BOTS_DEFAULT)


## Bots a fielded fleet brings to `mode` at `reinforcement_tier` — `floor + tier * per_tier`,
## clamped to the mode's `[floor, cap]`.
static func fleet_bots(reinforcement_tier: int, mode: String = "") -> int:
	var s := _mode_bots(mode)
	return clampi(int(s[0]) + maxi(0, reinforcement_tier) * int(s[1]), int(s[0]), int(s[2]))


## Bots an ordinary-world garrison-only defence fields — the mode's floor. Lighter than a
## fielded fleet in the same mode (whose tiers are its edge). Home worlds go through
## defender_bots instead.
static func garrison_bots(mode: String) -> int:
	return int(_mode_bots(mode)[0])


## The defending side's bot count, from the force present. `is_home` is accepted for the
## caller's convenience but is NOT a bonus (see MODE_BOTS) — a barely-held home should not
## win the headcount against a more-upgraded attacker.
static func defender_bots(has_fleet: bool, reinforcement_tier: int, mode: String, _is_home: bool) -> int:
	if has_fleet:
		return fleet_bots(reinforcement_tier, mode)
	return garrison_bots(mode)


## Single-player co-op's AI-only enemy team: 8 at reinforcement level 1, then 10 / 12 / 14
## for levels 2-4. The human side always requests COOP_PLAYER_BOTS; `reserve_human_slots`
## then turns that into 7 AI + the player.
static func coop_enemy_bots(reinforcement_tier: int) -> int:
	return COOP_ENEMY_BOTS[clampi(reinforcement_tier, 0, COOP_ENEMY_BOTS.size() - 1)]


## A real player takes a slot an AI would have had (`2026-09-20`, playtest 920): a 24v24 match
## is 23 AI + the human vs 24 AI, so the headcount stays even. `humans_tN` = how many humans
## sit on team N (single player: 1 on the player's team; online: 1 on each; local hotseat: 1
## on the seat at the controls). Never drops a team below one bot.
static func reserve_human_slots(bots_t1: int, bots_t2: int, humans_t1: int, humans_t2: int) -> Array[int]:
	return [maxi(1, bots_t1 - humans_t1), maxi(1, bots_t2 - humans_t2)]


## The aim-noise for one team: the player's team is normally sloppier than the AI enemy's;
## each Combat Training level on that side's fleet sharpens it one step. CO-OP's player side
## uses its own much sharper table instead (see KYBER_AIM_COOP_PLAYER).
static func team_aim(is_player_team: bool, training_level: int, coop: bool = false) -> float:
	var table: Array
	if is_player_team and coop:
		table = KYBER_AIM_COOP_PLAYER
	else:
		table = KYBER_AIM_PLAYER if is_player_team else KYBER_AIM_ENEMY
	return float(table[clampi(training_level, 0, table.size() - 1)])


## Pick which Battlefront map+mode hosts this battle. Deterministic — the situation alone
## decides it, so a replayed campaign produces a replayable war.
##
##   Space lane   → the CO-OP capital ship of the side being assaulted (defender_faction).
##   Home world   → Galactic Assault, always (fleet or garrison — the fleet only raises
##                  the bot count).
##   Otherwise    → score every catalog entry for this planet against the situation and
##                  take the best fit. An entry carries `trigger` ("fleet" = the defender
##                  brought a fleet, "garrison" = only a garrison, "any" = either) and an
##                  optional `held_by` (applies only when the defender holds the world).
##                  Per-planet mode rules therefore live entirely in data/campaigns/<id>/
##                  maps.json — no faction/planet names hardcoded here.
static func choose_map_key(request: Battle.Request, planet: Planet, catalog: Dictionary = {},
		player_faction: StringName = Faction.REPUBLIC, offline: bool = false) -> String:
	if planet.map_pool.is_empty():
		return ""

	# Space lane. Clone Wars: a capital-ship boarding co-op — the map is the DEFENDER's ship
	# (defender_faction), the mode is by the PLAYER's role: coop_role "attack" (Mode9, the
	# player boards) when the player is the attacker, "defend" (ModeDefend, the player is
	# boarded) otherwise. GCW: a Blast on one of the two adjacent planets — the player's pick
	# (request.lane_map_key), else the first pool entry that resolves.
	if not planet.capturable:
		# Offline (hand-set Arcade / Instant Action) a lane is a capital-ship co-op even in
		# GCW, whose KYBER lane battle is a Blast: the defender's ship, the player's role.
		if offline:
			var coop_key := _lane_coop_key(request, catalog, player_faction)
			if coop_key != "":
				return coop_key
		if request.lane_map_key != "" and planet.map_pool.has(request.lane_map_key):
			return request.lane_map_key
		var want_role := "attack" if player_faction == request.attacker else "defend"
		for key in planet.map_pool:
			var e := ContentLoader.find_map(catalog, key)
			if String(e.get("defender_faction", "")) != String(request.defender):
				continue
			if not e.has("coop_role") or String(e.get("coop_role", "")) == want_role:
				return key
		for key2 in planet.map_pool:
			if not ContentLoader.find_map(catalog, key2).is_empty():
				return key2
		return planet.map_pool[0]

	# A home world is always Galactic Assault.
	if planet.home_defence:
		for m in catalog.get("maps", []):
			if String(m.get("planet", "")) == String(planet.id) and String(m.get("mode", "")) == "galactic_assault":
				return String(m.get("key", ""))

	var is_fleet_battle := request.defender_fleet_strength > 0
	var defender := String(request.defender)
	var best_key := ""
	var best_score := -1
	for m in catalog.get("maps", []):
		if String(m.get("planet", "")) != String(planet.id):
			continue
		var score := _score_map_entry(m, is_fleet_battle, defender)
		if score > best_score:
			best_score = score
			best_key = String(m.get("key", ""))
	return best_key if best_key != "" else planet.map_pool[0]


## The capital-ship co-op entry (coop_role + defender_faction, no planet) for a lane, from the
## PLAYER's role. "" if the campaign's catalog has none for this defender.
static func _lane_coop_key(request: Battle.Request, catalog: Dictionary, player_faction: StringName) -> String:
	var want_role := "attack" if player_faction == request.attacker else "defend"
	for m in catalog.get("maps", []):
		if String(m.get("mode", "")) == "coop" and String(m.get("coop_role", "")) == want_role 				and String(m.get("defender_faction", "")) == String(request.defender):
			return String(m.get("key", ""))
	return ""


## How well a maps.json entry fits the current battle. Higher is better; -1 = does not
## apply (its `trigger` contradicts the fleet state, or its `held_by` names the other
## side). Ties break on file order — the first entry wins — so keep the more specific
## entries first in maps.json.
static func _score_map_entry(m: Dictionary, is_fleet_battle: bool, defender: String) -> int:
	var score := 0
	match String(m.get("trigger", "any")):
		"fleet":
			if not is_fleet_battle:
				return -1
			score += 4
		"garrison":
			if is_fleet_battle:
				return -1
			score += 4
		"lane":
			return -1   # only offered as a GCW space-lane Blast option, never a planet battle
		_:
			score += 2   # "any" (or unset)
	var held := String(m.get("held_by", ""))
	if held != "":
		if held != defender:
			return -1
		score += 1
	return score


## The situational map, with the Supremacy stand-in already applied when its real strings
## are not captured yet. Returns { key, entry, fallback_from } (fallback_from = "" when the
## situational map was used directly). Both build_briefing and match_params go through here.
static func resolve_map(request: Battle.Request, planet: Planet, catalog: Dictionary,
		player_faction: StringName = Faction.REPUBLIC, offline: bool = false) -> Dictionary:
	var key := choose_map_key(request, planet, catalog, player_faction, offline)
	var entry := ContentLoader.find_map(catalog, key)
	var fallback_from := ""
	if _is_placeholder(entry):
		var supr := _planet_supremacy_key(planet, catalog)
		if supr != "" and supr != key:
			fallback_from = mode_display_name(String(entry.get("mode", "")))
			key = supr
			entry = ContentLoader.find_map(catalog, key)
	return {"key": key, "entry": entry, "fallback_from": fallback_from}


## What a human needs in order to set this battle up by hand in the KYBER Launcher.
## Available even while the rotation schema is unverified, because none of it depends on
## knowing KYBER's file formats — it is just the campaign's demands stated in the
## Launcher's own vocabulary. This is what makes the manual bridge possible.
static func build_briefing(request: Battle.Request, planet: Planet, catalog: Dictionary,
		player_faction: StringName = Faction.REPUBLIC, offline: bool = false) -> Dictionary:
	var resolved := resolve_map(request, planet, catalog, player_faction, offline)
	var key: String = resolved["key"]
	var entry: Dictionary = resolved["entry"]
	return {
		"map_key": key,
		"map_name": String(entry.get("display_name", planet.display_name)),
		"mode": String(entry.get("mode", "")),
		"mode_name": mode_display_name(String(entry.get("mode", "")), String(entry.get("coop_role", ""))),
		"fallback_from": String(resolved["fallback_from"]),
		"attacker": Faction.display_name(request.attacker),
		"defender": Faction.display_name(request.defender),
		"attacker_bots": fleet_bots(request.attacker_reinforcement, String(entry.get("mode", ""))),
		"defender_bots": defender_bots(request.defender_fleet_strength > 0, request.defender_reinforcement,
			String(entry.get("mode", "")), planet.home_defence),
		"attacker_reinforcement": request.attacker_reinforcement,
		"defender_reinforcement": request.defender_reinforcement,
		"defender_has_fleet": request.defender_fleet_strength > 0,
	}


## SWBF2 Arcade / Instant Action bot difficulty for a campaign difficulty. The campaign's
## easy/normal/hard already scales the AI economy; this maps it onto the in-game bot
## setting so the manual match stays a real fight. Tier names corrected 2026-09-18 from a
## guessed "Normal/Hard/Master" (vanilla Arcade's own labels) to the real names the user
## reported live from Instant Action's own difficulty menu.
static func arcade_ai_difficulty(campaign_difficulty: StringName) -> String:
	match campaign_difficulty:
		Difficulty.EASY:
			return "Default"
		Difficulty.HARD:
			return "Elite"
	return "Expert"


## Everything a player needs to recreate this battle in Arcade / Instant Action by hand,
## from their point of view (your side / your bots), plus the recommended AI difficulty.
## Offline mode's equivalent of match_params — no KYBER involved.
static func offline_briefing(request: Battle.Request, planet: Planet, catalog: Dictionary,
		player_faction: StringName, campaign_difficulty: StringName) -> Dictionary:
	var resolved := resolve_map(request, planet, catalog, player_faction, true)
	var entry: Dictionary = resolved["entry"]
	var mode := String(entry.get("mode", ""))
	var ok := not _is_placeholder(entry)
	var attacker_bots := fleet_bots(request.attacker_reinforcement, mode)
	var defender_bot_count := defender_bots(request.defender_fleet_strength > 0,
		request.defender_reinforcement, mode, planet.home_defence)
	var player_attacks := String(request.attacker) == String(player_faction)
	var fallback_from := String(resolved["fallback_from"])

	var reason := ""
	if not ok:
		reason = "%s has no verified KYBER map/mode in data/maps.json." % planet.display_name
	elif fallback_from != "":
		reason = "%s (%s) is not captured yet — playing %s as a stand-in." % [
			planet.display_name, fallback_from, mode_display_name(mode)]

	return {
		"ok": ok,
		"reason": reason,
		"fallback_from": fallback_from,
		"map_name": String(entry.get("display_name", planet.display_name)),
		"mode_name": mode_display_name(mode),
		"your_bots": maxi(1, (attacker_bots if player_attacks else defender_bot_count) - 1),   # you take one slot
		"enemy_bots": defender_bot_count if player_attacks else attacker_bots,
		"ai_difficulty": arcade_ai_difficulty(campaign_difficulty),
		"your_side": Faction.display_name(player_faction),
		"enemy_side": Faction.display_name(Faction.opponent(player_faction)),
	}


## The concrete KYBER level path + Frostbite mode for this battle, for GC to send the
## running server as `load <level_path> <frostbite_mode>` over the gc_result plugin.
## Deterministic (same request → same map). ok = false with a reason when the catalog
## entry has no real strings yet.
##
## `two_player`: a local hotseat war has a human on BOTH teams, so the usual "player's bots
## are sloppier, the AI's are sharper" asymmetry (team_aim) doesn't apply — both sides use
## the human/"player" curve, scaled by their own Combat Training same as always. Map/mode
## selection itself is untouched (`player_faction` there just means "whichever side is
## currently at the controls," and only ever needs the ordinary attacker/defender framing).
static func match_params(request: Battle.Request, planet: Planet, catalog: Dictionary,
		player_faction: StringName = Faction.REPUBLIC, two_player: bool = false,
		offline: bool = false) -> Dictionary:
	var resolved := resolve_map(request, planet, catalog, player_faction, offline)
	var key: String = resolved["key"]
	var entry: Dictionary = resolved["entry"]
	var fallback_from: String = resolved["fallback_from"]

	var level_path := String(entry.get("level_path", ""))
	var frostbite_mode := String(entry.get("frostbite_mode", ""))
	var mode := String(entry.get("mode", ""))
	var coop_role := String(entry.get("coop_role", ""))
	var ok := not _is_placeholder(entry) and not level_path.is_empty() and not frostbite_mode.is_empty()

	# Per role (attacker / defender); ui/ maps them onto teams 1/2 via team_one_faction.
	# Reinforcement tier → bot count and per-team aim. BP + unit buying are gone.
	var attacker_bots := fleet_bots(request.attacker_reinforcement, mode)
	var defender_bot_count := defender_bots(request.defender_fleet_strength > 0,
		request.defender_reinforcement, mode, planet.home_defence)
	# Single-player CO-OP: the human side always gets the mode's 8-slot ceiling (7 AI + you
	# after reserve_human_slots), while the AI-only enemy side scales 8/10/12/14 by its
	# fleet's tier. Two-player co-op keeps symmetric 8v8 — both sides have a human.
	if mode == "coop" and not two_player:
		if String(request.attacker) == String(player_faction):
			attacker_bots = COOP_PLAYER_BOTS
			defender_bot_count = coop_enemy_bots(request.defender_reinforcement)
		else:
			attacker_bots = coop_enemy_bots(request.attacker_reinforcement)
			defender_bot_count = COOP_PLAYER_BOTS

	var one_faction := String(entry.get("team_one_faction", Faction.REPUBLIC))
	var one_is_attacker := one_faction == String(request.attacker)
	var aim_attacker := team_aim(two_player or String(request.attacker) == String(player_faction),
		request.attacker_training, mode == "coop")
	var aim_defender := team_aim(two_player or String(request.defender) == String(player_faction),
		request.defender_training, mode == "coop")

	var reason := ""
	if not ok:
		reason = "%s has no verified KYBER map/mode in data/maps.json." % planet.display_name
	elif fallback_from != "":
		reason = "%s (%s) is not captured yet — playing %s as a stand-in." % [
			planet.display_name, fallback_from, mode_display_name(mode)]

	return {
		"ok": ok,
		"reason": reason,
		"fallback": fallback_from != "",
		"map_key": key,
		"map_name": String(entry.get("display_name", planet.display_name)),
		"level_path": level_path,
		"frostbite_mode": frostbite_mode,
		"mode_name": mode_display_name(mode, coop_role),
		"coop_role": coop_role,
		"team_one_faction": one_faction,
		"attacker_bots": attacker_bots,
		"defender_bots": defender_bot_count,
		"hero_probability": hero_spawn_probability(
			request.attacker_reinforcement if String(request.attacker) != String(player_faction)
			else request.defender_reinforcement, two_player),
		"aim_attacker": aim_attacker,
		"aim_defender": aim_defender,
		"aim_t1": aim_attacker if one_is_attacker else aim_defender,
		"aim_t2": aim_defender if one_is_attacker else aim_attacker,
		"match_max_s": KYBER_MATCH_MAX_S,
		"match_margin": KYBER_MATCH_MARGIN,
	}


static func _is_placeholder(entry: Dictionary) -> bool:
	if entry.is_empty():
		return true
	return String(entry.get("level_path", "")).contains("PLACEHOLDER") \
		or String(entry.get("frostbite_mode", "")).contains("PLACEHOLDER")


static func _planet_supremacy_key(planet: Planet, catalog: Dictionary) -> String:
	for m in catalog.get("maps", []):
		if String(m.get("planet", "")) == String(planet.id) and String(m.get("mode", "")) == "supremacy":
			return String(m.get("key", ""))
	return ""


static func mode_display_name(mode: String, coop_role: String = "") -> String:
	match mode:
		"galactic_assault":
			return "Galactic Assault"
		"supremacy", "capital_supremacy":
			return "Supremacy"
		"starfighter_assault":
			return "Starfighter Assault"
		"blast":
			return "Blast"
		"extraction":
			return "Extraction"
		"coop":
			match coop_role:
				"attack":
					return "Co-Op Attack"
				"defend":
					return "Co-Op Defense"
			return "CO-OP"
		"instant_action":
			return "Instant Action"
	return mode


## Assemble everything needed to start a server. Returns a spec with ok = false and a
## reason when the map schema has not been verified — that is the intended behaviour,
## not a bug to work around.
static func build_launch_spec(
	request: Battle.Request,
	planet: Planet,
	catalog: Dictionary,
	server_name: String = "GC Campaign"
) -> LaunchSpec:
	var spec := LaunchSpec.new()
	spec.request_id = request.id

	var key := choose_map_key(request, planet)
	if key.is_empty():
		spec.reason = "%s has no maps in its pool." % planet.display_name
		return spec

	var map_entry := ContentLoader.find_map(catalog, key)
	if map_entry.is_empty():
		spec.reason = "Map key '%s' is not in the catalog." % key
		return spec

	spec.map_key = key
	spec.mode = String(map_entry.get("mode", ""))
	spec.attacker_bots = bots_for_strength(request.attacker_strength)
	spec.defender_bots = bots_for_strength(request.defender_strength)

	if not bool(catalog.get("schema_verified", false)):
		spec.reason = (
			"The map rotation strings have not been verified. Export a rotation from the "
			+ "KYBER Launcher Host tab, decode it to tests/fixtures/map_rotation.txt, "
			+ "replace the PLACEHOLDER frostbite_mode / level_path values in data/maps.json, "
			+ "then set schema_verified to true."
		)
		return spec

	spec.rotation_base64 = RotationEncoder.encode(_build_rotation(map_entry))
	spec.env = {
		"KYBER_SERVER_NAME": server_name.substr(0, 24),
		"KYBER_MAP_ROTATION": spec.rotation_base64,
		"KYBER_SERVER_MAX_PLAYERS": str(spec.max_players),
		"KYBER_LOG_LEVEL": "debug",
	}
	spec.ok = true
	return spec


## The rotation entries for this battle, in RotationEncoder's { "mode", "map" } shape.
## The format is taken from KYBER's CLI source; the strings come from data/maps.json and
## are PLACEHOLDER until schema_verified is set, so this is only reachable once it is.
## Bot counts are not part of a rotation entry in KYBER — they are a separate console
## command — so spec.attacker_bots / defender_bots do not appear here.
static func _build_rotation(map_entry: Dictionary) -> Array:
	return [{
		"mode": map_entry.get("frostbite_mode", ""),
		"map": map_entry.get("level_path", ""),
	}]


## The docker command a spec corresponds to. Returned as an argument array rather than a
## string so it can be handed straight to OS.create_process without shell quoting bugs.
## When the Docker path is built, the gc_result plugin mount and KYBER_SERVER_PLUGINS_PATH
## belong here (-v <plugin_dir>:/plugins -e KYBER_SERVER_PLUGINS_PATH=/plugins). The
## current test target is the KYBER Launcher desktop app, so this stays minimal.
static func docker_args(spec: LaunchSpec, battlefront_path: String, credentials_env: String, token_env: String) -> PackedStringArray:
	var args := PackedStringArray(["run", "--rm"])
	args.append_array(["-e", "MAXIMA_CREDENTIALS=%s" % credentials_env])
	args.append_array(["-e", "KYBER_TOKEN=%s" % token_env])
	for k in spec.env:
		args.append_array(["-e", "%s=%s" % [k, spec.env[k]]])
	args.append_array(["-v", "%s:/mnt/battlefront" % battlefront_path])
	args.append(IMAGE)
	return args
