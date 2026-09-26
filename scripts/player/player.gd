class_name Player
extends CharacterBody3D
## Third-person on-foot controller: move, look, jump, shoot, plant C4, enter vehicles.

signal health_changed(health: float, max_health: float)
signal charges_changed(charges: int)
signal prompt_changed(text: String)
signal weapon_changed(weapon: Weapon)

## Hitscan and aim rays hit world, vehicles, destructibles, and units (not debris).
const AIM_MASK := 1 | 4 | 16 | 32

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 5.5
@export var acceleration := 12.0
@export var mouse_sensitivity := 0.0025
@export var max_health := 100.0

@export_group("Equipment")
@export var c4_charges := 4
@export var plant_range := 3.0
@export var enter_vehicle_range := 3.5
@export var treats := 5
@export var treat_range := 5.0
@export var talk_range := 3.5
@export var repair_range := 3.0
@export var repair_rate := 60.0
## Health restored per $1 when the player repairs.
@export var repair_per_dollar := 5.0

var health: float
var vehicle: Car = null
## Set by BuildController: clicks place structures instead of shooting.
var build_mode := false
var weapons: Array[Weapon] = Weapon.default_loadout()
var weapon_index := 0

var _pitch := -0.25
var _fire_timer := 0.0
var _spawn: Transform3D
var _prompt := ""
var _vehicle_change_frame := -1
var _slow_factor := 1.0
var _repair_debt := 0.0
var _slow_timer := 0.0
## While > 0, input steering is suppressed so knockback carries the player.
var _knockback_left := 0.0
var _rig: CharacterModel
## Fark's "Algorithm Re-education": movement input is mirrored while > 0.
var _reversed_left := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _pivot: Node3D = $CameraPivot
@onready var _spring: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _body: Node3D = $Body


func _ready() -> void:
	add_to_group("player")
	# Swap the placeholder capsule for the Kenney character: orange hoodie, jeans.
	for child in _body.get_children():
		(child as Node3D).visible = false
	_rig = CharacterModel.create("player", 1.8, 1)
	_body.add_child(_rig)
	Models.set_gi_mode(_body, GeometryInstance3D.GI_MODE_DYNAMIC)
	health = max_health
	_spawn = global_transform
	_spring.rotation.x = _pitch
	_spring.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_pivot.rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.2, 0.6)
		_spring.rotation.x = _pitch
	if not build_mode:
		if event.is_action_pressed("next_weapon"):
			select_weapon(weapon_index + 1)
		elif event.is_action_pressed("prev_weapon"):
			select_weapon(weapon_index - 1)


func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_move(delta)

	if global_position.y < -30.0:
		_respawn()

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not build_mode:
		if Input.is_action_pressed("fire") and _fire_timer <= 0.0:
			fire()
		if Input.is_action_just_pressed("plant"):
			_plant()
	if Input.is_action_just_pressed("treat"):
		give_treat()
	if Input.is_action_just_pressed("interact") and Engine.get_physics_frames() != _vehicle_change_frame:
		if not talk_down():
			var stall := _nearest_vendor()
			if stall:
				stall.buy(self)
			else:
				_try_enter_vehicle()
	if Input.is_action_pressed("repair"):
		_repair(delta)
	_update_prompt()


func apply_damage(amount: float, _from: Vector3, _kind: StringName = &"generic") -> void:
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_respawn()


## Shoves the player (rams, shockwaves). Adds straight onto the velocity.
func apply_knockback(impulse: Vector3) -> void:
	if vehicle:
		return
	velocity += impulse
	_knockback_left = 0.4


## Mirrors movement controls for `duration` seconds.
func apply_control_reversal(duration: float) -> void:
	_reversed_left = maxf(_reversed_left, duration)


func controls_reversed() -> bool:
	return _reversed_left > 0.0


## Slows movement to `factor` for `duration` seconds (dog bites).
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = minf(_slow_factor, factor) if _slow_timer > 0.0 else factor
	_slow_timer = maxf(_slow_timer, duration)


