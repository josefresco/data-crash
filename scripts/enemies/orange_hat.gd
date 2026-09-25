class_name OrangeHat
extends Enemy
## Misinformed local protester. Walks to the nearest structure and pickets it;
## turrets won't fire while a protester stands next to them. Blocks bullets
## with their body. Harming one costs trust; talking them down ([E]) earns it.

@export var protest_radius := 6.0
@export var trust_loss_on_harm := 0.1
@export var trust_gain_on_persuade := 0.03
## Seconds after arriving before they get bored and go home (no trust gained).
@export var patience := 60.0

var persuaded := false

var _protest_left := 0.0
var _age := 0.0


func _init() -> void:
	max_health = 40.0
	move_speed = 3.0
	sight_range = 60.0
	attack_range = 3.0
	attack_interval = 1.0
	bounty = 0
	body_color = Color(0.78, 0.74, 0.66)


## True while actively picketing (refreshed each attack tick).
func is_protesting() -> bool:
	return _protest_left > 0.0 and is_alive() and not persuaded


## Blocks turret fire within `protest_radius` of `point`.
func blocks_turret_at(point: Vector3) -> bool:
	return is_protesting() and global_position.distance_to(point) <= protest_radius


func persuade() -> bool:
	if persuaded or not is_alive():
		return false
	if Game.district:
		Game.district.trust += trust_gain_on_persuade
	_flash(Color(0.6, 1.0, 0.6))
	_go_home()
	return true


func _go_home() -> void:
	persuaded = true
	target = null
	objective = null
	remove_from_group("protesters")
	_emit_defeated()
	_nav.target_position = home
	# Walk off and go home.
	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.4)
	tween.tween_callback(queue_free)


func _faction_group() -> String:
	return "" if persuaded else "protesters"


func _physics_process(delta: float) -> void:
	_age += delta
	# Counted from spawn, not from picketing: a protester stuck in a crowd
	# still gives up. A wave rush sends them home rather than charging.
	if not persuaded and (_age >= patience or rushing):
		_go_home()
	_protest_left = maxf(_protest_left - delta, 0.0)
	super(delta)


func _think() -> void:
	if persuaded:
		return
	super()


## Pickets structures, turrets first.
func _candidates() -> Array[Node3D]:
	var turrets: Array[Node3D] = []
	var others: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("structures"):
		if node is Turret:
			turrets.append(node as Node3D)
		elif not node is GreenCore:
			others.append(node as Node3D)
	return turrets if not turrets.is_empty() else others


func _attack(_victim: Node3D) -> void:
	_protest_left = attack_interval + 0.5
	# Bob the sign so it reads as chanting.
	var tween := create_tween()
	tween.tween_property(_visual, "position:y", 0.15, 0.15)
	tween.tween_property(_visual, "position:y", 0.0, 0.15)


func _on_death() -> void:
	if Game.district:
		Game.district.trust -= trust_loss_on_harm


func _decorate(visual_root: Node3D) -> void:
	var orange := _solid(Color(1.0, 0.45, 0.05))
	_add_box(visual_root, Vector3(0.45, 0.2, 0.45), Vector3(0.0, body_height + 0.02, 0.0), orange)
	_add_box(visual_root, Vector3(0.6, 0.06, 0.1), Vector3(0.0, body_height - 0.08, -0.25), orange)  # brim
	_add_box(visual_root, Vector3(0.05, 1.2, 0.05), Vector3(0.35, body_height * 0.8, 0.0), _solid(Color(0.5, 0.35, 0.2)))
	_add_box(visual_root, Vector3(0.8, 0.5, 0.04), Vector3(0.35, body_height + 0.5, 0.0), _solid(Color(0.95, 0.95, 0.9)))
