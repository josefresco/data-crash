class_name PauseMenu
extends CanvasLayer
## Esc / P: pauses the game and frees the mouse. Resume, settings, controls,
## restart, or quit to the title screen.

const TITLE_SCENE := "res://scenes/ui/title.tscn"

var is_open := false

var _root: Control
var _main: VBoxContainer
var _panel_holder: CenterContainer


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 12)
	center.add_child(_main)
	_main.add_child(UiTheme.label("PAUSED", 44, UiTheme.ACCENT))
	_main.add_child(UiTheme.label(Game.objective if Game.objective else " ", 18, UiTheme.MUTED))
	for entry in [["Resume", close], ["Settings", _show_panel.bind(SettingsPanel)],
			["Controls", _show_panel.bind(ControlsPanel)], ["Restart level", _restart],
			["Quit to title", _quit_to_title]]:
		var node := UiTheme.button(entry[0], entry[1])
		node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_main.add_child(node)
	_panel_holder = CenterContainer.new()
	_panel_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_panel_holder)
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_open and _panel_holder.get_child_count() > 0:
			_close_panel()
		elif is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open:
		return
	is_open = true
	(_main.get_child(1) as Label).text = Game.objective if Game.objective else " "
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ui(&"open")
	(_main.get_child(2) as Button).grab_focus()


func close() -> void:
	if not is_open:
		return
	_close_panel()
	is_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.ui(&"close")


func _show_panel(kind: GDScript) -> void:
	_close_panel()
	var panel := kind.new() as Control
	panel.connect(&"closed", _close_panel)
	_panel_holder.add_child(panel)
	_main.visible = false


func _close_panel() -> void:
	for child in _panel_holder.get_children():
		child.queue_free()
	_main.visible = true


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)
