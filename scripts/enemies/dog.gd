class_name Dog
extends Enemy
## Fast pursuer: weak bite that slows its victim. A treat turns it into a
## permanent ally that follows the player and bites hostiles.

@export var bite_damage := 4.0
@export var slow_factor := 0.5
@export var slow_duration := 1.5


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
	_emit_defeated()
	_flash(Color(0.6, 1.0, 0.6))
	return true


func _build_visual() -> Node3D:
	return Models.dog(_material, body_height)


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	# Allied dogs bite harder: they are "chasing away" low-tier guards.
	var damage := bite_damage * (2.5 if faction == Faction.ALLY else 1.0)
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", damage, global_position, &"bite")
	if victim.has_method("apply_slow"):
		victim.call(&"apply_slow", slow_factor, slow_duration)