## Befriends the nearest hostile dog within reach. Returns true on success.
func give_treat() -> bool:
	if treats <= 0:
		return false
	var best: Dog = null
	var best_distance := treat_range
	for node in get_tree().get_nodes_in_group("hostiles"):
		var dog := node as Dog
		if dog == null:
			continue
		var distance := global_position.distance_to(dog.global_position)
		if distance < best_distance:
			best = dog
			best_distance = distance
	if best == null or not best.befriend():
		return false
	treats -= 1
	charges_changed.emit(c4_charges)
	return true


## Talks the nearest protester out of it. Returns true on success.
func talk_down() -> bool:
	var protester := _nearest_in_group("protesters", talk_range) as OrangeHat
	return protester != null and protester.persuade()


## Nearest damaged structure within reach, or null.
func repair_target() -> Destructible:
	var best: Destructible = null
	var best_distance := repair_range
	for node in get_tree().get_nodes_in_group("structures"):
		var structure := node as Destructible
		if structure == null or not structure.needs_repair():
			continue
		var distance := structure.distance_to_point(global_position + Vector3.UP)
		if distance < best_distance:
			best = structure
			best_distance = distance
	return best


## Nearest unfixed Phase 1 fixable (water mains) within its reach, or null.
func fixable_target() -> WaterMain:
	for node in get_tree().get_nodes_in_group("fixables"):
		var main := node as WaterMain
		if main and not main.is_fixed and global_position.distance_to(main.global_position) <= main.reach:
			return main
	return null


func _repair(delta: float) -> void:
	var structure := repair_target()
	if structure == null:
		var main := fixable_target()
		if main:
			main.work(delta)
		return
	if Game.cash <= 0:
		return
	var affordable := Game.cash * repair_per_dollar
	var restored := structure.repair(minf(repair_rate * delta, affordable))
	_repair_debt += restored / repair_per_dollar
	if _repair_debt >= 1.0:
		var dollars := int(_repair_debt)
		_repair_debt -= dollars
		Game.add_cash(-dollars)


func _nearest_vendor() -> GunShow:
	for node in get_tree().get_nodes_in_group("vendors"):
		var stall := node as GunShow
		if stall and stall.in_reach(self):
			return stall
	return null


func _nearest_in_group(group: String, max_distance: float) -> Node3D:
	var best: Node3D = null
	var best_distance := max_distance
	for node in get_tree().get_nodes_in_group(group):
		var other := node as Node3D
		var distance := global_position.distance_to(other.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


## Called by Car. Pass a car to hide and disable the player, null to get out.
func set_driving(car: Car, exit_position := Vector3.ZERO) -> void:
	vehicle = car
	_vehicle_change_frame = Engine.get_physics_frames()
	if car:
		hide()
		process_mode = Node.PROCESS_MODE_DISABLED
		collision_layer = 0
		collision_mask = 0
		_set_prompt("")
	else:
		global_position = exit_position
		velocity = Vector3.ZERO
		collision_layer = Game.LAYER_PLAYER
		collision_mask = Game.LAYER_WORLD | Game.LAYER_VEHICLES | Game.LAYER_DESTRUCTIBLE | Game.LAYER_ENEMIES
		show()
		process_mode = Node.PROCESS_MODE_INHERIT
		_camera.make_current()


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _reversed_left > 0.0:
		_reversed_left -= delta
		input = -input
	var cam_basis := _pivot.global_basis
	var direction := cam_basis.x * input.x + cam_basis.z * input.y
	direction.y = 0.0
	direction = direction.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if _slow_timer > 0.0:
		_slow_timer -= delta
		speed *= _slow_factor
	var weight := 1.0 - exp(-acceleration * delta)
	if _knockback_left > 0.0:
		_knockback_left -= delta
		weight *= 0.1  # mostly ballistic until the shove wears off
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)

	if direction.length_squared() > 0.01:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-direction.x, -direction.z), weight)

	move_and_slide()
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		_rig.set_motion(ground_speed / Enemy.RUN_CLIP_SPEED)
	else:
		_rig.play_jump()


