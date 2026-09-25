class_name Weapon
extends RefCounted
## Stats for one player weapon. HITSCAN weapons fire `pellets` rays with random
## `spread`; THROWN weapons launch a Throwable of `throw_kind`.

enum Kind { HITSCAN, THROWN }

var display_name := ""
var kind := Kind.HITSCAN
var damage := 15.0
var pellets := 1
## Max random deviation per pellet, in radians.
var spread := 0.01
var cooldown := 0.25
var max_range := 60.0
## -1 = unlimited.
var ammo := -1
var max_ammo := -1
var throw_kind := &""
var tracer_color := Color(1.0, 1.0, 0.8)


static func make(weapon_name: String, props: Dictionary) -> Weapon:
	var weapon := Weapon.new()
	weapon.display_name = weapon_name
	for key: String in props:
		weapon.set(key, props[key])
	weapon.max_ammo = weapon.ammo
	return weapon


## Level 1 and 2 kit from WEAPONS.md.
static func default_loadout() -> Array[Weapon]:
	return [
		make("Pistol", {"damage": 15.0, "cooldown": 0.25, "spread": 0.01, "max_range": 60.0}),
		make("Shotgun", {"damage": 10.0, "pellets": 8, "spread": 0.045, "cooldown": 0.8,
			"max_range": 25.0, "ammo": 24}),
		make("Hunting rifle", {"damage": 70.0, "cooldown": 1.2, "spread": 0.0, "max_range": 120.0,
			"ammo": 15, "tracer_color": Color(1.0, 0.9, 0.6)}),
		make("Molotov", {"kind": Kind.THROWN, "throw_kind": &"molotov", "cooldown": 1.0, "ammo": 3}),
		make("Rocks", {"kind": Kind.THROWN, "throw_kind": &"rock", "damage": 5.0, "cooldown": 0.6}),
	]


func has_ammo() -> bool:
	return ammo != 0


func refill() -> void:
	ammo = max_ammo


func hud_label() -> String:
	return display_name if ammo < 0 else "%s  %d/%d" % [display_name, ammo, max_ammo]
