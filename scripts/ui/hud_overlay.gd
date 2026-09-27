class_name HudOverlay
extends Control
## World-anchored HUD drawn over the 3D view (full screen, ignores the mouse):
## - the objective marker (from `level.guidance_point()`) with its distance,
##   pinned to the screen edge when it's off screen or behind you
## - health bars over nearby hostiles that are hurt or fighting, and a "!"
##   when one starts fighting
## - floating damage numbers for the player's hits
## - red arcs around the crosshair pointing toward whatever just hurt you
## - big title cards (Game.banner)

const EDGE := 56.0
const BAR_RANGE := 45.0
const ALERT_SECONDS := 1.3
const NUMBER_SECONDS := 0.9
const ARC_SECONDS := 1.2
const BANNER_SECONDS := 3.2
const GOLD := Color(1.0, 0.85, 0.15)

var _player: Player
var _level: Node
var _font: Font
var _goal: Variant = null
var _scan_left := 0.0
var _units: Array[Enemy] = []
## instance id -> seconds of "!" left; instance id -> was fighting last scan.
var _alerts := {}
var _engaged := {}
## [world position, text, seconds left, killed]
var _numbers: Array[Array] = []
## [world position the hit came from, seconds left, strength]
var _arcs: Array[Array] = []
var _banner_title := ""
var _banner_sub := ""
var _banner_left := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Game.banner.connect(show_banner)


func show_banner(title: String, subtitle := "") -> void:
	_banner_title = title
	_banner_sub = subtitle
	_banner_left = BANNER_SECONDS


## The banner on screen ("" when none). Tests read this.
func current_banner() -> String:
	return _banner_title if _banner_left > 0.0 else ""


## Where the objective marker points (null when hidden). Tests read this.
func objective_point() -> Variant:
	return _goal


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player:
			_player.damage_dealt.connect(_on_damage_dealt)
			_player.hurt_from.connect(_on_hurt)
	if _level == null or not is_instance_valid(_level):
		_level = get_tree().get_first_node_in_group("level")
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.2
		_scan()
	for id: int in _alerts.keys():
		_alerts[id] -= delta
		if _alerts[id] <= 0.0:
			_alerts.erase(id)
	for entry in _numbers:
		entry[2] -= delta
	_numbers = _numbers.filter(func(e: Array) -> bool: return e[2] > 0.0)
	for entry in _arcs:
		entry[1] -= delta
	_arcs = _arcs.filter(func(e: Array) -> bool: return e[1] > 0.0)
	_banner_left = maxf(_banner_left - delta, 0.0)
	queue_redraw()


func _scan() -> void:
	_goal = _level.call(&"guidance_point") if _level and _level.has_method("guidance_point") else null
	_units.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit == null or not unit.is_alive() or unit.is_dormant() or unit.boss_name != "":
			continue
		var id := unit.get_instance_id()
		var fighting := is_instance_valid(unit.target)
		if fighting and not _engaged.get(id, false) and unit.global_position.distance_to(eye) < BAR_RANGE:
			_alerts[id] = ALERT_SECONDS
		_engaged[id] = fighting
		if unit.global_position.distance_to(eye) < BAR_RANGE and (fighting or unit.health < unit.max_health):
			_units.append(unit)
	if _engaged.size() > 400:
		_engaged.clear()


func _on_damage_dealt(at: Vector3, amount: float, killed: bool) -> void:
	var jitter := Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.3), randf_range(-0.3, 0.3))
	_numbers.append([at + jitter, str(ceili(amount)), NUMBER_SECONDS, killed])
	if _numbers.size() > 24:
		_numbers.pop_front()


func _on_hurt(from: Vector3, amount: float) -> void:
	if _player == null or from.distance_to(_player.global_position) < 0.8:
		return  # fires, gas, and other sourceless damage
	_arcs.append([from, ARC_SECONDS, clampf(amount / 20.0, 0.35, 1.0)])
	if _arcs.size() > 6:
		_arcs.pop_front()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for unit in _units:
		if is_instance_valid(unit):
			_draw_unit(camera, unit)
	for entry in _numbers:
		_draw_number(camera, entry)
	if _goal != null:
		_draw_goal(camera, _goal as Vector3)
	for entry in _arcs:
		_draw_arc(camera, entry)
	if _banner_left > 0.0:
		_draw_banner()


func _draw_unit(camera: Camera3D, unit: Enemy) -> void:
	var head := unit.global_position + Vector3.UP * (unit.body_height + 0.45)
	if camera.is_position_behind(head):
		return
	var p := camera.unproject_position(head)
	var distance := camera.global_position.distance_to(head)
	var fade := clampf((BAR_RANGE - distance) / 10.0, 0.0, 1.0)
	var width := lerpf(52.0, 30.0, clampf(distance / BAR_RANGE, 0.0, 1.0))
	var ratio := clampf(unit.health / maxf(unit.max_health, 1.0), 0.0, 1.0)
	var rect := Rect2(p - Vector2(width * 0.5, 0.0), Vector2(width, 5.0))
	draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.7 * fade))
	var fill := Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.75, 0.2), ratio)
	draw_rect(Rect2(rect.position, Vector2(width * ratio, 5.0)), Color(fill, fade))
	var id := unit.get_instance_id()
	if _alerts.has(id):
		var t: float = _alerts[id]
		var pop := 1.0 + maxf(t - (ALERT_SECONDS - 0.2), 0.0) * 3.0
		var font_size := int(28.0 * pop)
		var at := p + Vector2(-font_size * 0.2, -10.0)
		draw_string_outline(_font, at, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, minf(t * 3.0, 1.0)))
		draw_string(_font, at, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.3, 0.2, minf(t * 3.0, 1.0)))


