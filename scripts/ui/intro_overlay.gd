class_name IntroOverlay
extends CanvasLayer
## A short opening: captions fade in over a darkened view, then it clears.
## Any key or click skips. Shown when the run starts from the title's Play.

const LINES := [
	"Three datacenters moved into the neighborhood.",
	"The taps ran dry. The sky turned brown. The noise never stops.",
	"The town council got \"donations.\" The neighbors got a smog alert.",
	"Time to take the block back.",
]
const LINE_SECONDS := 2.6

## The captions (a district can bring its own; see Level.intro_lines).
var lines: Array = LINES

var _shade: ColorRect
var _label: Label
var _hint: Label
var _index := -1
var _left := 0.0
var _done := false


func _ready() -> void:
	layer = 20
	_shade = ColorRect.new()
	_shade.color = Color(0.02, 0.02, 0.02, 0.82)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.offset_left = -560
	_label.offset_right = 560
	_label.offset_top = -60
	_label.offset_bottom = 60
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(0.95, 0.96, 0.93))
	_shade.add_child(_label)
	_hint = Label.new()
	_hint.text = "Any key to skip"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -60
	_hint.offset_left = -200
	_hint.offset_right = 200
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", UiTheme.MUTED)
	_shade.add_child(_hint)
	_next()


func _process(delta: float) -> void:
	if _done:
		return
	_left -= delta
	_label.modulate.a = clampf(minf((LINE_SECONDS - _left) * 3.0, _left * 3.0), 0.0, 1.0)
	if _left <= 0.0:
		_next()


func _input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		finish()


func _next() -> void:
	_index += 1
	if _index >= lines.size():
		finish()
		return
	_label.text = lines[_index]
	_left = LINE_SECONDS


func finish() -> void:
	if _done:
		return
	_done = true
	var tween := create_tween()
	tween.tween_property(_shade, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
