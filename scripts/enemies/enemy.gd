class_name Enemy
extends CharacterBody3D
## Base for NPC combatants. Builds its own body, walks the navmesh, picks targets
## by faction, and calls _attack() when a target is in range and visible.
## Subclasses set stats in _init() and override _attack() / _decorate().

## Emitted when this unit dies.
signal died(enemy: Enemy)
## Emitted once when this unit stops counting as a hostile (death or conversion).
signal defeated(enemy: Enemy)

enum Faction { HOSTILE, ALLY }

## Line-of-sight blockers: world, player, destructibles, other units.
const LOS_MASK := 1 | 2 | 16 | 32
const THINK_INTERVAL := 0.25
## Ground speed (m/s) the Kenney run clip is authored for.
const RUN_CLIP_SPEED := 4.0
## AI level of detail: beyond this distance from the camera a unit thinks
## half as often and stops animating (bosses never go far).
const LOD_DISTANCE := 60.0
const LOD_CHECK := 0.5
## Damage let through while inside a projection drone's force field.
const FIELD_DAMAGE_FACTOR := 0.35
const ALLY_TINT := Color(0.3, 0.85, 0.4)
## Every group a unit can belong to via _faction_group().
const FACTION_GROUPS: Array[String] = ["hostiles", "allies", "protesters", "townspeople"]

@export var faction := Faction.HOSTILE
@export var max_health := 60.0
@export var move_speed := 4.0
@export var sight_range := 25.0
@export var attack_range := 16.0
@export var attack_interval := 0.7
@export var bounty := 25
## Max range for attacking structures. Shorter than attack_range so ranged
## units push into turret coverage instead of sniping from outside it.
@export var structure_engage_range := 9.0

## Hostiles with nothing to fight walk here (the green core in wave defense).
var objective: Node3D
## Idle units wander around this point. Defaults to the spawn position.
var home: Vector3
var health: float
var target: Node3D

## Set by the wave spawner when a wave drags on: charge the objective, ignore the rest.
var rushing := false
## How close counts as reaching a path corner. Vehicles need more slack.
var waypoint_reach := 0.8
## Non-empty for bosses: joins group "bosses" and gets the HUD boss bar.
var boss_name := ""

## Datacenter site this unit guards (&"" = none). Site security is passive
## (no targets) until that site's alarm goes off; hurting one raises it.
var site := &""
## Pitch of the gibberish voice played with speak() (0 = silent).
var voice_pitch := 0.0
## Kenney character skin (see CharacterModel / tools/generate_skins.py).
## Empty = procedural look (dogs, drones, turrets, pods).
var outfit := ""
var body_color := Color(0.2, 0.2, 0.25)
var skin_color := Models.random_skin()
var body_bulk := 1.0
var body_radius := 0.35
var body_height := 1.8

