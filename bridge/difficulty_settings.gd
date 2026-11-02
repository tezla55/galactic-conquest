class_name DifficultySettings
extends RefCounted

## The player's chosen campaign difficulty, remembered in user://difficulty.cfg so a new
## campaign starts at the last-used level. Not a game rule — core/Difficulty holds those.

const CONFIG_PATH := "user://difficulty.cfg"


static func load_saved() -> StringName:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)   # missing file is fine
	return Difficulty.normalise(StringName(cf.get_value("campaign", "difficulty", Difficulty.DEFAULT)))


static func save(level: StringName) -> void:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value("campaign", "difficulty", String(Difficulty.normalise(level)))
	cf.save(CONFIG_PATH)
