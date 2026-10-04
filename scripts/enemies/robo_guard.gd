class_name RoboGuard
extends SecurityGuard
## The Felsa Optimizer T-800: an AI security robot, a chrome endoskeleton
## with glowing red eyes and a machine gun. Slow and relentless: bullets and
## melee only do half (plating), but water shorts it out (x3), an EMP drops
## it for 6 s with real damage, and explosives hit it full. It doesn't take
## cover. The first time it "dies" it keeps coming on its hands, legs gone
## (a crawler at half speed), and goes down for good the second time. Its
## site's power (DatacenterSite.power) sets how fast it moves.

const LINES := ["I'll be back. With a subpoena.", "Hasta la vista, neighbor.", "Your water. Give it to me.",
	"Terminating... your lease.", "Resistance is inefficient.", "Scanning for trespassers."]

var crawling := false
## Its datacenter (for power), found by `site`.
var _home: Variant = null

var _line_left := 3.0
var _eyes: Array[MeshInstance3D] = []


func _init() -> void:
	super()
	outfit = "guard"
	max_health = 260.0
	move_speed = 2.6
	sight_range = 30.0
	attack_range = 22.0
	attack_interval = 0.35
	shot_damage = 6.0
	close_accuracy = 0.85
	far_accuracy = 0.5
	uses_cover = false
	bounty = 60
	body_height = 1.95
	voice_pitch = 0.55


func _ready() -> void:
	super()
	add_to_group("robots")


## It's a machine: it keeps watch (stealth) even though it never hides.
func _watches() -> bool:
	return true


func _base_color() -> Color:
	return Color(0.72, 0.74, 0.78)


func label_for_alarm() -> String:
	return "T-800 security robot"


func _modify_damage(amount: float, from: Vector3, kind: StringName) -> float:
	var base := super(amount, from, kind)
	match kind:
		&"bullet", &"melee", &"impact", &"bite":
			return base * 0.5
		&"water":
			return base * 3.0
		&"emp":
			stun(6.0)
			return 60.0
	return base


func _process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0 and not is_dormant():
		_line_left = randf_range(6.0, 10.0)
		speak(LINES.pick_random())


## Site power and lost legs slow it, on top of `speed_scale`.
func _speed_factor() -> float:
	var power := 1.0
	if _home == null and not String(site).is_empty():
		for node in get_tree().get_nodes_in_group("datacenter_sites"):
			if (node as DatacenterSite).site_id == site:
				_home = node
	if _home and is_instance_valid(_home):
		power = (_home as DatacenterSite).power
	return power * (0.5 if crawling else 1.0)


## The first kill only takes its legs (unless it's blown apart).
func _die() -> void:
	# An overkill blow (a rocket, a big blast) scraps it on the spot.
	if not crawling and _last_hit_amount < max_health * 1.5:
		crawling = true
		health = max_health * 0.35
		speak("...I'll be back.")
		Vfx.impact(get_parent(), global_position + Vector3.UP, Vector3.UP, &"metal", 2.0)
		Sfx.play(&"hit_metal", global_position, 0.0, 0.6)
		var model := _rig as Node3D
		if model:
			var tween := create_tween()
			tween.tween_property(model, "position:y", -body_height * 0.45, 0.4)
			tween.parallel().tween_property(model, "rotation:x", -1.2, 0.4)
		return
	Explosive.spawn_flash(get_parent(), global_position + Vector3.UP * 0.5, 1.2)
	super()


func _upper_pose() -> StringName:
	return &"pistol_aim" if _is_valid(target) and _has_los else &"pistol_idle"


func _decorate(_visual_root: Node3D) -> void:
	# Chrome plating: no skin texture, polished metal.
	var model := _rig as CharacterModel
	if model and model.material:
		model.material.albedo_texture = null
		model.material.albedo_color = _base_color()
		model.material.metallic = 1.0
		model.material.roughness = 0.22
	var steel := _solid(Color(0.55, 0.57, 0.6))
	steel.metallic = 1.0
	steel.roughness = 0.3
	var head := _anchor(&"head")
	var top := _head_top()
	# A skull: brow ridge, cheek plates, a grille of teeth, and two red eyes.
	_add_box(head, Vector3(0.24, 0.05, 0.08), Vector3(0.0, top - 0.1, -0.1), steel)
	for side: float in [-1.0, 1.0]:
		_add_box(head, Vector3(0.05, 0.1, 0.06), Vector3(side * 0.09, top - 0.22, -0.1), steel)
		var eye := _add_box(head, Vector3(0.05, 0.03, 0.02), Vector3(side * 0.055, top - 0.14, -0.14), Models.glow(Color(1.0, 0.05, 0.05), 5.0))
		_eyes.append(eye)
	for k in 5:
		_add_box(head, Vector3(0.022, 0.04, 0.02), Vector3(-0.05 + k * 0.025, top - 0.27, -0.13), Models.mat(Color(0.9, 0.9, 0.88), &"metal"))
	# Exposed spine and piston arms.
	_add_box(_anchor(&"chest"), Vector3(0.08, 0.5, 0.06), Vector3(0.0, -0.05, 0.12), steel)
	_hold_weapon(&"mg", Color(0.15, 0.15, 0.17), 1.1)
	var eye_light := OmniLight3D.new()
	eye_light.light_color = Color(1.0, 0.1, 0.05)
	eye_light.light_energy = 0.6
	eye_light.omni_range = 1.5
	eye_light.shadow_enabled = false
	eye_light.position = Vector3(0.0, top - 0.14, -0.2)
	head.add_child(eye_light)