var _nav: NavigationAgent3D
var _visual: Node3D
var _material: StandardMaterial3D
var _attack_timer := 0.0
var _think_timer := 0.0
var _stun_timer := 0.0
var _wander_timer := 0.0
var _has_los := false
var _is_dead := false
var _defeated_emitted := false
var _rig: Node3D
var _speech_label: Label3D
## Sham Crapman's projection drones keep this topped up (seconds, game time).
var _field_left := 0.0
var _field_bubble: MeshInstance3D
var _walk_phase := randf() * TAU
var _stuck_time := 0.0
## True while far from the camera (see LOD_DISTANCE); re-checked every LOD_CHECK s.
var _lod_far := false
var _lod_left := randf() * LOD_CHECK
var _was_resting := false
## The blow that landed last (drives the flinch and the ragdoll push).
var _last_hit_from := Vector3.INF
var _last_hit_kind := &""
var _last_hit_amount := 0.0
var _flinch: FlinchModifier
var _gun: Node3D
## While > 0 a shove (vehicle bump, blast) carries the unit instead of its legs.
var _knock_left := 0.0
var _investigate_left := 0.0
var _sidestep_left := 0.0
var _sidestep := Vector3.ZERO
## Multiplies move_speed (formations hold back their fastest members).
var speed_scale := 1.0
## Stealth: 0..1 while quiet site security watches the player trespass (see
## _watch_for_player); full raises the site alarm.
var suspicion := 0.0
var _voiced_suspicion := false
var _site_node: Variant = null
## Seconds left soaked by a hose (moves at 60%).
var soaked_left := 0.0
## Seconds left marked by the player's recon drone (HUD shows it through walls).
var spotted_left := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	collision_layer = Game.LAYER_ENEMIES
	# Not vehicles: bodies collide if either side's mask matches, and a crowd
	# must never wedge a car. Vehicles shove units with a Bumper instead.
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_DESTRUCTIBLE | Game.LAYER_ENEMIES
	if faction == Faction.HOSTILE and boss_name.is_empty():
		max_health *= Game.enemy_health_scale()
	health = max_health
	home = global_position
	_build_body()

	_nav = NavigationAgent3D.new()
	_nav.radius = body_radius + 0.1
	_nav.path_desired_distance = waypoint_reach
	_nav.target_desired_distance = 1.0
	add_child(_nav)
	_nav.target_position = global_position

	set_faction(faction)
	if not boss_name.is_empty():
		add_to_group("bosses")
	_think_timer = randf() * THINK_INTERVAL  # spread thinking across frames


func set_faction(value: Faction) -> void:
	faction = value
	for group in FACTION_GROUPS:
		remove_from_group(group)
	var group := _faction_group()
	if not group.is_empty():
		add_to_group(group)
	if _material:
		_material.albedo_color = _base_color()


## A bullet at world `point` hit the head (characters only: at or above the
## neck bone). Headshots deal HEADSHOT_FACTOR.
const HEADSHOT_FACTOR := 2.5


func is_head_hit(point: Vector3) -> bool:
	if not _rig is CharacterModel:
		return false
	return point.y >= (_rig as CharacterModel).anchor(&"head").global_position.y - 0.03


## Point other units aim at.
func aim_point() -> Vector3:
	return global_position + Vector3.UP * body_height * 0.6


func is_alive() -> bool:
	return not _is_dead


func apply_damage(amount: float, from: Vector3, kind: StringName = &"generic") -> void:
	if _is_dead:
		return
	if is_dormant():
		get_tree().call_group(&"site_alarm", &"raise_alarm", site, label_for_alarm())
	amount = _modify_damage(amount, from, kind)
	if _field_left > 0.0:
		amount *= FIELD_DAMAGE_FACTOR
	if amount <= 0.0:
		return
	health -= amount
	_flash(Color(1.0, 0.3, 0.3))
	_last_hit_from = from
	_last_hit_kind = kind
	_last_hit_amount = amount
	if health <= 0.0:
		_die()
		return
	# Visible wounds (character models near the camera): up to 3.
	if amount >= 10.0 and kind in [&"bullet", &"melee", &"impact", &"explosive", &"bite"] \
			and _rig is CharacterModel and not _lod_far and (_rig as CharacterModel).wound_count() < 3:
		(_rig as CharacterModel).add_wound((from - global_position) if from != Vector3.ZERO else -_visual.global_basis.z)
	if _flinch and not _lod_far and from != Vector3.ZERO:
		_flinch.hit(global_position - from, clampf(amount / 30.0, 0.25, 1.0))
	if amount >= 15.0:
		_act(&"hit_head" if randf() < 0.3 else &"hit_chest")
	elif not _is_valid(target) and _nav:
		# Getting hit reveals roughly where the attacker is: go look.
		_nav.target_position = from


## Speech bubbles: at most MAX_TALKERS flavor lines at once, only within
## TALK_RANGE of the camera; the nearest win and bubbles that would overlap
## stack upward. Bosses always talk.
const MAX_TALKERS := 3
const TALK_RANGE := 35.0
const TALK_STACK := 0.6
static var _talkers: Array = []


## Leaving the tree: drop out of the static talker list (a static array
## still holding freed nodes at engine exit is a crash risk).
func _exit_tree() -> void:
	_talkers.erase(self)


