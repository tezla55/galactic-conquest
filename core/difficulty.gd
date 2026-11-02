class_name Difficulty
extends RefCounted

## Campaign difficulty. Two levers on the AI faction's economy (whichever faction the
## player isn't playing — see Faction.opponent): a starting-credit head start, and a
## per-round bonus on top of ordinary income (both paid in TurnResolver) so a harder
## campaign keeps outpacing the player's reinforcement/Combat Training pace all game, not
## just early. AiCommander.AI_ATTACK_EDGE_BY_DIFFICULTY is the other lever — how big an edge
## the AI needs before it presses an attack — but that lives with the AI's own tuning, not
## here. Chosen at new-campaign time, remembered in bridge/difficulty_settings.gd, stored on
## the GalaxyState so a save keeps its setting.

const EASY := &"easy"
const NORMAL := &"normal"
const HARD := &"hard"
const ALL: Array[StringName] = [EASY, NORMAL, HARD]
const DEFAULT := NORMAL


## Bonus credits the AI faction starts the campaign with. Easy: none (a fair start).
static func ai_starting_bonus(level: StringName) -> int:
	match level:
		HARD:
			return 1000
		NORMAL:
			return 600
	return 0


## Bonus credits the AI faction earns on top of ordinary income every round (GalaxyState.
## income_for already runs the same for both sides) — a recurring edge so a harder AI keeps
## reinforcing/training faster all campaign, not just off a bigger opening bank.
static func ai_income_bonus(level: StringName) -> int:
	match level:
		HARD:
			return 150
		NORMAL:
			return 75
	return 0


static func display_name(level: StringName) -> String:
	match level:
		EASY:
			return "Easy"
		HARD:
			return "Hard"
	return "Normal"


static func blurb(level: StringName) -> String:
	match level:
		EASY:
			return "Both sides start even."
		HARD:
			return "The AI starts with more bonus credits, and also acts more aggressive."
	return "The AI starts with some bonus credits."


static func normalise(level: StringName) -> StringName:
	return level if level in ALL else DEFAULT
