class_name Vfx
extends RefCounted
## GPU particle effects with Kenney Particle Pack textures (CC0). Static only.
## One-shot bursts free themselves; continuous emitters are returned so the
## caller can toggle `emitting` or free them.
##
## All textures are the *_alpha.png versions from tools/prepare_particles.py
## (white, alpha from brightness): fire, sparks, and muzzle flashes add light,
## smoke and dust are alpha-blended and lit.

const TEX := "res://assets/kenney/particles/"
## Scorch decals kept on the ground at once (oldest fade first).
const MAX_SCORCHES := 40
const MAX_BULLET_HOLES := 80
const MUZZLE_TEXTURES: Array[String] = ["muzzle_01_alpha.png", "muzzle_02_alpha.png", "muzzle_03_alpha.png",
	"muzzle_04_alpha.png", "muzzle_05_alpha.png"]

static var _quads := {}
## Capped decals, by instance id: static arrays holding node references
## crashed the engine at exit (the same as the old skid-mark list).
static var _scorches: Array[int] = []
static var _holes: Array[int] = []
static var _flame_mats := {}


## Fireball, rolling smoke, sparks, and a scorch mark. `radius` in meters.
static func explosion(parent: Node, at: Vector3, radius := 4.0) -> void:
	var r := clampf(radius / 4.0, 0.4, 2.5)
	var fire := _burst(parent, at, "fire_01_alpha.png", false, 22, 0.6, false)
	var pm := fire.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0 * r
	pm.initial_velocity_max = 7.0 * r
	pm.gravity = Vector3(0.0, 2.0, 0.0)
	pm.damping_min = 4.0
	pm.damping_max = 6.0
	pm.scale_min = 1.2 * r
	pm.scale_max = 2.6 * r
	pm.scale_curve = _curve([1.0, 1.3, 0.2])
	pm.color_ramp = _ramp([Color(1.6, 0.75, 0.2, 0.95), Color(1.2, 0.3, 0.05, 0.8), Color(0.25, 0.06, 0.02, 0.0)])

	var smoke := _burst(parent, at + Vector3.UP * 0.5, "smoke_04_alpha.png", false, 14, 3.2)
	pm = smoke.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0 * r
	pm.initial_velocity_max = 3.5 * r
	pm.gravity = Vector3(0.0, 1.2, 0.0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 1.6 * r
	pm.scale_max = 3.2 * r
	pm.scale_curve = _curve([0.4, 1.0, 1.4])
	pm.color_ramp = _ramp([Color(0.25, 0.22, 0.2, 0.0), Color(0.22, 0.2, 0.18, 0.85), Color(0.35, 0.33, 0.3, 0.0)])
	smoke.lifetime = 3.2
	(smoke.process_material as ParticleProcessMaterial).lifetime_randomness = 0.3

	_sparks(parent, at, 26, 10.0 * r)
	if parent.is_inside_tree():
		var ground := parent.get_viewport().find_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 4.0, 1)
		var hit := ground.intersect_ray(query)
		if not hit.is_empty():
			scorch(parent, hit["position"], radius * 0.7)


