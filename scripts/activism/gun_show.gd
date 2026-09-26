class_name GunShow
extends Node3D
## Weekend gun show stall in the park. [E] buys the current offer: the machine
## gun once, then grenade packs as often as you can pay.

signal purchased(item: String)

@export var reach := 3.5
@export var machine_gun_cost := 400
@export var grenade_cost := 150
@export var grenades_per_pack := 3


func _ready() -> void:
	add_to_group("interactables")
	var wood := Models.mat(Color(0.5, 0.35, 0.22))
	var cloth := Models.mat(Color(0.2, 0.35, 0.25))
	Models.box(self, Vector3(3.0, 0.9, 1.0), Vector3(0.0, 0.45, 0.0), wood)
	Models.box(self, Vector3(3.4, 0.08, 1.8), Vector3(0.0, 2.3, 0.2), cloth)
	for x in [-1.6, 1.6]:
		Models.box(self, Vector3(0.08, 2.3, 0.08), Vector3(x, 1.15, 1.0), wood)
	Models.box(self, Vector3(0.9, 0.12, 0.3), Vector3(-0.6, 0.97, 0.0), Models.mat(Color(0.15, 0.15, 0.15)))
	Models.box(self, Vector3(0.3, 0.2, 0.3), Vector3(0.7, 1.0, 0.0), Models.mat(Color(0.25, 0.3, 0.2)))
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


## What [E] would buy right now, for the prompt.
func offer_text(player: Player) -> String:
	var gun := player.weapon_named("Machine gun")
	if gun and not gun.owned:
		return "[E] Gun show: machine gun $%d" % machine_gun_cost
	return "[E] Gun show: grenades x%d $%d" % [grenades_per_pack, grenade_cost]


func interact(player: Player) -> void:
	buy(player)


func buy(player: Player) -> bool:
	var gun := player.weapon_named("Machine gun")
	if gun and not gun.owned:
		if Game.cash < machine_gun_cost:
			Sfx.ui(&"error", -4.0)
			Game.notify("Not enough cash: the machine gun costs $%d. Deeds, turbines, and Grock cameras pay." % machine_gun_cost, 3.0)
			return false
		Game.add_cash(-machine_gun_cost)
		player.unlock_weapon("Machine gun")
		Sfx.ui(&"cash")
		Game.notify("Machine gun bought. Q switches to it. Come back for grenades.")
		purchased.emit("Machine gun")
		return true
	if Game.cash < grenade_cost:
		Sfx.ui(&"error", -4.0)
		Game.notify("Not enough cash: grenades cost $%d." % grenade_cost, 3.0)
		return false
	Game.add_cash(-grenade_cost)
	player.unlock_weapon("Grenades", grenades_per_pack)
	Sfx.ui(&"cash")
	Game.notify("+%d grenades. Throw with left click; they bounce, then blow." % grenades_per_pack)
	purchased.emit("Grenades")
	return true