## Speech bubble above the head (bosses taunt with this).
func speak(text: String, height := -1.0) -> void:
	var base_height := (body_height + 1.0) if height < 0.0 else height
	if text.is_empty():
		if _speech_label:
			_speech_label.text = ""
		_talkers.erase(self)
		return
	var boss := not boss_name.is_empty()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := camera.global_position if camera else global_position
	var distance := eye.distance_to(global_position)
	_talkers = _talkers.filter(func(t: Variant) -> bool:
		return is_instance_valid(t) and t != self and (t as Enemy)._speech_label != null \
			and not (t as Enemy)._speech_label.text.is_empty())
	if not boss:
		if distance > TALK_RANGE:
			return
		var others := _talkers.filter(func(t: Variant) -> bool: return (t as Enemy).boss_name.is_empty())
		if others.size() >= MAX_TALKERS:
			others.sort_custom(func(a: Variant, b: Variant) -> bool:
				return eye.distance_to((a as Node3D).global_position) > eye.distance_to((b as Node3D).global_position))
			var farthest := others[0] as Enemy
			if eye.distance_to(farthest.global_position) <= distance:
				return  # everyone talking is closer: this line goes unsaid
			farthest.speak("")
	_talkers.append(self)
	var stack := 0
	for t: Variant in _talkers:
		var other := t as Enemy
		if other == self or other._speech_label == null or other._speech_label.text.is_empty():
			continue
		var gap := other.global_position - global_position
		gap.y = 0.0
		if gap.length() < 3.0:
			stack += 1
	height = base_height + stack * TALK_STACK
	if _speech_label == null:
		_speech_label = Label3D.new()
		_speech_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_speech_label.pixel_size = 0.012
		_speech_label.font_size = 40
		_speech_label.outline_size = 10
		_speech_label.no_depth_test = true
		_speech_label.width = 560.0
		_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudOverlay.as_bubble(_speech_label, not boss_name.is_empty())
		add_child(_speech_label)
	_speech_label.position.y = height
	if text != _speech_label.text and not text.is_empty():
		_babble()
	_speech_label.text = text


## Robotic corporate gibberish in this unit's voice_pitch (bosses, reply guys).
func _babble() -> void:
	if voice_pitch > 0.0:
		Sfx.play(&"babble", aim_point(), -3.0 if not boss_name.is_empty() else -10.0, voice_pitch, 0.04)


## Protects this unit for `duration` seconds (see FIELD_DAMAGE_FACTOR).
func shield_field(duration: float) -> void:
	if _is_dead:
		return
	_field_left = maxf(_field_left, duration)
	if _field_bubble == null:
		var sphere := SphereMesh.new()
		sphere.radius = maxf(body_height, body_radius * 2.0) * 0.7
		sphere.height = sphere.radius * 2.0
		var bubble_mat := StandardMaterial3D.new()
		bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bubble_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.18)
		_field_bubble = MeshInstance3D.new()
		_field_bubble.mesh = sphere
		_field_bubble.material_override = bubble_mat
		_field_bubble.position.y = body_height * 0.5
		add_child(_field_bubble)
	_field_bubble.visible = true


func is_field_shielded() -> bool:
	return _field_left > 0.0


func _process(delta: float) -> void:
	# Game time, not wall time: fields must expire correctly when time scales.
	if _field_left > 0.0:
		_field_left -= delta
	if spotted_left > 0.0:
		spotted_left -= delta
	if soaked_left > 0.0:
		soaked_left -= delta
	if _field_bubble and _field_bubble.visible and not is_field_shielded():
		_field_bubble.visible = false


## Marked by the recon drone for `duration` seconds. True if it wasn't
## marked already.
func spot(duration: float) -> bool:
	var fresh := spotted_left <= 0.0
	spotted_left = maxf(spotted_left, duration)
	return fresh


