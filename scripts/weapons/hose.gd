class_name Hose
extends RefCounted
## What one 0.1 s tick of a water jet does, shared by the player's hoses and
## the fire truck's roof cannon: people in a narrow cone out to `reach` with
## a clear line get soaked and pushed back (knocked down up close when the
## weapon `stuns`), protesters scatter unharmed, and fires along the jet go
## out. Static only.

const CONE_COS := 0.93
const LOS_MASK := 1 | 16  # world, destructibles


## Sprays `weapon` (a SPRAY Weapon) from `from` along `aim` for one tick.
## Returns [[unit, health before], ...] for units it damaged (HUD numbers).
static func spray_tick(shooter: Node3D, from: Vector3, aim: Vector3, weapon: Weapon, exclude: Array[RID]) -> Array:
	var damaged := []
	var tree := shooter.get_tree()
	var flat_aim := Vector3(aim.x, 0.0, aim.z).normalized()
	var tick := weapon.cooldown
	var space := shooter.get_world_3d().direct_space_state
	for group: String in ["hostiles", "protesters"]:
		for node in tree.get_nodes_in_group(group):
			var unit := node as Enemy
			if unit == null or not unit.is_alive() or unit is FelsaCar or unit is Drone:
				continue
			var to := unit.aim_point() - from
			var distance := to.length()
			if distance > weapon.reach or to.normalized().dot(aim) < CONE_COS:
				continue
			var query := PhysicsRayQueryParameters3D.create(from, unit.aim_point(), LOS_MASK, exclude)
			if not space.intersect_ray(query).is_empty():
				continue
			if unit is OrangeHat:
				(unit as OrangeHat).scatter()
				unit.apply_knockback(flat_aim * weapon.knockback * 0.5)
				continue
			var falloff := 1.0 - distance / weapon.reach * 0.5
			unit.soak(3.0)
			if randf() < 0.3:
				Vfx.impact(shooter.get_parent(), unit.aim_point() - to.normalized() * 0.3, -to.normalized(), &"water", 0.8)
			if unit.boss_name.is_empty():
				unit.apply_knockback(flat_aim * weapon.knockback * falloff)
				if weapon.stuns and distance < weapon.reach * 0.6:
					unit.knock_down(0.4)
				elif randf() < 0.08:
					unit.call(&"_act", &"hit_chest")
			if weapon.damage > 0.0:
				var before := unit.health
				unit.apply_damage(weapon.damage * tick, from, &"water")
				damaged.append([unit, before])
	for node in tree.get_nodes_in_group("extinguishable"):
		var fire := node as Node3D
		if fire == null or fire == shooter:
			continue
		var on_line := Geometry3D.get_closest_point_to_segment(fire.global_position, from, from + aim * weapon.reach)
		var flat := Vector2(on_line.x - fire.global_position.x, on_line.z - fire.global_position.z)
		# Water arcs down: a fire below the jet line (a roof cannon aiming at the
		# street) still gets soaked; one well above it doesn't.
		var above := on_line.y - fire.global_position.y
		if flat.length() < 2.5 and above > -2.0 and above < 3.0 + from.distance_to(on_line) * 0.25:
			fire.call(&"douse", weapon.douse * tick)
	return damaged
