extends Node
## Global game state: cash, active district, current objective, and the input map.

signal cash_changed(cash: int)
signal objective_changed(text: String)
## Keyed HUD lines ("deeds", "boss", "wave", "core", "build", "bribe", "notice"). Empty text hides the line.
signal info_changed(key: String, text: String)
## Short-lived feedback line ("Rocket launcher acquired").
signal notice(text: String, seconds: float)
## A one-time contextual tip (see tip()).
signal tip_shown(text: String)

## Physics layer bits. Keep in sync with [layer_names] in project.godot.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_VEHICLES := 4
const LAYER_DEBRIS := 8
const LAYER_DESTRUCTIBLE := 16
const LAYER_ENEMIES := 32

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.0025

var cash: int = 0
var district: DistrictState
var objective: String = ""
## Pending one-shot favors bought from officials (see BribeMenu).
var bribes := {}
## Per-run counters for the end screen: kills, shots, cash_earned, built,
## repaired, deeds, dogs, talked_down, time.
var stats := {}
## Settings menu toggle. Tips already shown stay hidden for the whole session.
var show_tips := true
var _tips_seen := {}
## Radians per pixel of mouse motion (settings menu).
var mouse_sensitivity := DEFAULT_SENSITIVITY
var fullscreen := false


func _ready() -> void:
	_register_input_actions()
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = float(config.get_value("game", "mouse_sensitivity", mouse_sensitivity))
	show_tips = bool(config.get_value("game", "show_tips", show_tips))
	fullscreen = bool(config.get_value("game", "fullscreen", fullscreen))
	apply_display()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep the other sections
	config.set_value("game", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("game", "show_tips", show_tips)
	config.set_value("game", "fullscreen", fullscreen)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Couldn't save settings (error %d)" % err)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## Fresh state for a (re)loaded level.
func reset() -> void:
	cash = 0
	bribes.clear()
	stats = {}
	district = DistrictState.new()
	cash_changed.emit(cash)
	for key in ["deeds", "boss", "wave", "core", "build", "bribe", "notice"]:
		set_info(key, "")


func set_info(key: String, text: String) -> void:
	info_changed.emit(key, text)


func notify(text: String, seconds := 5.0) -> void:
	notice.emit(text, seconds)


## Shows `text` once per session under `key`. Returns true if it was shown.
func tip(key: String, text: String) -> bool:
	if not show_tips or _tips_seen.has(key):
		return false
	_tips_seen[key] = true
	tip_shown.emit(text)
	return true


func has_seen_tip(key: String) -> bool:
	return _tips_seen.has(key)


func count(stat: String, amount: float = 1.0) -> void:
	stats[stat] = stats.get(stat, 0.0) + amount


func stat(key: String) -> float:
	return stats.get(key, 0.0)


func has_bribe(key: String) -> bool:
	return bribes.get(key, false)


## Uses up a pending bribe. Returns true if there was one.
func consume_bribe(key: String) -> bool:
	if not has_bribe(key):
		return false
	bribes.erase(key)
	return true


func add_cash(amount: int) -> void:
	cash += amount
	if amount > 0:
		count("cash_earned", amount)
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
		"pause": KEY_ESCAPE,
		"treat": KEY_T,
		"repair": KEY_F,
		"next_weapon": KEY_Q,
		"bribe_menu": KEY_V,
		"graphics_quality": KEY_F10,
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

	var pause_key := InputEventKey.new()
	pause_key.physical_keycode = KEY_P
	InputMap.action_add_event("pause", pause_key)

	_ensure_action("fire")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", click)

	for pair in [["next_weapon", MOUSE_BUTTON_WHEEL_UP], ["prev_weapon", MOUSE_BUTTON_WHEEL_DOWN]]:
		_ensure_action(pair[0])
		var wheel := InputEventMouseButton.new()
		wheel.button_index = pair[1]
		InputMap.action_add_event(pair[0], wheel)

	_ensure_action("cancel")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("cancel", right_click)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