## Walk over to check out a noise (thrown rocks). Ignored while fighting.
func investigate(point: Vector3) -> void:
	if _is_dead or _is_valid(target) or faction != Faction.HOSTILE:
		return
	_investigate_left = 5.0
	_nav.target_position = point


## Shoved by a vehicle or a blast: slides with `impulse` for a moment.
func apply_knockback(impulse: Vector3) -> void:
	if _is_dead:
		return
	velocity += impulse
	_knock_left = 0.35


## Knocked off its feet (a car bump, a hose blast): a stagger clip, down for
## `duration`, then back up. Reads clearly as "still alive".
func knock_down(duration: float) -> void:
	if _is_dead:
		return
	_stun_timer = maxf(_stun_timer, duration)
	_act(&"knockback", true)


## Hosed: slowed while soaked, and grumbles about it.
func soak(duration: float) -> void:
	if _is_dead:
		return
	if soaked_left <= 0.0 and randf() < 0.5 and outfit != "":
		speak(["Hey! My uniform!", "Cut it out!", "That's cold!", "Ugh, soaked!"].pick_random())
	soaked_left = maxf(soaked_left, duration)


func stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)
	_flash(Color(0.4, 0.7, 1.0))


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_lod_left -= delta
	if _lod_left <= 0.0:
		_lod_left = LOD_CHECK
		_update_lod()

	var move_dir := Vector3.ZERO
	if _stun_timer > 0.0:
		_stun_timer -= delta
	else:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer = THINK_INTERVAL * (2.0 if _lod_far else 1.0)
			_think()
			if _rig is CharacterModel and not _lod_far:
				(_rig as CharacterModel).set_upper(_upper_pose())
				(_rig as CharacterModel).set_stance(_stance())

		if _is_valid(target) and _has_los and _distance_to(target) <= _engage_range(target):
			_face(target.global_position, delta)
			if _attack_timer <= 0.0:
				_attack_timer = attack_interval
				_attack(target)
		else:
			move_dir = _unstick(_nav_direction(), delta)

	var weight := 1.0 - exp(-10.0 * delta)
	if _knock_left > 0.0:
		_knock_left -= delta
		weight *= 0.08
	var pace := move_speed * speed_scale * (0.6 if soaked_left > 0.0 else 1.0)
	velocity.x = lerpf(velocity.x, move_dir.x * pace, weight)
	velocity.z = lerpf(velocity.z, move_dir.z * pace, weight)
	if move_dir != Vector3.ZERO:
		var look: Variant = _look_while_moving()
		_face(look as Vector3 if look != null else global_position + move_dir, delta)
	# Standing still on the floor: skip the physics move and the animation
	# update (most site security and townsfolk idle most of the time).
	if is_resting(move_dir):
		velocity = Vector3.ZERO
		if not _was_resting:
			_was_resting = true
			_animate(delta)
		return
	_was_resting = false
	move_and_slide()
	_animate(delta)

	if global_position.y < -30.0:
		_die()


## True when this frame needs no physics move: on the floor, not steering,
## not shoved, and (nearly) stopped.
func is_resting(move_dir: Vector3) -> bool:
	return move_dir == Vector3.ZERO and _knock_left <= 0.0 and is_on_floor() \
		and Vector2(velocity.x, velocity.z).length_squared() < 0.0025


func is_far() -> bool:
	return _lod_far


func _update_lod() -> void:
	var camera := get_viewport().get_camera_3d()
	var far := boss_name.is_empty() and camera != null \
		and camera.global_position.distance_squared_to(global_position) > LOD_DISTANCE * LOD_DISTANCE
	_lod_far = far
	if _rig is CharacterModel:
		var model := _rig as CharacterModel
		model.set_animation_active(not far)
		if camera and not far and boss_name.is_empty():
			var distance := camera.global_position.distance_to(global_position)
			model.set_update_step(1 if distance < 25.0 else (2 if distance < 40.0 else 3))


