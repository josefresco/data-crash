class_name OpticOverlay
extends Control
## What the player sees through an optic (Player.optic): the hunting
## rifle's scope (a round sight picture, crosshair, and mil dots) or the
## binoculars (two overlapping circles, a range readout, and the spotting
## bracket and progress). The mask is a canvas shader on a full-screen rect;
## the reticle and text are drawn on top.

const MASK_SHADER := """
shader_type canvas_item;
uniform int mode = 0;
uniform vec2 size = vec2(1920.0, 1080.0);
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float r = min(size.x, size.y);
	float inside = 0.0;
	if (mode == 1) {
		inside = 1.0 - smoothstep(0.42 * r - 2.0, 0.42 * r + 2.0, length(p));
	} else if (mode == 2) {
		float d1 = length(p - vec2(-0.2 * r, 0.0));
		float d2 = length(p - vec2(0.2 * r, 0.0));
		inside = 1.0 - smoothstep(0.38 * r - 3.0, 0.38 * r + 3.0, min(d1, d2));
	}
	// Dark edge vignette inside the glass.
	float edge = mode == 1 ? smoothstep(0.3 * r, 0.42 * r, length(p)) * 0.5 : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, mode == 0 ? 0.0 : max(1.0 - inside, edge));
}
"""

var _player: Player
var _mask: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask = ColorRect.new()
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = MASK_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_mask.material = _material
	add_child(_mask)
	visible = false


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var mode := 0
	match _player.optic:
		&"scope":
			mode = 1
		&"binoculars":
			mode = 2
	visible = mode != 0
	if not visible:
		return
	_material.set_shader_parameter(&"mode", mode)
	_material.set_shader_parameter(&"size", size)
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	var center := size * 0.5
	var r := minf(size.x, size.y)
	var font := ThemeDB.fallback_font
	if _player.optic == &"scope":
		var ink := Color(0.02, 0.02, 0.02, 0.9)
		var reach := 0.42 * r
		draw_line(center - Vector2(reach, 0.0), center - Vector2(18.0, 0.0), ink, 2.0)
		draw_line(center + Vector2(18.0, 0.0), center + Vector2(reach, 0.0), ink, 2.0)
		draw_line(center - Vector2(0.0, reach), center - Vector2(0.0, 18.0), ink, 2.0)
		draw_line(center + Vector2(0.0, 18.0), center + Vector2(0.0, reach), ink, 2.0)
		for k in range(1, 5):
			for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
				draw_circle(center + dir * k * reach * 0.12, 2.5, ink)
		draw_circle(center, 1.5, Color(0.9, 0.1, 0.1))
		return
	# Binoculars: a thin center reticle, range, and the spotting readout.
	var ink2 := Color(0.85, 1.0, 0.85, 0.75)
	draw_line(center - Vector2(24.0, 0.0), center - Vector2(8.0, 0.0), ink2, 1.5)
	draw_line(center + Vector2(8.0, 0.0), center + Vector2(24.0, 0.0), ink2, 1.5)
	draw_line(center + Vector2(0.0, 8.0), center + Vector2(0.0, 24.0), ink2, 1.5)
	var hit := _player.aim(Spotting.RANGE)
	var range_text := "RANGE ---" if hit.is_empty() else "RANGE %d m" % roundi(_player.global_position.distance_to(hit["position"]))
	draw_string(font, center + Vector2(0.18 * r, 0.3 * r), range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink2)
	var target := _player.spotting_target()
	if target and is_instance_valid(target):
		var camera := get_viewport().get_camera_3d()
		var point := Spotting.aim_point(target)
		if camera and not camera.is_position_behind(point):
			var at := camera.unproject_position(point)
			var box := 34.0
			var gold := Color(1.0, 0.8, 0.3)
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var c := at + corner * box
				draw_line(c, c - Vector2(corner.x * 12.0, 0.0), gold, 2.0)
				draw_line(c, c - Vector2(0.0, corner.y * 12.0), gold, 2.0)
		var share := clampf(_player.spot_progress / Spotting.SPOT_TIME, 0.0, 1.0)
		var bar := Rect2(center + Vector2(-110.0, 0.26 * r), Vector2(220.0, 8.0))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(1.0, 0.8, 0.3))
		draw_string(font, bar.position + Vector2(0.0, -6.0), "SPOTTING: %s" % String(target.get_meta(&"scout_label", "target")).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.4))
	var site := _player.watched_site()
	if not String(site).is_empty():
		var done := Spotting.progress(get_tree(), site)
		draw_string(font, center + Vector2(-0.2 * r, -0.3 * r), "SITE TARGETS SPOTTED %d/%d" % [done.x, done.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink2)
