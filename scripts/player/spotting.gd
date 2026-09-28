class_name Spotting
extends RefCounted
## Binocular scouting. Each datacenter's key pieces are tagged as scout
## targets (`tag_site`: cooling units, gas turbines, the cooling tower,
## diesel tanks, gates, river pumps, chatbot kiosks, Crapya's control room).
## Holding the binoculars on one with a clear line of sight for
## `SPOT_TIME` marks it: a see-through label over it and a target on the
## minimap (group `spotted_targets`). A site whose cooling units are all
## spotted is scouted (its ScoutPoint completes). Static only.

const SPOT_TIME := 0.6
const RANGE := 160.0
## Cone around the view center that counts as "on" a target (radians), and
## the extra allowance for big things up close (meters of radius).
const CONE := 0.045
const TARGET_RADIUS := 1.8
## LOS: the world and props block; chain-link fences are see-through.
const LOS_MASK := 1 | 16


## Tags a site's pieces as scout targets (meta `scout_label`, `scout_site`).
static func tag_site(site: DatacenterSite) -> void:
	for node in site.find_children("*", "", true, false):
		var label := _label_for(node)
		if label.is_empty() or node.is_in_group(&"scout_targets"):
			continue
		node.add_to_group(&"scout_targets")
		node.set_meta(&"scout_label", label)
		node.set_meta(&"scout_site", site.site_id)


static func _label_for(node: Node) -> String:
	if node.is_in_group(&"cooling_units"):
		return "Cooling unit"
	if node is GasTurbine:
		return "Gas turbine"
	if node is SiteGate:
		return "Gate"
	if node is CrapyaControlRoom:
		return "Control room"
	if node.is_in_group(&"river_pumps"):
		return "River pump"
	if node.is_in_group(&"chatbot_kiosks"):
		return "Chatbot kiosk"
	if node is Destructible:
		var name := String(node.name)
		if name == "CoolingTower":
			return "Cooling tower"
		if name.begins_with("DieselTank"):
			return "Diesel tank"
	return ""


static func is_spotted(node: Node) -> bool:
	return node.has_meta(&"spotted")


## Whether `node` still stands (not shattered or freed).
static func is_standing(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node is Destructible:
		return not (node as Destructible).is_destroyed
	if node is Enemy:
		return (node as Enemy).is_alive()
	return true


## The unspotted scout target nearest the view center of a ray from `eye`
## along `look` (unit), within the cone and in plain sight; else null.
static func target_in_view(tree: SceneTree, eye: Vector3, look: Vector3, space: PhysicsDirectSpaceState3D,
		exclude: Array[RID]) -> Node3D:
	var best: Node3D = null
	var best_angle := INF
	for node in tree.get_nodes_in_group(&"scout_targets"):
		var thing := node as Node3D
		if thing == null or is_spotted(thing) or not is_standing(thing):
			continue
		var center := aim_point(thing)
		var offset := center - eye
		var distance := offset.length()
		if distance > RANGE or distance < 0.5:
			continue
		var angle := look.angle_to(offset / distance)
		if angle > CONE + atan(TARGET_RADIUS / distance) or angle >= best_angle:
			continue
		if not can_see_any(thing, eye, space, exclude):
			continue
		best = thing
		best_angle = angle
	return best


## Middle of a target, a bit up from its origin (origins sit on the ground).
static func aim_point(thing: Node3D) -> Vector3:
	if thing is Destructible:
		return thing.global_position + Vector3.UP * (thing as Destructible).size.y * 0.5
	return thing.global_position + Vector3.UP * 1.2


## Any of a few points on `thing` (center, top, top corners) in plain sight:
## things in a row still show their tops past each other.
static func can_see_any(thing: Node3D, eye: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
	var points: Array[Vector3] = [aim_point(thing)]
	if thing is Destructible:
		var half := (thing as Destructible).size * 0.5
		var top := thing.global_position + Vector3.UP * half.y * 1.9
		points.append(top)
		for corner: Vector3 in [Vector3(half.x, 0.0, 0.0), Vector3(-half.x, 0.0, 0.0), Vector3(0.0, 0.0, half.z), Vector3(0.0, 0.0, -half.z)]:
			points.append(top + thing.global_basis * (corner * 0.8))
	for point in points:
		if can_see(thing, eye, point, space, exclude):
			return true
	return false


## Clear line from `eye` to `thing`: hits nothing, the thing itself (or a
## part of it), or only see-through things on the way (chain-link, the
## scout perch the player is standing on).
static func can_see(thing: Node3D, eye: Vector3, point: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
	var skip := exclude.duplicate()
	for i in 6:
		var query := PhysicsRayQueryParameters3D.create(eye, point, LOS_MASK, skip)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider := hit["collider"] as Node
		if collider == thing or thing.is_ancestor_of(collider) or (collider and collider.is_ancestor_of(thing)):
			return true
		if (collider is Destructible and (collider as Destructible).surface_kind == &"chainlink") or _on_perch(collider):
			skip.append((collider as CollisionObject3D).get_rid())
			continue
		return false
	return false


static func _on_perch(node: Node) -> bool:
	while node:
		if node is ScoutPoint:
			return true
		node = node.get_parent()
	return false


## Marks `thing` spotted: a see-through label over it and a minimap target.
## Returns true if it was new. A site with every cooling unit spotted is
## scouted (its ScoutPoint completes and pays).
static func spot(thing: Node3D) -> bool:
	if thing == null or is_spotted(thing):
		return false
	thing.set_meta(&"spotted", true)
	thing.add_to_group(&"spotted_targets")
	var label := String(thing.get_meta(&"scout_label", "Target"))
	if not thing.has_meta(&"marked"):
		thing.set_meta(&"marked", true)
		var marker := Label3D.new()
		marker.text = "v %s v" % label.to_upper()
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.pixel_size = 0.012
		marker.outline_size = 10
		marker.modulate = Color(1.0, 0.35, 0.3) if label == "Cooling unit" else Color(1.0, 0.75, 0.3)
		marker.position.y = (thing as Destructible).size.y + 2.0 if thing is Destructible else 3.0
		thing.add_child(marker)
	var site := StringName(thing.get_meta(&"scout_site", &""))
	_check_site(thing.get_tree(), site)
	return true


## [spotted, total] scout targets still standing or spotted at `site`.
static func progress(tree: SceneTree, site: StringName) -> Vector2i:
	var done := 0
	var total := 0
	for node in tree.get_nodes_in_group(&"scout_targets"):
		if StringName(node.get_meta(&"scout_site", &"")) != site:
			continue
		if not is_spotted(node) and not is_standing(node):
			continue
		total += 1
		if is_spotted(node):
			done += 1
	return Vector2i(done, total)


## Every cooling unit at `site` spotted (or gone): its scout point completes.
static func _check_site(tree: SceneTree, site: StringName) -> void:
	for node in tree.get_nodes_in_group(&"cooling_units"):
		if StringName(node.get_meta(&"scout_site", &"")) == site and not is_spotted(node) and is_standing(node):
			return
	for node in tree.get_nodes_in_group(&"scout_points"):
		var point := node as ScoutPoint
		if point.site_id == site and not point.is_scouted:
			point.call(&"_complete")
