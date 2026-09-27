class_name TouristRV
extends SupplyVan
## A camper van of lost Canadian tourists (maple-leaf flag, luggage on the
## roof). Rolls up the main road from the south, pulls over at `stop_point`,
## and lets the group out (see Canuck). Help them and they join you; ignore
## them and eventually they pile back in and drive off.

signal arrived(rv: TouristRV)

enum Leg { ARRIVING, PARKED, LEAVING }

var stop_point := Vector3.ZERO
var exit_point := Vector3.ZERO
var leg := Leg.ARRIVING
var tourists: Array[Canuck] = []
## One group in three brings a (retired) Mountie.
var with_mountie := false

var _wait_left := 150.0


func _init() -> void:
	max_health = 200.0
	top_speed = 8.0
	wobble = 0.0
	bounty = 0
	faction = Faction.ALLY
	body_size = Vector3(2.0, 1.8, 4.6)
	model_path = "res://assets/kenney/cars/van.glb"
	model_scale = 1.45
	explosion_damage = 30.0


func _faction_group() -> String:
	return "tourists"


func _decorate(visual_root: Node3D) -> void:
	# Luggage on the roof, a maple-leaf flag on a pole, and a canoe for good measure.
	var roof := 2.25
	Models.box(visual_root, Vector3(1.4, 0.4, 1.6), Vector3(0.0, roof, 0.3), Models.mat(Color(0.3, 0.25, 0.2), &"cloth"))
	var canoe := Models.box(visual_root, Vector3(0.6, 0.25, 4.2), Vector3(0.0, roof + 0.35, 0.0), Models.mat(Color(0.8, 0.25, 0.12), &"paint"))
	canoe.scale = Vector3(1.0, 1.0, 1.0)
	Models.cylinder(visual_root, 0.03, 1.4, Vector3(0.75, roof + 0.7, 1.9), Models.mat(Color(0.8, 0.8, 0.82), &"metal"), 6)
	var flag := Node3D.new()
	flag.position = Vector3(0.75, roof + 1.2, 1.55)
	visual_root.add_child(flag)
	var red := Models.mat(Color(0.85, 0.1, 0.1), &"cloth")
	Models.box(flag, Vector3(0.03, 0.4, 0.18), Vector3(0.0, 0.0, -0.21), red)
	Models.box(flag, Vector3(0.03, 0.4, 0.24), Vector3(0.0, 0.0, 0.0), Models.mat(Color(0.97, 0.97, 0.95), &"cloth"))
	Models.box(flag, Vector3(0.03, 0.4, 0.18), Vector3(0.0, 0.0, 0.21), red)
	Models.box(flag, Vector3(0.035, 0.16, 0.12), Vector3(0.0, 0.0, 0.0), red)  # the leaf, roughly
	var plate := Label3D.new()
	plate.text = "EH-2025"
	plate.font_size = 40
	plate.pixel_size = 0.004
	plate.outline_size = 0
	plate.modulate = Color(0.15, 0.2, 0.5)
	plate.position = Vector3(0.0, 0.6, 2.36)
	visual_root.add_child(plate)


func _physics_process(delta: float) -> void:
	if leg == Leg.PARKED:
		speed = 0.0
		velocity = Vector3.ZERO
		_wait_left -= delta
		var helped := tourists.any(func(t: Variant) -> bool: return is_instance_valid(t) and (t as Canuck).state == Canuck.State.ALLY)
		if _wait_left <= 0.0 and not helped:
			for t in tourists:
				if is_instance_valid(t):
					t.leave()
			if tourists.all(func(t: Variant) -> bool: return not is_instance_valid(t)):
				leg = Leg.LEAVING
				top_speed = 9.0
		return
	super(delta)


func _goal_point() -> Vector3:
	var goal := stop_point if leg == Leg.ARRIVING else exit_point
	var offset := goal - global_position
	if Vector2(offset.x, offset.z).length() < 3.0:
		if leg == Leg.ARRIVING:
			leg = Leg.PARKED
			_unload()
		elif leg == Leg.LEAVING:
			queue_free()
		return global_position
	return goal


func _unload() -> void:
	var count := 3 if with_mountie else 2
	for i in count:
		var tourist := Canuck.new()
		tourist.setup(with_mountie and i == count - 1)
		tourist.rv = self
		tourist.position = get_parent().to_local(global_position + Vector3(3.5, 0.2, -1.5 + i * 1.5))
		get_parent().add_child(tourist)
		tourists.append(tourist)
		tourist.helped.connect(_on_helped)
	arrived.emit(self)


func _on_helped(_rv: Node) -> void:
	for t in tourists:
		if is_instance_valid(t):
			t.join()
	Game.count("canadians", tourists.size())
	if Game.district:
		Game.district.trust += 0.03
	Game.notify("You pointed the lost Canadians the right way. They're sticking around to help, eh!", 5.0)
	Sfx.ui(&"confirm")
