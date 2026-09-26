class_name SolarPanel
extends Structure
## Solar array: pays the community a small income while it stands.

@export var income := 4
@export var income_interval := 2.0

var _income_timer := 0.0


func _init() -> void:
	size = Vector3(3.0, 0.5, 2.0)
	color = Color(0.8, 0.8, 0.82)
	surface_kind = &"plates"
	max_health = 120.0
	chunks = Vector3i(3, 1, 2)
	cost = 100
	label = "Solar panel"


func _ready() -> void:
	super()
	# Tilted photovoltaic panel sized to the base, on two legs.
	var panel := _add_box(Vector3(size.x - 0.1, 0.08, size.z - 0.1), Vector3(0.0, size.y + 0.45, 0.0),
		Color.WHITE, null, &"solar")
	panel.rotation.x = deg_to_rad(-25.0)
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.1, 0.6, 0.1), Vector3(side * (size.x * 0.5 - 0.3), size.y + 0.2, 0.0),
			Color(0.6, 0.62, 0.64), null, &"plates")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or is_destroyed:
		return
	_income_timer += delta
	if _income_timer >= income_interval:
		_income_timer -= income_interval
		Game.add_cash(income)
