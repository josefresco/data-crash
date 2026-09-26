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
var _step_left := 0.0
## Held weapon model and the arm-raising modifier (see _update_held).
var _held: Node3D
var _held_model := &"__none"
var _held_scale := 1.0
var _aim_pose: AimModifier
## Seconds the aim pose stays up after the last shot.
var _aim_hold := 0.0
## Melee swing animation, 1 -> 0.
var _swing := 0.0

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
	_aim_pose = AimModifier.new()
	_aim_pose.influence = 0.0
	_rig.skeleton().add_child(_aim_pose)
	weapon_changed.connect(func(_w: Weapon) -> void: _refresh_held())
	Models.set_gi_mode(_body, GeometryInstance3D.GI_MODE_DYNAMIC)
	health = max_health
	_spawn = global_transform
	_spring.rotation.x = _pitch
	_spring.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Esc / P belong to the pause menu, which frees the mouse.
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_pivot.rotate_y(-motion.relative.x * Game.mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * Game.mouse_sensitivity, -1.2, 0.6)
		_spring.rotation.x = _pitch
	if not build_mode:
		if event.is_action_pressed("next_weapon"):
			select_weapon(weapon_index + 1)
		elif event.is_action_pressed("prev_weapon"):
			select_weapon(weapon_index - 1)


func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_aim_hold = maxf(_aim_hold - delta, 0.0)
	_move(delta)
	_footsteps(delta)

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
			var thing := nearest_interactable()
			if thing:
				thing.call(&"interact", self)
			else:
				_try_enter_vehicle()
	if Input.is_action_pressed("repair"):
		_repair(delta)
	_update_prompt()


func apply_damage(amount: float, _from: Vector3, _kind: StringName = &"generic") -> void:
	if amount >= 3.0:
		Sfx.play(&"hit_soft", global_position + Vector3.UP, -6.0)
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


## Befriends the nearest untamed dog (stray or guard dog) within reach.
## Returns true on success.
func give_treat() -> bool:
	if treats <= 0:
		return false
	var best := _untamed_dog_in_reach()
	if best == null or not best.befriend():
		return false
	treats -= 1
	Game.count("dogs")
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


## Nearest unfixed hold-[F] job (water mains, paint jobs) within its reach, or
## null. Duck-typed: `is_fixed`, `reach`, `progress`, `label()`, `work(delta)`.
func fixable_target() -> Node3D:
	for group in ["fixables", "paint_jobs"]:
		for node in get_tree().get_nodes_in_group(group):
			var job := node as Node3D
			if job and not job.get("is_fixed") and global_position.distance_to(job.global_position) <= float(job.get("reach")):
				return job
	return null


func _repair(delta: float) -> void:
	var structure := repair_target()
	if structure == null:
		var main := fixable_target()
		if main:
			main.call(&"work", delta)
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


## Nearest [E] interactable (gun show, security cache) in reach, or null.
## Members of group "interactables" implement in_reach(player),
## offer_text(player), and interact(player).
func nearest_interactable() -> Node3D:
	for node in get_tree().get_nodes_in_group("interactables"):
		if node.call(&"in_reach", self):
			return node as Node3D
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

	if _aim_hold > 0.0:
		# Aiming: square up to the camera.
		var aim := _aim_direction()
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-aim.x, -aim.z), 1.0 - exp(-20.0 * delta))
	elif direction.length_squared() > 0.01:
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


## Owns and fills every weapon. For tests and debugging.
func arm_all() -> void:
	for weapon in weapons:
		weapon.owned = true
		weapon.refill()
	weapon_changed.emit(current_weapon())


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
		if _fire_timer <= 0.0:
			_fire_timer = 0.4
			Sfx.play(&"click", global_position, -6.0)
			Game.tip("ammo", "Out of ammo for this weapon. Ammo refills when the defense starts and after every wave; Q switches weapons (fists, the shovel, and the pistol never run dry).")
		return
	_fire_timer = weapon.cooldown
	if weapon.kind == Weapon.Kind.MELEE:
		_melee(weapon)
		return
	Game.count("shots")
	if weapon.aims():
		_aim_hold = 1.2
	_place_held(true)
	Sfx.play(weapon.sound, muzzle_point(), -2.0)
	if weapon.ammo > 0:
		weapon.ammo -= 1
	if weapon.kind == Weapon.Kind.THROWN:
		_throw(weapon)
	else:
		Vfx.muzzle(get_parent(), muzzle_point())
		for i in weapon.pellets:
			_fire_pellet(weapon)
	weapon_changed.emit(weapon)


## Where shots and throws leave from: the held weapon's muzzle, else the hand.
func muzzle_point() -> Vector3:
	if _held:
		var marker := _held.get_node_or_null("Muzzle") as Node3D
		if marker:
			return marker.global_position
		return _held.global_position
	return global_position + Vector3.UP * 1.4 + _aim_direction() * 0.5


## The model currently in the player's hand (null for fists). Tests read it.
func held_model() -> Node3D:
	return _held


