class_name ReconDrone
extends CharacterBody3D
## The player's quadcopter ([X], or fire with the Recon drone selected). It
## flies from its own chase camera while the player stands still: WASD moves,
## Space climbs, C descends, the mouse steers. Hostiles it sees (in front, a
## clear line of sight, within `spot_range`) are spotted for `spot_seconds`:
## the HUD marks them through walls. With an FPV payload (the Recon drone's
## ammo), the left mouse button dives it into whatever is under the
## crosshair and detonates. A flat battery, flying out of signal range, [X],
## or the pilot getting hurt bring it home; guards shoot it down.

signal ended(drone: ReconDrone)

const SPOT_INTERVAL := 0.25
## Line of sight for spotting: world and destructibles.
const SIGHT_MASK := 1 | 16
## Highest it flies (world y).
const CEILING := 45.0
## Recon pay: each site unit first spotted before its alarm, and a full
## recon (RECON_SHARE of a quiet site's security spotted) of a site.
const SPOT_BOUNTY := 5
const RECON_BONUS := 60
const RECON_SHARE := 0.7

@export var speed := 12.0
@export var climb_speed := 6.0
@export var battery := 45.0
@export var max_range := 90.0
@export var max_health := 25.0
@export var spot_range := 55.0
@export var spot_seconds := 30.0
@export var dive_speed := 26.0
@export var dive_seconds := 3.0
@export var blast_damage := 150.0
@export var blast_radius := 5.0

var pilot: Player
var health := 0.0
var battery_left := 0.0
var diving := false
## Hostiles newly spotted on this flight (tests read it).
var spotted_count := 0

var _yaw := 0.0
var _pitch := -0.3
var _visual: Node3D
var _pivot: Node3D
var _camera: Camera3D
var _rotors: Array[Node3D] = []
var _spot_left := 0.0
var _dive_left := 0.0
var _buzz: AudioStreamPlayer3D
var _ending := false


func _ready() -> void:
	add_to_group("player_drones")
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD | Game.LAYER_VEHICLES | Game.LAYER_DESTRUCTIBLE
	health = max_health
	battery_left = battery
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	_visual = WeaponModels.build(&"drone")
	_visual.scale = Vector3.ONE * 3.0
	add_child(_visual)
	for node in _visual.find_children("Rotor*", "MeshInstance3D", true, false):
		_rotors.append(node as Node3D)
	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.2, 2.8)
	_camera.fov = 80.0
	_pivot.add_child(_camera)
	_apply_look()
	_camera.make_current()
	_buzz = Sfx.loop(self, &"ev_loop", -6.0)
	if _buzz:
		_buzz.pitch_scale = 2.4
	Models.set_gi_mode(_visual, GeometryInstance3D.GI_MODE_DYNAMIC)
	Game.tip("drone", "Drone up! WASD flies, Space climbs, C descends. Hostiles in view get marked through walls. With an FPV payload loaded, left click dives it in and detonates. [X] brings it home.")


## Faces the drone (and its camera) along world yaw `yaw`.
func set_heading(yaw: float) -> void:
	_yaw = yaw
	_apply_look()


func payloads() -> int:
	if pilot == null:
		return 0
	var kit := pilot.weapon_named("Recon drone")
	return maxi(kit.ammo, 0) if kit else 0


## Where units aim when shooting at it.
func aim_point() -> Vector3:
	return global_position


func _unhandled_input(event: InputEvent) -> void:
	if _ending or diving:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * Game.mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * Game.mouse_sensitivity, -1.3, 0.5)
		_apply_look()


func _apply_look() -> void:
	if _pivot:
		_pivot.global_rotation = Vector3(_pitch, _yaw, 0.0)


func _physics_process(delta: float) -> void:
	if _ending:
		return
	for rotor in _rotors:
		rotor.rotate_y(delta * 45.0)
	if diving:
		_dive(delta)
		return
	battery_left -= delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y) * speed
	if Input.is_action_pressed("jump"):
		wish.y += climb_speed
	if Input.is_action_pressed("descend"):
		wish.y -= climb_speed
	if global_position.y > CEILING and wish.y > 0.0:
		wish.y = 0.0
	velocity = velocity.lerp(wish, 1.0 - exp(-4.0 * delta))
	move_and_slide()
	# Lean into the motion.
	var local := Basis(Vector3.UP, _yaw).inverse() * velocity
	_visual.rotation = Vector3(local.z * 0.03, _yaw, -local.x * 0.03)
	if _buzz:
		_buzz.pitch_scale = 2.2 + velocity.length() / speed * 0.5

	if Input.is_action_just_pressed("drone"):
		recall("Drone on its way back.", 2.0)
		return
	if Input.is_action_just_pressed("fire"):
		if payloads() > 0:
			_start_dive()
		else:
			Game.notify("No FPV payload loaded. DUECE Hardware's drone table has more.", 2.5)
	if pilot and global_position.distance_to(pilot.global_position) > max_range:
		recall("Signal lost: the drone flew home.", 4.0)
		return
	if battery_left <= 0.0:
		recall("Drone battery flat.", 6.0)
		return
	_spot_left -= delta
	if _spot_left <= 0.0:
		_spot_left = SPOT_INTERVAL
		_spot()
	_update_hud()


