class_name PadActionPill
extends PanelContainer

## A display-only pill in the controller bottom bar: face-button glyph + action label.
## Purely presentational (mouse ignored, no focus) because the physical X/Circle/Square/
## Triangle buttons invoke the action directly; the player never navigates these pills.

var action := ""
var glyph_px := 22.0

var _icon: GlyphIcon
var _label: Label
var _box: StyleBoxFlat
var _built := false
var _enabled := true
var _highlighted := false
var _show_icon := true


func setup(action_name: String, text: String, glyph_style: int,
		enabled: bool = true, highlighted: bool = false, show_icon: bool = true) -> void:
	_ensure_built()
	action = action_name
	_show_icon = show_icon and action_name != ""
	_icon.visible = _show_icon
	if _show_icon:
		_icon.setup(action_name, glyph_style, glyph_px)
	_label.text = text
	_enabled = enabled
	_highlighted = highlighted
	_apply_style()
	visible = true


func get_text() -> String:
	return _label.text if _built else ""


func is_enabled() -> bool:
	return _enabled


func _ensure_built() -> void:
	if _built:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = 38.0
	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(40)
	_box.set_content_margin_all(8)
	add_theme_stylebox_override("panel", _box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = GlyphIcon.new()
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_override("font", Tokens.FONT_MEDIUM)
	_label.add_theme_font_size_override("font_size", 14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_label)
	_built = true


func _apply_style() -> void:
	var ink := Tokens.TEXT if _enabled else Tokens.TEXT_DIM
	_label.add_theme_color_override("font_color", ink)
	_icon.modulate = Color(1, 1, 1, 1) if _enabled else Color(1, 1, 1, 0.5)
	_box.bg_color = Tokens.SURFACE_EDGE if _enabled else Tokens.SURFACE
	if _highlighted:
		_box.bg_color = Tokens.SURFACE_EDGE.lightened(0.18)
		_box.border_color = Tokens.TEXT
		_box.set_border_width_all(2)
		_label.add_theme_color_override("font_color", Tokens.TEXT)
	else:
		_box.border_color = Tokens.SURFACE_EDGE
		_box.set_border_width_all(1)
