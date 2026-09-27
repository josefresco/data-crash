class_name Dog
extends Enemy
## Fast pursuer: weak bite that slows its victim. A treat turns it into a
## permanent ally that follows the player and bites hostiles.
## Guard dogs (territory_radius > 0) only go after targets near the datacenter
## they guard, unless provoked. Neighborhood strays never attack.

@export var bite_damage := 4.0
@export var slow_factor := 0.5
@export var slow_duration := 1.5
## Neighborhood stray: wanders, never attacks, turrets ignore it. A treat tames it.
@export var stray := false
## Guard dogs only chase targets inside this circle (0 = anywhere).
@export var territory_radius := 0.0
@export var territory_center := Vector3.ZERO

## Getting hurt lets a guard dog chase past its territory for a few seconds.
var _provoked_left := 0.0
## A pet on a walk: trots beside this Resident (untyped: they may be freed).
var pet_owner: Variant = null


func _init() -> void:
	max_health = 30.0
	move_speed = 7.5
	sight_range = 20.0
	attack_range = 1.5
	attack_interval = 0.8
	bounty = 5
	body_color = Color(0.45, 0.3, 0.18)
	body_radius = 0.3
	body_height = 0.8


## Returns false if the dog was already friendly.
func befriend() -> bool:
	if faction == Faction.ALLY or not is_alive():
		return false
	set_faction(Faction.ALLY)
	target = null
	# A fed, loyal dog: sturdier than a hungry guard dog.
	max_health = maxf(max_health, 70.0)
	health = max_health
	Sfx.play(&"bark", global_position, -2.0, 1.25)
	speak("Good dog!")
	_emit_defeated()
	_flash(Color(0.6, 1.0, 0.6))
	return true


func apply_damage(amount: float, from: Vector3, kind: StringName = &"generic") -> void:
	super(amount, from, kind)
	_provoked_left = 6.0


func _process(delta: float) -> void:
	super(delta)
	_provoked_left = maxf(_provoked_left - delta, 0.0)


func _faction_group() -> String:
	if pet_owner != null and faction == Faction.HOSTILE:
		return "pets"
	if stray and faction == Faction.HOSTILE:
		return "strays"
	return super()


## Guard dogs sniff out trespassers all around, but only up close.
func _watches() -> bool:
	return not stray and faction == Faction.HOSTILE and site != &""


func _view_range() -> float:
	return 8.0


func _view_cos() -> float:
	return -1.0


func _candidates() -> Array[Node3D]:
	var list := super()
	if faction == Faction.ALLY:
		return _defending(list)
	if faction != Faction.HOSTILE:
		return list
	if stray:
		return []
	if territory_radius <= 0.0 or _provoked_left > 0.0:
		return list
	var inside: Array[Node3D] = []
	for node in list:
		if in_territory(node.global_position):
			inside.append(node)
	return inside


## A tamed dog is a bodyguard, not an attack dog: it only goes for hostiles
## that are after the player (or their car) or after the dog itself, and
## only near the player.
func _defending(list: Array[Node3D]) -> Array[Node3D]:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return []
	var guarded: Array[Node3D] = [player, self]
	if player.vehicle:
		guarded.append(player.vehicle)
	var near := player.vehicle.global_position if player.vehicle else player.global_position
	var threats: Array[Node3D] = []
	for node in list:
		var unit := node as Enemy
		# `target` may be freed; typed arrays reject freed objects in `in`.
		if unit and is_instance_valid(unit.target) and unit.target in guarded 				and unit.global_position.distance_to(near) < 20.0:
			threats.append(unit)
	return threats


func in_territory(point: Vector3) -> bool:
	var offset := point - territory_center
	return territory_radius <= 0.0 or Vector2(offset.x, offset.z).length() <= territory_radius


## Guard dogs trot back to their post once the intruder leaves; pets stay
## at their owner's heel.
func _idle() -> void:
	if pet_owner != null and is_instance_valid(pet_owner) and faction == Faction.HOSTILE:
		var owner_node := pet_owner as Node3D
		var heel := owner_node.global_position + owner_node.global_basis.x * 1.0
		move_speed = 3.5 if global_position.distance_to(heel) < 5.0 else 6.5
		_nav.target_position = heel if global_position.distance_to(heel) > 1.2 else global_position
		return
	if faction == Faction.HOSTILE and territory_radius > 0.0 and global_position.distance_to(home) > 6.0:
		_nav.target_position = home
		return
	super()


func _build_visual() -> Node3D:
	return Models.dog(_material, body_height)


func _think() -> void:
	var had_target := _is_valid(target)
	super()
	if not had_target and _is_valid(target) and faction == Faction.HOSTILE:
		Sfx.play(&"bark", global_position, 0.0)
		if target is Player:
			Game.tip("guard_dogs", "Guard dogs only defend the datacenter grounds: back off and they return to their post. A treat [T] turns one to your side.")


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	# Allied dogs bite harder: they are "chasing away" low-tier guards.
	var damage := bite_damage * (2.5 if faction == Faction.ALLY else 1.0)
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", damage, global_position, &"bite")
	if victim.has_method("apply_slow"):
		victim.call(&"apply_slow", slow_factor, slow_duration)
