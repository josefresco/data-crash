class_name CargoTruck
extends SupplyVan
## A datacenter's supply loop: rolls in the back gate loaded with Government
## Cheese, unloads at the dock, and leaves full of money. Off the map it swaps
## loads and comes back. Wreck a money truck for the cash inside; wreck a
## cheese truck and the neighbors eat well. It's site security: hitting it
## raises its site's alarm.

enum Cargo { CHEESE, MONEY }

## Route points, world space: off the map, the dock, off the map again.
var spawn_point := Vector3.ZERO
var dock_point := Vector3.ZERO
var cargo := Cargo.CHEESE

var _unload_left := 0.0
var _away_left := 0.0
var _heading_in := true
var _sign_left: Label3D
var _sign_right: Label3D
var _box: MeshInstance3D


func _init() -> void:
	max_health = 110.0
	top_speed = 6.5
	wobble = 0.0
	bounty = 0
	body_size = Vector3(2.0, 1.8, 4.6)
	model_path = "res://assets/kenney/cars/delivery.glb"
	model_scale = 1.45
	explosion_damage = 40.0


func _ready() -> void:
	super()
	add_to_group("cargo_trucks")
	route = [dock_point, spawn_point]
	_set_cargo(Cargo.CHEESE)


func _decorate(visual_root: Node3D) -> void:
	_box = _add_box(visual_root, Vector3(body_size.x * 1.02, 1.0, body_size.z * 0.5), Vector3(0.0, 2.1, 0.55),
		StandardMaterial3D.new())
	for side in [-1.0, 1.0]:
		var sign_label := Label3D.new()
		sign_label.font_size = 64
		sign_label.pixel_size = 0.008
		sign_label.outline_size = 8
		sign_label.position = Vector3(side * (body_size.x * 0.52 + 0.02), 2.1, 0.55)
		sign_label.rotation.y = PI * 0.5 * side
		visual_root.add_child(sign_label)
		if side < 0.0:
			_sign_left = sign_label
		else:
			_sign_right = sign_label


func _set_cargo(value: Cargo) -> void:
	cargo = value
	var cheese := cargo == Cargo.CHEESE
	var text := "GOVERNMENT\nCHEESE" if cheese else "$$$ PROFITS $$$"
	for sign_label in [_sign_left, _sign_right]:
		if sign_label:
			sign_label.text = text
			sign_label.modulate = Color(0.25, 0.2, 0.05) if cheese else Color(0.9, 1.0, 0.85)
	if _box:
		var mat := _box.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.98, 0.8, 0.2) if cheese else Color(0.15, 0.45, 0.2)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _away_left > 0.0:
		# Off the map, swapping loads.
		_away_left -= delta
		if _away_left <= 0.0:
			_set_cargo(Cargo.CHEESE)
			_heading_in = true
			global_position = spawn_point
			# Face the dock again for the next run.
			var inbound := dock_point - spawn_point
			global_rotation.y = atan2(-inbound.x, -inbound.z)
			visible = true
			collision_layer = Game.LAYER_ENEMIES
		return
	if _unload_left > 0.0:
		_unload_left -= delta
		speed = move_toward(speed, 0.0, 12.0 * delta)
		velocity = Vector3.ZERO
		if _unload_left <= 0.0:
			_set_cargo(Cargo.MONEY)
			_heading_in = false
		return
	super(delta)


func _goal_point() -> Vector3:
	var goal := dock_point if _heading_in else spawn_point
	var offset := goal - global_position
	if Vector2(offset.x, offset.z).length() < 3.0:
		if _heading_in:
			_unload_left = 6.0
		else:
			_away_left = 10.0
			visible = false
			collision_layer = 0
		return global_position
	return goal


func _on_death() -> void:
	super()
	if cargo == Cargo.MONEY:
		Game.add_cash(150)
		Game.notify("Money truck cracked open: the profits rain on the block. (+$150)")
	else:
		if Game.district:
			Game.district.trust += 0.03
		Game.notify("Government cheese for everyone! The neighbors are delighted. (Trust up)")
		var parent := get_parent()
		for i in 6:
			var wheel := Models.cylinder(parent as Node3D, 0.35, 0.18, global_position + Vector3(randf_range(-2.5, 2.5), 0.1, randf_range(-2.5, 2.5)),
				Models.mat(Color(0.98, 0.78, 0.2), &"rough"), 12)
			wheel.rotation.z = randf_range(-0.3, 0.3)
			var tween := wheel.create_tween()
			tween.tween_interval(20.0)
			tween.tween_callback(wheel.queue_free)
