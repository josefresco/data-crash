class_name UiTheme
extends RefCounted
## Shared look for menus (title, pause, settings, end screen): dark glassy
## panels, a green "restoration" accent, and buttons that click. Static only.

const ACCENT := Color(0.45, 0.95, 0.55)
const TEXT := Color(0.92, 0.95, 0.93)
const MUTED := Color(0.62, 0.68, 0.65)
const PANEL := Color(0.04, 0.07, 0.06, 0.88)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 20
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_color("font_color", "Button", TEXT)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_pressed_color", "Button", ACCENT)
	_theme.set_color("font_focus_color", "Button", Color.WHITE)
	_theme.set_color("font_color", "CheckBox", TEXT)
	_theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	_theme.set_color("font_color", "OptionButton", TEXT)
	_theme.set_stylebox("panel", "PanelContainer", _box(PANEL, ACCENT.darkened(0.5), 2, 10, 24))
	_theme.set_stylebox("normal", "Button", _box(Color(0.1, 0.16, 0.13, 0.95), Color(0.2, 0.32, 0.25), 1, 6, 12))
	_theme.set_stylebox("hover", "Button", _box(Color(0.14, 0.26, 0.18, 0.95), ACCENT, 1, 6, 12))
	_theme.set_stylebox("pressed", "Button", _box(Color(0.06, 0.12, 0.08, 0.95), ACCENT, 2, 6, 12))
	_theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 2, 6, 12))
	for type in ["OptionButton"]:
		_theme.set_stylebox("normal", type, _box(Color(0.1, 0.16, 0.13, 0.95), Color(0.2, 0.32, 0.25), 1, 6, 10))
		_theme.set_stylebox("hover", type, _box(Color(0.14, 0.26, 0.18, 0.95), ACCENT, 1, 6, 10))
	_theme.set_stylebox("slider", "HSlider", _box(Color(0.15, 0.2, 0.17), Color(0, 0, 0, 0), 0, 3, 0, 6))
	_theme.set_stylebox("grabber_area", "HSlider", _box(ACCENT.darkened(0.3), Color(0, 0, 0, 0), 0, 3, 0, 6))
	_theme.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, Color(0, 0, 0, 0), 0, 3, 0, 6))
	return _theme


static func _box(bg: Color, border: Color, width: int, radius: int, margin: int, min_height := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.5 if min_height == 0 else min_height * 0.5
	box.content_margin_bottom = margin * 0.5 if min_height == 0 else min_height * 0.5
	return box


## A menu button with hover and click sounds.
static func button(text: String, on_pressed: Callable, width := 320.0) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(width, 48)
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_entered.connect(func() -> void: Sfx.ui(&"hover", -8.0))
	node.pressed.connect(func() -> void:
		Sfx.ui(&"click")
		on_pressed.call())
	return node


static func label(text: String, size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = align
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


## Full-screen dimmer with a centered column; returns the column.
static func overlay(parent: Node, dim := 0.55) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.theme = get_theme()
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	return column
