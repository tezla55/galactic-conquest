class_name DisplaySettings
extends RefCounted

## Window resolution / fullscreen, chosen in-app and remembered in user://display.cfg.
## Not a game rule — ui/ calls apply() on startup and when the player picks one.

const CONFIG_PATH := "user://display.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const DEFAULT_SIZE := Vector2i(1600, 900)


static func load_saved() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)   # missing file is fine
	var w := int(cf.get_value("display", "width", DEFAULT_SIZE.x))
	var h := int(cf.get_value("display", "height", DEFAULT_SIZE.y))
	return {
		"size": Vector2i(maxi(640, w), maxi(480, h)),
		"fullscreen": bool(cf.get_value("display", "fullscreen", false)),
	}


static func save(size: Vector2i, fullscreen: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value("display", "width", size.x)
	cf.set_value("display", "height", size.y)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.save(CONFIG_PATH)


## Apply a {size, fullscreen} dict (as returned by load_saved). Windowed mode is resized
## and re-centred on the current screen so it can't land off the edge.
static func apply(settings: Dictionary) -> void:
	var fullscreen := bool(settings.get("fullscreen", false))
	var size: Vector2i = settings.get("size", DEFAULT_SIZE)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var pos := DisplayServer.screen_get_position(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(pos + (screen - size) / 2)
