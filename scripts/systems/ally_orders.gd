class_name AllyOrders
extends Node
## [H] opens the orders menu for your side (recruited Canadians, Regulars,
## playground moms, kids on bikes), so they can split up across targets:
##   [1] send the nearest free ally to the crosshair
##   [2] send half of those still following you
##   [3] everyone: follow me (clears orders)
##   [4] everyone: hold at the crosshair (fight only there)
## Allies under orders fight hostiles and wreck site targets (cooling units,
## turbines, tanks, gates) around their point (Enemy.give_order). Each point
## gets a small flag. The level adds this node; the HUD line is "orders".

signal ordered(kind: String, count: int)

const FLAG_COLOR := Color(0.3, 0.9, 0.45)

var is_open := false
var _flags: Array[Node3D] = []


func _ready() -> void:
	add_to_group("ally_orders")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("orders"):
		is_open = not is_open
		Sfx.ui(&"open" if is_open else &"close", -4.0)
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	for i in 4:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			var player := get_tree().get_first_node_in_group("player") as Player
			if player:
				issue(i, _aim_point(player))
			get_viewport().set_input_as_handled()
			return


## Everyone who takes orders.
func squad() -> Array[Enemy]:
	var list: Array[Enemy] = []
	for group in ["allies", "moms", "kids"]:
		for node in get_tree().get_nodes_in_group(group):
			var unit := node as Enemy
			if unit and unit.is_alive() and (unit is Canuck or unit is Mom or unit is KidRider) and not unit in list:
				if unit is Canuck and (unit as Canuck).state != Canuck.State.ALLY:
					continue
				list.append(unit)
	return list


## Issues order `index` (0..3) at `point`. Returns how many allies got it.
func issue(index: int, point: Vector3) -> int:
	var team := squad()
	var free := team.filter(func(u: Enemy) -> bool: return u.order_point == Vector3.INF)
	free.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.global_position.distance_to(point) < b.global_position.distance_to(point))
	var count := 0
	match index:
		0:
			if not free.is_empty():
				(free[0] as Enemy).give_order(point)
				count = 1
		1:
			var half := ceili(free.size() * 0.5)
			for i in half:
				(free[i] as Enemy).give_order(point)
			count = half
		2:
			for unit in team:
				unit.give_order(Vector3.INF)
			count = team.size()
			_clear_flags()
		3:
			for unit in team:
				unit.give_order(point, true)
			count = team.size()
			_clear_flags()
	if index != 2 and count > 0:
		_plant_flag(point)
	var names := ["Sent one ally", "Sent %d allies" % count, "Everyone's following you", "Everyone holds there"]
	Game.notify(names[index] + ("." if count > 0 else ": nobody's free to send."), 2.5)
	Sfx.ui(&"confirm" if count > 0 else &"error", -6.0)
	is_open = false
	_refresh()
	ordered.emit(["send_one", "send_half", "follow", "hold"][index], count)
	_prune_flags()
	return count


func _aim_point(player: Player) -> Vector3:
	var hit := player.aim(250.0)
	if not hit.is_empty():
		return hit["position"]
	var forward := -player.get_viewport().get_camera_3d().global_basis.z
	forward.y = 0.0
	return player.global_position + forward.normalized() * 20.0


func _refresh() -> void:
	if not is_open:
		Game.set_info("orders", "")
		return
	var team := squad()
	var free := team.filter(func(u: Enemy) -> bool: return u.order_point == Vector3.INF).size()
	Game.set_info("orders", "ORDERS (%d allies, %d following)   [1] Send one   [2] Send half   [3] All follow me   [4] All hold there   [H] Close"
		% [team.size(), free])


## A little green flag where allies were sent.
func _plant_flag(point: Vector3) -> void:
	var flag := Node3D.new()
	var level := get_parent() as Node3D
	level.add_child(flag)
	flag.global_position = point
	Models.cylinder(flag, 0.03, 2.2, Vector3(0.0, 1.1, 0.0), Models.mat(Color(0.8, 0.8, 0.8), &"metal"), 6)
	Models.box(flag, Vector3(0.7, 0.45, 0.02), Vector3(0.35, 1.95, 0.0), Models.glow(FLAG_COLOR, 1.2))
	flag.set_meta(&"point", point)
	_flags.append(flag)


func _clear_flags() -> void:
	for flag in _flags:
		if is_instance_valid(flag):
			flag.queue_free()
	_flags.clear()


## Flags nobody is headed for anymore come down.
func _prune_flags() -> void:
	var points: Array[Vector3] = []
	for unit in squad():
		if unit.order_point != Vector3.INF:
			points.append(unit.order_point)
	for flag in _flags.duplicate():
		if not is_instance_valid(flag):
			_flags.erase(flag)
			continue
		var point: Vector3 = flag.get_meta(&"point")
		if not points.any(func(p: Vector3) -> bool: return p.distance_to(point) < 0.5):
			flag.queue_free()
			_flags.erase(flag)


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 == 0:
		_prune_flags()
		if is_open:
			_refresh()
