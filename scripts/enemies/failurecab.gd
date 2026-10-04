class_name Failurecab
extends FelsaCar
## A Felsa Failurecab: a driverless gold two-seat robotaxi that roams the
## streets on a loop (`route`) with its "FULL SELF-DRIVING (BETA)" roof sign,
## obeying traffic, bothering nobody. [E] next to one hacks it: it turns
## green, joins your side, and drives itself down the roads (Level.road_route)
## to the nearest datacenter still standing, through the front gate, and
## into the nearest cooling unit, where its battery goes up (`blast_damage`).
## During the defense a hacked cab rams the nearest hostile instead. Group
## `failurecabs` (and `robotaxis` until hacked).

signal hacked(cab: Failurecab)

@export var route: Array[Vector3] = []
@export var blast_radius := 8.0
@export var blast_damage := 260.0
@export var hack_reach := 4.0

var is_hacked := false

var _leg := 0
## After hacking: road waypoints to the site's gate, then the target.
var _mission: Array[Vector3] = []
var _strike: Variant = null  # the cooling unit (or hostile) it's going for
var _sign: Label3D
var _detonated := false
var _site: DatacenterSite = null
## Mission watchdog: seconds on the mission, and seconds without progress.
var _mission_time := 0.0
var _still_time := 0.0
var _last_spot := Vector3.INF
const MISSION_LIMIT := 45.0


func _init() -> void:
	super()
	obeys_traffic = true
	thermal_runaway = false
	bullet_factor = 1.0
	max_health = 110.0
	top_speed = 13.0
	traffic_speed = 7.0
	wobble = 0.0
	bounty = 0
	body_size = Vector3(1.9, 1.15, 3.9)
	body_color = Color(0.86, 0.72, 0.42)  # the gold robotaxi
	explosion_damage = 40.0


func _ready() -> void:
	super()
	add_to_group("failurecabs")
	add_to_group("interactables")


func _faction_group() -> String:
	return "allies" if is_hacked else "robotaxis"


func _candidates() -> Array[Node3D]:
	if not is_hacked:
		return []
	return []  # it steers by `_strike`, not by sight


## [E] interactable: hack it while it's still roaming.
func in_reach(player: Node3D) -> bool:
	return not is_hacked and is_alive() and player.global_position.distance_to(global_position) <= hack_reach


func offer_text(_player: Player) -> String:
	return "[E] Hack the Failurecab (it'll drive itself into a datacenter)"


func interact(_player: Player) -> void:
	hack()


## Turns it: green, allied, and on a mission. Returns false if it can't.
func hack() -> bool:
	if is_hacked or not is_alive():
		return false
	is_hacked = true
	remove_from_group("robotaxis")
	remove_from_group("interactables")
	set_faction(Faction.ALLY)
	obeys_traffic = false
	rushing = true  # ignores traffic from here on
	# A battering ram now: it shoves through cars (they don't stop it) and
	# smashes gates and fences it runs into.
	collision_mask = Game.LAYER_WORLD | Game.LAYER_DESTRUCTIBLE
	ram_damage_per_mps = 40.0
	Sfx.play(&"glitch", global_position, 0.0)
	Vfx.impact(get_parent(), global_position + Vector3.UP * 1.5, Vector3.UP, &"metal", 1.2)
	if _sign:
		_sign.text = "FULL SELF-DESTRUCT\n(BETA)"
		_sign.modulate = Color(0.4, 1.0, 0.5)
		Models.fit_label(_sign, Vector2(0.85, 0.26))
	if _material:
		_material.albedo_color = Color(0.45, 0.9, 0.5)
	_plan_mission()
	Game.count("cabs_hacked")
	hacked.emit(self)
	return true


## Where it's headed: the nearest cooling unit of a standing datacenter (by
## road to its front gate, then straight in); in the defense, the nearest
## hostile.
func _plan_mission() -> void:
	_mission.clear()
	_strike = null
	var level := get_tree().get_first_node_in_group("level")
	var best: Node3D = null
	for node in get_tree().get_nodes_in_group("cooling_units"):
		var unit := node as Destructible
		if unit == null or unit.is_destroyed:
			continue
		if best == null or unit.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = unit
	if best == null:
		Game.notify("Failurecab hacked: no datacenters left, so it's hunting hostiles.", 4.0)
		return
	_strike = best
	var site_node: DatacenterSite = null
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		var candidate := node as DatacenterSite
		if candidate.site_id == best.site_id or best.is_ancestor_of(candidate) or candidate.is_ancestor_of(best):
			site_node = candidate
	_site = site_node
	if site_node and level and level.has_method("road_route"):
		var gate := site_node.at(Vector3(0.0, 0.2, site_node.compound.y * 0.5 + 6.0))
		_mission.assign(level.call(&"road_route", global_position, gate))
		_mission.append(site_node.at(Vector3(0.0, 0.2, site_node.compound.y * 0.5 - 4.0)))
		# Line up with the cooling unit, then straight in.
		var unit_local := site_node.to_local(best.global_position)
		_mission.append(site_node.to_global(Vector3(unit_local.x, 0.2, site_node.compound.y * 0.5 - 4.0)))
		Game.notify("Failurecab hacked! It's driving itself into %s. Stand clear." % site_node.display_name, 5.0)
	Game.tip("failurecab", "Hacked Failurecabs drive to the nearest datacenter and blow up against a cooling unit. Hack more for a bigger bang.")


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_hacked or _detonated or _is_dead:
		return
	# Wedged somewhere (a gate post, a wreck, a corner): skip ahead, or blow
	# up right there if it's close to the target or has been at it too long.
	_mission_time += delta
	if _last_spot == Vector3.INF or global_position.distance_to(_last_spot) > 2.0:
		_last_spot = global_position
		_still_time = 0.0
	else:
		_still_time += delta
	var near_target := _strike != null and is_instance_valid(_strike) and (_strike as Node3D).global_position.distance_to(global_position) < 25.0
	if _mission_time > MISSION_LIMIT or (_still_time > 3.0 and near_target):
		_detonate()
	elif _still_time > 3.0 and not _mission.is_empty():
		_mission.remove_at(0)
		_still_time = 0.0


