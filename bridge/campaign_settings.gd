class_name CampaignSettings
extends RefCounted

## The player's last-played campaign, remembered in user://campaign.cfg so the start
## screen defaults to it. Not a game rule — core/CampaignDef + data/campaigns.json hold
## those; this only remembers the pick.

const CONFIG_PATH := "user://campaign.cfg"
const DEFAULT := &"clone_wars"


static func load_saved() -> StringName:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)   # missing file is fine
	var id := StringName(cf.get_value("campaign", "id", DEFAULT))
	for c in ContentLoader.load_campaigns():
		if c.id == id:
			return id
	return DEFAULT


static func save(campaign_id: StringName) -> void:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value("campaign", "id", String(campaign_id))
	cf.save(CONFIG_PATH)
