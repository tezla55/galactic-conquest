class_name Faction
extends RefCounted

## The war's powers, across every campaign. Stored as StringName so state serialises to
## readable JSON. A campaign uses exactly two of these (see core/campaign.gd), always one
## from each fixed pair — Republic↔Separatist (Clone Wars), Empire↔Rebellion (Galactic
## Civil War), First Order↔Resistance (the sequel era).

const REPUBLIC := &"republic"
const SEPARATIST := &"separatist"
const EMPIRE := &"empire"
const REBELLION := &"rebellion"
const FIRST_ORDER := &"first_order"
const RESISTANCE := &"resistance"
const NEUTRAL := &"neutral"

## Every known playable faction. A campaign exposes only its own two; this is for
## validation and 6-way lookups, not for iterating a single campaign's sides.
const ALL: Array[StringName] = [REPUBLIC, SEPARATIST, EMPIRE, REBELLION, FIRST_ORDER, RESISTANCE]


static func display_name(faction: StringName) -> String:
	match faction:
		REPUBLIC:
			return "Galactic Republic"
		SEPARATIST:
			return "Separatist Alliance"
		EMPIRE:
			return "Galactic Empire"
		REBELLION:
			return "Rebel Alliance"
		FIRST_ORDER:
			return "First Order"
		RESISTANCE:
			return "The Resistance"
		NEUTRAL:
			return "Unaligned"
	return "Unknown"


## The one-word name for tight UI (status line, battle labels). NOT
## `display_name().split(" ")[-1]` — that turns both "Separatist Alliance" and "Rebel
## Alliance" into "Alliance", which reads wrong for the CIS in a Clone Wars context.
static func short_name(faction: StringName) -> String:
	match faction:
		REPUBLIC:
			return "Republic"
		SEPARATIST:
			return "CIS"
		EMPIRE:
			return "Empire"
		REBELLION:
			return "Rebels"
		FIRST_ORDER:
			return "First Order"
		RESISTANCE:
			return "Resistance"
		NEUTRAL:
			return "Unaligned"
	return "Unknown"


## The opposing faction within the same campaign. The six factions form three fixed pairs,
## so this needs no campaign context.
static func opponent(faction: StringName) -> StringName:
	match faction:
		REPUBLIC:
			return SEPARATIST
		SEPARATIST:
			return REPUBLIC
		EMPIRE:
			return REBELLION
		REBELLION:
			return EMPIRE
		FIRST_ORDER:
			return RESISTANCE
		RESISTANCE:
			return FIRST_ORDER
	return NEUTRAL


static func is_playable(faction: StringName) -> bool:
	return faction in ALL


## SWBF2's fixed team layout, independent of campaign: Team 1 is the light side,
## Team 2 the dark side. This is what the co-op team pin and the `coopdef` line use.
static func is_light_side(faction: StringName) -> bool:
	return faction == REPUBLIC or faction == REBELLION or faction == RESISTANCE


static func is_dark_side(faction: StringName) -> bool:
	return faction == SEPARATIST or faction == EMPIRE or faction == FIRST_ORDER


## 1 for the light side, 2 for the dark side, 0 for neutral/unknown.
static func team_side(faction: StringName) -> int:
	if is_light_side(faction):
		return 1
	if is_dark_side(faction):
		return 2
	return 0
