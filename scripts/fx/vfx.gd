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

static var _quads := {}
static var _scorches: Array[Decal] = []


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
static func impact(parent: Node, at: Vector3, normal := Vector3.UP) -> void:
	var sparks := _sparks(parent, at, 7, 5.0)
	(sparks.process_material as ParticleProcessMaterial).direction = normal
	(sparks.process_material as ParticleProcessMaterial).spread = 50.0
	var puff := _burst(parent, at, "smoke_01_alpha.png", false, 2, 0.6)
	var pm := puff.process_material as ParticleProcessMaterial
	pm.direction = normal
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.scale_min = 0.3
	pm.scale_max = 0.5
	pm.scale_curve = _curve([0.6, 1.2])
	pm.color_ramp = _ramp([Color(0.6, 0.58, 0.55, 0.7), Color(0.6, 0.58, 0.55, 0.0)])


## Muzzle flash: a camera-facing star and a blink of light.
static func muzzle(parent: Node, at: Vector3, color := Color(1.0, 0.85, 0.5)) -> void:
	if parent == null:
		return
	var flash := MeshInstance3D.new()
	flash.mesh = _quad("muzzle_02_alpha.png", true, false)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	flash.scale = Vector3.ONE * randf_range(0.5, 0.75)
	flash.rotation.z = randf() * TAU
	parent.add_child(flash)
	flash.global_position = at
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 4.0
	flash.add_child(light)
	var tween := flash.create_tween()
	tween.tween_interval(0.05)
	tween.tween_callback(flash.queue_free)


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
	_scorches.append(decal)
	_scorches = _scorches.filter(func(d: Variant) -> bool: return is_instance_valid(d))
	if _scorches.size() > MAX_SCORCHES:
		var oldest := _scorches.pop_front() as Decal
		oldest.queue_free()
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
