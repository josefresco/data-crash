extends Node
## Global game state: cash, active district, current objective, and the input map.

signal cash_changed(cash: int)
signal objective_changed(text: String)

## Physics layer bits. Keep in sync with [layer_names] in project.godot.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_VEHICLES := 4
const LAYER_DEBRIS := 8
const LAYER_DESTRUCTIBLE := 16

var cash: int = 0
var district: DistrictState
var objective: String = ""


func _ready() -> void:
	_register_input_actions()


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


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
