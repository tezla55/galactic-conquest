class_name ControllerGlyphs
extends RefCounted

## Controller-agnostic action names -> the glyph that should be drawn for a given
## controller family. Pure data/formatting: no Node, no textures, no input polling. The
## actual drawing lives in ui/glyph_icon.gd; this class only answers "what should it look
## like / say?" so it can be unit-tested headless.
##
## Style values deliberately mirror ControllerDevice.Family (GENERIC, XBOX_360, XBOX, PS4,
## PS5) so "auto" is a no-op cast. A manual override exists for Steam Input / DS4Windows,
## which commonly present a DualSense or DualShock 4 as an Xbox pad.

enum Style { GENERIC, XBOX_360, XBOX, PS4, PS5 }
enum Shape { CROSS, CIRCLE, SQUARE, TRIANGLE, LETTER, NUMBER }

const ACTION_CONFIRM := "confirm"
const ACTION_CANCEL := "cancel"
const ACTION_WEST := "west"
const ACTION_NORTH := "north"
const ACTION_ZOOM_OUT := "zoom_out"
const ACTION_ZOOM_IN := "zoom_in"
const ACTION_MENU := "menu"
const ACTION_HELP := "help"
const ACTION_CENTER := "center"
const ACTION_DPAD := "dpad"
const ACTION_LEFT_STICK := "left_stick"
const ACTION_RIGHT_STICK := "right_stick"

const FACE_ACTIONS := [
	ACTION_CONFIRM, ACTION_CANCEL, ACTION_WEST, ACTION_NORTH,
]

## The game's neutral text colour. Glyph chips use it; face-button shapes use the
## platform colours below where that family actually has them.
const INK := Color("e4e4e6")
const INK_DIM := Color("8a8a8d")
const DARK_INK := Color("121214")

## Authentic-ish face colours. PS4 and Xbox 360 glyphs are coloured on the real hardware;
## PS5 and Xbox One/Series face buttons are monochrome. Keeping both lets a player switch
## the override to whatever they are used to.
const PS4_CROSS := Color("5aa9e6")
const PS4_CIRCLE := Color("e05a5a")
const PS4_SQUARE := Color("d97fb0")
const PS4_TRIANGLE := Color("5fbf8f")

const X360_A := Color("6fbf4a")
const X360_B := Color("d94b4b")
const X360_X := Color("4a8fd9")
const X360_Y := Color("e8b23a")


static func style_for(family: int, override: String) -> int:
	match override:
		"xbox360":
			return Style.XBOX_360
		"xbox":
			return Style.XBOX
		"ps4":
			return Style.PS4
		"ps5":
			return Style.PS5
		"generic":
			return Style.GENERIC
	return clampi(family, Style.GENERIC, Style.PS5)


static func family_name(family: int) -> String:
	match family:
		Style.XBOX_360:
			return "Xbox 360"
		Style.XBOX:
			return "Xbox One / Series"
		Style.PS4:
			return "PlayStation 4"
		Style.PS5:
			return "PlayStation 5"
	return "Generic controller"


static func style_name(style: int) -> String:
	match style:
		Style.XBOX_360:
			return "Xbox 360"
		Style.XBOX:
			return "Xbox"
		Style.PS4:
			return "PlayStation 4"
		Style.PS5:
			return "PlayStation 5"
	return "Generic"


static func style_label(style: int, auto: bool) -> String:
	return ("Auto (%s)" % style_name(style)) if auto else style_name(style)


static func is_face_action(action: String) -> bool:
	return FACE_ACTIONS.has(action)


static func shape_for(style: int, action: String) -> Shape:
	if style == Style.PS4 or style == Style.PS5:
		match action:
			ACTION_CONFIRM:
				return Shape.CROSS
			ACTION_CANCEL:
				return Shape.CIRCLE
			ACTION_WEST:
				return Shape.SQUARE
			ACTION_NORTH:
				return Shape.TRIANGLE
	if style == Style.GENERIC:
		return Shape.NUMBER
	return Shape.LETTER


static func face_letter(action: String) -> String:
	match action:
		ACTION_CONFIRM:
			return "A"
		ACTION_CANCEL:
			return "B"
		ACTION_WEST:
			return "X"
		ACTION_NORTH:
			return "Y"
	return "?"


static func face_number(action: String) -> String:
	match action:
		ACTION_CONFIRM:
			return "1"
		ACTION_CANCEL:
			return "2"
		ACTION_WEST:
			return "3"
		ACTION_NORTH:
			return "4"
	return "?"


static func face_color(style: int, action: String) -> Color:
	match style:
		Style.PS4:
			match action:
				ACTION_CONFIRM:
					return PS4_CROSS
				ACTION_CANCEL:
					return PS4_CIRCLE
				ACTION_WEST:
					return PS4_SQUARE
				ACTION_NORTH:
					return PS4_TRIANGLE
		Style.XBOX_360:
			match action:
				ACTION_CONFIRM:
					return X360_A
				ACTION_CANCEL:
					return X360_B
				ACTION_WEST:
					return X360_X
				ACTION_NORTH:
					return X360_Y
	return INK


## Is the face glyph a filled badge with dark lettering (Xbox 360 / generic) rather than
## an outlined mark (PS, Xbox One/Series)?
static func filled_face(style: int) -> bool:
	return style == Style.XBOX_360 or style == Style.GENERIC


static func chip_text(style: int, action: String) -> String:
	match action:
		ACTION_ZOOM_OUT:
			return "L2" if _is_playstation(style) else "LT"
		ACTION_ZOOM_IN:
			return "R2" if _is_playstation(style) else "RT"
		ACTION_MENU:
			if style == Style.PS4 or style == Style.PS5:
				return "Options"
			if style == Style.XBOX:
				return "Menu"
			if style == Style.XBOX_360:
				return "Start"
			return "Menu"
		ACTION_HELP:
			if style == Style.PS4:
				return "Share"
			if style == Style.PS5:
				return "Create"
			if style == Style.XBOX:
				return "View"
			if style == Style.XBOX_360:
				return "Back"
			return "Back"
		ACTION_CENTER:
			return "R3"
		ACTION_DPAD:
			return "D-Pad"
		ACTION_LEFT_STICK:
			return "L Stick"
		ACTION_RIGHT_STICK:
			return "R Stick"
	return "?"


static func action_label(style: int, action: String) -> String:
	if is_face_action(action):
		if style == Style.GENERIC:
			return face_number(action)
		if style == Style.PS4 or style == Style.PS5:
			match action:
				ACTION_CONFIRM:
					return "Cross"
				ACTION_CANCEL:
					return "Circle"
				ACTION_WEST:
					return "Square"
				ACTION_NORTH:
					return "Triangle"
		return face_letter(action)
	return chip_text(style, action)


static func _is_playstation(style: int) -> bool:
	return style == Style.PS4 or style == Style.PS5
