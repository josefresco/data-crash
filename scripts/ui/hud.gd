class_name Hud
extends CanvasLayer
## In-game HUD, built in code:
## - top-left: circular minimap ([M] toggles a full map), district meters
## - top-center: objective (two lines max) and status lines (boss, wave, core)
## - top-right column: cash, checklists (datacenters, good deeds), then toasts
## - bottom-center: key menus (build, bribes, market) above the [E]/[F] prompt
## - bottom-left: health bar (flashes on damage), turbo bar while driving,
##   C4 and treat counts; the tip panel sits above it
## - bottom-right: weapon and ammo
## - a red vignette when hurt, pulsing at low health, over a faint dark one
## - HudOverlay: objective marker, enemy bars, damage numbers, hit arcs, banners
## - CameraFx: FOV kick, explosion shake, dust motes

const TIP_SECONDS := 9.0
const INFO_KEYS: Array[String] = ["boss", "wave", "core", "notice", "build", "bribe", "shop"]
## Info keys that are key menus: shown bottom-center instead of under the objective.
const MENU_KEYS: Array[String] = ["build", "bribe", "shop"]
const CHECKLIST_KEYS: Array[String] = ["sites", "deeds"]
const COLUMN_WIDTH := 320.0
const CENTER_WIDTH := 600.0
## [district key, label, icon, fill color, high-is-bad]
const METERS := [
	["smog", "SMOG", &"smog", Color(0.6, 0.5, 0.4), true],
	["noise", "NOISE", &"noise", Color(0.95, 0.55, 0.2), true],
	["water_table", "WATER", &"water", Color(0.3, 0.6, 1.0), false],
	["trust", "TRUST", &"trust", Color(0.35, 0.85, 0.45), false],
]

