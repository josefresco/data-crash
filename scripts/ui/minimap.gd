class_name Minimap
extends Control
## Circular heading-up minimap (top-left), or a north-up full map with a
## legend when `expanded` ([M]). Draws roads and buildings from the
## NeighborhoodBuilder, the three datacenter compounds colored by status,
## points of interest, nearby units, the player arrow, and a yellow marker for
## the level's guidance_point() (clamped to the edge when it's off the map).

## Meters shown from the center to the edge.
@export var view_radius := 85.0
var expanded := false

const ROAD := Color(0.36, 0.37, 0.4)
const HOUSE := Color(0.55, 0.5, 0.46)
const STORE := Color(0.75, 0.62, 0.42)
const GROUND := Color(0.14, 0.17, 0.13, 0.92)

var _player: Player
var _level: Node
var _hood: NeighborhoodBuilder
var _rotation := 0.0
var _center := Vector3.ZERO
var _scale := 1.0
## Redraws are throttled: drawing every frame cost more than the rest of the HUD.
var _redraw_left := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		_level = get_tree().get_first_node_in_group("level")
		_hood = _level.get_node_or_null("Neighborhood") as NeighborhoodBuilder if _level else null
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = 1.0 / 12.0
		queue_redraw()


## World (x, z) to local pixels.
func to_map(world: Vector3) -> Vector2:
	var rel := Vector2(world.x - _center.x, world.z - _center.z).rotated(_rotation) * _scale
	return size * 0.5 + rel


