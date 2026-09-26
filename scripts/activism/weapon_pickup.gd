class_name WeaponPickup
extends Node3D
## Something lying around the neighborhood you can arm yourself with: a shovel
## (kept for good), a pile of rocks, or a crate of bottles and gas (molotovs).
## [E] picks it up. Piles and crates restock after `respawn` seconds.

signal picked_up(pickup: WeaponPickup)

## &"shovel", &"rocks", or &"molotovs".
@export var kind := &"rocks"
@export var reach := 2.6
## Seconds until it's back (0 = gone for good).
@export var respawn := 45.0

var available := true

var _visual: Node3D
var _left := 0.0


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		&"shovel":
			respawn = 0.0
			var shovel := WeaponModels.build(&"shovel")
			shovel.rotation = Vector3(0.0, randf() * TAU, PI * 0.5)
			shovel.position.y = 0.05
			_visual.add_child(shovel)
		&"molotovs":
			var crate := Models.box(_visual, Vector3(0.8, 0.4, 0.55), Vector3(0.0, 0.2, 0.0), Models.mat(Color(0.5, 0.36, 0.22)))
			for i in 3:
				var bottle := WeaponModels.build(&"molotov")
				bottle.position = Vector3(-0.22 + i * 0.22, 0.38, 0.0)
				_visual.add_child(bottle)
			Models.box(_visual, Vector3(0.35, 0.45, 0.2), Vector3(0.65, 0.22, 0.0), Models.mat(Color(0.8, 0.12, 0.1), &"paint")).name = "GasCan"
			crate.name = "Crate"
		_:
			var stone := Models.mat(Color(0.52, 0.5, 0.47), &"rough")
			for i in 6:
				var angle := i * TAU / 6.0
				Models.ball(_visual, randf_range(0.1, 0.16), Vector3(cos(angle) * 0.25, 0.1, sin(angle) * 0.25), stone)
			Models.ball(_visual, 0.15, Vector3(0.0, 0.2, 0.0), stone)
	var tag := Label3D.new()
	tag.text = label()
	tag.pixel_size = 0.005
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 0.9
	_visual.add_child(tag)


func label() -> String:
	match kind:
		&"shovel":
			return "Shovel"
		&"molotovs":
			return "Bottles + gas"
	return "Rocks"


func weapon_name() -> String:
	match kind:
		&"shovel":
			return "Shovel"
		&"molotovs":
			return "Molotov"
	return "Rocks"


func amount() -> int:
	match kind:
		&"molotovs":
			return 3
		&"rocks":
			return 6
	return 0


func _process(delta: float) -> void:
	if available or respawn <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		available = true
		_visual.visible = true


func in_reach(player: Node3D) -> bool:
	return available and player.global_position.distance_to(global_position) <= reach


func offer_text(player: Player) -> String:
	var weapon := player.weapon_named(weapon_name())
	if kind == &"shovel":
		return "[E] Pick up the shovel" if not weapon.owned else "[E] You already have a shovel"
	return "[E] Grab %s (x%d)" % ["rocks" if kind == &"rocks" else "molotovs", amount()]


func interact(player: Player) -> void:
	var weapon := player.weapon_named(weapon_name())
	if weapon == null:
		return
	if kind == &"shovel" and weapon.owned:
		return
	if weapon.max_ammo >= 0 and weapon.owned and weapon.ammo >= weapon.max_ammo:
		Game.notify("Your pockets are full of %s." % weapon.display_name.to_lower(), 3.0)
		return
	player.unlock_weapon(weapon.display_name, amount())
	if weapon.max_ammo >= 0:
		weapon.ammo = mini(weapon.ammo, weapon.max_ammo)
	player.select_weapon(player.weapons.find(weapon))
	Sfx.play(&"hit_wood", global_position, -2.0)
	Game.notify("Picked up: %s%s." % [weapon.display_name.to_lower(), "" if amount() == 0 else " x%d" % amount()], 3.0)
	match kind:
		&"shovel":
			Game.tip("shovel", "Shovel: left click swings it. Hits hard up close, shoves guards back, and smashes Grock cameras.")
		&"rocks":
			Game.tip("rocks", "Rocks: throw them to hurt, or to lure guards toward the noise.")
		&"molotovs":
			Game.tip("molotovs", "Molotovs leave a fire that burns hostiles and scatters protesters without hurting them.")
	available = false
	_visual.visible = false
	_left = respawn
	picked_up.emit(self)