## Brown-gray dust cloud (buildings and walls breaking apart).
static func dust(parent: Node, at: Vector3, size := 2.0) -> void:
	var s := clampf(size / 2.0, 0.3, 3.0)
	var cloud := _burst(parent, at, "smoke_07_alpha.png", false, 10, 2.4)
	var pm := cloud.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.flatness = 0.5
	pm.initial_velocity_min = 0.8 * s
	pm.initial_velocity_max = 3.0 * s
	pm.gravity = Vector3(0.0, 0.3, 0.0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 1.2 * s
	pm.scale_max = 2.6 * s
	pm.scale_curve = _curve([0.5, 1.0, 1.3])
	pm.color_ramp = _ramp([Color(0.55, 0.5, 0.44, 0.0), Color(0.5, 0.46, 0.4, 0.7), Color(0.55, 0.52, 0.48, 0.0)])
	pm.lifetime_randomness = 0.3


## Bullet hit: a few sparks plus a puff of grit.
## Bullet impact, by surface: &"metal" (bright sparks and a flash), &"flesh"
## (a quick puff), &"dirt" (a dust plume and flung dirt), or &"default"
## (plaster dust and a few sparks). `normal` points out of the surface.
static func impact(parent: Node, at: Vector3, normal := Vector3.UP, kind := &"default", scale := 1.0) -> void:
	if parent == null:
		return
	match kind:
		&"metal":
			var sparks := _sparks(parent, at, int(14 * scale), 9.0)
			var pm := sparks.process_material as ParticleProcessMaterial
			pm.direction = normal
			pm.spread = 55.0
			pm.scale_min = 0.05
			pm.scale_max = 0.12
			sparks.lifetime = 0.45
			_flash(parent, at + normal * 0.05, 0.45 * scale, Color(2.2, 1.8, 1.1))
		&"flesh":
			var puff := _burst(parent, at, "smoke_01_alpha.png", false, 3, 0.35)
			var pm := puff.process_material as ParticleProcessMaterial
			pm.direction = normal
			pm.spread = 40.0
			pm.initial_velocity_min = 0.8
			pm.initial_velocity_max = 2.0
			pm.scale_min = 0.2
			pm.scale_max = 0.35
			pm.color_ramp = _ramp([Color(0.75, 0.35, 0.3, 0.8), Color(0.6, 0.3, 0.28, 0.0)])
			_flash(parent, at, 0.3 * scale, Color(1.6, 1.4, 1.3))
		&"dirt":
			var plume := _burst(parent, at, "smoke_07_alpha.png", false, 6, 1.1)
			var pm := plume.process_material as ParticleProcessMaterial
			pm.direction = normal + Vector3.UP
			pm.spread = 20.0
			pm.initial_velocity_min = 1.5
			pm.initial_velocity_max = 3.5
			pm.scale_min = 0.45 * scale
			pm.scale_max = 0.8 * scale
			pm.scale_curve = _curve([0.5, 1.4])
			pm.color_ramp = _ramp([Color(0.5, 0.42, 0.32, 0.8), Color(0.5, 0.42, 0.32, 0.0)])
			var clods := _burst(parent, at, "dirt_02_alpha.png", false, int(10 * scale), 0.8)
			var cm := clods.process_material as ParticleProcessMaterial
			cm.direction = normal + Vector3.UP * 0.5
			cm.spread = 35.0
			cm.initial_velocity_min = 2.0
			cm.initial_velocity_max = 4.5
			cm.gravity = Vector3(0.0, -12.0, 0.0)
			cm.scale_min = 0.07
			cm.scale_max = 0.14
			cm.color_ramp = _ramp([Color(0.35, 0.28, 0.2, 1.0), Color(0.35, 0.28, 0.2, 0.0)])
		_:
			var sparks := _sparks(parent, at, int(5 * scale), 5.0)
			(sparks.process_material as ParticleProcessMaterial).direction = normal
			(sparks.process_material as ParticleProcessMaterial).spread = 50.0
			var puff := _burst(parent, at, "smoke_01_alpha.png", false, 3, 0.7)
			var pm := puff.process_material as ParticleProcessMaterial
			pm.direction = normal
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.8
			pm.scale_min = 0.25
			pm.scale_max = 0.45
			pm.scale_curve = _curve([0.6, 1.3])
			pm.color_ramp = _ramp([Color(0.72, 0.7, 0.66, 0.75), Color(0.72, 0.7, 0.66, 0.0)])


## Dark pockmark decal on a surface (walls, cars, the ground). Parented to
## `host` so it goes when the prop breaks; the oldest fade past the cap.
static func bullet_hole(host: Node, at: Vector3, normal: Vector3) -> void:
	if host == null or not host.is_inside_tree():
		return
	var decal := Decal.new()
	decal.texture_albedo = load(TEX + "circle_05_alpha.png")
	decal.modulate = Color(0.05, 0.045, 0.04, 0.9)
	decal.size = Vector3(0.18, 0.3, 0.18) * randf_range(0.8, 1.2)
	decal.cull_mask = 1
	host.add_child(decal)
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	decal.global_transform = Transform3D(Basis(side, up, side.cross(up)), at)
	_holes.append(decal.get_instance_id())
	_holes = _live(_holes)
	if _holes.size() > MAX_BULLET_HOLES:
		(instance_from_id(_holes.pop_front()) as Decal).queue_free()
	var tween := decal.create_tween()
	tween.tween_interval(40.0)
	tween.tween_property(decal, "modulate:a", 0.0, 3.0)
	tween.tween_callback(decal.queue_free)


## A spent casing flipping out of the gun and bouncing to the ground.
## `side` is the ejection direction; `ground_y` where it lands.
static func shell_casing(parent: Node, at: Vector3, side: Vector3, ground_y: float, shotgun := false) -> void:
	if parent == null:
		return
	var casing := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.022 if not shotgun else 0.035
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.07 if not shotgun else 0.1
	mesh.radial_segments = 6
	mesh.rings = 1
	casing.mesh = mesh
	casing.material_override = Models.mat(Color(0.85, 0.65, 0.25) if not shotgun else Color(0.8, 0.15, 0.1), &"metal")
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(casing)
	casing.global_position = at
	var velocity := side.normalized() * randf_range(1.8, 2.8) + Vector3.UP * randf_range(2.0, 3.0)
	var spin := Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var flight := func(t: float) -> void:
		if not is_instance_valid(casing):
			return
		var p := at + velocity * t + Vector3.DOWN * 4.9 * t * t
		p.y = maxf(p.y, ground_y + 0.02)
		casing.global_position = p
		casing.rotation = spin * t
	var landing := (velocity.y + sqrt(velocity.y * velocity.y + 19.6 * maxf(at.y - ground_y, 0.0))) / 9.8
	var tween := casing.create_tween()
	tween.tween_method(flight, 0.0, landing, landing)
	tween.tween_callback(func() -> void:
		Sfx.play(&"casing", casing.global_position, -10.0, 1.0, 0.15))
	tween.tween_interval(3.0)
	tween.tween_callback(casing.queue_free)


## Additive, camera-facing flash (impacts and the muzzle's star).
static func _flash(parent: Node, at: Vector3, size: float, color: Color, lifetime := 0.06) -> void:
	var star := MeshInstance3D.new()
	star.mesh = _quad("star_06_alpha.png", true, false)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	star.scale = Vector3.ONE * size
	star.rotation.z = randf() * TAU
	parent.add_child(star)
	star.global_position = at
	var tween := star.create_tween()
	tween.tween_property(star, "scale", Vector3.ONE * size * 0.3, lifetime)
	tween.tween_callback(star.queue_free)
	if color != Color.WHITE:
		# A tinted blink of light for colored flashes (metal sparks).
		var light := OmniLight3D.new()
		light.light_color = Color(minf(color.r, 1.0), minf(color.g, 1.0), minf(color.b, 1.0))
		light.light_energy = 1.5
		light.omni_range = 2.5
		star.add_child(light)


## Muzzle flash along `direction`: two crossed flame quads (visible from any
## side), a bright star at the muzzle, a blink of light, and a smoke wisp.
## `size` scales it (pistol ~0.8, shotgun ~1.4). No direction = star only.
static func muzzle(parent: Node, at: Vector3, color := Color(1.0, 0.85, 0.5), direction := Vector3.ZERO, size := 1.0) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at
	if direction.length_squared() > 0.001:
		var up := Vector3.UP if absf(direction.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		root.look_at(at + direction, up)
		var length := 0.75 * size * randf_range(0.85, 1.2)
		var mat := _flame_material(MUZZLE_TEXTURES.pick_random())
		for k in 2:
			var spin := Node3D.new()
			spin.rotation.z = k * PI * 0.5 + randf_range(-0.3, 0.3)
			root.add_child(spin)
			var quad := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(0.38 * size, length)
			quad.mesh = mesh
			quad.material_override = mat
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			quad.rotation.x = -PI * 0.5  # the texture's "up" runs down the barrel (-Z)
			quad.position = Vector3(0.0, 0.0, -length * 0.5 + 0.05)
			spin.add_child(quad)
	_flash(parent, at, 0.5 * size, Color.WHITE, 0.05)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0 * size
	light.omni_range = 5.0 * size
	light.shadow_enabled = false
	root.add_child(light)
	var tween := root.create_tween()
	tween.tween_property(root, "scale", Vector3.ONE * 1.25, 0.045)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.06)
	tween.tween_callback(root.queue_free)
	# A thin wisp of smoke hangs at the muzzle.
	var wisp := _burst(parent, at, "smoke_01_alpha.png", false, 2, 0.9)
	var pm := wisp.process_material as ParticleProcessMaterial
	pm.direction = direction if direction != Vector3.ZERO else Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.scale_min = 0.18 * size
	pm.scale_max = 0.3 * size
	pm.scale_curve = _curve([0.5, 1.6])
	pm.color_ramp = _ramp([Color(0.8, 0.8, 0.8, 0.35), Color(0.8, 0.8, 0.8, 0.0)])


## Additive, unshaded, double-sided flame material for a muzzle texture (cached).
static func _flame_material(texture: String) -> StandardMaterial3D:
	if _flame_mats.has(texture):
		return _flame_mats[texture]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX + texture)
	mat.albedo_color = Color(2.0, 1.45, 0.7)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_mats[texture] = mat
	return mat


