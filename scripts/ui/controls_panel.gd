class_name ControlsPanel
extends PanelContainer
## Key reference for every phase.

signal closed

const SECTIONS := [
	["On foot", [
		["WASD", "Move"], ["Mouse", "Aim"], ["Shift", "Sprint"], ["Space", "Jump"],
		["Left click", "Fire"], ["Q / wheel", "Switch weapon"], ["E", "Drive / talk down / use"],
		["G", "Plant C4"], ["T", "Give a dog a treat"], ["F (hold)", "Repair / fix"],
	]],
	["Driving", [
		["W / S", "Throttle / reverse"], ["A / D", "Steer"], ["Space", "Brake"], ["E", "Get out"],
	]],
	["Defense", [
		["B", "Build mode"], ["1-4", "Pick structure"], ["R", "Rotate"], ["Left click", "Place"],
		["Right click", "Leave build mode"], ["N", "Start the next wave now"],
	]],
	["Anytime", [
		["V", "Bribe officials"], ["F10", "Graphics quality"], ["Esc / P", "Pause"],
	]],
]


func _ready() -> void:
	theme = UiTheme.get_theme()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(UiTheme.label("CONTROLS", 30, UiTheme.ACCENT))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	column.add_child(columns)
	for half in 2:
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 4)
		columns.add_child(side)
		for section: Array in SECTIONS.slice(half * 2, half * 2 + 2):
			side.add_child(UiTheme.label(section[0], 22, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 18)
			side.add_child(grid)
			for pair: Array in section[1]:
				grid.add_child(UiTheme.label(pair[0], 18, Color(1.0, 0.9, 0.5), HORIZONTAL_ALIGNMENT_RIGHT))
				grid.add_child(UiTheme.label(pair[1], 18, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
			side.add_child(Control.new())
	var back := UiTheme.button("Back", func() -> void: closed.emit(), 200.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)
