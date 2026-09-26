class_name HudIcons
extends RefCounted
## Small vector icons drawn with CanvasItem primitives (no image assets):
## heart, coin, smog, noise, water, trust, turbo, ammo, c4, treat. Static.


## Draws `kind` centered at `at`, `size` px tall.
static func draw(ci: CanvasItem, kind: StringName, at: Vector2, size: float, color: Color) -> void:
	var s := size * 0.5
	match kind:
		&"heart":
			ci.draw_circle(at + Vector2(-s * 0.45, -s * 0.2), s * 0.52, color)
			ci.draw_circle(at + Vector2(s * 0.45, -s * 0.2), s * 0.52, color)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.95, -s * 0.05), at + Vector2(s * 0.95, -s * 0.05),
				at + Vector2(0.0, s * 0.95)]), color)
		&"coin":
			ci.draw_circle(at, s, color)
			ci.draw_arc(at, s * 0.72, 0.0, TAU, 20, color.darkened(0.35), maxf(size * 0.08, 1.5))
			ci.draw_string(ThemeDB.fallback_font, at + Vector2(-s * 0.32, s * 0.4), "$", HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(size * 0.7), color.darkened(0.45))
		&"smog":
			for spot in [Vector2(-0.45, 0.15), Vector2(0.0, -0.2), Vector2(0.45, 0.15)]:
				ci.draw_circle(at + spot * s, s * 0.48, color)
			ci.draw_rect(Rect2(at + Vector2(-s * 0.9, 0.0), Vector2(s * 1.8, s * 0.5)), color)
		&"noise":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.9, -s * 0.3), Vector2(s * 0.45, s * 0.6)), color)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.45, -s * 0.3), at + Vector2(0.05 * s, -s * 0.8),
				at + Vector2(0.05 * s, s * 0.8), at + Vector2(-s * 0.45, s * 0.3)]), color)
			for r in [0.45, 0.8]:
				ci.draw_arc(at + Vector2(s * 0.1, 0.0), s * r, -0.9, 0.9, 10, color, maxf(size * 0.09, 1.5))
		&"water":
			ci.draw_circle(at + Vector2(0.0, s * 0.3), s * 0.62, color)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -s * 0.95), at + Vector2(s * 0.58, s * 0.1),
				at + Vector2(-s * 0.58, s * 0.1)]), color)
		&"trust":
			for x in [-0.42, 0.42]:
				ci.draw_circle(at + Vector2(x * s, -s * 0.42), s * 0.3, color)
				ci.draw_arc(at + Vector2(x * s, s * 0.55), s * 0.45, PI, TAU, 10, color, s * 0.35)
		&"turbo":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(s * 0.2, -s), at + Vector2(-s * 0.55, s * 0.1),
				at + Vector2(-s * 0.05, s * 0.1), at + Vector2(-s * 0.25, s), at + Vector2(s * 0.55, -s * 0.15),
				at + Vector2(s * 0.05, -s * 0.15)]), color)
		&"ammo":
			for x in [-0.45, 0.0, 0.45]:
				ci.draw_rect(Rect2(at + Vector2(x * s - s * 0.14, -s * 0.2), Vector2(s * 0.28, s * 0.95)), color)
				ci.draw_circle(at + Vector2(x * s, -s * 0.2), s * 0.14, color)
				ci.draw_colored_polygon(PackedVector2Array([at + Vector2(x * s - s * 0.14, -s * 0.2),
					at + Vector2(x * s + s * 0.14, -s * 0.2), at + Vector2(x * s, -s * 0.75)]), color)
		&"c4":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.85, -s * 0.5), Vector2(s * 1.7, s)), color)
			ci.draw_line(at + Vector2(-s * 0.3, -s * 0.5), at + Vector2(-s * 0.1, -s * 0.95), Color(1.0, 0.3, 0.2), maxf(size * 0.08, 1.5))
			ci.draw_circle(at + Vector2(s * 0.45, 0.0), s * 0.16, Color(1.0, 0.25, 0.2))
		&"treat":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.55, -s * 0.18), Vector2(s * 1.1, s * 0.36)), color)
			for x in [-0.6, 0.6]:
				for y in [-0.25, 0.25]:
					ci.draw_circle(at + Vector2(x * s, y * s), s * 0.25, color)
		_:
			ci.draw_circle(at, s * 0.5, color)
