class_name FactionSettings
extends RefCounted

## The player's chosen side, remembered in user://faction.cfg so a new campaign starts on
## the last-used faction. Not a game rule — core/Faction holds those; core/GalaxyState is
## already faction-agnostic (player_faction is just data), this only remembers the pick.

const CONFIG_PATH := "user://faction.cfg"
const DEFAULT := Faction.REPUBLIC


static func load_saved() -> StringName:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)   # missing file is fine
	var f := StringName(cf.get_value("campaign", "faction", DEFAULT))
	return f if Faction.is_playable(f) else DEFAULT


static func save(faction: StringName) -> void:
	if not Faction.is_playable(faction):
		return
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value("campaign", "faction", String(faction))
	cf.save(CONFIG_PATH)
