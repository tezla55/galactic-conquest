class_name ControllerDevice
extends Node

## Tracks which input device the player is actually using, which controller family is
## active (for glyphs), and hot-plug/disconnect. Observes events in `_input()` and never
## consumes them: menus keep using Godot's built-in `ui_*` actions and focused Controls,
## while main.gd handles only the gameplay actions that are left over.
##
## Godot 4.7's built-in `ui_accept` / `ui_cancel` actions contain keyboard events only in
## this project (verified via InputMap), so `_ready()` adds the missing A/Cross and B/Circle
## joypad bindings. Without them, D-pad navigation works but no focused Button can be
## activated by a controller. No other input mapping is changed.

signal mode_changed(mode: int)
signal family_changed(family: int)
signal connection_changed(connected: bool, device: int, device_name: String)

enum Mode { KEYBOARD_MOUSE, GAMEPAD }

## Order matches ControllerGlyphs.Style, so `family` can be passed straight through when
## the glyph style is "auto".
enum Family { GENERIC, XBOX_360, XBOX, PS4, PS5 }

## A stick must move this far before it counts as "the player picked up the controller".
## The map cursor itself uses a separate, wider threshold in main.gd.
const DEADZONE := 0.35

## Mouse motion only takes input mode back after this much real movement across at least
## two events inside the window. A DualSense touchpad, a jittery wireless mouse, or desk
## vibration can emit one tiny (or even one large) `InputEventMouseMotion` every couple of
## seconds that would otherwise flip the UI out of gamepad mode. A real mouse move produces
## a burst of events, so it still switches immediately in practice.
const MOUSE_MOVE_SWITCH_PX := 10.0
const MOUSE_MOVE_WINDOW_MS := 300
const MOUSE_MOVE_MIN_EVENTS := 2

var mode := Mode.KEYBOARD_MOUSE
var family := Family.GENERIC
var active_device := -1
## Set by main.gd from window focus notifications. While false, ALL gamepad events are
## swallowed (and marked handled so focused Controls cannot act on them) — the player is
## usually driving SWBF2 in another window at that point.
var window_focused := true
var _mouse_accum := 0.0
var _mouse_events := 0
var _mouse_window_start := 0


func _ready() -> void:
	_ensure_ui_joy_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		active_device = pads[0]
		family = family_for(active_device)
	set_process_input(true)


func _exit_tree() -> void:
	stop_rumble()


func set_window_focused(focused: bool) -> void:
	window_focused = focused
	_mouse_accum = 0.0
	_mouse_events = 0
	if not focused:
		stop_rumble()


func _input(event: InputEvent) -> void:
	# While another window (normally SWBF2 itself) has focus, gamepad events must not reach
	# GC's menus or map. Godot can still deliver joypad input to an unfocused window on some
	# stacks, so mark it handled here; `_input` runs before GUI/focus handling. `has_focus()`
	# is a second check in case a focus notification was missed.
	var focused := window_focused
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		focused = focused and get_window().has_focus()
	if not focused:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if is_inside_tree():
				get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_mouse_accum = 0.0
			_mouse_events = 0
			_activate(jb.device)
			_set_mode(Mode.GAMEPAD)
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if _axis_counts_as_input(jm.axis, jm.axis_value):
			_mouse_accum = 0.0
			_mouse_events = 0
			_activate(jm.device)
			_set_mode(Mode.GAMEPAD)
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var now := Time.get_ticks_msec()
		if now - _mouse_window_start > MOUSE_MOVE_WINDOW_MS:
			_mouse_window_start = now
			_mouse_accum = 0.0
			_mouse_events = 0
		_mouse_accum += mm.relative.length()
		_mouse_events += 1
		if _mouse_accum >= MOUSE_MOVE_SWITCH_PX and _mouse_events >= MOUSE_MOVE_MIN_EVENTS:
			_mouse_accum = 0.0
			_mouse_events = 0
			_set_mode(Mode.KEYBOARD_MOUSE)
		return
	# A key press or a real mouse click is unambiguous; switch immediately.
	if event is InputEventKey or event is InputEventMouseButton:
		_mouse_accum = 0.0
		_mouse_events = 0
		var was_gamepad := mode == Mode.GAMEPAD
		_set_mode(Mode.KEYBOARD_MOUSE)
		# Don't let the click that leaves controller mode also activate whatever mouse
		# button happens to be under the cursor after the bottom bar swaps.
		if was_gamepad and event is InputEventMouseButton and is_inside_tree():
			get_viewport().set_input_as_handled()


func has_controller() -> bool:
	return active_device >= 0 and Input.get_connected_joypads().has(active_device)


func device_name() -> String:
	if active_device < 0:
		return "No controller"
	var n := Input.get_joy_name(active_device)
	return n if not n.is_empty() else "Controller"