## Puts a WeaponModels gun in the right hand, barrel along the forearm (the
## hand anchor's +X: forward in the aim poses), optionally tinted. Returns
## the model; its "Muzzle" marker is where shots leave (see muzzle_point()).
func _hold_weapon(model: StringName, tint := Color(0, 0, 0, 0), scale_by := 1.0) -> Node3D:
	var gun := WeaponModels.build(model)
	if gun == null:
		return null
	gun.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	gun.scale *= scale_by * body_height / 1.8
	gun.position = Vector3(0.05, -0.02, 0.0)
	if tint.a > 0.0:
		for mesh in gun.find_children("*", "MeshInstance3D", true, false):
			var material := StandardMaterial3D.new()
			material.albedo_color = tint
			material.roughness = 0.5
			(mesh as MeshInstance3D).material_override = material
	_anchor(&"hand_r").add_child(gun)
	_gun = gun
	return gun


## Where this unit's shots leave from: the held gun's muzzle, else the chest.
func muzzle_point() -> Vector3:
	if _gun and is_instance_valid(_gun):
		var marker := _gun.get_node_or_null("Muzzle") as Node3D
		if marker:
			return marker.global_position
	return global_position + Vector3.UP * body_height * 0.75


## Override: the clip held on the upper body right now (&"" = none), e.g.
## a raised shield or a phone. Checked on each think tick.
func _upper_pose() -> StringName:
	return &""


## Override: a world point to keep facing while walking (a shield toward
## the enemy); null faces the way it walks.
func _look_while_moving() -> Variant:
	return null


## Override: a full-body loop held in place of walking (&"" = none), e.g.
## crouching in cover. Checked on each think tick.
func _stance() -> StringName:
	return &""


## Plays a one-shot animation clip (see CharacterModel.play_action) on
## character models near the camera.
func _act(clip: StringName, full_body := false) -> void:
	if _rig is CharacterModel and not _lod_far and not _is_dead:
		(_rig as CharacterModel).play_action(clip, full_body)


## How hard the killing blow throws the body (N*s, for a ~70 kg ragdoll).
func _death_impulse() -> Vector3:
	var push := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if _last_hit_from != Vector3.INF and _last_hit_from != Vector3.ZERO:
		push = global_position - _last_hit_from
	push.y = 0.0
	push = push.normalized() if push.length_squared() > 0.0001 else Vector3.FORWARD
	match _last_hit_kind:
		&"explosive":
			return push * 320.0 + Vector3.UP * 260.0
		&"impact":
			return push * 380.0 + Vector3.UP * 140.0
		&"shockwave":
			return push * 300.0 + Vector3.UP * 200.0
		&"melee":
			return push * 150.0 + Vector3.UP * 40.0
		&"bullet":
			return push * clampf(_last_hit_amount * 5.0, 60.0, 260.0) + Vector3.UP * 20.0
	return push * 80.0


## Override: group this unit joins. Turrets and allied dogs only shoot "hostiles".
func _faction_group() -> String:
	return "hostiles" if faction == Faction.HOSTILE else "allies"


## Override: armor, shields. `from` is the attacker's position.
func _modify_damage(amount: float, _from: Vector3, _kind: StringName) -> float:
	return amount


## Override: extra consequences of dying (trust penalties, dropping captives).
func _on_death() -> void:
	pass


## The heat is off (the player was knocked out): forget the target and go
## back to post. Site units are dormant again once their alarm is cleared.
func stand_down() -> void:
	if _is_dead:
		return
	target = null
	rushing = false
	suspicion = 0.0
	_voiced_suspicion = false
	_investigate_left = 0.0
	_has_los = false
	if _nav:
		_nav.target_position = home


func is_defeated() -> bool:
	return _defeated_emitted


## Stuck failsafe: hop to the nearest navmesh point and head for `goal`.
func renavigate(goal: Variant) -> void:
	var map := get_world_3d().navigation_map
	var snapped := NavigationServer3D.map_get_closest_point(map, global_position)
	if snapped != Vector3.ZERO and snapped.distance_to(global_position) < 12.0:
		global_position = snapped + Vector3.UP * 0.1
	velocity = Vector3.ZERO
	if is_instance_valid(goal):
		objective = goal as Node3D
		_nav.target_position = objective.global_position