## Short burst of flame drifting along `direction` (flamethrowers).
static func fire_puff(parent: Node, at: Vector3, size := 0.6, direction := Vector3.UP) -> void:
	var fire := _burst(parent, at, "flame_03_alpha.png", false, 3, 0.45, false)
	var pm := fire.process_material as ParticleProcessMaterial
	pm.direction = direction
	pm.spread = 25.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0.0, 2.5, 0.0)
	pm.scale_min = size * 1.2
	pm.scale_max = size * 2.0
	pm.scale_curve = _curve([0.6, 1.2, 0.3])
	pm.color_ramp = _ramp([Color(1.5, 0.7, 0.18, 0.9), Color(1.1, 0.28, 0.05, 0.7), Color(0.25, 0.06, 0.02, 0.0)])


## Continuous smoke column (burning cars, fires, rocket trails). Attach to a
## node; set `emitting = false` to let it die out.
static func smoke_column(host: Node3D, offset := Vector3.ZERO, size := 1.0, dark := true) -> GPUParticles3D:
	var column := _emitter("smoke_07_alpha.png", false, 16, 2.8)
	column.one_shot = false
	column.explosiveness = 0.0
	var pm := column.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4 * size
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 1.5 * size
	pm.initial_velocity_max = 2.5 * size
	pm.gravity = Vector3(0.6, 0.8, 0.0)  # a little wind
	pm.scale_min = 0.8 * size
	pm.scale_max = 1.6 * size
	pm.scale_curve = _curve([0.5, 1.2, 2.0])
	var tone := 0.15 if dark else 0.7
	pm.color_ramp = _ramp([Color(tone, tone, tone, 0.0), Color(tone, tone, tone, 0.7), Color(tone + 0.1, tone + 0.1, tone + 0.1, 0.0)])
	host.add_child(column)
	column.position = offset
	return column


