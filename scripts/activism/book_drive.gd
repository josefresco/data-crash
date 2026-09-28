class_name BookDrive
extends Node3D
## The library's book drive (placed at the library's lot origin: +Z out the
## door). The shelves are nearly bare since the county moved the budget to
## "digital infrastructure". [E] at the circulation desk buys a box of books
## for `box_price`; each box fills more of the shelves. `boxes_needed` boxes
## complete the deed.

signal donated(boxes: int)
signal completed

@export var box_price := 30
@export var boxes_needed := 4
@export var reach := 2.6
## The circulation desk (local).
@export var desk := Vector3(0.0, 0.0, 1.2)

var boxes := 0

## One MultiMesh of books per box, revealed as they arrive.
var _shelf_sets: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("book_drives")
	set_meta(&"poi", "L")
	set_meta(&"poi_color", Color(0.55, 0.75, 0.95))
	add_to_group("map_pois")
	_build_books()
	# A cardboard box on the desk with a hand-lettered sign.
	var box := Models.box(self, Vector3(0.6, 0.4, 0.45), desk + Vector3(1.0, 1.2, -0.9), Models.mat(Color(0.7, 0.55, 0.35), &"cloth"))
	var note := Label3D.new()
	note.text = "BOOK DRIVE\n$%d A BOX" % box_price
	note.modulate = Color(0.1, 0.1, 0.12)
	note.outline_size = 0
	note.position = Vector3(0.0, 0.0, 0.235)
	box.add_child(note)
	Models.fit_label(note, Vector2(0.55, 0.35))


func is_done() -> bool:
	return boxes >= boxes_needed


func in_reach(player: Node3D) -> bool:
	return player.global_position.distance_to(global_transform * desk) <= reach


func offer_text(_player: Player) -> String:
	if is_done():
		return "[E] The shelves are full again. The librarian waves."
	return "[E] Buy a box of books for the library ($%d, %d/%d)" % [box_price, boxes, boxes_needed]


func interact(_player: Player) -> void:
	donate()


## Buys one box. Returns false if it's done or there isn't enough cash.
func donate() -> bool:
	if is_done():
		return false
	if Game.cash < box_price:
		Sfx.ui(&"error", -4.0)
		Game.notify("A box of books is $%d." % box_price, 3.0)
		return false
	Game.add_cash(-box_price)
	boxes += 1
	if boxes <= _shelf_sets.size():
		_shelf_sets[boxes - 1].visible = true
	Sfx.play(&"hit_wood", global_transform * desk, -4.0, 1.2)
	if Game.district:
		Game.district.trust += 0.015
	donated.emit(boxes)
	if is_done():
		completed.emit()
	else:
		Game.notify("A box of books for the library (%d/%d). Story time is back on Saturdays." % [boxes, boxes_needed], 3.5)
	return true


## Rows of books along the shelves, split into `boxes_needed` sets.
func _build_books() -> void:
	var size := WalkIn.dimensions("library")
	var spots: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	# Side bookcases (both walls), five shelves each.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (size.x * 0.5 - 0.55) - side * 0.28
		for level in 5:
			var z := -size.z * 0.5 + 1.6
			while z < size.z * 0.5 - 1.8:
				var thick := rng.randf_range(0.04, 0.08)
				spots.append(Transform3D(Basis.from_scale(Vector3(0.22, rng.randf_range(0.22, 0.32), thick)),
					Vector3(x, 0.5 + level * 0.55, z)))
				z += thick + 0.01
	# The freestanding cases at the back, both faces.
	for x0: float in [-2.5, 0.0, 2.5]:
		for face: float in [-1.0, 1.0]:
			for level in 4:
				var z2 := -size.z * 0.5 + 1.0
				while z2 < -size.z * 0.5 + 3.4:
					var thick2 := rng.randf_range(0.04, 0.08)
					spots.append(Transform3D(Basis.from_scale(Vector3(0.2, rng.randf_range(0.22, 0.3), thick2)),
						Vector3(x0 + face * 0.28, 0.45 + level * 0.52, z2)))
					z2 += thick2 + 0.01
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	mesh.material = material
	var colors: Array[Color] = [Color(0.6, 0.1, 0.1), Color(0.15, 0.3, 0.55), Color(0.2, 0.45, 0.25), Color(0.85, 0.7, 0.3),
		Color(0.35, 0.2, 0.4), Color(0.9, 0.88, 0.8), Color(0.2, 0.2, 0.22)]
	spots.shuffle()
	var per := ceili(float(spots.size()) / boxes_needed)
	for set_index in boxes_needed:
		var chunk := spots.slice(set_index * per, (set_index + 1) * per)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = chunk.size()
		for i in chunk.size():
			multimesh.set_instance_transform(i, chunk[i])
			multimesh.set_instance_color(i, colors[rng.randi() % colors.size()])
		var books := MultiMeshInstance3D.new()
		books.name = "Books%d" % (set_index + 1)
		books.multimesh = multimesh
		books.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		books.visible = false
		add_child(books)
		_shelf_sets.append(books)
