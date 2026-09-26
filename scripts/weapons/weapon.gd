class_name Weapon
extends RefCounted
## Stats for one player weapon. HITSCAN weapons fire `pellets` rays with random
## `spread`; THROWN weapons launch a Throwable of `throw_kind`; MELEE weapons
## hit everything in a short arc (`reach`) in front of the player.

enum Kind { HITSCAN, THROWN, MELEE }

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
## Launch speed for THROWN weapons; rockets fly flat and fast.
var throw_speed := 16.0
## Level 3 gear starts locked (gun show, security cache).
var owned := true
var tracer_color := Color(1.0, 1.0, 0.8)
## Sfx cue played on each shot.
var sound := &"pistol"
## Held model (WeaponModels.build); empty = bare hands.
var model := &""
## Both hands on it: the off hand reaches for the model's "Grip" marker.
var two_handed := false
## MELEE: how far the swing reaches, and how hard it shoves.
var reach := 2.0
var knockback := 0.0


static func make(weapon_name: String, props: Dictionary) -> Weapon:
	var weapon := Weapon.new()
	weapon.display_name = weapon_name
	for key: String in props:
		weapon.set(key, props[key])
	if not props.has("max_ammo"):
		weapon.max_ammo = weapon.ammo
	return weapon


## Everything the player can ever carry. Only fists are owned at the start:
## shovels, rocks, and molotovs are picked up around the neighborhood, guns and
## grenades come from the gun show, rockets from the security cache.
static func default_loadout() -> Array[Weapon]:
	return [
		make("Fists", {"kind": Kind.MELEE, "damage": 6.0, "cooldown": 0.45, "reach": 1.7, "sound": &"throw"}),
		make("Shovel", {"kind": Kind.MELEE, "damage": 28.0, "cooldown": 0.7, "reach": 2.5, "knockback": 5.0,
			"owned": false, "sound": &"throw", "model": &"shovel", "two_handed": true}),
		make("Rocks", {"kind": Kind.THROWN, "throw_kind": &"rock", "damage": 5.0, "cooldown": 0.6, "ammo": 0,
			"max_ammo": 12, "owned": false, "sound": &"throw", "model": &"rock"}),
		make("Pistol", {"damage": 15.0, "cooldown": 0.25, "spread": 0.01, "max_range": 60.0, "owned": false,
			"model": &"pistol"}),
		make("Shotgun", {"damage": 10.0, "pellets": 8, "spread": 0.045, "cooldown": 0.8,
			"max_range": 25.0, "ammo": 24, "owned": false, "sound": &"shotgun", "model": &"shotgun", "two_handed": true}),
		make("Hunting rifle", {"damage": 70.0, "cooldown": 1.2, "spread": 0.0, "max_range": 120.0,
			"ammo": 15, "owned": false, "tracer_color": Color(1.0, 0.9, 0.6), "sound": &"rifle", "model": &"rifle",
			"two_handed": true}),
		make("Molotov", {"kind": Kind.THROWN, "throw_kind": &"molotov", "cooldown": 1.0, "ammo": 0, "max_ammo": 3,
			"owned": false, "sound": &"throw", "model": &"molotov"}),
		make("Grenades", {"kind": Kind.THROWN, "throw_kind": &"grenade", "damage": 130.0, "cooldown": 0.9,
			"ammo": 0, "max_ammo": 3, "owned": false, "sound": &"throw", "model": &"grenade"}),
		make("Machine gun", {"damage": 9.0, "cooldown": 0.08, "spread": 0.03, "max_range": 50.0,
			"ammo": 150, "owned": false, "tracer_color": Color(1.0, 0.8, 0.4), "sound": &"mg", "model": &"mg",
			"two_handed": true}),
		make("Rocket launcher", {"kind": Kind.THROWN, "throw_kind": &"rocket", "damage": 260.0,
			"cooldown": 1.5, "throw_speed": 42.0, "ammo": 0, "max_ammo": 4, "owned": false, "sound": &"rocket",
			"model": &"rocket", "two_handed": true}),
	]


## Guns and the launcher raise the arms to aim; throwables and melee don't.
func aims() -> bool:
	return kind == Kind.HITSCAN or throw_kind == &"rocket"


func has_ammo() -> bool:
	return owned and ammo != 0


func refill() -> void:
	if owned:
		ammo = max_ammo if max_ammo >= 0 else -1


func hud_label() -> String:
	return display_name if ammo < 0 else "%s  %d/%d" % [display_name, ammo, max_ammo]