var _meters := {}
var _cash: Label
var _objective: Label
var _prompt: Label
var _info_box: VBoxContainer
var _menu_box: VBoxContainer
var _tracker: VBoxContainer
## checklist key -> [PanelContainer, last rows]
var _checklists := {}
var _info := {}
var _player: Player
var _toasts: VBoxContainer
var _tip_panel: PanelContainer
var _tip_label: Label
var _tip_queue: Array[String] = []
var _tip_left := 0.0
var _health: HudBar
var _turbo: HudBar
var _kit: Label
var _weapon_name: Label
var _ammo: Label
var _vignette: TextureRect
var _hurt := 0.0
var _last_health := -1.0
var _map_frame: Panel
var _hit_marker: _HitMarker
var _minimap: Minimap
var _overlay: HudOverlay
var _allies_left := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var shade := _build_vignette(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.5), 0.55)
	shade.modulate.a = 1.0
	root.add_child(shade)
	_vignette = _build_vignette(Color(0.7, 0.0, 0.0, 0.0), Color(0.75, 0.0, 0.0, 0.85), 0.4)
	root.add_child(_vignette)
	_overlay = HudOverlay.new()
	root.add_child(_overlay)
	add_child(CameraFx.new())

	# Minimap in a circular frame; children clip to the circle.
	_map_frame = Panel.new()
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.05, 0.06, 0.05, 0.9)
	circle.set_corner_radius_all(200)
	circle.border_color = Color(0.85, 0.9, 0.85, 0.8)
	circle.set_border_width_all(3)
	_map_frame.add_theme_stylebox_override("panel", circle)
	_map_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_map_frame)
	_minimap = Minimap.new()
	_minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_frame.add_child(_minimap)
	_set_map_expanded(false)

	# District meters under the minimap.
	var meters := VBoxContainer.new()
	meters.add_theme_constant_override("separation", 5)
	meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(meters)
	_place(meters, Control.PRESET_TOP_LEFT, Rect2(18, 248, 236, 0))
	for spec: Array in METERS:
		var bar := HudBar.new()
		bar.icon = spec[2]
		bar.icon_color = (spec[3] as Color).lerp(Color.WHITE, 0.3)
		bar.fill_color = spec[3]
		bar.text_size = 12
		bar.custom_minimum_size = Vector2(236, 20)
		meters.add_child(bar)
		_meters[spec[0]] = [bar, spec[1], spec[4]]

	# Right column: cash with a coin, the checklists, then toasts. One column,
	# so nothing on the right can overlap.
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)
	_place(column, Control.PRESET_TOP_RIGHT, Rect2(-COLUMN_WIDTH - 20.0, 16, COLUMN_WIDTH, 0))
	var cash_box := HBoxContainer.new()
	cash_box.alignment = BoxContainer.ALIGNMENT_END
	cash_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cash_box)
	var coin := _IconControl.new(&"coin", Color(1.0, 0.82, 0.25), 30.0)
	cash_box.add_child(coin)
	_cash = _make_label(cash_box, 32, HORIZONTAL_ALIGNMENT_RIGHT)
	_cash.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))

	_tracker = VBoxContainer.new()
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.add_theme_constant_override("separation", 6)
	column.add_child(_tracker)
	for key in CHECKLIST_KEYS:
		var panel := _checklist_panel()
		panel.visible = false
		_tracker.add_child(panel)
		_checklists[key] = [panel, []]
	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_toasts)

	# Objective plus status lines, stacked so wrapping pushes the rest down.
	_info_box = VBoxContainer.new()
	_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_info_box)
	_place(_info_box, Control.PRESET_CENTER_TOP, Rect2(-CENTER_WIDTH * 0.5, 14, CENTER_WIDTH, 0))
	_objective = _make_label(_info_box, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(CENTER_WIDTH, 0)
	_objective.max_lines_visible = 2
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Key menus (build, bribes, market) sit bottom-center, above the prompt.
	_menu_box = VBoxContainer.new()
	_menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_menu_box)
	_place(_menu_box, Control.PRESET_CENTER_BOTTOM, Rect2(-450, -200, 900, 0))
	_menu_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for key in INFO_KEYS:
		var menu := key in MENU_KEYS
		var line := _make_label(_menu_box if menu else _info_box, 17, HORIZONTAL_ALIGNMENT_CENTER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(900.0 if menu else CENTER_WIDTH, 0)
		line.visible = false
		_info[key] = line

	# Health, turbo, and kit, bottom-left.
	var vitals := VBoxContainer.new()
	vitals.add_theme_constant_override("separation", 6)
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	_place(vitals, Control.PRESET_BOTTOM_LEFT, Rect2(20, -118, 380, 100))
	vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vitals.alignment = BoxContainer.ALIGNMENT_END
	_health = HudBar.new()
	_health.custom_minimum_size = Vector2(380, 36)
	_health.fill_color = Color(0.85, 0.15, 0.15)
	_health.icon_color = Color(1.0, 0.3, 0.3)
	_health.text_size = 20
	vitals.add_child(_health)
	_turbo = HudBar.new()
	_turbo.icon = &"turbo"
	_turbo.icon_color = Color(1.0, 0.7, 0.2)
	_turbo.fill_color = Color(1.0, 0.55, 0.1)
	_turbo.custom_minimum_size = Vector2(380, 18)
	_turbo.text_size = 12
	_turbo.visible = false
	vitals.add_child(_turbo)
	var kit := HBoxContainer.new()
	kit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kit.add_theme_constant_override("separation", 8)
	vitals.add_child(kit)
	kit.add_child(_IconControl.new(&"c4", Color(0.75, 0.7, 0.55), 22.0))
	_kit = _make_label(kit, 18, HORIZONTAL_ALIGNMENT_LEFT)

	# Weapon and ammo, bottom-right.
	var arms := VBoxContainer.new()
	arms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(arms)
	_place(arms, Control.PRESET_BOTTOM_RIGHT, Rect2(-330, -110, 310, 96))
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arms.add_child(ammo_row)
	ammo_row.add_child(_IconControl.new(&"ammo", Color(1.0, 0.85, 0.45), 30.0))
	_ammo = _make_label(ammo_row, 40, HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon_name = _make_label(arms, 20, HORIZONTAL_ALIGNMENT_RIGHT)

	# One contextual tip at a time, above the health bar.
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
	_place(_tip_panel, Control.PRESET_BOTTOM_LEFT, Rect2(20, -140, 470, 0))
	_tip_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tip_label = _make_label(_tip_panel, 17, HORIZONTAL_ALIGNMENT_LEFT)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(440, 0)
	_tip_panel.visible = false

	_prompt = _make_label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_prompt, Control.PRESET_CENTER_BOTTOM, Rect2(-320, -150, 640, 40))
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color(0.03, 0.05, 0.04, 0.72)
	badge.border_color = Color(UiTheme.ACCENT, 0.8)
	badge.border_width_left = 4
	badge.set_corner_radius_all(6)
	badge.content_margin_left = 16
	badge.content_margin_right = 16
	badge.content_margin_top = 4
	badge.content_margin_bottom = 4
	_prompt.add_theme_stylebox_override("normal", badge)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.visible = false

	var crosshair := _make_label(root, 24, HORIZONTAL_ALIGNMENT_CENTER)
	crosshair.text = "+"
	_place(crosshair, Control.PRESET_CENTER, Rect2(-20, -18, 40, 36))
	_hit_marker = _HitMarker.new()
	root.add_child(_hit_marker)
	_place(_hit_marker, Control.PRESET_CENTER, Rect2(-24, -24, 48, 48))

	Game.cash_changed.connect(func(_c: int) -> void: _refresh_status())
	Game.objective_changed.connect(func(text: String) -> void: _objective.text = text)
	Game.info_changed.connect(_on_info_changed)
	Game.checklist_changed.connect(_on_checklist_changed)
	Game.notice.connect(show_toast)
	Game.tip_shown.connect(func(text: String) -> void: _tip_queue.append(text))
	_objective.text = Game.objective
	_connect_player.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		_set_map_expanded(not _minimap.expanded)


func _set_map_expanded(expanded: bool) -> void:
	_minimap.expanded = expanded
	if expanded:
		_place(_map_frame, Control.PRESET_CENTER, Rect2(-340, -340, 680, 680))
		(_map_frame.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(12)
	else:
		_place(_map_frame, Control.PRESET_TOP_LEFT, Rect2(18, 16, 220, 220))
		(_map_frame.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(200)


func is_map_expanded() -> bool:
	return _minimap.expanded


func _process(delta: float) -> void:
	_update_tip(delta)
	var district := Game.district
	if district:
		for key: String in _meters:
			var entry: Array = _meters[key]
			var bar := entry[0] as HudBar
			var value: float = district.get(key)
			bar.value = value
			var word := "%s %d%%" % [entry[1], roundi(value * 100.0)]
			bar.text = word
	_allies_left -= delta
	if _allies_left <= 0.0:
		_allies_left = 0.5
		_refresh_status()
	if _player and is_instance_valid(_player):
		var driving := _player.vehicle != null
		_turbo.visible = driving
		if driving:
			_turbo.value = _player.vehicle.turbo_ratio()
			_turbo.text = "TURBO  [Shift]" if _turbo.value > 0.05 else "TURBO recharging"
		# Red vignette: flash on damage, pulse when low.
		_hurt = maxf(_hurt - delta * 1.2, 0.0)
		var ratio := _player.health / maxf(_player.max_health, 1.0)
		var low := clampf((0.5 - ratio) / 0.5, 0.0, 1.0)
		var pulse := low * (0.65 + 0.3 * sin(Time.get_ticks_msec() * 0.008))
		_vignette.modulate.a = clampf(maxf(_hurt, pulse), 0.0, 0.9)


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("HUD: no node in group 'player'")
		return
	_player.health_changed.connect(func(health: float, _m: float) -> void:
		if _last_health >= 0.0 and health < _last_health - 0.5:
			_hurt = minf(_hurt + 0.6, 0.9)
			_health.flash()
		_last_health = health
		_refresh_status())
	_player.charges_changed.connect(func(_c: int) -> void: _refresh_status())
	_player.hit_confirmed.connect(func(killed: bool) -> void:
		_hit_marker.show_hit(killed)
		Sfx.ui(&"hitmarker", -2.0 if killed else -8.0))
	_player.prompt_changed.connect(func(text: String) -> void:
		_prompt.text = text
		_prompt.visible = not text.is_empty())
	_player.weapon_changed.connect(func(_w: Weapon) -> void: _refresh_status())
	_last_health = _player.health
	_refresh_status()


## Pops a feedback line on the right that fades after `seconds`.
func show_toast(text: String, seconds := 5.0) -> void:
	var label := _make_label(_toasts, 18, HORIZONTAL_ALIGNMENT_RIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	label.add_theme_font_size_override("font_size", 16)
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
	if _player == null:
		return
	var health := maxf(_player.health, 0.0)
	_health.value = health / maxf(_player.max_health, 1.0)
	_health.text = "%d / %d" % [ceili(health), int(_player.max_health)]
	_kit.text = "C4 x%d      Treats x%d" % [_player.c4_charges, _player.treats]
	var allies := ally_count()
	if allies > 0:
		_kit.text += "      Allies x%d" % allies
	var weapon := _player.current_weapon()
	_weapon_name.text = "[Q] %s" % weapon.display_name
	_ammo.text = "--" if weapon.ammo < 0 else "%d / %d" % [weapon.ammo, weapon.max_ammo]
	_ammo.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if weapon.ammo == 0 else Color.WHITE)


## The between-waves card: a title and [label, value] rows, until the next
## wave starts or 14 s pass.
func show_wave_summary(title: String, rows: Array) -> void:
	hide_wave_summary()
	var panel := PanelContainer.new()
	panel.name = "WaveSummary"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.05, 0.86)
	style.border_color = UiTheme.ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var header := _make_label(box, 26, HORIZONTAL_ALIGNMENT_CENTER)
	header.text = title
	header.add_theme_color_override("font_color", UiTheme.ACCENT)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	box.add_child(grid)
	for row: Array in rows:
		var key := _make_label(grid, 17, HORIZONTAL_ALIGNMENT_LEFT)
		key.text = str(row[0])
		key.add_theme_color_override("font_color", UiTheme.MUTED)
		var value := _make_label(grid, 17, HORIZONTAL_ALIGNMENT_RIGHT)
		value.text = str(row[1])
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(260, 0)
	get_child(0).add_child(panel)
	_place(panel, Control.PRESET_CENTER_TOP, Rect2(-280, 150, 560, 0))
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Weak ref: the next wave may already have removed the card.
	var card: WeakRef = weakref(panel)
	get_tree().create_timer(14.0).timeout.connect(func() -> void:
		var node := card.get_ref() as Node
		if node:
			node.queue_free())


func hide_wave_summary() -> void:
	var old := get_child(0).get_node_or_null("WaveSummary")
	if old:
		old.queue_free()


func wave_summary_visible() -> bool:
	var panel := get_child(0).get_node_or_null("WaveSummary")
	return panel != null and not panel.is_queued_for_deletion()


## Rows currently shown for a checklist (tests read this).
func checklist_rows(key: String) -> Array:
	var entry: Array = _checklists.get(key, [null, []])
	return entry[1]


func _checklist_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.04, 0.62)
	style.border_color = Color(UiTheme.ACCENT, 0.6)
	style.border_width_right = 3
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 1)
	panel.add_child(rows)
	return panel


