class_name Hud
extends CanvasLayer
## Prototype HUD: district meters, cash, health, C4, objective, prompt, crosshair.
## Built in code so layout tweaks stay in one readable place.

var _bars := {}
var _cash: Label
var _status: Label
var _weapon: Label
var _objective: Label
var _prompt: Label
var _info_box: VBoxContainer
var _info := {}
var _player: Player
var _toasts: VBoxContainer
var _tip_panel: PanelContainer
var _tip_label: Label
var _tip_queue: Array[String] = []
var _tip_left := 0.0

const TIP_SECONDS := 9.0


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
	_place(right, Control.PRESET_TOP_RIGHT, Rect2(-340, 20, 320, 0))
	_cash = _make_label(right, 28, HORIZONTAL_ALIGNMENT_RIGHT)
	_status = _make_label(right, 18, HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon = _make_label(right, 20, HORIZONTAL_ALIGNMENT_RIGHT)

	# Objective plus keyed lines (boss, wave, core health, build menu), stacked
	# so a wrapped objective pushes the rest down instead of overlapping.
	_info_box = VBoxContainer.new()
	root.add_child(_info_box)
	# 860 px keeps clear of the meters (left) and the status block (right).
	_place(_info_box, Control.PRESET_CENTER_TOP, Rect2(-430, 20, 860, 0))
	_objective = _make_label(_info_box, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(860, 0)
	for key: String in ["sites", "deeds", "boss", "wave", "core", "build", "bribe", "shop", "notice"]:
		var line := _make_label(_info_box, 18, HORIZONTAL_ALIGNMENT_CENTER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(860, 0)
		line.visible = false
		_info[key] = line

	_prompt = _make_label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_prompt, Control.PRESET_CENTER_BOTTOM, Rect2(-300, -80, 600, 40))

	# Feedback toasts stack on the right under the status block.
	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toasts)
	_place(_toasts, Control.PRESET_TOP_RIGHT, Rect2(-460, 150, 440, 0))

	# One contextual tip at a time, bottom-left, queued.
	_tip_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.08, 0.82)
	style.border_color = Color(0.45, 0.95, 0.55)
	style.border_width_left = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	_tip_panel.add_theme_stylebox_override("panel", style)
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tip_panel)
	_place(_tip_panel, Control.PRESET_BOTTOM_LEFT, Rect2(20, -190, 470, 0))
	_tip_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tip_label = _make_label(_tip_panel, 17, HORIZONTAL_ALIGNMENT_LEFT)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(440, 0)
	_tip_panel.visible = false

	var crosshair := _make_label(root, 24, HORIZONTAL_ALIGNMENT_CENTER)
	crosshair.text = "+"
	_place(crosshair, Control.PRESET_CENTER, Rect2(-20, -18, 40, 36))

	Game.cash_changed.connect(func(_c: int) -> void: _refresh_status())
	Game.objective_changed.connect(func(text: String) -> void: _objective.text = text)
	Game.info_changed.connect(_on_info_changed)
	Game.notice.connect(show_toast)
	Game.tip_shown.connect(func(text: String) -> void: _tip_queue.append(text))
	_objective.text = Game.objective
	_connect_player.call_deferred()


func _process(delta: float) -> void:
	_update_tip(delta)
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
	_player.weapon_changed.connect(func(_w: Weapon) -> void: _refresh_status())
	_refresh_status()


## Pops a feedback line on the right that fades after `seconds`.
func show_toast(text: String, seconds := 5.0) -> void:
	var label := _make_label(_toasts, 19, HORIZONTAL_ALIGNMENT_RIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(440, 0)
	label.text = text
	label.modulate = Color(1.0, 0.95, 0.6)
	while _toasts.get_child_count() > 4:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	var tween := label.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


## The tip currently on screen ("" when none). Tests read this.
func current_tip() -> String:
	return _tip_label.text if _tip_panel.visible else ""


func _update_tip(delta: float) -> void:
	if _tip_panel.visible:
		_tip_left -= delta
		if _tip_left > 0.0:
			return
		_tip_panel.visible = false
	if _tip_queue.is_empty():
		return
	_tip_label.text = "TIP  " + _tip_queue.pop_front()
	_tip_left = TIP_SECONDS if _tip_queue.is_empty() else TIP_SECONDS * 0.7
	_tip_panel.visible = true
	Sfx.ui(&"tip")


func _refresh_status() -> void:
	_cash.text = "$%d" % Game.cash
	if _player:
		_status.text = "HP %d   C4 x%d   Treats x%d" % [
			ceili(maxf(_player.health, 0.0)), _player.c4_charges, _player.treats]
		_weapon.text = "[Q] %s" % _player.current_weapon().hud_label()


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
