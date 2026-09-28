class_name Hospital
extends Node3D
## The front desk inside the hospital (a WalkIn "hospital"). [E] patches the
## player up to full health. While the corporate datacenters run the town
## the hospital is a subsidiary and bills `price_per_hp` for every point
## healed (partial care if you're short); once the green datacenter goes up
## (Phase 3 on) it's community-run again and free. Hurt allies, townspeople,
## and residents walk in on their own (Enemy.hospital_share) and recover
## beside the beds.

signal treated(amount: float, cost: int)

@export var reach := 2.6
@export var price_per_hp := 0.6
@export var min_bill := 10
## Health per second for patients resting on the ward.
@export var ward_rate := 25.0

## Local spot on the ward (beds along the back wall), set by the level.
var ward := Vector3(0.0, 0.0, -2.8)
var _sign: Label3D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("hospitals")
	set_meta(&"poi", "+")
	set_meta(&"poi_color", Color(1.0, 0.35, 0.35))
	add_to_group("map_pois")
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.pixel_size = 0.006
	_sign.outline_size = 8
	_sign.position = Vector3(0.0, 2.2, -0.9)
	add_child(_sign)
	_update_sign()


## Free once the neighborhood's green datacenter is up (Phase 3 and later).
func is_free() -> bool:
	var level := get_tree().get_first_node_in_group("level")
	if level == null or not "phase" in level:
		return false
	return int(level.get("phase")) >= Level.Phase.BUILD


## What topping `player` up would cost right now.
func bill_for(player: Player) -> int:
	var missing := player.max_health - player.health
	if missing <= 0.5 or is_free():
		return 0
	return maxi(min_bill, ceili(missing * price_per_hp))


func in_reach(player: Node3D) -> bool:
	return player.global_position.distance_to(global_position) <= reach


func offer_text(player: Player) -> String:
	if player.health >= player.max_health - 0.5:
		return "[E] Front desk: you look healthy" + ("" if is_free() else " (care is billed while the datacenters own us)")
	if is_free():
		return "[E] Get patched up (free: the community runs the hospital again)"
	return "[E] Get patched up ($%d: a Corporate Health Partner(TM))" % bill_for(player)


func interact(player: Player) -> void:
	var missing := player.max_health - player.health
	if missing <= 0.5:
		Game.notify("\"You're fine, hon. Drink some water. If you can find any.\"", 3.0)
		return
	var cost := bill_for(player)
	var healed := missing
	if cost > Game.cash:
		# Partial care: whatever the cash covers.
		healed = missing * float(Game.cash) / float(cost)
		cost = Game.cash
		if healed < 1.0:
			Sfx.ui(&"error", -4.0)
			Game.notify("The desk wants $%d up front. The datacenters bought the hospital." % bill_for(player), 4.0)
			return
	Game.add_cash(-cost)
	player.heal(healed)
	Game.count("hospital")
	Sfx.ui(&"cash" if cost > 0 else &"open", -4.0)
	if cost > 0:
		Game.notify("Patched up (+%d health). Billed $%d. Build the green datacenter and it's free again." % [roundi(healed), cost], 4.0)
		Game.tip("hospital", "The hospital bills you while the corporate datacenters run the town. Once the green datacenter is up, care is free.")
	else:
		Game.notify("Patched up (+%d health), no charge. \"Community care, like it used to be.\"" % roundi(healed), 4.0)
	treated.emit(healed, cost)


## Where patients rest (world space).
func treatment_point() -> Vector3:
	return global_transform * ward


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 60 == 0:
		_update_sign()


func _update_sign() -> void:
	if is_free():
		_sign.text = "FRONT DESK\ncare is FREE"
		_sign.modulate = Color(0.5, 1.0, 0.55)
	else:
		_sign.text = "FRONT DESK\n$%.1f per health point" % price_per_hp
		_sign.modulate = Color(1.0, 0.7, 0.4)
