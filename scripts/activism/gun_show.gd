class_name GunShow
extends Node3D
## Weekend gun show stall in the park. [E] opens the table: [1-5] buys a gun
## (once each) or a grenade pack (as often as you can pay). Walking away or
## [E] again closes it.

signal purchased(item: String)

## [weapon name, price, ammo added (0 = full)]
const OFFERS := [
	["Pistol", 120, 0],
	["Shotgun", 250, 0],
	["Hunting rifle", 300, 0],
	["Machine gun", 450, 0],
	["Grenades", 150, 3],
]

@export var reach := 3.5

var is_open := false

var _player: Player


func _ready() -> void:
	add_to_group("interactables")
	var wood := Models.mat(Color(0.5, 0.35, 0.22))
	var cloth := Models.mat(Color(0.2, 0.35, 0.25))
	Models.box(self, Vector3(3.0, 0.9, 1.0), Vector3(0.0, 0.45, 0.0), wood)
	Models.box(self, Vector3(3.4, 0.08, 1.8), Vector3(0.0, 2.3, 0.2), cloth)
	for x in [-1.6, 1.6]:
		Models.box(self, Vector3(0.08, 2.3, 0.08), Vector3(x, 1.15, 1.0), wood)
	# The wares, laid out on the table.
	var offsets := [-1.1, -0.45, 0.25, 0.95]
	var models := [&"pistol", &"shotgun", &"rifle", &"mg"]
	for i in models.size():
		var gun := WeaponModels.build(models[i])
		gun.position = Vector3(offsets[i], 0.93, 0.1)
		gun.rotation = Vector3(-PI * 0.5, PI * 0.5, 0.0)
		add_child(gun)
	var vendor := CharacterModel.create("vendor")
	vendor.position = Vector3(0.0, 0.0, -1.0)
	vendor.rotation.y = PI
	add_child(vendor)
	var sign_label := Label3D.new()
	sign_label.text = "GUN SHOW"
	sign_label.pixel_size = 0.02
	sign_label.outline_size = 10
	sign_label.modulate = Color(1.0, 0.85, 0.4)
	sign_label.position = Vector3(0.0, 2.8, 1.0)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)


func in_reach(player: Node3D) -> bool:
	return player.global_position.distance_to(global_position) <= reach


func offer_text(_player_node: Player) -> String:
	return "[1-5] Buy   [E] Close the table" if is_open else "[E] Browse the gun show"


func interact(player: Player) -> void:
	set_open(not is_open, player)


func set_open(open: bool, player: Player = null) -> void:
	is_open = open
	if player:
		_player = player
	Sfx.ui(&"open" if open else &"close", -4.0)
	_refresh()


func _process(_delta: float) -> void:
	if is_open and (_player == null or not in_reach(_player) or not _player.is_visible_in_tree()):
		set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	for i in OFFERS.size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			buy_item(i, _player)
			get_viewport().set_input_as_handled()
			return


## Buys OFFERS[index]. Guns sell once; grenades stack. Returns success.
func buy_item(index: int, player: Player) -> bool:
	if player == null or index < 0 or index >= OFFERS.size():
		return false
	var offer: Array = OFFERS[index]
	var item: String = offer[0]
	var price: int = offer[1]
	var weapon := player.weapon_named(item)
	if weapon == null or (weapon.owned and int(offer[2]) == 0):
		Sfx.ui(&"error", -4.0)
		Game.notify("You already have the %s." % item.to_lower(), 3.0)
		return false
	if Game.cash < price:
		Sfx.ui(&"error", -4.0)
		Game.notify("Not enough cash: the %s costs $%d. Good deeds, turbines, and Grock cameras pay." % [item.to_lower(), price], 3.0)
		return false
	Game.add_cash(-price)
	player.unlock_weapon(item, int(offer[2]))
	player.select_weapon(player.weapons.find(weapon))
	Sfx.ui(&"cash")
	Game.notify("Bought: %s. It's in your hands (Q switches)." % item.to_lower())
	purchased.emit(item)
	_refresh()
	return true


func _refresh() -> void:
	if not is_open:
		Game.set_info("shop", "")
		return
	var parts: Array[String] = []
	for i in OFFERS.size():
		var offer: Array = OFFERS[i]
		var weapon := _player.weapon_named(offer[0]) if _player else null
		var sold := weapon != null and weapon.owned and int(offer[2]) == 0
		var name_text: String = offer[0] if int(offer[2]) == 0 else "%s x%d" % [offer[0], offer[2]]
		parts.append("[%d] %s %s" % [i + 1, name_text, "(owned)" if sold else "$%d" % offer[1]])
	Game.set_info("shop", "GUN SHOW   " + "   ".join(parts))