func _on_checklist_changed(key: String, title: String, rows: Array) -> void:
	var entry: Array = _checklists.get(key, [])
	if entry.is_empty() or entry[1] == rows:
		return
	entry[1] = rows.duplicate(true)
	var panel := entry[0] as PanelContainer
	panel.visible = not rows.is_empty()
	var box := panel.get_node("Rows") as VBoxContainer
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	if rows.is_empty():
		return
	var header := _make_label(box, 13, HORIZONTAL_ALIGNMENT_LEFT)
	header.text = title
	header.add_theme_color_override("font_color", UiTheme.ACCENT)
	for row: Array in rows:
		var line := _make_label(box, 15, HORIZONTAL_ALIGNMENT_LEFT)
		var state: StringName = row[1]
		var mark := {&"done": "[x] ", &"alert": "[!] ", &"info": "      "}.get(state, "[  ] ") as String
		line.text = mark + str(row[0])
		match state:
			&"done":
				line.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6, 0.8))
			&"alert":
				line.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
			&"info":
				line.add_theme_color_override("font_color", UiTheme.MUTED)


func _on_info_changed(key: String, text: String) -> void:
	var line := _info.get(key) as Label
	if line:
		line.text = text
		line.visible = not text.is_empty()


## Living allies on your side (befriended dogs, recruited Canadians).
func ally_count() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group("allies"):
		if node is Enemy and (node as Enemy).is_alive():
			total += 1
	return total


