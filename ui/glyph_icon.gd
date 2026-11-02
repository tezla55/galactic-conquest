class_name GlyphIcon
extends Control

## One controller glyph, drawn procedurally so there are no image assets to import and the
## mark stays crisp at any window size. Face buttons are vector shapes/letters in the
## platform's own colours; shoulders, triggers, and system buttons are text chips
## ("L1", "Options", "View"). Everything is derived from ui/controller_glyphs.gd.

var action := ControllerGlyphs.ACTION_CONFIRM
var style := ControllerGlyphs.Style.GENERIC
var glyph_px := 20.0

var _text := ""
var _face := false
var _font_size := 11
var _chip_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(action_name: String, glyph_style: int, px: float = 20.0) -> void:
	action = action_name
	style = glyph_style
	glyph_px = maxf(px, 10.0)
	_face = ControllerGlyphs.is_face_action(action)
	if _face:
		_text = ""
		custom_minimum_size = Vector2(glyph_px, glyph_px)
	else:
		_text = ControllerGlyphs.chip_text(style, action)
		_font_size = int(clampf(glyph_px * 0.52, 9.0, 14.0))
		var w := Tokens.FONT_BOLD.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		# A little extra on the right of the text, and a chip never narrower than it is tall.
		custom_minimum_size = Vector2(ceilf(maxf(w + glyph_px * 0.55, glyph_px * 1.15)), glyph_px)
		_chip_style = StyleBoxFlat.new()
		_chip_style.bg_color = Color(0.11, 0.115, 0.125, 0.92)
		_chip_style.border_color = ControllerGlyphs.INK_DIM
		_chip_style.set_border_width_all(1)
		_chip_style.set_corner_radius_all(int(glyph_px * 0.5))
	tooltip_text = ControllerGlyphs.action_label(style, action)
	queue_redraw()


func _draw() -> void:
	if _face:
		_draw_face()
	elif _chip_style != null:
		_draw_chip()


func _draw_face() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.0
	var col := ControllerGlyphs.face_color(style, action)
	var line_w := maxf(2.0, glyph_px * 0.11)
	match ControllerGlyphs.shape_for(style, action):
		ControllerGlyphs.Shape.CROSS:
			var d := radius * 0.55
			draw_line(centre + Vector2(-d, -d), centre + Vector2(d, d), col, line_w, true)
			draw_line(centre + Vector2(d, -d), centre + Vector2(-d, d), col, line_w, true)
		ControllerGlyphs.Shape.CIRCLE:
			draw_arc(centre, radius * 0.62, 0.0, TAU, 40, col, line_w, true)
		ControllerGlyphs.Shape.SQUARE:
			var half := radius * 0.48
			draw_rect(Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0),
				col, false, line_w, true)
		ControllerGlyphs.Shape.TRIANGLE:
			var top := centre + Vector2(0.0, -radius * 0.62)
			var right := centre + Vector2(radius * 0.58, radius * 0.40)
			var left := centre + Vector2(-radius * 0.58, radius * 0.40)
			draw_polyline(PackedVector2Array([top, right, left, top]), col, line_w, true)
		_:
			_draw_letter(centre, radius, col)


func _draw_letter(centre: Vector2, radius: float, col: Color) -> void:
	var filled := ControllerGlyphs.filled_face(style)
	if filled:
		draw_circle(centre, radius * 0.82, col)
	else:
		draw_arc(centre, radius * 0.82, 0.0, TAU, 40, col, maxf(2.0, glyph_px * 0.09), true)
	var txt := ControllerGlyphs.face_letter(action) if style != ControllerGlyphs.Style.GENERIC \
		else ControllerGlyphs.face_number(action)
	var fs := int(clampf(glyph_px * 0.56, 9.0, 16.0))
	var ink := ControllerGlyphs.DARK_INK if filled else ControllerGlyphs.INK
	var extent := Tokens.FONT_BOLD.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var ascent := Tokens.FONT_BOLD.get_ascent(fs)
	var descent := Tokens.FONT_BOLD.get_descent(fs)
	var baseline := centre + Vector2(-extent.x * 0.5, (ascent - descent) * 0.5)
	draw_string(Tokens.FONT_BOLD, baseline, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, ink)


func _draw_chip() -> void:
	if _text.is_empty():
		return
	draw_style_box(_chip_style, Rect2(Vector2.ZERO, size))
	var extent := Tokens.FONT_BOLD.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	var ascent := Tokens.FONT_BOLD.get_ascent(_font_size)
	var y := (size.y - extent.y) * 0.5 + ascent
	draw_string(Tokens.FONT_BOLD, Vector2(0.0, y), _text, HORIZONTAL_ALIGNMENT_CENTER,
		size.x, _font_size, ControllerGlyphs.INK)
