class_name Frost
extends Enemy
## FROST: heavy armored agent. Hunts townspeople and carries them off the map
## (trust loss). With no one to grab, zip-ties the player (damage + heavy slow).
## Priority target: kill it before it reaches its exit to free the captive.

@export var grab_damage := 10.0
@export var bullet_armor := 0.5
@export var carry_speed_factor := 0.7

var captive: Townsperson = null


func _init() -> void:
	outfit = "frost"
	max_health = 220.0
	move_speed = 3.2
	sight_range = 40.0
	attack_range = 1.8
	attack_interval = 1.0
	bounty = 40
	body_color = Color(0.08, 0.1, 0.16)
	body_radius = 0.45
	body_height = 2.0


func _physics_process(delta: float) -> void:
	if captive and not is_instance_valid(captive):
		captive = null
	super(delta)


func _think() -> void:
	if captive == null:
		super()
		return
	# Carrying someone: head back to where we came in, ignore everything else.
	target = null
	_has_los = false
	_nav.target_position = home
	var offset := home - global_position
	if Vector2(offset.x, offset.z).length() < 3.0:
		var taken := captive
		captive = null
		taken.abduct()
		_emit_defeated()  # escaped: no longer part of the wave, no bounty
		queue_free()


func _nav_direction() -> Vector3:
	var direction := super()
	return direction * carry_speed_factor if captive else direction


func _candidates() -> Array[Node3D]:
	var people: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("townspeople"):
		var person := node as Townsperson
		if person and not person.is_captured():
			people.append(person)
	return people if not people.is_empty() else super()


func _modify_damage(amount: float, _from: Vector3, kind: StringName) -> float:
	return amount * bullet_armor if kind == &"bullet" else amount


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	var person := victim as Townsperson
	if person and not person.is_captured():
		captive = person
		person.captured_by(self)
		target = null
		return
	if victim is Destructible:
		(victim as Destructible).apply_damage(grab_damage * 2.0, global_position, &"melee")
		return
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", grab_damage, global_position, &"melee")
	if victim.has_method("apply_slow"):
		victim.call(&"apply_slow", 0.3, 2.5)


func _on_death() -> void:
	if captive:
		captive.release()
		captive = null


func _decorate(_visual_root: Node3D) -> void:
	var armor := _solid(Color(0.15, 0.18, 0.25))
	var top := _head_top()
	_add_box(_anchor(&"chest"), Vector3(0.56, 0.5, 0.4), Vector3(0.0, -0.05, 0.0), armor)  # plate carrier
	_add_box(_anchor(&"head"), Vector3(0.66, 0.34, 0.66), Vector3(0.0, top - 0.16, 0.02), armor)  # helmet
	# Visor stripe so they read at a distance.
	_add_box(_anchor(&"head"), Vector3(0.52, 0.08, 0.04), Vector3(0.0, top - 0.26, -0.34), _solid(Color(0.4, 0.8, 1.0)))
	_add_box(_anchor(&"hand_r"), Vector3(0.14, 0.14, 0.6), Vector3(0.0, -0.05, -0.25), armor)  # capture launcher