func overlay() -> HudOverlay:
	return _overlay


## Full-screen edge glow (transparent middle). The red one's alpha is driven by damage.
func _build_vignette(inner: Color, outer: Color, start: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, inner)
	gradient.set_color(1, outer)
	gradient.set_offset(0, start)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 256
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	return rect


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


## Four short strokes around the crosshair when a shot lands: white for a
## hit, red and bigger for a kill.
class _HitMarker extends Control:
	var _left := 0.0
	var _killed := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_hit(killed: bool) -> void:
		_left = 0.3 if killed else 0.15
		_killed = killed
		queue_redraw()

	func _process(delta: float) -> void:
		if _left > 0.0:
			_left -= delta
			queue_redraw()

	func _draw() -> void:
		if _left <= 0.0:
			return
		var c := size * 0.5
		var color := Color(1.0, 0.25, 0.2, minf(_left * 8.0, 1.0)) if _killed else Color(1, 1, 1, minf(_left * 8.0, 1.0))
		var inner := 7.0 if not _killed else 8.0
		var outer := 14.0 if not _killed else 19.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := (d as Vector2).normalized()
			draw_line(c + n * inner, c + n * outer, Color(0, 0, 0, color.a * 0.6), 5.0)
			draw_line(c + n * inner, c + n * outer, color, 2.5)


## A fixed-size control that draws one HudIcons icon.
class _IconControl extends Control:
	var kind: StringName
	var color: Color

	func _init(icon_kind: StringName, icon_color: Color, px: float) -> void:
		kind = icon_kind
		color = icon_color
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		HudIcons.draw(self, kind, size * 0.5, minf(size.x, size.y) * 0.9, color)
