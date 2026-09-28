extends Node
## Global game state: cash, active district, current objective, and the input map.

signal cash_changed(cash: int)
signal objective_changed(text: String)
## Keyed HUD lines ("deeds", "boss", "wave", "core", "build", "bribe", "notice"). Empty text hides the line.
signal info_changed(key: String, text: String)
## The boss health bar: name ("" hides it), 0..1 health, and a short hint.
signal boss_changed(boss_name: String, ratio: float, hint: String)
## A titled checklist on the HUD's right column ("sites", "deeds"). Each row is
## [text, state] with state &"todo", &"done", &"alert", or &"info". No rows hides it.
signal checklist_changed(key: String, title: String, rows: Array)
## Short-lived feedback line ("Rocket launcher acquired").
signal notice(text: String, seconds: float)
## A one-time contextual tip (see tip()).
signal tip_shown(text: String)
## A big center-screen title card (phase changes, waves, wins).
signal banner(title: String, subtitle: String)

## Physics layer bits. Keep in sync with [layer_names] in project.godot.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_VEHICLES := 4
const LAYER_DEBRIS := 8
const LAYER_DESTRUCTIBLE := 16
const LAYER_ENEMIES := 32
## Ragdolls: they collide with the world and props only, so cars run over
## bodies instead of bouncing off (or being launched by) them.
const LAYER_BODIES := 64

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
## Datacenter sites on alert (the player attacked them): site id -> true.
## Units and props tagged with a site stay passive until theirs is raised.
var alarms := {}
## Radians per pixel of mouse motion (settings menu).
var mouse_sensitivity := DEFAULT_SENSITIVITY
var fullscreen := false
## 0 Easy, 1 Normal, 2 Hard (settings menu): scales damage the player takes,
## hostile health, and wave sizes.
var difficulty := 1
const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]
## Set by the title screen for the next level load.
var pending_intro := false
var pending_save := {}


## The campaign, in order: [scene, name]. Winning a district unlocks the
## next; each one starts fresh (cash, weapons, and trust reset on load).
const DISTRICTS := [
	["res://scenes/levels/test_block.tscn", "Maple Grove"],
	["res://scenes/levels/district_2.tscn", "Riverbend"],
]
const PROGRESS_PATH := "user://progress.cfg"
## Scenes under res://tests/ use their own progress file (never the player's).
const TEST_PROGRESS_PATH := "user://progress_test.cfg"
## How many districts can be played (at least the first).
var districts_unlocked := 1


func district_scene(index: int) -> String:
	return DISTRICTS[clampi(index, 0, DISTRICTS.size() - 1)][0]


func district_name(index: int) -> String:
	return DISTRICTS[clampi(index, 0, DISTRICTS.size() - 1)][1]


func _progress_file() -> String:
	var scene := get_tree().current_scene
	return TEST_PROGRESS_PATH if scene and scene.scene_file_path.begins_with("res://tests/") else PROGRESS_PATH


func load_progress() -> void:
	districts_unlocked = 1
	var config := ConfigFile.new()
	if config.load(_progress_file()) == OK:
		districts_unlocked = clampi(int(config.get_value("campaign", "unlocked", 1)), 1, DISTRICTS.size())


## Unlocks district `index` (0-based). Returns true when it was locked.
func unlock_district(index: int) -> bool:
	if index >= DISTRICTS.size() or index < districts_unlocked:
		return false
	districts_unlocked = index + 1
	var config := ConfigFile.new()
	config.set_value("campaign", "unlocked", districts_unlocked)
	var err := config.save(_progress_file())
	if err != OK:
		push_warning("Couldn't save progress (error %d)" % err)
	return true


## Tests: back to only the first district (the test progress file).
func reset_progress() -> void:
	districts_unlocked = 1
	var file := _progress_file()
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))


