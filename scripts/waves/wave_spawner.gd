class_name WaveSpawner
extends Node3D
## Spawns hostile waves at child Marker3D points; they march on `objective`.
## A wave is cleared when every unit it spawned is dead or befriended.

signal wave_started(number: int, total: int)
signal wave_cleared(number: int, total: int)
signal all_waves_cleared

## Unit keys usable in `waves`. Static var, not const: class refs aren't constant expressions.
static var unit_types := {
	"guard": SecurityGuard,
	"dog": Dog,
	"police": Police,
	"frost": Frost,
	"orange_hat": OrangeHat,
	"felsa": FelsaCar,
	"sham": ShamCrapman,
	"fark": FarkPod,
	"harry": HarryPerckerson,
}

@export var spawn_interval := 1.2
## Seconds into a wave after which survivors charge the objective (no stalemates).
@export var rush_after := 75.0
## One entry per wave: unit key -> count (see unit_types).
@export var waves: Array[Dictionary] = [
	{"guard": 4, "dog": 3},
	{"guard": 5, "dog": 3, "orange_hat": 2, "sham": 1},
	{"guard": 7, "police": 4, "frost": 1, "orange_hat": 3, "felsa": 2},
	{"guard": 11, "police": 6, "dog": 4, "frost": 3, "orange_hat": 4, "felsa": 2, "fark": 1},
	{"guard": 12, "police": 8, "dog": 6, "frost": 4, "orange_hat": 5, "felsa": 2, "harry": 1},
]

var objective: Node3D
var current_wave := 0
var wave_active := false
var remaining := 0

var _queue: Array[GDScript] = []
var _spawn_timer := 0.0
var _wave_time := 0.0
var _spawned: Array[Enemy] = []


func total_waves() -> int:
	return waves.size()


func has_more_waves() -> bool:
	return current_wave < waves.size()


func start_next_wave() -> bool:
	if wave_active or not has_more_waves():
		return false
	current_wave += 1
	var wave := waves[current_wave - 1].duplicate()
	_apply_bribes(wave)
	_queue.clear()
	for key: String in wave:
		if not unit_types.has(key):
			push_warning("WaveSpawner: unknown unit type '%s'" % key)
			continue
		for i in int(wave[key]):
			_queue.append(unit_types[key])
	_queue.shuffle()
	remaining = _queue.size()
	_spawn_timer = 0.0
	_wave_time = 0.0
	_spawned.clear()
	wave_active = true
	wave_started.emit(current_wave, waves.size())
	return true


## Bribes bought from officials reshape the wave about to start.
func _apply_bribes(wave: Dictionary) -> void:
	if Game.consume_bribe("municipal_delay"):
		wave.erase("police")
		wave.erase("frost")
	if Game.consume_bribe("supply_blockade"):
		for key: String in wave.keys():
			wave[key] = int(floor(int(wave[key]) * 0.7))


func _physics_process(delta: float) -> void:
	if not wave_active:
		return
	_wave_time += delta
	if _wave_time >= rush_after:
		for enemy in _spawned:
			if is_instance_valid(enemy):
				enemy.rushing = true
	if _queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_spawn(_queue.pop_back())


func _spawn(kind: GDScript) -> void:
	# Markers with metadata "reserved" (BoardroomSite) are only used by units that name them.
	var points: Array[Node] = get_children().filter(func(child: Node) -> bool:
		return child is Marker3D and not child.get_meta(&"reserved", false))
	if points.is_empty():
		push_warning("WaveSpawner has no Marker3D spawn points")
		_on_unit_defeated(null)
		return
	var point := points.pick_random() as Marker3D
	# Some units (Harry's boardroom) insist on a named marker.
	var wanted: String = kind.get_script_constant_map().get("SPAWN_MARKER", "")
	if not wanted.is_empty() and has_node(wanted):
		point = get_node(wanted) as Marker3D
	var enemy := kind.new() as Enemy
	enemy.objective = objective
	# Set before add_child so _ready records the right home position.
	var jitter := Vector3.ZERO if not wanted.is_empty() else Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	enemy.position = point.global_position + jitter
	enemy.defeated.connect(_on_unit_defeated)
	get_parent().add_child(enemy)
	_spawned.append(enemy)


func _on_unit_defeated(_enemy: Enemy) -> void:
	remaining -= 1
	if remaining > 0 or not _queue.is_empty():
		return
	wave_active = false
	wave_cleared.emit(current_wave, waves.size())
	if not has_more_waves():
		all_waves_cleared.emit()
