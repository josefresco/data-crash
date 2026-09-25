class_name FarkPod
extends Enemy
## Boss (wave 4): Fark Suckerbush, Surveillance King, in a hovering glass
## command pod. Summons holographic clones, sends surveillance drones after
## the player (tracked = he hits harder from farther), and periodically
## "re-educates" the player: controls reverse for a few seconds.
## The glass halves bullet damage; explosives and fire go through.

const LINES := [
	"I just want to connect you. With my ads.",
	"Your data looks delicious today.",
	"Privacy is a legacy feature.",
	"We're building community. Your community. For us.",
]

@export var clone_interval := 12.0
@export var clone_count := 3
@export var drone_count := 2
@export var reeducation_interval := 20.0
@export var reeducation_charge := 2.0
@export var reeducation_duration := 5.0
@export var reeducation_range := 30.0
@export var glass_armor := 0.5
@export var beam_damage := 14.0
@export var tracked_beam_damage := 28.0
@export var tracked_range := 40.0

var drones: Array[SurveillanceDrone] = []
var clones: Array[HoloClone] = []

var _clone_left := 6.0
var _reeducate_left := 10.0
var _charge_left := 0.0
var _line_left := 0.0


func _init() -> void:
	max_health = 1100.0
	move_speed = 2.5
	sight_range = 30.0
	attack_range = 18.0
	structure_engage_range = 14.0
	attack_interval = 1.5
	bounty = 500
	body_color = Color(0.3, 0.35, 0.6)
	# Collider stays agent-sized so the pod fits navmesh corners; the glass
	# sphere is visual only.
	body_radius = 0.6
	body_height = 2.4
	boss_name = "FARK SUCKERBUSH"


func _ready() -> void:
	super()
	speak(LINES[0], 4.0)
	_deploy_drones.call_deferred()


func is_tracking() -> bool:
	return drones.any(func(d: Variant) -> bool:
		return is_instance_valid(d) and (d as SurveillanceDrone).is_alive() and (d as SurveillanceDrone).sees_player)


func _deploy_drones() -> void:
	for i in drone_count:
		var drone := SurveillanceDrone.new()
		drone.owner_unit = self
		drone.position = global_position + Vector3(0.0, 5.0, 0.0)
		drone.set("_angle", PI * i)
		get_parent().add_child(drone)
		drones.append(drone)


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0 and _charge_left <= 0.0:
		_line_left = 8.0
		speak(LINES.pick_random(), 4.0)

	_clone_left -= delta
	if _clone_left <= 0.0:
		_clone_left = clone_interval
		_summon_clones()

	var player := get_tree().get_first_node_in_group("player") as Player
	if _charge_left > 0.0:
		_charge_left -= delta
		speak("ALGORITHM RE-EDUCATION in %d..." % ceili(_charge_left), 4.0)
		if _charge_left <= 0.0 and player and player.is_visible_in_tree() \
				and player.global_position.distance_to(global_position) <= reeducation_range:
			player.apply_control_reversal(reeducation_duration)
			Explosive.spawn_flash(get_parent(), player.global_position + Vector3.UP, 1.5, Color(0.7, 0.4, 1.0))
			speak("Feed recalibrated. You're welcome.", 4.0)
		return
	_reeducate_left -= delta
	if _reeducate_left <= 0.0 and player and player.is_visible_in_tree() \
			and player.global_position.distance_to(global_position) <= reeducation_range:
		_reeducate_left = reeducation_interval
		_charge_left = reeducation_charge


func _summon_clones() -> void:
	clones = clones.filter(func(c: Variant) -> bool: return is_instance_valid(c))
	for i in clone_count:
		var clone := HoloClone.new()
		clone.objective = objective
		var angle := TAU * i / clone_count
		clone.position = global_position + Vector3(cos(angle) * 3.0, 0.1, sin(angle) * 3.0)
		get_parent().add_child(clone)
		clones.append(clone)
	speak("Meet my friends. All 3 billion of them.", 4.0)


func _engage_range(other: Node3D) -> float:
	if other is Player and is_tracking():
		return tracked_range
	return super(other)


func _pick_target() -> Node3D:
	# Tracked players are visible from anywhere the drones can see them.
	if is_tracking():
		var player := get_tree().get_first_node_in_group("player") as Player
		if player and player.is_visible_in_tree() and global_position.distance_to(player.global_position) <= tracked_range:
			return player
	return super()


func _can_see(other: Node3D) -> bool:
	return (other is Player and is_tracking()) or super(other)


func _modify_damage(amount: float, _from: Vector3, kind: StringName) -> float:
	return amount * glass_armor if kind == &"bullet" else amount


func _attack(victim: Node3D) -> void:
	if _is_friend(victim):
		return
	var from := global_position + Vector3.UP * 2.2
	var damage := tracked_beam_damage if victim is Player and is_tracking() else beam_damage
	if victim.has_method("apply_damage"):
		victim.call(&"apply_damage", damage, from, &"energy")
	Fx.tracer(get_parent(), from, _aim_point_of(victim), Color(0.7, 0.4, 1.0), 0.1, 0.15)


func _on_death() -> void:
	speak("Logging off. For now.", 4.0)
	for clone in clones:
		if is_instance_valid(clone) and clone.is_alive():
			clone.apply_damage(9999.0, global_position)


## Glass pod hovering over a base, with Fark at the controls inside.
func _build_visual() -> Node3D:
	var rig := Node3D.new()
	Models.cylinder(rig, 1.2, 0.4, Vector3(0.0, 0.5, 0.0), _material, 12)
	var thruster := StandardMaterial3D.new()
	thruster.albedo_color = Color(0.5, 0.7, 1.0)
	thruster.emission_enabled = true
	thruster.emission = Color(0.4, 0.6, 1.0)
	thruster.emission_energy_multiplier = 2.0
	Models.cylinder(rig, 0.8, 0.1, Vector3(0.0, 0.25, 0.0), thruster, 12)
	var fark := Models.humanoid(Models.mat(Color(0.55, 0.55, 0.6)), Color(0.25, 0.3, 0.45), Models.random_skin(), 1.3)
	fark.position.y = 0.7
	rig.add_child(fark)
	Models.ball(rig, 1.25, Vector3(0.0, 1.55, 0.0), Models.glass(Color(0.6, 0.85, 1.0, 0.25)))
	return rig
