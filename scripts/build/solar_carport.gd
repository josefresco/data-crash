class_name SolarCarport
extends Node3D
## A solar canopy over a row of parking spaces at the green datacenter:
## steel posts, a slightly tilted deck of solar panels high enough to park
## under, and LED strips underneath. Pays `income` every `income_interval`
## seconds while the green core stands. `length` runs along local X, `depth`
## along Z (origin at the ground, centered). Posts are solid; the rest is
## overhead.

@export var length := 28.0
@export var depth := 5.5
@export var height := 3.2
@export var income := 1
@export var income_interval := 4.0

var _left := 0.0


func _ready() -> void:
	add_to_group("solar_carports")
	_left = income_interval  # the first payout is earned, not paid on arrival
	var steel := Models.mat(Color(0.75, 0.77, 0.8), &"metal")
	var solar := Models.mat(Color(0.35, 0.45, 0.7), &"solar")
	var posts := maxi(2, int(length / 6.0) + 1)
	for i in posts:
		var x := -length * 0.5 + 0.5 + i * (length - 1.0) / (posts - 1)
		Models.box(self, Vector3(0.18, height, 0.18), Vector3(x, height * 0.5, -depth * 0.3), steel)
		Models.collider(self, Vector3(0.25, height, 0.25), Vector3(x, height * 0.5, -depth * 0.3))
		# A cantilever arm out to the front edge.
		Models.box(self, Vector3(0.12, 0.14, depth), Vector3(x, height, 0.0), steel)
	var deck := Models.box(self, Vector3(length, 0.1, depth), Vector3(0.0, height + 0.15, 0.0), solar)
	deck.rotation.x = -0.08
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Panel seams across the deck, and a light strip under it.
	for k in int(length / 1.7):
		Models.box(deck, Vector3(0.04, 0.02, depth), Vector3(-length * 0.5 + (k + 1) * 1.7, 0.06, 0.0), steel)
	Models.box(self, Vector3(length - 1.0, 0.05, 0.1), Vector3(0.0, height - 0.05, 0.0), Models.glow(Color(0.9, 0.95, 1.0), 1.5))
	Models.merge_static(self)
	Models.set_gi_mode(self, GeometryInstance3D.GI_MODE_DYNAMIC)


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = income_interval
	var level := get_tree().get_first_node_in_group("level")
	var core: Variant = level.get("core") if level else null
	if core != null and is_instance_valid(core) and not (core as Destructible).is_destroyed:
		Game.add_cash(income)
