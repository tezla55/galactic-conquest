class_name CampaignDef
extends RefCounted

## One playable campaign — an era, its two factions, and where its map data lives. Pure
## data read from data/campaigns.json by bridge/content_loader.gd; core/ never does the
## file I/O itself.

var id: StringName = &""
var display_name: String = ""
var era: StringName = &""
var factions: Array[StringName] = []      ## exactly two — [light_side, dark_side] order not assumed
var light_side: StringName = &""          ## the faction that is KYBER Team 1 on its levels
var planets_path: String = ""             ## res:// path to this campaign's planets.json
var maps_path: String = ""                ## res:// path to this campaign's maps.json


static func from_dict(d: Dictionary) -> CampaignDef:
	var c := CampaignDef.new()
	c.id = StringName(d.get("id", ""))
	c.display_name = String(d.get("display_name", ""))
	c.era = StringName(d.get("era", ""))
	for f in d.get("factions", []):
		c.factions.append(StringName(f))
	c.light_side = StringName(d.get("light_side", c.factions[0] if not c.factions.is_empty() else ""))
	c.planets_path = String(d.get("planets", ""))
	c.maps_path = String(d.get("maps", ""))
	return c


## The other of this campaign's two factions.
func other_faction(faction: StringName) -> StringName:
	for f in factions:
		if f != faction:
			return f
	return Faction.NEUTRAL
