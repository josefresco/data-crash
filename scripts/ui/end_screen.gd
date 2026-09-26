class_name EndScreen
extends CanvasLayer
## Win / lose screen with the run's stats (Game.stats). The world keeps
## running behind it (tests and the balance sim rely on game time moving).

const TITLE_SCENE := "res://scenes/ui/title.tscn"

var is_shown := false
## The last stats table shown, as [label, value] pairs (tests read it).
var rows: Array = []


func show_result(won: bool, waves_cleared: int, total_waves: int) -> void:
	if is_shown:
		return
	is_shown = true
	layer = 40
	var column := UiTheme.overlay(self, 0.6)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	column.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	body.add_child(UiTheme.label("DISTRICT RESTORED" if won else "THE GREEN CORE FELL", 40,
		UiTheme.ACCENT if won else Color(1.0, 0.45, 0.35)))
	body.add_child(UiTheme.label("Water is flowing, the air is clear, and the block is yours." if won
		else "Felsa Cloud's crews are pouring concrete. The neighbors will remember you tried.", 18, UiTheme.MUTED))

	var minutes := int(Game.stat("time")) / 60
	var seconds := int(Game.stat("time")) % 60
	rows = [
		["Time", "%d:%02d" % [minutes, seconds]],
		["Waves held", "%d / %d" % [waves_cleared, total_waves]],
		["Hostiles stopped", str(int(Game.stat("kills")))],
		["Shots fired", str(int(Game.stat("shots")))],
		["Cash earned", "$%d" % int(Game.stat("cash_earned"))],
		["Structures built", str(int(Game.stat("built")))],
		["Good deeds", str(int(Game.stat("deeds")))],
		["Grock cameras smashed", str(int(Game.stat("cameras")))],
		["Dogs befriended", str(int(Game.stat("dogs")))],
		["Protesters talked down", str(int(Game.stat("talked_down")))],
		["Neighborhood trust", "%d%%" % roundi((Game.district.trust if Game.district else 0.0) * 100.0)],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(grid)
	for row: Array in rows:
		grid.add_child(UiTheme.label(row[0], 20, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UiTheme.label(row[1], 20, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	body.add_child(buttons)
	buttons.add_child(UiTheme.button("Play again", func() -> void: get_tree().reload_current_scene(), 220.0))
	buttons.add_child(UiTheme.button("Title screen", func() -> void: get_tree().change_scene_to_file(TITLE_SCENE), 220.0))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ui(&"jingle_win" if won else &"jingle_lose", 0.0, "Music")
