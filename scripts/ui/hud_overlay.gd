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
## - speech as chat bubbles: Label3Ds registered with as_bubble() are hidden
##   and drawn here as rounded bubbles with a tail (bosses get a red border)

const EDGE := 56.0
const BAR_RANGE := 45.0
const ALERT_SECONDS := 1.3
const NUMBER_SECONDS := 0.9
const ARC_SECONDS := 1.2
const BANNER_SECONDS := 3.2
const GOLD := Color(1.0, 0.85, 0.15)
const BUBBLE_RANGE := 45.0
const BUBBLE_WIDTH := 240.0

var _player: Player
var _level: Node
var _font: Font
var _goal: Variant = null
var _scan_left := 0.0
var _units: Array[Enemy] = []
## Hostiles marked by the recon drone (drawn through walls, any distance).
var _spotted: Array[Enemy] = []
## Quiet site security getting suspicious of the player (stealth).
var _suspicious: Array[Enemy] = []
## instance id -> seconds of "!" left; instance id -> was fighting last scan.
var _alerts := {}
var _engaged := {}
## [world position, text, seconds left, killed]
var _numbers: Array[Array] = []
## [world position the hit came from, seconds left, strength]
var _arcs: Array[Array] = []
var _speakers: Array[Label3D] = []
var _bubble_style: StyleBoxFlat
var _banner_title := ""
var _banner_sub := ""
var _banner_left := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Game.banner.connect(show_banner)


## Turns a speech Label3D into a chat bubble: the 3D text is hidden and the
## overlay draws its text in a bubble at the label's position.
static func as_bubble(label: Label3D, boss := false) -> void:
	label.visible = false
	label.add_to_group(&"speech")
	label.set_meta(&"boss", boss)


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
			_player.headshot_landed.connect(_on_headshot)
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
	_spotted.clear()
	_suspicious.clear()
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit and unit.is_alive() and unit.spotted_left > 0.0:
			_spotted.append(unit)
		if unit and unit.is_alive() and unit.suspicion > 0.02 and unit.is_dormant() \
				and unit.global_position.distance_to(eye) < BAR_RANGE:
			_suspicious.append(unit)
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
	_speakers.clear()
	var space := camera.get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group(&"speech"):
		var label := node as Label3D
		if label == null or label.text.is_empty() or not label.is_inside_tree() 				or label.global_position.distance_to(eye) >= BUBBLE_RANGE:
			continue
		# Hidden behind a building or prop: no bubble through the wall.
		var head := label.global_position + Vector3.DOWN * 0.8
		var ray := PhysicsRayQueryParameters3D.create(eye, head, 1 | 16)
		if space.intersect_ray(ray).is_empty():
			_speakers.append(label)


func _on_headshot(at: Vector3) -> void:
	_numbers.append([at + Vector3.UP * 0.45, "HEADSHOT", NUMBER_SECONDS * 1.3, true])
	if _numbers.size() > 24:
		_numbers.pop_front()


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
	for unit in _spotted:
		if is_instance_valid(unit):
			_draw_spotted(camera, unit)
	for unit in _suspicious:
		if is_instance_valid(unit):
			_draw_suspicion(camera, unit)
	for unit in _units:
		if is_instance_valid(unit):
			_draw_unit(camera, unit)
	for label in _speakers:
		if is_instance_valid(label):
			_draw_bubble(camera, label)
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


## Drone mark: a red chevron over the unit's head, through walls, with its
## distance once it's far. Fades out over the mark's last seconds.
func _draw_spotted(camera: Camera3D, unit: Enemy) -> void:
	var head := unit.global_position + Vector3.UP * (unit.body_height + 0.9)
	if camera.is_position_behind(head):
		return
	var p := camera.unproject_position(head)
	var alpha := clampf(unit.spotted_left / 3.0, 0.0, 1.0)
	var color := Color(1.0, 0.25, 0.2, 0.9 * alpha)
	var s := 7.0
	var chevron := PackedVector2Array([p + Vector2(-s, -s), p + Vector2(0, 0), p + Vector2(s, -s)])
	draw_polyline(chevron, Color(0, 0, 0, 0.7 * alpha), 5.0)
	draw_polyline(chevron, color, 2.5)
	var distance := camera.global_position.distance_to(head)
	if distance > 25.0:
		var text := "%dm" % roundi(distance)
		draw_string_outline(_font, p + Vector2(-12, -s - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.7 * alpha))
		draw_string(_font, p + Vector2(-12, -s - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


## Stealth: a "?" over a suspicious guard, with a meter that fills yellow to
## red as they close in on raising the alarm.
func _draw_suspicion(camera: Camera3D, unit: Enemy) -> void:
	var head := unit.global_position + Vector3.UP * (unit.body_height + 0.7)
	if camera.is_position_behind(head):
		return
	var p := camera.unproject_position(head)
	var level := clampf(unit.suspicion, 0.0, 1.0)
	var color := Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.25, 0.15), level)
	draw_string_outline(_font, p + Vector2(-7, -8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0, 0, 0, 0.8))
	draw_string(_font, p + Vector2(-7, -8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)
	var rect := Rect2(p + Vector2(-16, 0), Vector2(32, 4))
	draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(rect.position, Vector2(32 * level, 4)), color)


## Quiet units currently suspicious of the player (tests read it).
func suspicious_units() -> Array[Enemy]:
	return _suspicious


## Units the drone has marked (tests read it).
func spotted_units() -> Array[Enemy]:
	return _spotted


## A rounded speech bubble above the speaker, tail pointing down at them.
func _draw_bubble(camera: Camera3D, label: Label3D) -> void:
	var anchor := label.global_position
	if camera.is_position_behind(anchor):
		return
	var distance := camera.global_position.distance_to(anchor)
	var fade := clampf((BUBBLE_RANGE - distance) / 10.0, 0.0, 1.0)
	if fade <= 0.0:
		return
	var font_size := int(lerpf(17.0, 13.0, clampf(distance / 40.0, 0.0, 1.0)))
	var text_size := _font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, BUBBLE_WIDTH, font_size)
	var pad := Vector2(11.0, 7.0)
	var tip := camera.unproject_position(anchor)
	text_size.x += 4.0
	var box := Rect2(tip - Vector2(text_size.x * 0.5 + pad.x, text_size.y + pad.y * 2.0 + 10.0), text_size + pad * 2.0)
	var boss: bool = label.get_meta(&"boss", false)
	var fill := Color(1.0, 1.0, 0.98, 0.94 * fade)
	var edge := Color(0.85, 0.2, 0.15, fade) if boss else Color(0.12, 0.14, 0.12, 0.7 * fade)
	if _bubble_style == null:
		_bubble_style = StyleBoxFlat.new()
		_bubble_style.set_corner_radius_all(9)
		_bubble_style.set_border_width_all(2)
	_bubble_style.bg_color = fill
	_bubble_style.border_color = edge
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8.0, -12.0), tip + Vector2(8.0, -12.0)]), edge)
	_bubble_style.draw(get_canvas_item(), box)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0.0, -3.0), tip + Vector2(-6.0, -13.0), tip + Vector2(6.0, -13.0)]), fill)
	draw_multiline_string(_font, box.position + Vector2(pad.x, pad.y + _font.get_ascent(font_size)), label.text,
		HORIZONTAL_ALIGNMENT_CENTER, text_size.x, font_size, -1, Color(0.08, 0.09, 0.08, fade))


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