func _goal_point() -> Vector3:
	if not is_hacked:
		if route.is_empty():
			return global_position
		var goal := route[_leg]
		var offset := goal - global_position
		if Vector2(offset.x, offset.z).length() < 4.0:
			_leg = (_leg + 1) % route.size()
			goal = route[_leg]
		return goal
	while not _mission.is_empty():
		var next := _mission[0]
		var offset := next - global_position
		if Vector2(offset.x, offset.z).length() > 5.0:
			return next
		_mission.remove_at(0)
	if _strike == null or not is_instance_valid(_strike) or (_strike is Destructible and (_strike as Destructible).is_destroyed) \
			or (_strike is Enemy and not (_strike as Enemy).is_alive()):
		_retarget()
	if _strike != null and is_instance_valid(_strike):
		var point := (_strike as Node3D).global_position
		if Vector2(point.x - global_position.x, point.z - global_position.z).length() < 3.5:
			_detonate()
		return point
	return global_position


## The strike target is gone: the next cooling unit, else the nearest hostile.
func _retarget() -> void:
	_strike = null
	var best: Node3D = null
	for group in ["cooling_units", "hostiles"]:
		for node in get_tree().get_nodes_in_group(group):
			var thing := node as Node3D
			if thing is Destructible and (thing as Destructible).is_destroyed:
				continue
			if thing is Enemy and (not (thing as Enemy).is_alive() or (thing as Enemy).is_dormant()):
				continue
			if thing.global_position.distance_to(global_position) > 80.0:
				continue
			if best == null or thing.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
				best = thing
		if best:
			break
	_strike = best


func _handle_collisions() -> void:
	if not is_hacked:
		# Neutral traffic: bump and back off, never ram damage.
		for i in get_slide_collision_count():
			var contact := get_slide_collision(i)
			if contact.get_normal().y <= 0.7 and absf(speed) >= ram_min_speed and _reverse_left <= 0.0:
				_begin_reverse()
				return
		return
	if not _detonated:
		for i in get_slide_collision_count():
			var hit := get_slide_collision(i).get_collider() as Node
			if hit is Destructible and _site and is_instance_valid(_site) and is_instance_valid(_site.datacenter) \
					and _site.datacenter.is_ancestor_of(hit):
				_detonate()  # the building, a rack, or a cooling unit
				return
	# Ramming its way in (gates, fences) is the autopilot's fault too.
	Game.alarm_hold += 1
	super()
	Game.alarm_hold -= 1


## Rams home: its battery goes up.
func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var blast := Explosive.new()
	blast.radius = blast_radius
	blast.damage = blast_damage
	get_parent().add_child(blast)
	blast.global_position = global_position + Vector3.UP * 0.8
	_quiet_blast.call_deferred(blast)
	apply_damage(99999.0, global_position, &"explosive")


## The blast raises no alarm: the site blames Felsa's autopilot, not you.
func _quiet_blast(blast: Explosive) -> void:
	Game.alarm_hold += 1
	blast.detonate()
	Game.alarm_hold -= 1
	Game.notify("Security blames the Failurecab's autopilot. Nobody's looking for you.", 4.0)


func _decorate(visual_root: Node3D) -> void:
	# Roof sign, both sides (it's a cab).
	var box := _add_box(visual_root, Vector3(0.9, 0.3, 0.12), Vector3(0.0, body_size.y + 0.62, 0.2), _solid(Color(0.1, 0.1, 0.12)))
	for side: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = "FULL SELF-DRIVING\n(BETA)"
		label.modulate = Color(1.0, 0.85, 0.4)
		label.outline_size = 0
		label.position = Vector3(0.0, 0.0, side * 0.065)
		label.rotation.y = 0.0 if side > 0.0 else PI
		box.add_child(label)
		Models.fit_label(label, Vector2(0.85, 0.26))
		if side > 0.0:
			_sign = label
	var brand := Label3D.new()
	brand.text = "FELSA FAILURECAB"
	brand.modulate = Color(0.15, 0.15, 0.17)
	brand.outline_size = 0
	brand.position = Vector3(body_size.x * 0.5 + 0.02, 0.75, 0.2)
	brand.rotation.y = PI * 0.5
	visual_root.add_child(brand)
	Models.fit_label(brand, Vector2(2.2, 0.3))