## Swings fists or a shovel: hits every hostile (and stray-free target) in a
## short arc in front, plus the first prop along the aim (Grock cameras, fences).
func _melee(weapon: Weapon) -> void:
	_swing = 1.0
	Sfx.play(&"throw", global_position + Vector3.UP * 1.2, -4.0, 0.8)
	var facing := _aim_direction()
	facing.y = 0.0
	facing = facing.normalized()
	_body.rotation.y = atan2(-facing.x, -facing.z)
	var chest := global_position + Vector3.UP * 1.2
	var landed := false
	for node in get_tree().get_nodes_in_group("hostiles"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive():
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > weapon.reach + 0.4 or (offset.length() > 0.3 and offset.normalized().dot(facing) < 0.35):
			continue
		enemy.apply_damage(weapon.damage, chest, &"melee")
		if weapon.knockback > 0.0:
			enemy.velocity += facing * weapon.knockback
		landed = true
	var query := PhysicsRayQueryParameters3D.create(chest, chest + facing * (weapon.reach + 0.3), 1 | 16, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var prop := hit["collider"] as Node
		if prop and not prop.is_in_group("structures") and prop.has_method("apply_damage"):
			prop.call(&"apply_damage", weapon.damage, chest, &"melee")
			landed = true
	if landed:
		Sfx.play(&"hit_metal" if weapon.model == &"shovel" else &"hit_flesh", chest + facing, -2.0)


func _refresh_held() -> void:
	var weapon := current_weapon()
	if weapon.model == _held_model:
		return
	_held_model = weapon.model
	if _held:
		_held.queue_free()
		_held = null
	_held = WeaponModels.build(weapon.model)
	if _held:
		_held_scale = _held.scale.x
		add_child(_held)
		_held.top_level = true
		_place_held(false)


## Aiming: the gun sits out in front of the right shoulder along the aim, and
## the arm modifier straightens the arm onto it. Otherwise it follows the hand,
## pointing forward and down. Melee swings sweep it through an overhead arc.
func _place_held(aiming_now: bool) -> void:
	if _held == null:
		return
	var weapon := current_weapon()
	var aim := _aim_direction()
	var right := _body.global_basis.x.normalized()
	var chest := _rig.anchor(&"chest").global_position
	if (aiming_now or _aim_hold > 0.0) and weapon.aims():
		var at := chest + Vector3.UP * 0.2 - right * 0.14 + aim * 0.5
		if weapon.model == &"rocket":
			at = chest + Vector3.UP * 0.38 - right * 0.18 + aim * 0.1
		_held.global_transform = Transform3D(Basis.looking_at(aim, Vector3.UP).scaled(Vector3.ONE * _held_scale), at)
		return
	var forward := -_body.global_basis.z.normalized()
	var pitch := -0.7
	if weapon.kind == Weapon.Kind.MELEE:
		pitch = lerpf(-0.9, 1.3, _swing) if _swing > 0.0 else -0.35
	var along := (forward * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var hand := _rig.anchor(&"hand_r").global_position
	_held.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP).scaled(Vector3.ONE * _held_scale), hand)


func _process(delta: float) -> void:
	if _swing > 0.0:
		_swing = maxf(_swing - delta / 0.3, 0.0)
	var weapon := current_weapon()
	var target := 1.0 if _aim_hold > 0.0 and weapon.aims() and vehicle == null else 0.0
	_aim_pose.influence = move_toward(_aim_pose.influence, target, delta * 8.0)
	_aim_pose.aim_direction = _aim_direction()
	_aim_pose.two_handed = weapon.two_handed
	_place_held(false)
	if _held:
		var grip := _held.get_node_or_null("Grip") as Node3D
		_aim_pose.grip_point = grip.global_position if grip else _held.global_position


func _aim_direction() -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	return _camera.project_ray_normal(center)


func _fire_pellet(weapon: Weapon) -> void:
	var muzzle := muzzle_point()
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
		if randf() < 0.35:
			Sfx.play(&"hit_metal", hit["position"], -10.0)
	elif randf() < 0.5:
		Sfx.play(&"hit_flesh", hit["position"], -8.0)
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
	var from := muzzle_point() + direction * 0.3
	if weapon.throw_kind != &"rocket":
		_swing = 1.0
		from = global_position + Vector3.UP * 1.6 + direction * 0.6
	thrown.global_position = from
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
	Sfx.play(&"beep", c4.global_position, -2.0)
	Game.tip("c4", "C4 is armed: get clear before it blows. Explosives break walls, turbines, cooling units, and bosses' glass.")

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
		_set_prompt("[F] Hold to %s the %s  (%d%%)" % ["help with" if main is PaintJob else "fix", main.call(&"label"),
			roundi(float(main.get("progress")) * 100.0)])
		return
	var dog := _untamed_dog_in_reach()
	if dog:
		if treats > 0:
			_set_prompt("[T] Give a treat: %s" % ("this stray will follow you and guard the block" if dog.stray else "turn this guard dog"))
		else:
			_set_prompt("Out of treats")
		return
	var nearby := _nearest_vehicle()
	if nearby:
		if nearby.can_enter():
			_set_prompt("[E] Drive")
		else:
			_set_prompt("Locked: the foreman wants more neighborhood trust (%d%% / %d%%)" % [
				roundi(Game.district.trust * 100.0), roundi(nearby.required_trust * 100.0)])
		return
	var thing := nearest_interactable()
	if thing:
		_set_prompt(thing.call(&"offer_text", self))
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


func _untamed_dog_in_reach() -> Dog:
	var best: Dog = null
	var best_distance := treat_range
	for group in ["hostiles", "strays"]:
		for node in get_tree().get_nodes_in_group(group):
			var dog := node as Dog
			if dog == null:
				continue
			var distance := global_position.distance_to(dog.global_position)
			if distance < best_distance:
				best = dog
				best_distance = distance
	return best


func _set_prompt(text: String) -> void:
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 1.0:
		_step_left = 0.1
		return
	_step_left -= delta
	if _step_left <= 0.0:
		_step_left = 1.7 / maxf(speed, 1.0)
		Sfx.play(&"step_grass", global_position, -14.0, 1.0, 0.1)


func _respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	health = max_health
	health_changed.emit(health, max_health)
