extends Node
## Global game state: cash, active district, current objective, and the input map.

signal cash_changed(cash: int)
signal objective_changed(text: String)
## Keyed HUD lines ("wave", "core", "build"). Empty text hides the line.
signal info_changed(key: String, text: String)

## Physics layer bits. Keep in sync with [layer_names] in project.godot.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_VEHICLES := 4
const LAYER_DEBRIS := 8
const LAYER_DESTRUCTIBLE := 16
const LAYER_ENEMIES := 32

var cash: int = 0
var district: DistrictState
var objective: String = ""


func _ready() -> void:
	_register_input_actions()


## Fresh state for a (re)loaded level.
func reset() -> void:
	cash = 0
	district = DistrictState.new()
	cash_changed.emit(cash)
	for key in ["wave", "core", "build"]:
		set_info(key, "")


func set_info(key: String, text: String) -> void:
	info_changed.emit(key, text)


func add_cash(amount: int) -> void:
	cash += amount
	cash_changed.emit(cash)


func set_objective(text: String) -> void:
	objective = text
	objective_changed.emit(text)


func _register_input_actions() -> void:
	var keys := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"interact": KEY_E,
		"plant": KEY_G,
		"toggle_mouse": KEY_ESCAPE,
		"treat": KEY_T,
		"build_mode": KEY_B,
		"start_wave": KEY_N,
		"rotate": KEY_R,
		"retry": KEY_ENTER,
		"slot_1": KEY_1,
		"slot_2": KEY_2,
		"slot_3": KEY_3,
		"slot_4": KEY_4,
	}
	for action: String in keys:
		_ensure_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)

	_ensure_action("fire")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", click)

	_ensure_action("cancel")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("cancel", right_click)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
