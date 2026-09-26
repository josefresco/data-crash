class_name HarryPerckerson
extends Enemy
## Boss (wave 5 finale): Harry Perckerson, Venture Capital Heavyweight. Sits
## behind reinforced boardroom glass that shrugs off anything weaker than
## heavy explosives (rockets, grenades, C4, the bulldozer), throwing "Capital
## Subsidies" that summon Private Security and FROST. Untouchable until the
## glass breaks. Spawns at the WaveSpawner's "BoardroomSite" marker.

const SPAWN_MARKER := "BoardroomSite"
const LINES := [
	"Every problem is a funding opportunity.",
	"Let's circle back to your eviction.",
	"I don't lose money. I redistribute it upward.",
	"Security, please. Series B security.",
]

@export var subsidy_interval := 10.0
@export var guards_per_subsidy := 2
## Every Nth subsidy also funds a FROST agent.
@export var frost_every := 3
@export var glass_health := 900.0
## Hits below this bounce off the boardroom glass.
@export var glass_threshold := 100.0

var boardroom: Destructible
var summoned: Array[Enemy] = []

var _subsidy_left := 4.0
var _subsidies := 0
var _line_left := 0.0


func _init() -> void:
	voice_pitch = 0.7
	outfit = "harry"
	max_health = 400.0
	move_speed = 0.0
	sight_range = 0.0
	attack_range = 0.0
	bounty = 1000
	body_color = Color(0.12, 0.15, 0.3)
	body_bulk = 1.3
	boss_name = "HARRY PERCKERSON"


func _ready() -> void:
	super()
	boardroom = Destructible.new()
	boardroom.size = Vector3(7.0, 3.6, 7.0)
	boardroom.color = Color(0.55, 0.7, 0.85)
	boardroom.opacity = 0.35
	boardroom.max_health = glass_health
	boardroom.damage_threshold = glass_threshold
	boardroom.chunks = Vector3i(3, 2, 3)
	boardroom.label = "Boardroom glass"
	add_child(boardroom)
	add_collision_exception_with(boardroom)
	# The glass appears mid-wave: route everyone around it.
	get_tree().call_group(&"nav_baker", &"request_rebake")
	boardroom.destroyed.connect(func(_d: Destructible) -> void:
		speak("My glass! Do you know what that cost? Nothing, I expensed it."))
	# Furniture: a long table and a chair.
	Models.box(self, Vector3(3.5, 0.1, 1.4), Vector3(0.0, 0.85, -1.5), Models.mat(Color(0.3, 0.2, 0.12)))
	Models.box(self, Vector3(0.7, 1.2, 0.7), Vector3(0.0, 0.6, 0.4), Models.mat(Color(0.1, 0.1, 0.1)))
	speak(LINES[0], 4.5)


func is_exposed() -> bool:
	return boardroom == null or not is_instance_valid(boardroom) or boardroom.is_destroyed


func _modify_damage(amount: float, _from: Vector3, _kind: StringName) -> float:
	return amount if is_exposed() else 0.0


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = 9.0
		speak(LINES.pick_random(), 4.5)
	_subsidy_left -= delta
	if _subsidy_left <= 0.0:
		# Exposed and panicking: the checks come faster.
		_subsidy_left = subsidy_interval * (0.6 if is_exposed() else 1.0)
		_capital_subsidy()


func _capital_subsidy() -> void:
	_subsidies += 1
	summoned = summoned.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).is_alive())
	var kinds: Array[GDScript] = []
	for i in guards_per_subsidy:
		kinds.append(SecurityGuard)
	if _subsidies % frost_every == 0:
		kinds.append(Frost)
	for i in kinds.size():
		var unit := kinds[i].new() as Enemy
		unit.objective = objective
		unit.position = global_position + Vector3(-3.0 + i * 3.0, 0.1, -6.0)
		get_parent().add_child(unit)
		summoned.append(unit)
		# Money bag arcing over to where the hire appears.
		var bag := Models.box(get_parent() as Node3D, Vector3(0.35, 0.35, 0.35),
			global_position + Vector3.UP * 2.0, Models.mat(Color(0.3, 0.6, 0.25)))
		var tween := bag.create_tween()
		tween.tween_property(bag, "global_position", unit.position + Vector3.UP * 0.3, 0.6)
		tween.tween_callback(bag.queue_free)
	speak("Capital subsidy! %d new hires." % kinds.size(), 4.5)


func _on_death() -> void:
	speak("I'm stepping back to spend more time with my yacht.", 4.5)


func _decorate(_visual_root: Node3D) -> void:
	# Fleece vest over the suit, and a gold watch.
	_add_box(_anchor(&"chest"), Vector3(0.54, 0.46, 0.38), Vector3(0.0, -0.05, 0.0), Models.mat(Color(0.35, 0.37, 0.4), &"cloth"))
	_add_box(_anchor(&"hand_l"), Vector3(0.12, 0.06, 0.12), Vector3(0.0, 0.1, 0.0), Models.mat(Color(0.95, 0.8, 0.2), &"metal"))
