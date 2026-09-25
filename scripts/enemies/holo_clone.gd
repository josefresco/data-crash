class_name HoloClone
extends SecurityGuard
## Fark Suckerbush's holographic decoy: looks like a guard, pops in one hit,
## barely hurts, fades after `lifetime`. Soaks up turret fire.

@export var lifetime := 15.0


func _init() -> void:
	max_health = 1.0
	shot_damage = 3.0
	bounty = 0
	body_color = Color(0.4, 0.8, 1.0)


func _ready() -> void:
	super()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(0.4, 0.8, 1.0, 0.45)
	_material.emission_enabled = true
	_material.emission = Color(0.3, 0.7, 1.0)
	get_tree().create_timer(lifetime).timeout.connect(_expire)


func _base_color() -> Color:
	return Color(0.4, 0.8, 1.0, 0.45)


func _expire() -> void:
	if is_alive():
		_die()


func _play_death() -> void:
	queue_free()