## Ray from the screen center along the camera view.
func aim(max_distance: float, mask := AIM_MASK) -> Dictionary:
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := _camera.project_ray_origin(center)
	var to := from + _camera.project_ray_normal(center) * max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


## Aim ray limited to what the player can reach with their hands.
func _aim_in_reach() -> Dictionary:
	var hit := aim(_spring.spring_length + plant_range + 1.0)
	if hit.is_empty():
		return hit
	var chest := global_position + Vector3.UP
	if (hit["position"] as Vector3).distance_to(chest) > plant_range:
		return {}
	return hit


## Turns the camera so the crosshair sits on `point`. The camera orbits with
## yaw and pitch, so a few passes converge on the offset shoulder view.
func aim_at(point: Vector3) -> void:
	for i in 4:
		var direction := (point - _camera.global_position).normalized()
		_pivot.global_rotation.y = atan2(-direction.x, -direction.z)
		_pitch = clampf(asin(clampf(direction.y, -1.0, 1.0)), -1.2, 0.6)
		_spring.rotation.x = _pitch
		_spring.force_update_transform()
		_camera.force_update_transform()


func current_weapon() -> Weapon:
	return weapons[weapon_index]


## Selects `index`, skipping locked weapons in the direction of travel.
func select_weapon(index: int) -> void:
	var step := 1 if index >= weapon_index else -1
	for i in weapons.size():
		var candidate := wrapi(index + i * step, 0, weapons.size())
		if weapons[candidate].owned:
			weapon_index = candidate
			break
	weapon_changed.emit(current_weapon())


func weapon_named(weapon_name: String) -> Weapon:
	for weapon in weapons:
		if weapon.display_name == weapon_name:
			return weapon
	return null


## Unlocks a weapon (gun show, security cache) and adds ammo. Returns it.
func unlock_weapon(weapon_name: String, ammo := 0) -> Weapon:
	var weapon := weapon_named(weapon_name)
	if weapon == null:
		return null
	weapon.owned = true
	if weapon.max_ammo < 0:
		weapon.ammo = -1
	elif ammo > 0:
		weapon.ammo = maxi(weapon.ammo, 0) + ammo
	else:
		weapon.ammo = weapon.max_ammo
	weapon_changed.emit(current_weapon())
	return weapon


## Tops up every weapon (between waves, at the start of the defense).
func refill_ammo() -> void:
	for weapon in weapons:
		weapon.refill()
	weapon_changed.emit(current_weapon())


## Fires the current weapon once. Public so tests can shoot without input.
func fire() -> void:
	var weapon := current_weapon()
	if not weapon.has_ammo():
		return
	_fire_timer = weapon.cooldown
	if weapon.ammo > 0:
		weapon.ammo -= 1
	if weapon.kind == Weapon.Kind.THROWN:
		_throw(weapon)
	else:
		Vfx.muzzle(get_parent(), global_position + Vector3.UP * 1.4 + _aim_direction() * 0.6)
		for i in weapon.pellets:
			_fire_pellet(weapon)
	weapon_changed.emit(weapon)


func _aim_direction() -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	return _camera.project_ray_normal(center)


func _fire_pellet(weapon: Weapon) -> void:
	var muzzle := global_position + Vector3.UP * 1.4
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := _camera.project_ray_origin(center)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * weapon.spread
	var direction := (_aim_direction() + jitter).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * weapon.max_range, AIM_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		Fx.tracer(get_parent(), muzzle, origin + direction * weapon.max_range, weapon.tracer_color)
		return
	Fx.tracer(get_parent(), muzzle, hit["position"], weapon.tracer_color)
	var target := hit["collider"] as Node
	if not target is Enemy:
		Vfx.impact(get_parent(), hit["position"], hit["normal"])
	var friendly := target != null and (target.is_in_group("structures") \
		or (target is Enemy and (target as Enemy).faction == Enemy.Faction.ALLY))
	if target and not friendly and target.has_method("apply_damage"):
		# `from` is the shooter: riot shields and debris direction depend on it.
		target.call(&"apply_damage", weapon.damage, muzzle, &"bullet")
	if target is RigidBody3D:
		(target as RigidBody3D).apply_impulse(
			-(hit["normal"] as Vector3) * 2.0, (hit["position"] as Vector3) - (target as Node3D).global_position)


