class_name WaveSpawner
extends Node3D
## Spawns hostile waves at child Marker3D points; they march on `objective`.
## A wave is cleared when every unit it spawned is dead or befriended.

signal wave_started(number: int, total: int)
signal wave_cleared(number: int, total: int)
signal all_waves_cleared

@export var spawn_interval := 1.2
## One entry per wave: x = security guards, y = dogs.
@export var waves: Array[Vector2i] = [
	Vector2i(3, 1), Vector2i(5, 2), Vector2i(6, 3), Vector2i(8, 3), Vector2i(10, 4),
]

var objective: Node3D
var current_wave := 0
var wave_active := false
var remaining := 0

var _queue: Array[GDScript] = []
var _spawn_timer := 0.0


func total_waves() -> int:
	return waves.size()


func has_more_waves() -> bool:
	return current_wave < waves.size()


func start_next_wave() -> bool:
	if wave_active or not has_more_waves():
		return false
	current_wave += 1
	var wave := waves[current_wave - 1]
	_queue.clear()
	for i in wave.x:
		_queue.append(SecurityGuard)
	for i in wave.y:
		_queue.append(Dog)
	_queue.shuffle()
	remaining = _queue.size()
	_spawn_timer = 0.0
	wave_active = true
	wave_started.emit(current_wave, waves.size())
	return true


func _physics_process(delta: float) -> void:
	if not wave_active or _queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_spawn(_queue.pop_back())


func _spawn(kind: GDScript) -> void:
	var points: Array[Node] = get_children().filter(func(child: Node) -> bool: return child is Marker3D)
	if points.is_empty():
		push_warning("WaveSpawner has no Marker3D spawn points")
		_on_unit_defeated(null)
		return
	var point := points.pick_random() as Marker3D
	var enemy := kind.new() as Enemy
	enemy.objective = objective
	# Set before add_child so _ready records the right home position.
	enemy.position = point.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	enemy.defeated.connect(_on_unit_defeated)
	get_parent().add_child(enemy)


func _on_unit_defeated(_enemy: Enemy) -> void:
	remaining -= 1
	if remaining > 0 or not _queue.is_empty():
		return
	wave_active = false
	wave_cleared.emit(current_wave, waves.size())
	if not has_more_waves():
		all_waves_cleared.emit()
