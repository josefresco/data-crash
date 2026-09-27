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

## Units arrive in squads from one entry point at a time: `squad_interval`
## seconds apart, 2 + wave number strong (at most `max_squad`). One at a
## time, turrets picked them off before they could ever threaten the core.
@export var squad_interval := 5.0
@export var max_squad := 6
## Seconds into a wave after which survivors charge the objective (no stalemates).
@export var rush_after := 60.0
## Seconds a targetless unit may stay within `STUCK_RADIUS` before it's
## nudged back onto the navmesh (first strike) or withdraws (second).
@export var stuck_seconds := 20.0
const STUCK_RADIUS := 1.5
const STUCK_CHECK := 2.0
## One entry per wave: unit key -> count (see unit_types).
@export var waves: Array[Dictionary] = [
	{"guard": 4, "dog": 3},
	{"guard": 6, "dog": 3, "orange_hat": 2},
	{"guard": 9, "police": 5, "frost": 2, "orange_hat": 3, "felsa": 3},
	{"guard": 13, "police": 7, "dog": 5, "frost": 3, "orange_hat": 4, "felsa": 3, "fark": 1},
	{"guard": 14, "police": 9, "dog": 7, "frost": 4, "orange_hat": 5, "felsa": 4, "harry": 1},
]

var objective: Node3D
var current_wave := 0
var wave_active := false
var remaining := 0

var _queue: Array[GDScript] = []
var _spawn_timer := 0.0
var _wave_time := 0.0
var _spawned: Array[Enemy] = []
## Stuck-unit failsafe: instance id -> [position at last check, seconds stuck, strikes].
var _stuck := {}
var _stuck_check_left := 0.0


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
		var count := int(wave[key])
		if key != "harry" and key != "fark":  # bosses stay one each
			count = maxi(roundi(count * Game.wave_size_scale()), 1 if count > 0 else 0)
		for i in count:
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
		_stuck_check_left -= delta
		if _stuck_check_left <= 0.0:
			_stuck_check_left = STUCK_CHECK
			_check_stuck()
	if _queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = squad_interval
		var entry := _entry_point()
		for i in mini(squad_size(), _queue.size()):
			_spawn(_queue.pop_back(), entry)


## How many units spawn together this wave.
func squad_size() -> int:
	return mini(2 + current_wave, max_squad)


## A random open entry point (markers with metadata "reserved", like Harry's
## BoardroomSite, are only used by units that name them).
func _entry_point() -> Marker3D:
	var points: Array[Node] = get_children().filter(func(child: Node) -> bool:
		return child is Marker3D and not child.get_meta(&"reserved", false))
	return points.pick_random() as Marker3D if not points.is_empty() else null


func _spawn(kind: GDScript, point: Marker3D = null) -> void:
	if point == null:
		point = _entry_point()
	if point == null:
		push_warning("WaveSpawner has no Marker3D spawn points")
		_on_unit_defeated(null)
		return
	# Some units (Harry's boardroom) insist on a named marker.
	var wanted: String = kind.get_script_constant_map().get("SPAWN_MARKER", "")
	if not wanted.is_empty() and has_node(wanted):
		point = get_node(wanted) as Marker3D
	var enemy := kind.new() as Enemy
	enemy.objective = objective
	# Set before add_child so _ready records the right home position.
	var jitter := Vector3.ZERO if not wanted.is_empty() else Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))
	enemy.position = point.global_position + jitter
	enemy.defeated.connect(_on_unit_defeated)
	get_parent().add_child(enemy)
	_spawned.append(enemy)


## "7 guards, 4 police, ..." for wave `number` (1-based), or "".
func describe_wave(number: int) -> String:
	if number < 1 or number > waves.size():
		return ""
	var parts: PackedStringArray = []
	var names := {"guard": "guards", "dog": "dogs", "police": "riot police", "frost": "FROST", "orange_hat": "protesters",
		"felsa": "Cyberdouches", "fark": "Fark's pod", "harry": "Harry Perckerson"}
	for key: String in waves[number - 1]:
		parts.append("%d %s" % [int(waves[number - 1][key]), names.get(key, key)])
	return ", ".join(parts)


func queue_empty() -> bool:
	return _queue.is_empty()


## The closest still-counted unit of this wave (null if none).
func nearest_remaining(from: Vector3) -> Variant:
	var best: Variant = null
	for enemy in _spawned:
		if is_instance_valid(enemy) and enemy.is_alive() and not enemy.is_defeated():
			if best == null or enemy.global_position.distance_to(from) < (best as Vector3).distance_to(from):
				best = enemy.global_position
	return best


## After the rush, a unit with no target that hasn't moved for stuck_seconds
## is snapped to the nearest navmesh point and re-sent at the objective; a
## second strike and it withdraws (counts as defeated) so the wave can end.
func _check_stuck() -> void:
	_spawned = _spawned.filter(func(e: Variant) -> bool: return is_instance_valid(e))
	for enemy in _spawned:
		if not enemy.is_alive() or enemy.is_defeated() or enemy.boss_name != "":
			continue
		var id := enemy.get_instance_id()
		var entry: Array = _stuck.get(id, [enemy.global_position, 0.0, 0])
		if enemy.global_position.distance_to(entry[0]) > STUCK_RADIUS or is_instance_valid(enemy.target):
			entry = [enemy.global_position, 0.0, entry[2]]
		else:
			entry[1] += STUCK_CHECK
		if entry[1] >= stuck_seconds:
			entry[1] = 0.0
			entry[2] += 1
			if entry[2] >= 2:
				enemy.give_up()
			else:
				enemy.renavigate(objective)
		_stuck[id] = entry


func _on_unit_defeated(_enemy: Enemy) -> void:
	remaining -= 1
	if remaining > 0 or not _queue.is_empty():
		return
	wave_active = false
	wave_cleared.emit(current_wave, waves.size())
	if not has_more_waves():
		all_waves_cleared.emit()