func _draw_number(camera: Camera3D, entry: Array) -> void:
	var t: float = 1.0 - entry[2] / NUMBER_SECONDS
	var at: Vector3 = entry[0] + Vector3.UP * t * 1.2
	if camera.is_position_behind(at):
		return
	var p := camera.unproject_position(at)
	var killed: bool = entry[3]
	var font_size := 26 if killed else 20
	var color := Color(1.0, 0.35, 0.25) if killed else Color(1.0, 0.95, 0.7)
	color.a = clampf((1.0 - t) * 2.5, 0.0, 1.0)
	var text: String = entry[1]
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(_font, p - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0, 0, 0, color.a))
	draw_string(_font, p - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Diamond marker over the objective; pinned to the screen edge (with an
## arrow) when it's off screen.
func _draw_goal(camera: Camera3D, goal: Vector3) -> void:
	var here := _player.global_position if _player else camera.global_position
	var distance := Vector2(goal.x - here.x, goal.z - here.z).length()
	if distance < 4.0:
		return
	var point := goal + Vector3.UP * 2.5
	var screen := size
	var center := screen * 0.5
	var behind := camera.is_position_behind(point)
	var p := camera.unproject_position(point)
	if behind:
		p = center - (p - center) * 1000.0
	if screen.x < EDGE * 4.0 or screen.y < EDGE * 4.0:
		return  # tiny (headless) viewport
	var inner := Rect2(Vector2(EDGE, EDGE + 40.0), screen - Vector2(EDGE * 2.0, EDGE * 2.0 + 120.0))
	var pinned := behind or not inner.has_point(p)
	if pinned:
		var d := p - center
		var fit := INF
		if absf(d.x) > 0.001:
			fit = minf(fit, (inner.size.x * 0.5) / absf(d.x))
		if absf(d.y) > 0.001:
			fit = minf(fit, (inner.size.y * 0.5) / absf(d.y))
		p = center + d * minf(fit, 1.0)
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
	var r := 11.0 * pulse
	var diamond := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(diamond, Color(GOLD, 0.9))
	diamond.append(diamond[0])
	draw_polyline(diamond, Color(0, 0, 0, 0.8), 2.0)
	if pinned:
		var dir := (p - center).normalized()
		var tip := p + dir * (r + 12.0)
		var side := Vector2(-dir.y, dir.x) * 7.0
		draw_colored_polygon(PackedVector2Array([tip, p + dir * (r + 3.0) + side, p + dir * (r + 3.0) - side]), GOLD)
	var text := "%d m" % roundi(distance)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var at := p + Vector2(-width * 0.5, r + 20.0)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.85))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)


## A red arc around the crosshair toward the attacker (up = in front).
func _draw_arc(camera: Camera3D, entry: Array) -> void:
	var from: Vector3 = entry[0]
	var local := camera.global_basis.inverse() * (from - camera.global_position)
	var angle := atan2(local.x, -local.z) - PI * 0.5
	var alpha: float = clampf(entry[1] / ARC_SECONDS, 0.0, 1.0) * float(entry[2])
	var center := size * 0.5
	draw_arc(center, 120.0, angle - 0.35, angle + 0.35, 16, Color(0, 0, 0, alpha * 0.5), 12.0)
	draw_arc(center, 120.0, angle - 0.32, angle + 0.32, 16, Color(1.0, 0.15, 0.1, alpha), 8.0)


func _draw_banner() -> void:
	var t := BANNER_SECONDS - _banner_left
	var alpha := clampf(minf(t * 4.0, _banner_left * 2.0), 0.0, 1.0)
	var y := size.y * 0.3
	var slide := (1.0 - clampf(t * 4.0, 0.0, 1.0)) * 30.0
	draw_rect(Rect2(0.0, y - 58.0, size.x, 92.0), Color(0.0, 0.0, 0.0, 0.45 * alpha))
	draw_rect(Rect2(size.x * 0.3, y + 32.0, size.x * 0.4, 2.0), Color(UiTheme.ACCENT, alpha))
	var width := _font.get_string_size(_banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	var at := Vector2((size.x - width) * 0.5 - slide, y)
	draw_string_outline(_font, at, _banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 8, Color(0, 0, 0, alpha))
	draw_string(_font, at, _banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(1, 1, 1, alpha))
	if _banner_sub != "":
		width = _font.get_string_size(_banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		at = Vector2((size.x - width) * 0.5 + slide, y + 26.0)
		draw_string(_font, at, _banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UiTheme.ACCENT, alpha))