## Quits after freeing the running scene and letting a few frames pass.
## Tearing a live level (physics bodies, ragdoll joints, audio loops) down
## inside the engine's own shutdown segfaulted now and then; freeing it
## while the tree still runs normally doesn't. Tests, the title's Quit, and
## the window's close button all come through here.
func quit_cleanly(code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	var scene := get_tree().current_scene
	if scene:
		scene.queue_free()
	for i in 3:
		await get_tree().process_frame
	_release_static_caches()
	await get_tree().process_frame
	get_tree().quit(code)


## Static caches of materials, meshes, and textures would otherwise be freed
## during script unload, after the rendering server is already gone.
func _release_static_caches() -> void:
	Models._materials.clear()
	Car._plate_mat = null
	Car._trim_mat = null
	Car._chrome_mat = null
	Models._scenes.clear()
	Models._retextured.clear()
	Models._textures.clear()
	Models._beam_materials.clear()
	Fx._streak_mats.clear()
	Vfx._quads.clear()
	Vfx._flame_mats.clear()
	Vfx._scorches.clear()
	Vfx._holes.clear()
	CharacterModel._library = null
	Car._skid_material = null
	UiTheme._theme = null
	Enemy._talkers.clear()
	DatacenterSite._art.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_cleanly()


func _ready() -> void:
	get_tree().auto_accept_quit = false  # the close button goes through quit_cleanly()
	load_progress.call_deferred()  # after the main scene is set (test scenes use their own file)
	_register_input_actions()
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = float(config.get_value("game", "mouse_sensitivity", mouse_sensitivity))
	show_tips = bool(config.get_value("game", "show_tips", show_tips))
	fullscreen = bool(config.get_value("game", "fullscreen", fullscreen))
	difficulty = clampi(int(config.get_value("game", "difficulty", difficulty)), 0, 2)
	apply_display()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep the other sections
	config.set_value("game", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("game", "show_tips", show_tips)
	config.set_value("game", "fullscreen", fullscreen)
	config.set_value("game", "difficulty", difficulty)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Couldn't save settings (error %d)" % err)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func damage_taken_scale() -> float:
	return [0.6, 1.0, 1.4][difficulty]


func enemy_health_scale() -> float:
	return [0.8, 1.0, 1.25][difficulty]


func wave_size_scale() -> float:
	return [0.75, 1.0, 1.25][difficulty]


## Fresh state for a (re)loaded level.
var _quitting := false
## Sites fully scouted by the recon drone (site id -> true); per level.
var recons := {}


func reset() -> void:
	cash = 0
	bribes.clear()
	recons.clear()
	stats = {}
	alarms = {}
	district = DistrictState.new()
	cash_changed.emit(cash)
	for key in ["sites", "deeds", "boss", "wave", "core", "build", "bribe", "shop", "notice", "drone"]:
		set_info(key, "")
	for key in ["sites", "deeds"]:
		set_checklist(key, "", [])
	set_boss("")


func set_boss(boss_name: String, ratio := 0.0, hint := "") -> void:
	boss_changed.emit(boss_name, ratio, hint)


func set_info(key: String, text: String) -> void:
	info_changed.emit(key, text)


func set_checklist(key: String, title: String, rows: Array) -> void:
	checklist_changed.emit(key, title, rows)


func is_alarmed(site: StringName) -> bool:
	return alarms.get(site, false)


## True once any site has been attacked.
func any_alarm() -> bool:
	return not alarms.is_empty()


func show_banner(title: String, subtitle := "") -> void:
	banner.emit(title, subtitle)


## Shakes the active camera (explosions): `strength` fades with distance.
func shake(at: Vector3, strength: float) -> void:
	get_tree().call_group(&"camera_fx", &"shake", at, strength)


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
		"slot_5": KEY_5,
		"map": KEY_M,
		"drone": KEY_X,
		"descend": KEY_C,
		"crouch": KEY_C,
		"binoculars": KEY_Z,
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
	# Hold right click to aim (build mode uses the same button to exit).
	_ensure_action("aim")
	var aim_click := InputEventMouseButton.new()
	aim_click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("aim", aim_click)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