func _draw() -> void:
	if _player == null:
		return
	var camera := get_viewport().get_camera_3d()
	var forward := -camera.global_basis.z if camera else Vector3.FORWARD
	var eye: Vector3 = _player.vehicle.global_position if _player.vehicle else _player.global_position
	var radius := size.x * 0.5
	if expanded:
		# North-up, fit the whole playing field.
		_center = Vector3(0.0, 0.0, 30.0)
		_rotation = 0.0
		_scale = (size.x * 0.5) / 200.0
	else:
		_center = eye
		_rotation = atan2(-forward.x, -forward.z)
		_scale = radius / view_radius
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	_draw_roads()
	_draw_buildings()
	_draw_sites()
	_draw_points_of_interest()
	_draw_units(eye)
	_draw_guidance(radius)
	# The player: an arrow pointing where the camera looks.
	var me := to_map(eye)
	var heading := Vector2(forward.x, forward.z).normalized().rotated(_rotation)
	if heading == Vector2.ZERO:
		heading = Vector2.UP
	var side := Vector2(-heading.y, heading.x)
	draw_colored_polygon(PackedVector2Array([me + heading * 9.0, me - heading * 6.0 + side * 6.0, me - heading * 3.0,
		me - heading * 6.0 - side * 6.0]), Color(1.0, 1.0, 1.0))
	if not expanded:
		# North marker on the rim.
		var north := size * 0.5 + Vector2(0.0, -1.0).rotated(_rotation) * (radius - 10.0)
		draw_string(ThemeDB.fallback_font, north + Vector2(-5.0, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	else:
		_draw_legend()


func _line(a: Vector3, b: Vector3, width_m: float, color: Color) -> void:
	draw_line(to_map(a), to_map(b), color, maxf(width_m * _scale, 2.0))


func _draw_roads() -> void:
	if _hood == null:
		return
	var w := _hood.road_width
	if _hood.has_river:
		_line(Vector3(-_hood.river_length * 0.5, 0, _hood.river_z), Vector3(_hood.river_length * 0.5, 0, _hood.river_z),
			_hood.river_width, Color(0.25, 0.45, 0.65, 0.9))
	_line(Vector3(0, 0, -12), Vector3(0, 0, _hood.main_road_end_z), w, ROAD)
	for z: float in _hood.street_z:
		_line(Vector3(-_hood.street_half_length, 0, z), Vector3(_hood.street_half_length, 0, z), w, ROAD)
	_line(Vector3(-_hood.access_road_x, 0, _hood.street_z[0]), Vector3(_hood.access_road_x, 0, _hood.street_z[0]), w, ROAD)


func _draw_buildings() -> void:
	if _hood == null:
		return
	for entry: Array in _hood.footprints():
		var rect: Rect2 = entry[0]
		var corners := PackedVector2Array()
		for c in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			corners.append(to_map(Vector3(c.x, 0.0, c.y)))
		draw_colored_polygon(corners, STORE if entry[1] else HOUSE)


func _draw_sites() -> void:
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		var site := node as DatacenterSite
		var color := Color(0.85, 0.55, 0.2)
		if site.is_cleared:
			color = Color(0.3, 0.85, 0.4)
		elif site.is_alarmed():
			color = Color(1.0, 0.2, 0.15)
		var half := site.compound * 0.5
		var outline := PackedVector2Array()
		for c in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(-half.x, 0, -half.y)]:
			outline.append(to_map(site.at(c)))
		draw_polyline(outline, color, 2.0)
		var building := PackedVector2Array()
		var f := site.datacenter.footprint * 0.5
		for c in [Vector3(-f.x, 0, -f.y), Vector3(f.x, 0, -f.y), Vector3(f.x, 0, f.y), Vector3(-f.x, 0, f.y)]:
			building.append(to_map(site.at(site.building_offset + c)))
		draw_colored_polygon(building, Color(color, 0.55) if not site.is_neutralized else Color(0.3, 0.3, 0.3, 0.5))
		var label_at := to_map(site.global_position) + Vector2(-26.0, 4.0)
		draw_string(ThemeDB.fallback_font, label_at, site.display_name.substr(0, 9), HORIZONTAL_ALIGNMENT_LEFT, -1,
			12 if not expanded else 14, Color.WHITE)


func _poi(at: Vector3, letter: String, color: Color) -> void:
	var p := to_map(at)
	draw_circle(p, 7.0, color)
	draw_string(ThemeDB.fallback_font, p + Vector2(-4.0, 4.5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)


func _draw_points_of_interest() -> void:
	if _hood:
		for spec in [["DUECE HARDWARE", "H", Color(1.0, 0.35, 0.3)], ["POLICE", "P", Color(0.45, 0.6, 1.0)],
				["TOWN HALL", "T", Color(0.95, 0.82, 0.4)]]:
			var door := _hood.store_door(spec[0])
			if door != Vector3.ZERO:
				_poi(door, spec[1], spec[2])
		var guns := _hood.store_door(_hood.walk_in_sign("gunstore"))
		if guns != Vector3.ZERO:
			_poi(guns, "A", Color(1.0, 0.6, 0.2))
	# Town services mark themselves (meta "poi" letter and "poi_color").
	for node in get_tree().get_nodes_in_group("map_pois"):
		_poi((node as Node3D).global_position, node.get_meta(&"poi", "?"), node.get_meta(&"poi_color", Color.WHITE))
	if Game.has_meta(&"home"):
		var home := to_map(Game.get_meta(&"home"))
		draw_colored_polygon(PackedVector2Array([home + Vector2(-6, 0), home + Vector2(0, -6), home + Vector2(6, 0)]), Color(0.4, 1.0, 0.5))
		draw_rect(Rect2(home + Vector2(-4, 0), Vector2(8, 5)), Color(0.4, 1.0, 0.5))
	for node in get_tree().get_nodes_in_group("markets"):
		_poi((node as Node3D).global_position, "M", Color(0.45, 0.9, 0.45))
	if _level:
		var main := _level.get_node_or_null("WaterMain") as WaterMain
		if main and not main.is_fixed:
			_poi(main.global_position, "W", Color(0.4, 0.7, 1.0))
		var job := _level.get_node_or_null("PaintJob") as PaintJob
		if job and not job.is_fixed:
			_poi(job.global_position, "~", Color(0.8, 0.65, 1.0))
		var cache := _level.get_node_or_null("SecurityCache") as SecurityCache
		if cache and not cache.is_looted:
			_poi(cache.global_position, "R", Color(1.0, 0.8, 0.3))
	for node in get_tree().get_nodes_in_group("neighbors"):
		if node is OldLady and (node as OldLady).state != OldLady.State.CROSSED:
			_poi((node as Node3D).global_position, "G", Color(0.95, 0.75, 0.95))
	for node in get_tree().get_nodes_in_group("tourists"):
		if node is Canuck and (node as Canuck).state == Canuck.State.LOST:
			_poi((node as Node3D).global_position, "C", Color(1.0, 0.3, 0.3))
			break
	for node in get_tree().get_nodes_in_group("litter"):
		draw_circle(to_map((node as Node3D).global_position), 2.0, Color(0.9, 0.9, 0.6))
	for node in get_tree().get_nodes_in_group("grock_cameras"):
		if not (node as Destructible).is_destroyed:
			draw_rect(Rect2(to_map((node as Node3D).global_position) - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.3, 0.8))


func _draw_units(eye: Vector3) -> void:
	var reach := view_radius * 1.1 if not expanded else 1000.0
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit == null or unit.global_position.distance_to(eye) > reach:
			continue
		var color := Color(0.5, 0.65, 1.0) if unit is PoliceCruiser or (unit is Police and unit.is_dormant()) \
			else (Color(0.8, 0.5, 0.45) if unit.is_dormant() else Color(1.0, 0.15, 0.1))
		draw_circle(to_map(unit.global_position), 3.5 if not unit is FelsaCar else 5.0, color)
	for group in ["allies", "strays"]:
		for node in get_tree().get_nodes_in_group(group):
			if (node as Node3D).global_position.distance_to(eye) < reach:
				draw_circle(to_map((node as Node3D).global_position), 3.0, Color(0.4, 1.0, 0.5))
	for node in get_tree().get_nodes_in_group("residents"):
		if (node as Node3D).global_position.distance_to(eye) < reach:
			draw_circle(to_map((node as Node3D).global_position), 1.8, Color(0.85, 0.85, 0.85, 0.7))


func _draw_guidance(radius: float) -> void:
	if _level == null or not _level.has_method(&"guidance_point"):
		return
	var target: Variant = _level.call(&"guidance_point")
	if target == null:
		return
	var p := to_map(target)
	var from_center := p - size * 0.5
	var edge := radius - 12.0
	var clamped := from_center.length() > edge and not expanded
	if clamped:
		p = size * 0.5 + from_center.normalized() * edge
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.2
	var r := 7.0 * pulse
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]),
		Color(1.0, 0.85, 0.15))
	if clamped:
		var dir := from_center.normalized()
		draw_line(p + dir * r, p + dir * (r + 7.0), Color(1.0, 0.85, 0.15), 3.0)


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var rows := [["Objective", Color(1.0, 0.85, 0.15)], ["Hostile", Color(1.0, 0.15, 0.1)], ["Security (quiet)", Color(0.8, 0.5, 0.45)],
		["Police", Color(0.5, 0.65, 1.0)], ["Friendly dog", Color(0.4, 1.0, 0.5)], ["H Hardware (free)", Color(1.0, 0.35, 0.3)],
		["M Market", Color(0.45, 0.9, 0.45)], ["C Lost Canadians", Color(1.0, 0.3, 0.3)], ["T Town Hall (bribes)", Color(0.95, 0.82, 0.4)], ["Home", Color(0.4, 1.0, 0.5)], ["G Grandma  W Burst hydrant", Color(0.95, 0.75, 0.95)], ["Grock camera", Color(1.0, 0.3, 0.8)]]
	var at := Vector2(14.0, size.y - rows.size() * 18.0 - 10.0)
	draw_rect(Rect2(at - Vector2(6, 14), Vector2(220, rows.size() * 18.0 + 8.0)), Color(0, 0, 0, 0.55))
	for row: Array in rows:
		draw_circle(at + Vector2(4.0, -4.0), 5.0, row[1])
		draw_string(font, at + Vector2(14.0, 0.0), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		at.y += 18.0
