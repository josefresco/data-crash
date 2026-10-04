class_name PoliceCruiser
extends SupplyVan
## A patrol car on a loop around the block, light bar flashing. When a
## datacenter's alarm goes off, the level dispatches it: siren on, it drives to
## that site's front gate and two riot officers jump out to back up corporate
## security. Neighborhood police belong to site &"police": they only turn on
## you if you attack them.

## Road waypoints to the scene when dispatched (world space); empty = patrolling.
var respond_route: Array[Vector3] = []
## True while dispatched (siren on).
var responding := false
## The site the deployed officers join (their `site`).
var respond_site := &""
var deployed := false

## It pulls up and the officers get out this close to the suspect.
const DEPLOY_RANGE := 11.0

var _lights: Array[MeshInstance3D] = []
var _light_clock := 0.0
var _siren: AudioStreamPlayer3D


func _init() -> void:
	max_health = 160.0
	top_speed = 9.0
	wobble = 0.0
	bounty = 0
	body_size = Vector3(2.0, 1.5, 4.4)
	model_path = "res://assets/kenney/cars/police.glb"
	model_scale = 1.45
	thermal_runaway = false
	motor_cue = &"engine_loop"
	bullet_factor = 1.0
	explosion_damage = 50.0


func _decorate(visual_root: Node3D) -> void:
	# Light bar on the roof: red and blue halves that alternate.
	for side in [-1.0, 1.0]:
		var light := _add_box(visual_root, Vector3(0.55, 0.14, 0.3), Vector3(side * 0.32, 2.05, 0.2),
			Models.glow(Color(1.0, 0.1, 0.1) if side < 0.0 else Color(0.15, 0.35, 1.0), 4.0))
		_lights.append(light)


## Siren on, down the road `waypoints` to the last one, where the officers
## deploy and join `site_id`.
func dispatch(waypoints: Array[Vector3], site_id: StringName) -> void:
	respond_route = waypoints
	responding = true
	respond_site = site_id
	top_speed = 13.0
	site = site_id  # awake for as long as that alarm rings


## On a call it goes for the player the moment it sees them (see
## `_goal_point`); on patrol it hunts nobody.
func _candidates() -> Array[Node3D]:
	var list: Array[Node3D] = []
	if not responding or deployed:
		return list
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.is_visible_in_tree():
		list.append(player)
	elif player and player.vehicle:
		list.append(player.vehicle)
	return list


## Called off: siren off, back to the patrol loop (deployed officers stand down).
func recall() -> void:
	responding = false
	deployed = false
	respond_route.clear()
	respond_site = &""
	site = &"police"
	target = null
	top_speed = 9.0
	if _siren:
		_siren.queue_free()
		_siren = null


func in_traffic_mode() -> bool:
	return not is_pursuing() and super()


## Lights and siren only while there's a call: dispatched to a site, or
## chasing the player after they attacked the police. Patrols ride dark.
func is_pursuing() -> bool:
	return is_alive() and (responding or (site == &"police" and Game.is_alarmed(&"police")))


func _process(delta: float) -> void:
	super(delta)
	var active := is_pursuing()
	if active:
		_light_clock += delta * 8.0
	for i in _lights.size():
		_lights[i].visible = active and int(_light_clock) % 2 == i
	if active and _siren == null:
		_siren = Sfx.loop(self, &"siren_loop", -14.0 if deployed else -4.0)
	elif not active and _siren:
		_siren.queue_free()
		_siren = null


func _goal_point() -> Vector3:
	if not responding:
		return super()
	if deployed:
		return global_position
	# Spotted the suspect: leave the route, run them down, and pull up to
	# let the officers out right there.
	if _is_valid(target) and _has_los:
		if _distance_to(target) < DEPLOY_RANGE and absf(speed) < 9.0:
			_deploy()
			return global_position
		return target.global_position
	if respond_route.is_empty():
		_deploy()
		return global_position
	var goal: Vector3 = respond_route[0]
	var offset := goal - global_position
	if Vector2(offset.x, offset.z).length() < (5.0 if respond_route.size() == 1 else 4.0):
		respond_route.pop_front()
		if respond_route.is_empty():
			_deploy()
			return global_position
		goal = respond_route[0]
	return goal


func _deploy() -> void:
	deployed = true
	speed = 0.0
	top_speed = 0.0
	if _siren:
		_siren.volume_db = -14.0
	for side in [-1.0, 1.0]:
		var officer := Police.new()
		officer.site = respond_site
		officer.position = get_parent().to_local(global_position + global_basis.x * side * 2.5 + Vector3.UP * 0.2)
		get_parent().add_child(officer)
	Game.notify("The police have arrived to protect corporate property.", 4.0)
	Game.tip("police", "Riot police block bullets from the front with their shields. Flank them, use explosives or fire, or stun them with an EMP.")