func family_for(device: int) -> int:
	if device < 0:
		return Family.GENERIC
	return family_from_strings(Input.get_joy_name(device), Input.get_joy_guid(device))


## Pure name/GUID classification, split out so it can be tested without a physical pad.
static func family_from_strings(device_name: String, guid: String) -> int:
	var n := device_name.to_lower()
	var vendor := _vendor_from_guid(guid)
	var product := _product_from_guid(guid)
	if n.contains("dualsense") or n.contains("dual sense") or n.contains("ps5"):
		return Family.PS5
	if n.contains("dualshock") or n.contains("dual shock") or n.contains("ds4") \
			or n.contains("ps4"):
		return Family.PS4
	# Sony's own generic name for a DualShock 4 / DualSense on several stacks. The product
	# id distinguishes a DualSense (0x0ce6 / Edge 0x0df2) from a DualShock 4 (0x05c4 /
	# 0x09cc) even when the name is just "Wireless Controller".
	if vendor == 0x054C:
		if product == 0x0CE6 or product == 0x0DF2:
			return Family.PS5
		if product == 0x05C4 or product == 0x09CC:
			return Family.PS4
		return Family.PS4
	if n.contains("xbox 360") or n.contains("xbox360") or n.contains("x360"):
		return Family.XBOX_360
	# Microsoft's 360 product ids (0x028e wired, 0x028f / 0x0719 wireless) can show up
	# under a generic "XInput Controller" name too.
	if vendor == 0x045E and (product == 0x028E or product == 0x028F or product == 0x0719):
		return Family.XBOX_360
	if n.contains("xbox") or n.contains("xinput"):
		return Family.XBOX
	if vendor == 0x045E:   # Microsoft
		return Family.XBOX
	if n.contains("playstation"):
		return Family.PS4
	return Family.GENERIC


func rumble(weak: float, strong: float, seconds: float) -> void:
	if mode != Mode.GAMEPAD or not has_controller():
		return
	Input.start_joy_vibration(active_device, clampf(weak, 0.0, 1.0),
		clampf(strong, 0.0, 1.0), maxf(seconds, 0.01))


func stop_rumble() -> void:
	if active_device >= 0 and Input.get_connected_joypads().has(active_device):
		Input.stop_joy_vibration(active_device)


func _activate(device: int) -> void:
	if device < 0 or device == active_device:
		return
	active_device = device
	var new_family := family_for(device)
	if new_family != family:
		family = new_family
		family_changed.emit(family)


func _set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	mode_changed.emit(mode)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		if active_device < 0:
			_activate(device)
		connection_changed.emit(true, device,
			Input.get_joy_name(device) if not Input.get_joy_name(device).is_empty() else "Controller")
		return
	stop_rumble()
	var was_active := device == active_device
	if was_active:
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			active_device = -1
			if family != Family.GENERIC:
				family = Family.GENERIC
				family_changed.emit(family)
			_set_mode(Mode.KEYBOARD_MOUSE)
		else:
			_activate(pads[0])
	connection_changed.emit(false, device, "Controller")


static func _axis_counts_as_input(axis: int, value: float) -> bool:
	# Triggers rest at 0 (some stacks report -1); stick axes rest at 0. Only a positive
	# trigger pull or a real stick deflection should steal input mode.
	if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT:
		return value > DEADZONE
	if axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_LEFT_Y \
			or axis == JOY_AXIS_RIGHT_X or axis == JOY_AXIS_RIGHT_Y:
		return absf(value) >= DEADZONE
	return false


## Add only the two joypad events Godot's built-in UI actions are missing here. Called
## before any input is processed; idempotent if a future Godot/project change already has
## them. These make focused Buttons/CheckBoxes respond to Cross/A and Circle/B natively.
static func _ensure_ui_joy_bindings() -> void:
	_ensure_joy_button(&"ui_accept", JOY_BUTTON_A)
	_ensure_joy_button(&"ui_cancel", JOY_BUTTON_B)


static func _ensure_joy_button(action: StringName, button_index: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button_index:
			return
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index
	ev.device = -1
	ev.pressed = true
	InputMap.action_add_event(action, ev)


static func _vendor_from_guid(guid: String) -> int:
	# SDL GUID strings put the 16-bit vendor id in bytes 4-5, little-endian: Sony is
	# 4c05 in the string, Microsoft is 5e04.
	if guid.length() < 12:
		return 0
	var as_text := "0x" + guid.substr(10, 2) + guid.substr(8, 2)
	return as_text.hex_to_int()


static func _product_from_guid(guid: String) -> int:
	# Product id lives at bytes 8-9: the DualShock 4 identifiers appear as cc09 / c405,
	# the DualSense as e60c.
	if guid.length() < 20:
		return 0
	var as_text := "0x" + guid.substr(18, 2) + guid.substr(16, 2)
	return as_text.hex_to_int()