## Stuck failsafe, second strike: leaves the fight (counts as defeated).
func give_up() -> void:
	if _is_dead:
		return
	_emit_defeated()
	Vfx.dust(get_parent(), global_position)
	queue_free()


## Marks this unit as no longer part of the fight (wave bookkeeping). Idempotent.
func _emit_defeated() -> void:
	if not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit(self)


## Override: deal damage to `victim`.
func _attack(_victim: Node3D) -> void:
	pass


## Override: add extra meshes (helmets, snouts) under `visual`.
func _decorate(_visual_root: Node3D) -> void:
	pass


func _think() -> void:
	if is_dormant() and _watches():
		_watch_for_player(THINK_INTERVAL * (2.0 if _lod_far else 1.0))
	target = _pick_target()
	if _is_valid(target):
		_has_los = _can_see(target)
		_nav.target_position = target.global_position
		return
	_has_los = false
	if _investigate_left > 0.0:
		_investigate_left -= THINK_INTERVAL
		return
	_idle()


## Override: quiet site security that keeps an eye out for trespassers.
func _watches() -> bool:
	return false


## Override: how far this unit notices the player, and the cosine of its
## view cone's half-angle (-1 = all around, like a dog's nose).
func _view_range() -> float:
	return 18.0


func _view_cos() -> float:
	return 0.5


