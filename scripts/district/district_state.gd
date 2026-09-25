class_name DistrictState
extends Resource
## Environmental health of one district. All values are 0..1.
## Smog and noise: 1 = ruined. Water table and trust: 1 = healthy.
## Emits `changed` on any edit; EnvironmentDriver and the HUD listen to it.

@export_range(0.0, 1.0) var smog: float = 1.0:
	set(value):
		smog = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(0.0, 1.0) var noise: float = 1.0:
	set(value):
		noise = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(0.0, 1.0) var water_table: float = 0.1:
	set(value):
		water_table = clampf(value, 0.0, 1.0)
		emit_changed()

@export_range(0.0, 1.0) var trust: float = 0.2:
	set(value):
		trust = clampf(value, 0.0, 1.0)
		emit_changed()


## 0 = fully polluted, 1 = fully restored. Drives the grey-to-green blend.
func restoration() -> float:
	return clampf(((1.0 - smog) + (1.0 - noise) + water_table) / 3.0, 0.0, 1.0)
