class_name Hud
extends CanvasLayer
## Prototype HUD: district meters, cash, health, C4, objective, prompt, crosshair.
## Built in code so layout tweaks stay in one readable place.

var _bars := {}
var _cash: Label
var _status: Label
var _objective: Label
var _prompt: Label
var _info_box: VBoxContainer
var _info := {}
var _player: Player


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var meters := VBoxContainer.new()
	meters.position = Vector2(20, 20)
	meters.custom_minimum_size = Vector2(260, 0)
	root.add_child(meters)
	for key: String in ["smog", "noise", "water_table", "trust"]:
		var label := Label.new()
		label.text = key.replace("_", " ").to_upper()
		meters.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.01
		bar.custom_minimum_size = Vector2(260, 14)
		bar.show_percentage = false
		meters.add_child(bar)
		_bars[key] = bar

	var right := VBoxContainer.new()
	root.add_child(right)
	_place(right, Control.PRESET_TOP_RIGHT, Rect2(-240, 20, 220, 0))
	_cash = _make_label(right, 28, HORIZONTAL_ALIGNMENT_RIGHT)
	_status = _make_label(right, 18, HORIZONTAL_ALIGNMENT_RIGHT)

	_objective = _make_label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_objective, Control.PRESET_CENTER_TOP, Rect2(-400, 20, 800, 0))
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Keyed lines (wave, core health, build menu) under the objective.
	_info_box = VBoxContainer.new()
	root.add_child(_info_box)
	_place(_info_box, Control.PRESET_CENTER_TOP, Rect2(-500, 60, 1000, 0))
	for key: String in ["wave", "core", "build"]:
		var line := _make_label(_info_box, 18, HORIZONTAL_ALIGNMENT_CENTER)
		line.visible = false
		_info[key] = line

	_prompt = _make_label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_prompt, Control.PRESET_CENTER_BOTTOM, Rect2(-300, -80, 600, 40))

	var crosshair := _make_label(root, 24, HORIZONTAL_ALIGNMENT_CENTER)
	crosshair.text = "+"
	_place(crosshair, Control.PRESET_CENTER, Rect2(-20, -18, 40, 36))

	Game.cash_changed.connect(func(_c: int) -> void: _refresh_status())
	Game.objective_changed.connect(func(text: String) -> void: _objective.text = text)
	Game.info_changed.connect(_on_info_changed)
	_objective.text = Game.objective
	_connect_player.call_deferred()


func _process(_delta: float) -> void:
	var district := Game.district
	if district == null:
		return
	for key: String in _bars:
		(_bars[key] as ProgressBar).value = district.get(key)


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("HUD: no node in group 'player'")
		return
	_player.health_changed.connect(func(_h: float, _m: float) -> void: _refresh_status())
	_player.charges_changed.connect(func(_c: int) -> void: _refresh_status())
	_player.prompt_changed.connect(func(text: String) -> void: _prompt.text = text)
	_refresh_status()


func _refresh_status() -> void:
	_cash.text = "$%d" % Game.cash
	if _player:
		_status.text = "HP %d   C4 x%d   Treats x%d" % [
			ceili(maxf(_player.health, 0.0)), _player.c4_charges, _player.treats]


func _on_info_changed(key: String, text: String) -> void:
	var line := _info.get(key) as Label
	if line:
		line.text = text
		line.visible = not text.is_empty()


## Anchors `control` to `preset`, then offsets it by `rect` (relative to that anchor).
func _place(control: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _make_label(parent: Control, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
