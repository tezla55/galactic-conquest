class_name ContentLoader
extends RefCounted

## Reads static content off disk and hands core/ plain objects. This lives in bridge/
## rather than core/ because it does file I/O.
##
## Content is per-campaign: data/campaigns.json indexes each campaign to its own
## planets.json + maps.json under data/campaigns/<id>/.

const CAMPAIGNS_PATH := "res://data/campaigns.json"
const DEFAULT_CAMPAIGN := &"clone_wars"


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s did not contain a JSON object." % path)
		return {}
	return parsed


# --- campaigns --------------------------------------------------------------

## Every playable campaign, in file order (Clone Wars first).
static func load_campaigns() -> Array[CampaignDef]:
	var out: Array[CampaignDef] = []
	for cd in _read_json(CAMPAIGNS_PATH).get("campaigns", []):
		out.append(CampaignDef.from_dict(cd))
	return out


## One campaign by id, or the default (Clone Wars) if the id is unknown.
static func campaign_def(campaign_id: StringName) -> CampaignDef:
	var all := load_campaigns()
	for c in all:
		if c.id == campaign_id:
			return c
	for c in all:
		if c.id == DEFAULT_CAMPAIGN:
			return c
	return all[0] if not all.is_empty() else CampaignDef.new()


# --- a fresh campaign ------------------------------------------------------

## Build a fresh campaign from its planets file. `seed` fixes the AI's determinism for the
## whole playthrough; pass a random value for a varied game, a constant one for tests.
## `difficulty` seeds the AI faction with bonus starting credits (Difficulty).
## `two_player`: a local hotseat war — both `player_faction` and its opponent are
## human-controlled (see TurnResolver.end_turn). No AI exists to give a starting-credit
## bonus to or hand an opening move, so both are skipped regardless of `difficulty` /
## `ai_opening` — the two sides start perfectly even.
static func new_campaign(campaign_id: StringName = DEFAULT_CAMPAIGN,
		player_faction: StringName = Faction.REPUBLIC, seed: int = 0,
		difficulty: StringName = Difficulty.DEFAULT, ai_opening := true,
		two_player := false) -> GalaxyState:
	var cd := campaign_def(campaign_id)
	var data := _read_json(cd.planets_path)
	var state := GalaxyState.new()
	state.campaign_id = cd.id
	state.player_faction = player_faction
	state.active_faction = player_faction
	state.campaign_seed = seed
	state.difficulty = Difficulty.normalise(difficulty)
	state.two_player = two_player
	var ai_faction := Faction.opponent(player_faction)
	state.credits = {player_faction: 0, ai_faction: 0}
	if not two_player:
		state.credits[ai_faction] = Difficulty.ai_starting_bonus(state.difficulty)
	for pd in data.get("planets", []):
		state.add_planet(Planet.from_dict(pd))
	for fd in data.get("starting_fleets", []):
		state.spawn_fleet(
			StringName(fd.get("owner", Faction.NEUTRAL)),
			StringName(fd.get("location", "")),
			int(fd.get("strength", 1))
		)

	# 50/50 (seeded): the enemy takes the opening move before the player's first turn.
	if ai_opening and not two_player:
		if ai_takes_opening(seed):
			TurnResolver.run_ai_opening(state, seed + state.turn)

	return state


## The seeded 50/50 coin flip that hands the enemy the opening move. Its own function so the
## UI can pass `ai_opening := false` to new_campaign, show the starting board, and THEN run
## `TurnResolver.run_ai_opening(state, seed + state.turn)` itself — the player watching the
## enemy fleets actually move — while still getting exactly the flip new_campaign would have.
static func ai_takes_opening(seed: int) -> bool:
	var coin := RandomNumberGenerator.new()
	coin.seed = seed
	return coin.randi() % 2 == 0


# --- the map catalog -----------------------------------------------------

static func load_map_catalog(campaign_id: StringName = DEFAULT_CAMPAIGN) -> Dictionary:
	return _read_json(campaign_def(campaign_id).maps_path)


## True only once the placeholder KYBER identifiers have been replaced with real ones
## captured from an exported map rotation.
static func map_schema_verified(campaign_id: StringName = DEFAULT_CAMPAIGN) -> bool:
	return bool(load_map_catalog(campaign_id).get("schema_verified", false))


static func find_map(catalog: Dictionary, key: String) -> Dictionary:
	for m in catalog.get("maps", []):
		if String(m.get("key", "")) == key:
			return m
	return {}
