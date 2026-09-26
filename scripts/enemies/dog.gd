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
	if stray and faction == Faction.HOSTILE:
		return "strays"
	return super()


func _candidates() -> Array[Node3D]:
	var list := super()
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


func in_territory(point: Vector3) -> bool:
	var offset := point - territory_center
	return territory_radius <= 0.0 or Vector2(offset.x, offset.z).length() <= territory_radius


## Guard dogs trot back to their post once the intruder leaves.
func _idle() -> void:
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
