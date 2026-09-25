extends Node3D
## Vertical-slice test level: ram the fence, blow the cooling units, watch the sky clear.

@onready var _datacenter: Datacenter = $Datacenter
@onready var _env_driver: EnvironmentDriver = $EnvironmentDriver

var _fence_breached := false


func _ready() -> void:
	Game.district = DistrictState.new()

	_env_driver.world_environment = $WorldEnvironment
	_env_driver.sun = $Sun
	_env_driver.ground = $Ground/Mesh

	for child in get_children():
		if child is FenceLine:
			(child as FenceLine).breached.connect(_on_fence_breached)
	_datacenter.cooling_unit_destroyed.connect(_on_cooling_unit_destroyed)
	_datacenter.neutralized.connect(_on_neutralized)

	Game.set_objective("Get in the car [E] and ram through the fence.")


func _on_fence_breached() -> void:
	if _fence_breached:
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
