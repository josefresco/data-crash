class_name SettingsPanel
extends PanelContainer
## Settings: graphics quality, fullscreen, mouse sensitivity, bus volumes, and
## tips. Changes apply live; everything persists to user://settings.cfg
## (sections graphics, audio, game).

signal closed

const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]


func _ready() -> void:
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(620, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(UiTheme.label("SETTINGS", 30, UiTheme.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)

	var quality := OptionButton.new()
	for name in QUALITY_NAMES:
		quality.add_item(name)
	quality.selected = EnvironmentDriver.saved_quality()
	quality.item_selected.connect(func(index: int) -> void:
		Sfx.ui(&"click")
		EnvironmentDriver.save_quality(index)
		get_tree().call_group(&"environment_drivers", &"set_quality", index))
	_row(grid, "Graphics quality (F10)", quality)

	var fullscreen := CheckBox.new()
	fullscreen.button_pressed = Game.fullscreen
	fullscreen.toggled.connect(func(on: bool) -> void:
		Sfx.ui(&"click")
		Game.fullscreen = on
		Game.apply_display()
		Game.save_settings())
	_row(grid, "Fullscreen", fullscreen)

	var sensitivity := _slider(0.2, 3.0, Game.mouse_sensitivity / Game.DEFAULT_SENSITIVITY)
	sensitivity.value_changed.connect(func(value: float) -> void:
		Game.mouse_sensitivity = Game.DEFAULT_SENSITIVITY * value
		Game.save_settings())
	_row(grid, "Mouse sensitivity", sensitivity)

	for bus: String in ["Master", "Music", "SFX", "UI", "Ambience"]:
		var volume := _slider(0.0, 1.0, Sfx.volumes.get(bus, 1.0))
		volume.value_changed.connect(func(value: float) -> void:
			Sfx.set_volume(bus, value)
			Sfx.save_settings())
		_row(grid, "%s volume" % ("Jingles" if bus == "Music" else bus), volume)

	var tips := CheckBox.new()
	tips.button_pressed = Game.show_tips
	tips.toggled.connect(func(on: bool) -> void:
		Sfx.ui(&"click")
		Game.show_tips = on
		Game.save_settings())
	_row(grid, "Show tips", tips)

	var back := UiTheme.button("Back", func() -> void: closed.emit(), 200.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)


func _row(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(UiTheme.label(text, 20, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	control.custom_minimum_size.x = 260
	grid.add_child(control)


func _slider(low: float, high: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 28)
	return slider
