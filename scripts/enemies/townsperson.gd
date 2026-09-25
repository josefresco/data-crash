class_name Townsperson
extends Enemy
## Neighbor who joins after the green datacenter goes up. Walks to damaged
## structures and repairs them. FROST agents try to abduct them.

signal abducted(person: Townsperson)

## Per 0.5 s attack tick: 10 hp/s each, slower than a guard can chip it.
@export var repair_per_tick := 5.0
@export var trust_loss_on_abduction := 0.15
@export var trust_loss_on_death := 0.1
## Civilians won't repair anything with a hostile this close (no stalemates
## where repairs out-heal an ongoing attack).
@export var safe_distance := 10.0

var carrier: Node3D = null


func _init() -> void:
	faction = Faction.ALLY
	max_health = 50.0
	move_speed = 4.2
	sight_range = 45.0
	attack_range = 2.0
	attack_interval = 0.5
	bounty = 0
	body_color = Color(0.85, 0.72, 0.55)


func is_captured() -> bool:
	return carrier != null


func captured_by(new_carrier: Node3D) -> void:
	carrier = new_carrier
	target = null
	collision_layer = 0
	collision_mask = 0
	remove_from_group("townspeople")


func release() -> void:
	if carrier == null:
		return
	carrier = null
	collision_layer = Game.LAYER_ENEMIES
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_VEHICLES \
		| Game.LAYER_DESTRUCTIBLE | Game.LAYER_ENEMIES
	global_position.y = 0.2
	if is_alive():
		add_to_group("townspeople")


## Called by FROST on reaching the map edge with this person.
func abduct() -> void:
	if Game.district:
		Game.district.trust -= trust_loss_on_abduction
	abducted.emit(self)
	queue_free()


func _faction_group() -> String:
	return "townspeople"


func _physics_process(delta: float) -> void:
	if carrier:
		if is_instance_valid(carrier):
			global_position = carrier.global_position + Vector3.UP * 1.9
		else:
			release()
		return
	super(delta)


## Targets are damaged structures to fix, not enemies.
func _candidates() -> Array[Node3D]:
	var list: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("structures"):
		var structure := node as Destructible
		if structure and structure.needs_repair() and _is_safe(structure):
			list.append(structure)
	return list


func _is_safe(structure: Destructible) -> bool:
	for node in get_tree().get_nodes_in_group("hostiles"):
		if structure.distance_to_point((node as Node3D).global_position) < safe_distance:
			return false
	return true


## Idle near the green core (home) instead of following the player.
func _idle() -> void:
	if _is_valid(objective) and global_position.distance_to(objective.global_position) > 10.0:
		_nav.target_position = objective.global_position
	else:
		_wander()


func _attack(victim: Node3D) -> void:
	var structure := victim as Destructible
	if structure:
		if not _is_safe(structure):
			target = null
			return
		structure.repair(repair_per_tick)
		if not structure.needs_repair():
			target = null


func _on_death() -> void:
	if Game.district:
		Game.district.trust -= trust_loss_on_death


func _decorate(visual_root: Node3D) -> void:
	# Hard hat and tool belt: this is the repair crew.
	_add_box(visual_root, Vector3(0.5, 0.15, 0.5), Vector3(0.0, body_height, 0.0), _solid(Color(0.95, 0.8, 0.1)))
	_add_box(visual_root, Vector3(0.75, 0.12, 0.45), Vector3(0.0, body_height * 0.45, 0.0), _solid(Color(0.35, 0.25, 0.15)))