## Continuous fire over a disc of `radius` (fire zones, burning wrecks).
static func fire_patch(host: Node3D, offset := Vector3.ZERO, radius := 1.0) -> GPUParticles3D:
	var fire := _emitter("fire_02_alpha.png", false, int(12 + radius * 8.0), 0.7, false)
	fire.one_shot = false
	fire.explosiveness = 0.0
	var pm := fire.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.scale_curve = _curve([0.7, 1.0, 0.2])
	pm.color_ramp = _ramp([Color(1.5, 0.7, 0.18, 0.9), Color(1.1, 0.28, 0.05, 0.75), Color(0.25, 0.06, 0.02, 0.0)])
	host.add_child(fire)
	fire.position = offset
	return fire


## Continuous white steam jet (vents). Toggle `emitting`.
static func steam_jet(host: Node3D, offset := Vector3.ZERO, height := 4.0) -> GPUParticles3D:
	var jet := _emitter("smoke_04_alpha.png", false, 24, 1.1)
	jet.one_shot = false
	jet.explosiveness = 0.0
	jet.emitting = false
	var pm := jet.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = height * 0.9
	pm.initial_velocity_max = height * 1.4
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	pm.scale_curve = _curve([0.4, 1.3, 2.2])
	pm.color_ramp = _ramp([Color(1, 1, 1, 0.0), Color(0.95, 0.95, 0.95, 0.75), Color(1, 1, 1, 0.0)])
	host.add_child(jet)
	jet.position = offset
	return jet


## Continuous water spray (broken water main). Toggle `emitting`.
static func water_spray(host: Node3D, offset := Vector3.ZERO) -> GPUParticles3D:
	var spray := _emitter("circle_05_alpha.png", false, 60, 1.2)
	spray.one_shot = false
	spray.explosiveness = 0.0
	var pm := spray.process_material as ParticleProcessMaterial
	pm.direction = Vector3.UP
	pm.spread = 18.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 7.5
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.12
	pm.scale_max = 0.3
	pm.color_ramp = _ramp([Color(0.75, 0.88, 1.0, 0.9), Color(0.8, 0.9, 1.0, 0.0)])
	host.add_child(spray)
	spray.position = offset
	return spray


