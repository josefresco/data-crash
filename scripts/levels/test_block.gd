extends Node3D
## Vertical-slice test level.
## Phase 2 (ASSAULT): ram the fence, blow the cooling units, watch the sky clear.
## Phase 3 (BUILD / WAVE): defend the new green datacenter against waves.

enum Phase { ASSAULT, BUILD, WAVE, WON, LOST }

## Seconds between the collapse and the green core going up (lets debris settle).
@export var core_delay := 3.0
## Seconds of build time before the next wave starts on its own.
@export var auto_wave_delay := 45.0

var phase := Phase.ASSAULT
var core: GreenCore

var _fence_breached := false
var _auto_wave_left := -1.0

@onready var _datacenter: Datacenter = $Datacenter
@onready var _env_driver: EnvironmentDriver = $EnvironmentDriver
@onready var _spawner: WaveSpawner = $WaveSpawner
@onready var _build: BuildController = $BuildController


func _ready() -> void:
	Game.reset()

	_env_driver.world_environment = $WorldEnvironment
	_env_driver.sun = $Sun
	_env_driver.ground = $Ground/Mesh

	for child in get_children():
		if child is FenceLine:
			(child as FenceLine).breached.connect(_on_fence_breached)
	_datacenter.cooling_unit_destroyed.connect(_on_cooling_unit_destroyed)
	_datacenter.neutralized.connect(_on_neutralized)
	_spawner.wave_started.connect(_on_wave_started)
	_spawner.wave_cleared.connect(_on_wave_cleared)
	_spawner.all_waves_cleared.connect(_on_all_waves_cleared)

	Game.set_objective("Get in the car [E] and ram through the fence. Guard dogs? Try a treat [T].")


func _process(delta: float) -> void:
	if phase != Phase.BUILD or _auto_wave_left < 0.0:
		return
	_auto_wave_left -= delta
	Game.set_info("wave", "Wave %d/%d arrives in %ds  ([N] to start now)"
		% [_spawner.current_wave + 1, _spawner.total_waves(), ceili(_auto_wave_left)])
	if _auto_wave_left <= 0.0:
		start_next_wave()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.BUILD and event.is_action_pressed("start_wave"):
		start_next_wave()
	elif phase == Phase.LOST and event.is_action_pressed("retry"):
		get_tree().reload_current_scene()


## Skips straight to Phase 3. Used by tests and handy for debugging.
func start_defense() -> void:
	if phase != Phase.ASSAULT:
		return
	phase = Phase.BUILD
	core = GreenCore.new()
	core.position = Vector3(_datacenter.global_position.x, 0.0, _datacenter.global_position.z)
	add_child(core)
	core.damaged.connect(_on_core_damaged)
	core.destroyed.connect(_on_core_destroyed)
	_on_core_damaged(0.0, core.health)

	_spawner.objective = core
	_build.center = core.global_position
	_build.enabled = true
	_build.set_active(false)
	get_tree().call_group(&"nav_baker", &"request_rebake")

	_auto_wave_left = auto_wave_delay
	Game.set_objective("Defend the green datacenter. Build defenses, then hold off %d waves."
		% _spawner.total_waves())


func start_next_wave() -> void:
	if phase == Phase.BUILD:
		_spawner.start_next_wave()


func _on_fence_breached() -> void:
	if _fence_breached or phase != Phase.ASSAULT:
		return
	_fence_breached = true
	Game.set_objective("Fence down. Plant C4 [G] on the %d cooling units, then get clear."
		% _datacenter.cooling_remaining)


func _on_cooling_unit_destroyed(remaining: int) -> void:
	if remaining > 0:
		Game.set_objective("Cooling unit destroyed. %d left." % remaining)
	else:
		Game.set_objective("Cooling offline. The building is coming down!")


func _on_neutralized() -> void:
	Game.set_objective("Datacenter down. The air is clearing. (+$%d)" % _datacenter.cash_reward)
	get_tree().create_timer(core_delay).timeout.connect(start_defense)


func _on_wave_started(number: int, total: int) -> void:
	phase = Phase.WAVE
	_auto_wave_left = -1.0
	Game.set_info("wave", "Wave %d/%d" % [number, total])
	Game.set_objective("Wave %d/%d incoming. Hold the line!" % [number, total])


func _on_wave_cleared(number: int, total: int) -> void:
	if phase == Phase.LOST:
		return
	if number >= total:
		return  # _on_all_waves_cleared handles the finale
	phase = Phase.BUILD
	_auto_wave_left = auto_wave_delay
	Game.district.trust += 0.05
	Game.set_objective("Wave %d cleared. Repair, rebuild, then [N] for the next one." % number)


func _on_all_waves_cleared() -> void:
	if phase == Phase.LOST:
		return
	phase = Phase.WON
	Game.district.trust = 1.0
	Game.district.water_table = 1.0
	Game.set_info("wave", "")
	Game.set_objective("Zone held! Water is flowing and the neighborhood is yours.")


func _on_core_damaged(_amount: float, health: float) -> void:
	Game.set_info("core", "Green datacenter  %d / %d" % [maxi(ceili(health), 0), int(core.max_health)])


func _on_core_destroyed(_core: Destructible) -> void:
	phase = Phase.LOST
	_build.enabled = false
	_build.set_active(false)
	Game.district.smog += 0.6
	Game.set_info("core", "")
	Game.set_objective("The green datacenter fell. Press [Enter] to retry.")
