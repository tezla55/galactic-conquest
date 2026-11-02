class_name Planet
extends RefCounted

## A world on the galactic map. One planet maps to one or more real Battlefront II
## locations; see data/planets.json and bridge/map_catalog.gd.

var id: StringName = &""
var display_name: String = ""
var owner: StringName = Faction.NEUTRAL
var capital_faction: StringName = &""   ## Which faction calls this world its capital, or &"" for none.
var capturable: bool = true    ## False for space lanes — transit nodes nobody can own.
var income: int = 0            ## Credits contributed to its owner each turn.
var garrison: int = 0          ## Defensive strength. Drives defender bot count.
## A "home" world stays a real fight even when only a garrison defends it — it is exempt
## from the rule that a garrison-only defence hands the attacker a bot-count advantage.
var home_defence: bool = false
var connections: Array[StringName] = []   ## Hyperlane neighbours, by planet id.
var map_pool: Array[String] = []          ## Keys into the KYBER map catalog.
var position: Vector2 = Vector2.ZERO      ## Galactic map placement, in arbitrary units.


static func from_dict(d: Dictionary) -> Planet:
	var p := Planet.new()
	p.id = StringName(d.get("id", ""))
	p.display_name = String(d.get("display_name", ""))
	p.owner = StringName(d.get("owner", Faction.NEUTRAL))
	p.capital_faction = StringName(d.get("capital_faction", ""))
	p.capturable = bool(d.get("capturable", true))
	p.income = int(d.get("income", 0))
	p.garrison = int(d.get("garrison", 0))
	p.home_defence = bool(d.get("home_defence", false))
	p.position = Vector2(
		float(d.get("x", 0.0)),
		float(d.get("y", 0.0))
	)
	for c in d.get("connections", []):
		p.connections.append(StringName(c))
	for m in d.get("map_pool", []):
		p.map_pool.append(String(m))
	return p


func to_dict() -> Dictionary:
	var conns: Array = []
	for c in connections:
		conns.append(String(c))
	var maps: Array = []
	for m in map_pool:
		maps.append(m)
	return {
		"id": String(id),
		"display_name": display_name,
		"owner": String(owner),
		"capital_faction": String(capital_faction),
		"capturable": capturable,
		"income": income,
		"garrison": garrison,
		"home_defence": home_defence,
		"x": position.x,
		"y": position.y,
		"connections": conns,
		"map_pool": maps,
	}


func copy() -> Planet:
	return Planet.from_dict(to_dict())


func is_connected_to(other_id: StringName) -> bool:
	return connections.has(other_id)
