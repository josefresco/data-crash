class_name Barricade
extends Structure
## Concrete jersey barrier (a tall T-wall profile). Blocks paths (the navmesh
## rebakes around it) and soaks fire.

const SLOGANS := ["PEOPLE > SERVERS", "OUR WATER", "NOT FOR SALE", "UNPLUG IT", "GROW, DON'T MINE"]
## Side profile (z, y): wide sloped foot, narrow stem, flat top.
const PROFILE := [
	Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.3, 0.12), Vector2(0.13, 0.4), Vector2(0.09, 1.55),
	Vector2(0.06, 1.6), Vector2(-0.06, 1.6), Vector2(-0.09, 1.55), Vector2(-0.13, 0.4), Vector2(-0.3, 0.12),
]


func _init() -> void:
	size = Vector3(4.0, 1.6, 0.6)
	color = Color(0.92, 0.9, 0.86)
	surface_kind = &"concrete"
	max_health = 350.0
	chunks = Vector3i(4, 2, 1)
	cost = 50
	label = "Barricade"


func _visual_mesh() -> Mesh:
	return Models.extrude_mesh(PackedVector2Array(PROFILE), size.x)


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	var half := size.x * 0.5
	# A hazard band on the foot and lifting eyes on top.
	for side in [-1.0, 1.0]:
		for i in 8:
			var stripe := _add_box(Vector3(0.22, 0.12, 0.02), Vector3(-half + 0.25 + i * 0.5, 0.23, side * 0.245),
				Color(0.95, 0.75, 0.1) if i % 2 == 0 else Color(0.08, 0.08, 0.08), null, &"paint")
			stripe.rotation.x = side * -0.55
	for x in [-half * 0.6, half * 0.6]:
		_add_box(Vector3(0.14, 0.08, 0.05), Vector3(x, 1.63, 0.0), Color(0.3, 0.3, 0.3), null, &"metal")
	var tag := Label3D.new()
	tag.text = SLOGANS.pick_random()
	tag.font_size = 64
	tag.pixel_size = 0.006
	tag.outline_size = 0
	tag.modulate = Color(0.25, 0.75, 0.35)
	tag.position = Vector3(randf_range(-0.6, 0.6), 0.95, 0.115)
	tag.double_sided = false
	tag.rotation.z = randf_range(-0.06, 0.06)
	add_child(tag)
	var back := tag.duplicate() as Label3D
	back.position.z = -0.115
	back.rotation.y = PI
	add_child(back)