## Pressurized stream along the host's -Z (water cannons). Starts off: toggle
## `emitting`. Droplets arc under gravity and fade.
static func water_jet(host: Node3D, offset := Vector3.ZERO) -> GPUParticles3D:
	var jet := _emitter("circle_05_alpha.png", false, 380, 1.1, false)
	jet.one_shot = false
	jet.explosiveness = 0.0
	jet.emitting = false
	jet.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	var pm := jet.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 21.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.35
	pm.scale_max = 0.7
	pm.scale_curve = _curve([0.5, 1.0, 2.2])
	pm.color_ramp = _ramp([Color(0.92, 0.97, 1.0, 1.0), Color(0.82, 0.92, 1.0, 0.85), Color(0.9, 0.95, 1.0, 0.0)])
	host.add_child(jet)
	jet.position = offset
	return jet


## Burn mark on the ground that fades out after a while.
static func scorch(parent: Node, at: Vector3, radius := 2.0) -> void:
	var decal := Decal.new()
	decal.texture_albedo = load(TEX + ["scorch_01_alpha.png", "scorch_02_alpha.png", "scorch_03_alpha.png"].pick_random())
	decal.modulate = Color(0.05, 0.04, 0.03, 0.85)
	decal.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	decal.cull_mask = 1  # ground and props, not characters
	parent.add_child(decal)
	decal.global_position = at
	decal.rotation.y = randf() * TAU
	_scorches.append(decal.get_instance_id())
	_scorches = _live(_scorches)
	if _scorches.size() > MAX_SCORCHES:
		(instance_from_id(_scorches.pop_front()) as Decal).queue_free()
	var tween := decal.create_tween()
	tween.tween_interval(25.0)
	tween.tween_property(decal, "modulate:a", 0.0, 5.0)
	tween.tween_callback(decal.queue_free)


static func _sparks(parent: Node, at: Vector3, amount: int, speed: float) -> GPUParticles3D:
	var sparks := _burst(parent, at, "circle_05_alpha.png", true, amount, 0.7)
	var pm := sparks.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.08
	pm.scale_max = 0.2
	pm.color_ramp = _ramp([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.45, 0.1, 0.0)])
	return sparks


## One-shot emitter added to `parent` at `at`; frees itself when finished.
static func _burst(parent: Node, at: Vector3, texture: String, additive: bool, amount: int, lifetime: float,
		lit := not additive) -> GPUParticles3D:
	var particles := _emitter(texture, additive, amount, lifetime, lit)
	if parent == null:
		return particles
	parent.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


## `additive` = light-adding (sparks, muzzle); otherwise alpha-blended, `lit`
## (smoke, dust) or unshaded (fire: keeps its color against bright smog).
static func _emitter(texture: String, additive: bool, amount: int, lifetime: float,
		lit := not additive) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	particles.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 24, 24))
	var pm := ParticleProcessMaterial.new()
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.gravity = Vector3.ZERO
	particles.process_material = pm
	particles.draw_pass_1 = _quad(texture, additive, lit)
	return particles


## Camera-facing quad with vertex-colored texture, cached per look.
static func _quad(texture: String, additive: bool, lit: bool) -> QuadMesh:
	var key := "%s/%s/%s" % [texture, additive, lit]
	if _quads.has(key):
		return _quads[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX + texture)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.proximity_fade_enabled = true  # soft edges where smoke meets geometry
	mat.proximity_fade_distance = 0.6
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif not lit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.material = mat
	_quads[key] = quad
	return quad


static func _ramp(colors: Array[Color]) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	for i in colors.size():
		gradient.add_point(float(i) / maxf(colors.size() - 1, 1), colors[i])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _curve(values: Array[float]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = maxf(2.5, values.max())
	for i in values.size():
		curve.add_point(Vector2(float(i) / maxf(values.size() - 1, 1), values[i]))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## The ids in `ids` whose nodes still exist.
static func _live(ids: Array[int]) -> Array[int]:
	var alive: Array[int] = []
	for id in ids:
		if is_instance_id_valid(id):
			alive.append(id)
	return alive