## Marks hostiles in view (dormant site security too: that's the point of
## scouting before an attack).
func _spot() -> void:
	var eye := _camera.global_position
	var forward := -_camera.global_basis.z
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit == null or not unit.is_alive() or unit.spotted_left > spot_seconds - 1.0:
			continue
		var to := unit.aim_point() - eye
		if to.length() > spot_range or to.normalized().dot(forward) < 0.55:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, unit.aim_point(), SIGHT_MASK, [get_rid()])
		if not space.intersect_ray(query).is_empty():
			continue
		if unit.spot(spot_seconds):
			spotted_count += 1
		if unit.site != &"" and unit.is_dormant() and not unit.has_meta(&"recon"):
			unit.set_meta(&"recon", true)
			Game.add_cash(SPOT_BOUNTY)
			_check_recon(unit.site)


## A quiet site with most of its security spotted: recon complete, once per
## site. Pays a bonus and marks its cooling units.
func _check_recon(site: StringName) -> void:
	if site == &"police" or Game.recons.has(site):
		return
	var total := 0
	var seen := 0
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		# Bosses and indoor posts (the executive suite) are out of a drone's sight.
		if unit == null or not unit.is_alive() or unit.site != site or not unit.boss_name.is_empty() or unit.stay_put:
			continue
		total += 1
		if unit.has_meta(&"recon"):
			seen += 1
	if total == 0 or float(seen) / total < RECON_SHARE:
		return
	Game.recons[site] = true
	Game.add_cash(RECON_BONUS)
	Game.count("recons")
	var marked := ScoutPoint.mark_cooling_units(get_tree(), site)
	var site_name := String(site).capitalize()
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		if (node as DatacenterSite).site_id == site:
			site_name = (node as DatacenterSite).display_name
	Game.notify("Recon of %s complete: security mapped%s. (+$%d)" % [site_name,
		", cooling units marked" if marked > 0 else "", RECON_BONUS], 4.0)
	Sfx.ui(&"jingle_clear", -8.0)


## Sites this drone (or any) has fully scouted (tests read it).
static func recon_done(site: StringName) -> bool:
	return Game.recons.has(site)


func _update_hud() -> void:
	var signal_left := 1.0
	if pilot:
		signal_left = 1.0 - global_position.distance_to(pilot.global_position) / max_range
	Game.set_info("drone", "DRONE   battery %d%%   signal %d%%   spotted %d      [LMB] FPV dive (%d)   [X] return" % [
		ceili(maxf(battery_left, 0.0) / battery * 100.0), ceili(clampf(signal_left, 0.0, 1.0) * 100.0),
		spotted_count, payloads()])


func _start_dive() -> void:
	diving = true
	_dive_left = dive_seconds
	var kit := pilot.weapon_named("Recon drone") if pilot else null
	if kit:
		kit.ammo -= 1
		pilot.weapon_changed.emit(pilot.current_weapon())
	Sfx.play(&"rocket", global_position, -6.0, 1.6)
	Game.set_info("drone", "FPV DIVE")


## Straight down the crosshair until it hits something or runs out of time.
func _dive(delta: float) -> void:
	_dive_left -= delta
	velocity = -_camera.global_basis.z * dive_speed
	var hit := move_and_collide(velocity * delta)
	if hit != null or _dive_left <= 0.0 or _hostile_close():
		_detonate()


func _hostile_close() -> bool:
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Node3D
		if unit and unit.global_position.distance_to(global_position) < 2.0 + (1.5 if unit is FelsaCar else 0.0):
			return true
	return false


func _detonate() -> void:
	var blast := Explosive.new()
	blast.radius = blast_radius
	blast.damage = blast_damage
	get_parent().add_child(blast)
	blast.global_position = global_position
	blast.detonate.call_deferred()
	Game.count("fpv_strikes")
	_end("", 10.0)


func apply_damage(amount: float, _from: Vector3, _kind: StringName = &"generic") -> void:
	if _ending or amount <= 0.0:
		return
	health -= amount
	Sfx.play(&"hit_metal", global_position, -4.0, 1.4)
	if health <= 0.0:
		Vfx.explosion(get_parent(), global_position, 1.2)
		Sfx.play(&"explosion", global_position, -8.0, 1.8)
		_end("Drone shot down. A new one is ready in 20 s.", 20.0)


## Brings the drone home (the pilot gets their own view back).
func recall(reason := "", cooldown := 2.0) -> void:
	if _ending:
		return
	Vfx.dust(get_parent(), global_position)
	_end(reason, cooldown)


func _end(reason: String, cooldown: float) -> void:
	if _ending:
		return
	_ending = true
	Game.set_info("drone", "")
	if not reason.is_empty():
		Game.notify(reason, 3.0)
	if pilot and is_instance_valid(pilot):
		pilot.drone_ended(cooldown)
	ended.emit(self)
	queue_free()
