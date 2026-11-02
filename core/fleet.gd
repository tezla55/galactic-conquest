class_name Fleet
extends RefCounted

## An army group. Strength is the only combat statistic: it sets the attacker's
## bot count in the Battlefront match. Keep it small and legible — 1 to 10 — because
## every point has to survive translation into a setting KYBER can actually express.

const MIN_STRENGTH := 1
const MAX_STRENGTH := 10

## Highest reinforcement tier any fleet can reach. Mirrors TurnResolver.MAX_REINFORCEMENTS;
## kept here too so from_dict can clamp without a cross-class reference in core/.
const MAX_REINFORCEMENT_TIER := 3

## Highest Combat Training level. Mirrors TurnResolver.MAX_COMBAT_TRAINING.
## `2026-09-21` (playtest 921): a 4th level (0..3) — the last step costs far more than a
## straight line would (see TurnResolver.combat_training_cost) for a sharper top-end aim.
const MAX_COMBAT_TRAINING := 3

var id: StringName = &""
var owner: StringName = Faction.NEUTRAL
var location: StringName = &""   ## Planet id the fleet currently occupies.
var strength: int = 1
var has_moved: bool = false      ## Reset at the start of each turn.

## How much this fleet has invested in reinforcements (0..MAX_REINFORCEMENT_TIER). Sets
## the fleet's bot count in KYBER (bridge/kyber_bridge.gd) — nothing else. Bought per
## fleet; lost with the fleet if it is destroyed.
var reinforcement_tier: int = 0

## Combat Training: a per-fleet aim upgrade with four levels (0..MAX_COMBAT_TRAINING).
## Each level makes this side's bots sharper in the fleet's KYBER matches
## (KyberBridge.team_aim). Independent of reinforcements. Lost with the fleet.
var combat_training_level: int = 0


static func from_dict(d: Dictionary) -> Fleet:
	var f := Fleet.new()
	f.id = StringName(d.get("id", ""))
	f.owner = StringName(d.get("owner", Faction.NEUTRAL))
	f.location = StringName(d.get("location", ""))
	f.strength = clampi(int(d.get("strength", 1)), MIN_STRENGTH, MAX_STRENGTH)
	f.has_moved = bool(d.get("has_moved", false))
	f.reinforcement_tier = clampi(int(d.get("reinforcement_tier", 0)), 0, MAX_REINFORCEMENT_TIER)
	# Accept the old bool "combat_training" key from pre-3-level saves.
	var training: int = int(d.get("combat_training_level", int(bool(d.get("combat_training", false)))))
	f.combat_training_level = clampi(training, 0, MAX_COMBAT_TRAINING)
	return f


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"owner": String(owner),
		"location": String(location),
		"strength": strength,
		"has_moved": has_moved,
		"reinforcement_tier": reinforcement_tier,
		"combat_training_level": combat_training_level,
	}


func copy() -> Fleet:
	return Fleet.from_dict(to_dict())


func is_destroyed() -> bool:
	return strength < MIN_STRENGTH


func apply_losses(amount: int) -> void:
	strength = maxi(0, strength - maxi(0, amount))
