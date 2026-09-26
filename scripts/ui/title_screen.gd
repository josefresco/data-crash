extends Control
## Title screen: smoggy suburb skyline with the datacenter looming over it,
## and Play / Settings / Controls / Quit. The main scene (project.godot).

const LEVEL_SCENE := "res://scenes/levels/test_block.tscn"

var _menu: VBoxContainer
var _panel_holder: CenterContainer
var _clock := 0.0
var _smoke: Array[Polygon2D] = []


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	center.add_child(_menu)
	var title := UiTheme.label("DATA CRASH", 96, Color(0.95, 0.97, 0.94))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.07))
	title.add_theme_constant_override("outline_size", 18)
	_menu.add_child(title)
	_menu.add_child(UiTheme.label("Sabotage the server farm. Save the suburb.", 24, UiTheme.ACCENT))
	_menu.add_child(Control.new())
	for entry in [["Play", _play], ["Settings", _show_panel.bind(SettingsPanel)],
			["Controls", _show_panel.bind(ControlsPanel)], ["Quit", func() -> void: get_tree().quit()]]:
		var node := UiTheme.button(entry[0], entry[1], 340.0)
		node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_menu.add_child(node)
	(_menu.get_child(3) as Button).grab_focus()

	_panel_holder = CenterContainer.new()
	_panel_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_holder)

	var footer := UiTheme.label("Esc pauses in game  •  Models, sounds, and textures: Kenney and ambientCG (CC0)  •  Godot 4.7",
		15, UiTheme.MUTED)
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.offset_top = -40
	footer.offset_left = -500
	footer.offset_right = 500
	add_child(footer)


func _process(delta: float) -> void:
	_clock += delta
	for i in _smoke.size():
		var puff := _smoke[i]
		puff.position.y -= delta * (18.0 + i % 3 * 6.0)
		puff.position.x += sin(_clock * 0.7 + i) * delta * 10.0
		puff.modulate.a = clampf(puff.position.y / 500.0, 0.0, 0.7)
		if puff.position.y < 40.0:
			puff.position = puff.get_meta(&"origin")


func _play() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _show_panel(kind: GDScript) -> void:
	for child in _panel_holder.get_children():
		child.queue_free()
	var panel := kind.new() as Control
	panel.connect(&"closed", func() -> void:
		panel.queue_free()
		_menu.visible = true)
	_panel_holder.add_child(panel)
	_menu.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _panel_holder.get_child_count() > 0:
		for child in _panel_holder.get_children():
			child.queue_free()
		_menu.visible = true


## Gradient sky, the datacenter with smoking stacks, and a row of houses.
func _build_backdrop() -> void:
	var size := Vector2(1600, 900)
	var sky := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.36, 0.27, 0.17))
	gradient.set_color(1, Color(0.78, 0.6, 0.38))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	sky.texture = texture
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)

	var scene := Node2D.new()
	add_child(scene)
	var fit := func() -> void:
		var view := get_viewport_rect().size
		scene.scale = Vector2.ONE * maxf(view.x / size.x, view.y / size.y)
	fit.call()
	get_viewport().size_changed.connect(fit)
	var far := Color(0.22, 0.17, 0.12)
	var near := Color(0.1, 0.08, 0.06)
	# Datacenter block, stacks, and cooling units.
	_poly(scene, [Vector2(900, 640), Vector2(900, 470), Vector2(1400, 470), Vector2(1400, 640)], far)
	for x in [980.0, 1080.0, 1180.0]:
		_poly(scene, [Vector2(x, 640), Vector2(x, 330), Vector2(x + 26, 330), Vector2(x + 26, 640)], far)
		for k in 6:
			var puff := _poly(scene, _circle(22.0 + k * 3.0), Color(0.5, 0.42, 0.34, 0.5))
			var origin := Vector2(x + 13, 320 - k * 45)
			puff.position = origin
			puff.set_meta(&"origin", Vector2(x + 13, 320))
			_smoke.append(puff)
	for k in 12:
		var led := _poly(scene, [Vector2(0, 0), Vector2(14, 0), Vector2(14, 4), Vector2(0, 4)], Color(0.3, 0.85, 1.0))
		led.position = Vector2(930 + k * 38, 520)
	# Houses in the foreground.
	var x := -20.0
	while x < 1650.0:
		var w := randf_range(120.0, 180.0)
		var h := randf_range(90.0, 130.0)
		var base := 900.0 - randf_range(90.0, 130.0)
		_poly(scene, [Vector2(x, 900), Vector2(x, base - h * 0.4), Vector2(x + w * 0.5, base - h), Vector2(x + w, base - h * 0.4), Vector2(x + w, 900)], near)
		var window := _poly(scene, [Vector2(0, 0), Vector2(18, 0), Vector2(18, 16), Vector2(0, 16)], Color(1.0, 0.8, 0.45, 0.9))
		window.position = Vector2(x + w * 0.3, base - h * 0.15)
		x += w + randf_range(10.0, 60.0)


func _poly(parent: Node, points: Array, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array(points)
	poly.color = color
	parent.add_child(poly)
	return poly


func _circle(radius: float) -> Array:
	var points := []
	for i in 12:
		points.append(Vector2.from_angle(TAU * i / 12.0) * radius)
	return points