## Stealth. While quiet, a watcher that sees the player inside its site's
## compound (or aiming a weapon close by) grows suspicious, faster up close
## and scaled by Player.stealth_rate(); unseen, suspicion fades. Over 0.35 it
## comes to look; at 1 it raises the site alarm.
func _watch_for_player(step: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var rate := 0.0
	if player and (player.is_visible_in_tree() or player.vehicle):
		var body: Node3D = player.vehicle if player.vehicle else player
		var offset := body.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		var reach := _view_range() * player.stealth_visibility()
		if distance < reach:
			var facing := -_visual.global_basis.z
			facing.y = 0.0
			var in_view := distance < 2.0 or _view_cos() <= -0.99 \
				or facing.normalized().dot(offset.normalized()) >= _view_cos()
			if in_view and _can_see(body):
				var trespassing := _site_contains(body.global_position)
				if trespassing or (player.is_threatening() and distance < 12.0):
					rate = lerpf(1.0 / 1.2, 1.0 / 5.0, clampf(distance / reach, 0.0, 1.0)) * player.stealth_rate()
		if rate > 0.0:
			suspicion = minf(suspicion + rate * step, 1.0)
			if suspicion > 0.35:
				investigate(body.global_position)
				if not _voiced_suspicion:
					_voiced_suspicion = true
					speak(["Huh? Who's there?", "Hey... you're not staff.", "Did something move?"].pick_random())
				Game.tip("stealth", "Security noticed something (the ? over them). Inside a datacenter compound, guards and dogs that see you grow suspicious: crouch [C], stay behind them, and keep out of sight to sneak in.")
			if suspicion >= 1.0:
				speak("INTRUDER!")
				get_tree().call_group(&"site_alarm", &"raise_alarm", site, label_for_alarm(), label_for_alarm())
			return
	suspicion = maxf(suspicion - 0.12 * step, 0.0)
	if suspicion <= 0.0:
		_voiced_suspicion = false


func _site_contains(point: Vector3) -> bool:
	if _site_node == null or not is_instance_valid(_site_node):
		_site_node = null
		for node in get_tree().get_nodes_in_group("datacenter_sites"):
			if (node as DatacenterSite).site_id == site:
				_site_node = node
		if _site_node == null:
			return false
	return (_site_node as DatacenterSite).contains(point, 1.0)


## Override: what to do with no target. Allies tag along with the player,
## hostiles march on their objective, everyone else wanders near home.
func _idle() -> void:
	if faction == Faction.ALLY:
		_follow_player()
	elif _is_valid(objective):
		_nav.target_position = objective.global_position
	else:
		_wander()


func _animate(delta: float) -> void:
	if _rig == null:
		return
	var real := get_real_velocity()
	var speed := Vector2(real.x, real.z).length()
	if _rig is CharacterModel:
		(_rig as CharacterModel).set_motion(speed / RUN_CLIP_SPEED)
		return
	_walk_phase += speed * delta * 3.2
	Models.animate_walk(_rig, _walk_phase, clampf(speed / maxf(move_speed, 0.1), 0.0, 1.0))


## Units blocked by things the navmesh can't see (parked cars, crowds) sidestep.
func _unstick(move_dir: Vector3, delta: float) -> Vector3:
	if move_dir == Vector3.ZERO:
		_stuck_time = 0.0
		return move_dir
	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		return (move_dir * 0.3 + _sidestep).normalized()
	var real := get_real_velocity()
	if Vector2(real.x, real.z).length() < move_speed * 0.2:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.0:
		_stuck_time = 0.0
		_sidestep_left = randf_range(0.6, 1.2)
		_sidestep = move_dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	return move_dir


func _engage_range(other: Node3D) -> float:
	if other is Destructible:
		return minf(attack_range, structure_engage_range)
	return attack_range


## Site security whose site hasn't been attacked yet.
func is_dormant() -> bool:
	return site != &"" and not Game.is_alarmed(site)


## What the alarm message calls this unit.
func label_for_alarm() -> String:
	return boss_name if not boss_name.is_empty() else (get_script() as Script).get_global_name().capitalize()


func _pick_target() -> Node3D:
	if is_dormant():
		return null
	if rushing and faction == Faction.HOSTILE and _is_valid(objective):
		return objective
	var best: Node3D = null
	var best_distance := sight_range
	for candidate in _candidates():
		if not _is_valid(candidate):
			continue
		var distance := _distance_to(candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _candidates() -> Array[Node3D]:
	var list: Array[Node3D] = []
	if faction == Faction.HOSTILE:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player:
			list.append(player.vehicle if player.vehicle else player)
		for node in get_tree().get_nodes_in_group("allies"):
			list.append(node as Node3D)
		for node in get_tree().get_nodes_in_group("structures"):
			list.append(node as Node3D)
	else:
		# Allies leave quiet site security and neighborhood police alone.
		for node in get_tree().get_nodes_in_group("hostiles"):
			if not (node as Enemy).is_dormant():
				list.append(node as Node3D)
	return list


func _can_see(other: Node3D) -> bool:
	if other is VehicleBody3D:
		return true  # not on the LOS mask; bullets just bounce off anyway
	var from := global_position + Vector3.UP * body_height * 0.8
	var to := _aim_point_of(other)
	var query := PhysicsRayQueryParameters3D.create(from, to, LOS_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == other


func _follow_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.is_visible_in_tree() and global_position.distance_to(player.global_position) > 4.0:
		_nav.target_position = player.global_position
	else:
		_wander()


func _wander() -> void:
	_wander_timer -= THINK_INTERVAL
	if _wander_timer > 0.0 or not _nav.is_navigation_finished():
		return
	_wander_timer = randf_range(2.0, 5.0)
	var offset := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
	_nav.target_position = home + offset


func _nav_direction() -> Vector3:
	if _nav.is_navigation_finished():
		return Vector3.ZERO
	var step := _nav.get_next_path_position() - global_position
	step.y = 0.0
	return step.normalized() if step.length_squared() > 0.0025 else Vector3.ZERO


func _face(point: Vector3, delta: float) -> void:
	var direction := point - global_position
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	var yaw := atan2(-direction.x, -direction.z)
	# World yaw: units parented under a rotated DatacenterSite must still face
	# world-space directions.
	_visual.global_rotation.y = lerp_angle(_visual.global_rotation.y, yaw, 1.0 - exp(-12.0 * delta))


## Horizontal distance, or distance to the surface for big box targets.
func _distance_to(other: Node3D) -> float:
	if other is Destructible:
		return (other as Destructible).distance_to_point(global_position + Vector3.UP * 0.5)
	var offset := other.global_position - global_position
	return Vector2(offset.x, offset.z).length()


func _aim_point_of(other: Node3D) -> Vector3:
	if other is Enemy:
		return (other as Enemy).aim_point()
	if other is Destructible:
		var box := other as Destructible
		return box.global_position + Vector3.UP * minf(box.size.y * 0.5, 1.5)
	if other.has_method("aim_point"):
		return other.call(&"aim_point")  # the player's drone
	return other.global_position + Vector3.UP * 1.0


func _is_friend(other: Object) -> bool:
	if other is Enemy:
		return (other as Enemy).faction == faction
	# Allies never hurt the player or player-built structures.
	return faction == Faction.ALLY and (other is Player or (other is Node and (other as Node).is_in_group("structures")))


## `node` is untyped: targets may be freed between think ticks.
func _is_valid(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node as Node).is_inside_tree():
		return false
	if node is Enemy:
		return (node as Enemy).is_alive()
	if node is Destructible:
		return not (node as Destructible).is_destroyed
	return true


func _base_color() -> Color:
	if not outfit.is_empty():
		return Color.WHITE  # the skin texture carries the colors
	return body_color if faction == Faction.HOSTILE else body_color.lerp(ALLY_TINT, 0.6)


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = maxf(body_height, body_radius * 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)

	_visual = Node3D.new()
	add_child(_visual)
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color()
	Models.surface(_material, &"cloth")
	_rig = _build_visual()
	if _rig:
		_visual.add_child(_rig)
	if _rig is CharacterModel:
		_flinch = FlinchModifier.new()
		(_rig as CharacterModel).skeleton().add_child(_flinch)
		# The skinned model's own material takes over hit flashes and tints.
		_material = (_rig as CharacterModel).material
		_material.albedo_color = _base_color()
	_decorate(_visual)
	# Moving: lit by GI but not baked into it.
	Models.set_gi_mode(_visual, GeometryInstance3D.GI_MODE_DYNAMIC)


## Override: the model under _visual. `_material` is this unit's own shirt /
## fur material (tinted for allies, flashed on hits).
func _build_visual() -> Node3D:
	if not outfit.is_empty():
		return CharacterModel.create(outfit, body_height)
	return Models.humanoid(_material, body_color.darkened(0.55), skin_color, body_height, body_bulk)


## Where to hang gear: a bone-following anchor on character models
## (head, chest, hips, hand_r, hand_l), else the visual root.
func _anchor(anchor_name: StringName) -> Node3D:
	if _rig is CharacterModel:
		return (_rig as CharacterModel).anchor(anchor_name)
	return _visual


## Height of the top of the head above the head anchor (Kenney proportions).
func _head_top() -> float:
	return body_height * 0.27


func _add_box(parent: Node3D, box_size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = box_size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
	return mesh


func _solid(color: Color) -> StandardMaterial3D:
	return Models.mat(color, &"cloth")


func _flash(color: Color) -> void:
	if _material == null:
		return
	_material.albedo_color = color
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", _base_color(), 0.2)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if faction == Faction.HOSTILE and not _defeated_emitted:
		Game.add_cash(bounty)
		Game.count("kills")
	_emit_defeated()
	_on_death()
	for group in FACTION_GROUPS:
		remove_from_group(group)
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	died.emit(self)
	_play_death()


## Override: death animation. Must free the node when done. Character
## models near the camera go limp (Ragdoll); everything else tips over.
func _play_death() -> void:
	if _rig is CharacterModel and not _lod_far and is_inside_tree():
		if _flinch:
			_flinch.active = false
		var doll := Ragdoll.start(_rig as CharacterModel, get_parent(), _death_impulse(), aim_point(), velocity)
		if doll:
			doll.finished.connect(queue_free)
			tree_exiting.connect(doll.queue_free)
			return
	var tween := create_tween()
	tween.tween_property(_visual, "rotation:x", -PI * 0.5, 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.4)
	tween.tween_callback(queue_free)
