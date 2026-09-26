class_name SolarArray
extends SolarPanel
## One row of the green datacenter's solar field. Laid out automatically when
## the green datacenter goes up; earns a trickle of income and draws attackers
## away from the core.


func _init() -> void:
	size = Vector3(4.2, 0.5, 2.2)
	max_health = 60.0
	cost = 0
	income = 1
	income_interval = 8.0
	label = "Solar array"