func _throw(weapon: Weapon) -> void:
	var thrown := Throwable.new()
	thrown.kind = weapon.throw_kind
	thrown.damage = weapon.damage
	get_parent().add_child(thrown)
	var direction := _aim_direction()
	thrown.global_position = global_position + Vector3.UP * 1.6 + direction * 0.6
	thrown.add_collision_exception_with(self)
	var lob := Vector3.ZERO if weapon.throw_kind == &"rocket" else Vector3.UP * 3.0
	thrown.linear_velocity = direction * weapon.throw_speed + lob
	thrown.angular_velocity = Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))


func _plant() -> void:
	if c4_charges <= 0:
		return
	var hit := _aim_in_reach()
	if hit.is_empty() or not (hit["collider"] is Destructible):
		return

	var c4 := Explosive.new()
	get_tree().current_scene.add_child(c4)
	var normal := hit["normal"] as Vector3
	c4.global_position = (hit["position"] as Vector3) + normal * 0.05
	if absf(normal.dot(Vector3.UP)) < 0.99:
		c4.look_at(c4.global_position + normal, Vector3.UP)
	c4.arm()

	c4_charges -= 1
	charges_changed.emit(c4_charges)


func _nearest_vehicle() -> Car:
	var best: Car = null
	var best_distance := enter_vehicle_range
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as Car
		if car == null:
			continue
		var distance := global_position.distance_to(car.global_position)
		if distance < best_distance:
			best = car
			best_distance = distance
	return best


func _try_enter_vehicle() -> void:
	var car := _nearest_vehicle()
	if car:
		car.enter(self)


func _update_prompt() -> void:
	if _reversed_left > 0.0:
		_set_prompt("ALGORITHM RE-EDUCATION: controls reversed (%ds)" % ceili(_reversed_left))
		return
	if _nearest_in_group("protesters", talk_range):
		_set_prompt("[E] Talk them down")
		return
	var damaged := repair_target()
	if damaged:
		_set_prompt("[F] Repair %s  (%d/%d)" % [damaged.label, ceili(damaged.health), int(damaged.max_health)])
		return
	var main := fixable_target()
	if main:
		_set_prompt("[F] Hold to fix the %s  (%d%%)" % [main.label(), roundi(main.progress * 100.0)])
		return
	if treats > 0 and _hostile_dog_in_reach():
		_set_prompt("[T] Give treat")
		return
	var nearby := _nearest_vehicle()
	if nearby:
		if nearby.can_enter():
			_set_prompt("[E] Drive")
		else:
			_set_prompt("Locked: the foreman wants more neighborhood trust (%d%% / %d%%)" % [
				roundi(Game.district.trust * 100.0), roundi(nearby.required_trust * 100.0)])
		return
	var stall := _nearest_vendor()
	if stall:
		_set_prompt(stall.offer_text(self))
		return
	var hit := _aim_in_reach()
	if not hit.is_empty() and hit["collider"] is Destructible:
		var target := hit["collider"] as Destructible
		if c4_charges > 0:
			_set_prompt("[G] Plant C4 on %s" % (target.label if target.label else "target"))
		else:
			_set_prompt("Out of C4")
		return
	_set_prompt("")


func _hostile_dog_in_reach() -> bool:
	for node in get_tree().get_nodes_in_group("hostiles"):
		if node is Dog and global_position.distance_to((node as Dog).global_position) < treat_range:
			return true
	return false


func _set_prompt(text: String) -> void:
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	health = max_health
	health_changed.emit(health, max_health)
