class_name HudBar
extends Control
## A rounded meter with an icon on the left and optional text on the right:
## health, turbo, and the district meters. `value` is 0..1. `flash()` blinks
## it (damage taken).

var value := 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if absf(v - value) > 0.001:
			value = v
			queue_redraw()
var fill_color := Color(0.85, 0.2, 0.2)
var back_color := Color(0.05, 0.06, 0.07, 0.75)
var icon := &"heart"
var icon_color := Color(1.0, 0.35, 0.35)
var text := "":
	set(v):
		if v != text:
			text = v
			queue_redraw()
var text_size := 16

var _flash := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var icon_space := h + 6.0
	var bar := Rect2(Vector2(icon_space, 0.0), Vector2(size.x - icon_space, h))
	var back := StyleBoxFlat.new()
	back.bg_color = back_color
	back.set_corner_radius_all(int(h * 0.35))
	back.border_color = Color(1, 1, 1, 0.18 + _flash * 0.6)
	back.set_border_width_all(1 if _flash <= 0.0 else 2)
	draw_style_box(back, bar)
	if value > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = fill_color.lerp(Color.WHITE, _flash * 0.6)
		fill.set_corner_radius_all(int(h * 0.3))
		var inner := bar.grow(-2.0)
		inner.size.x = maxf(inner.size.x * value, h * 0.6)
		draw_style_box(fill, inner)
		# Sheen along the top.
		draw_rect(Rect2(inner.position + Vector2(h * 0.2, 1.0), Vector2(maxf(inner.size.x - h * 0.4, 0.0), inner.size.y * 0.3)),
			Color(1, 1, 1, 0.14))
	HudIcons.draw(self, icon, Vector2(h * 0.5, h * 0.5), h * 0.9, icon_color)
	if not text.is_empty():
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		var at := Vector2(bar.end.x - width - 10.0, h * 0.5 + text_size * 0.36)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 4, Color(0, 0, 0, 0.8))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color.WHITE)
