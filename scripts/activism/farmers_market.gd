class_name FarmersMarket
extends Node3D
## Saturday farmer's market in the park: four stalls of local food and crafts.
## [E] near the stalls opens the table, [1-5] buys. Food heals you; everything
## you buy supports the neighbors (trust). Walking away closes it.

signal purchased(item: String)

## [item, price, health restored, trust gained]
const OFFERS := [
	["Fresh bread", 15, 25.0, 0.01],
	["Farm eggs", 20, 40.0, 0.01],
	["Wildflower honey", 30, 15.0, 0.02],
	["Hand-thrown pottery", 50, 0.0, 0.03],
	["Community quilt", 80, 0.0, 0.05],
]
const STALL_COLORS: Array[Color] = [Color(0.85, 0.2, 0.2), Color(0.2, 0.55, 0.85), Color(0.95, 0.75, 0.15), Color(0.3, 0.7, 0.35)]

@export var reach := 7.0

var is_open := false

var _player: Player


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("markets")
	var wood := Models.mat(Color(0.55, 0.4, 0.25))
	var outfits := ["vendor", "townsperson", "old_lady", "foreman"]
	for i in 4:
		var stall := Node3D.new()
		stall.position = Vector3(-7.5 + i * 5.0, 0.0, 0.0)
		add_child(stall)
		Models.box(stall, Vector3(3.2, 0.85, 1.1), Vector3(0.0, 0.43, 0.0), wood)
		# Counter, poles, and awning: nobody walks through the stall.
		Models.collider(stall, Vector3(3.3, 2.5, 1.3), Vector3(0.0, 1.25, 0.0))
		# Striped awning on four poles.
		for x in [-1.5, 1.5]:
			for z in [-0.6, 0.6]:
				Models.box(stall, Vector3(0.08, 2.4, 0.08), Vector3(x, 1.2, z), wood)
		for k in 6:
			var stripe := STALL_COLORS[i] if k % 2 == 0 else Color(0.95, 0.95, 0.9)
			var slat := Models.box(stall, Vector3(0.55, 0.06, 1.6), Vector3(-1.4 + k * 0.56, 2.45, 0.0), Models.mat(stripe, &"cloth"))
			slat.rotation.x = 0.12
		_dress_stall(stall, i)
		var vendor := CharacterModel.create(outfits[i])
		vendor.position = Vector3(0.0, 0.0, -1.2)
		vendor.rotation.y = PI
		stall.add_child(vendor)
	# Banner across the front.
	for x in [-10.5, 10.5]:
		Models.box(self, Vector3(0.12, 3.6, 0.12), Vector3(x, 1.8, 1.8), wood)
		Models.collider(self, Vector3(0.3, 3.6, 0.3), Vector3(x, 1.8, 1.8))
	var banner := Models.box(self, Vector3(8.0, 1.0, 0.05), Vector3(0.0, 3.2, 1.8), Models.mat(Color(0.95, 0.9, 0.75), &"cloth"))
	var text := Label3D.new()
	text.text = "FARMER'S MARKET\nlocal food & crafts"
	text.font_size = 72
	text.pixel_size = 0.009
	text.outline_size = 0
	text.modulate = Color(0.25, 0.45, 0.2)
	text.position = Vector3(0.0, 0.0, 0.04)
	banner.add_child(text)


## Goods on each table: produce, bread and eggs, honey jars, pottery and quilts.
func _dress_stall(stall: Node3D, index: int) -> void:
	match index:
		0:
			for k in 3:
				var crate := Models.box(stall, Vector3(0.8, 0.25, 0.6), Vector3(-1.0 + k * 1.0, 0.98, 0.1), Models.mat(Color(0.6, 0.45, 0.3)))
				var fruit: Color = [Color(0.85, 0.15, 0.1), Color(0.95, 0.55, 0.1), Color(0.35, 0.7, 0.2)][k]
				for f in 5:
					Models.ball(crate, 0.1, Vector3(-0.25 + f * 0.12, 0.17, 0.0), Models.mat(fruit, &"paint"))
		1:
			for k in 5:
				Models.box(stall, Vector3(0.45, 0.2, 0.22), Vector3(-1.2 + k * 0.5, 0.96, 0.1), Models.mat(Color(0.78, 0.55, 0.3), &"rough"))
			for k in 6:
				Models.ball(stall, 0.06, Vector3(-0.4 + k * 0.14, 0.92, -0.25), Models.mat(Color(0.95, 0.92, 0.85), &"paint"))
		2:
			for k in 7:
				Models.cylinder(stall, 0.09, 0.2, Vector3(-1.2 + k * 0.4, 0.96, 0.1), Models.glass(Color(0.95, 0.65, 0.1, 0.85)), 8)
		_:
			for k in 3:
				Models.cylinder(stall, 0.18, 0.35, Vector3(-1.1 + k * 0.5, 1.03, 0.1), Models.mat(Color(0.7, 0.4, 0.28), &"rough"), 10)
			var quilt := Models.box(stall, Vector3(1.4, 1.0, 0.04), Vector3(0.9, 1.6, -0.55), Models.mat(Color(0.7, 0.3, 0.45), &"cloth"))
			for q in 4:
				Models.box(quilt, Vector3(0.33, 0.24, 0.01), Vector3(-0.5 + q * 0.33, 0.2 - (q % 2) * 0.35, 0.03),
					Models.mat([Color(0.95, 0.85, 0.3), Color(0.3, 0.6, 0.85), Color(0.9, 0.9, 0.85), Color(0.4, 0.7, 0.4)][q], &"cloth"))


func in_reach(player: Node3D) -> bool:
	return player.global_position.distance_to(global_position) <= reach


func offer_text(_player_node: Player) -> String:
	return "[1-5] Buy   [E] Close the market" if is_open else "[E] Browse the farmer's market (food heals, everything builds goodwill)"


func interact(player: Player) -> void:
	is_open = not is_open
	_player = player
	Sfx.ui(&"open" if is_open else &"close", -4.0)
	if is_open:
		Game.tip("market", "Food from the market heals you. Every purchase supports the neighbors and raises trust.")
	_refresh()


func _process(_delta: float) -> void:
	if is_open and (_player == null or not in_reach(_player) or not _player.is_visible_in_tree()):
		is_open = false
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	for i in OFFERS.size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			buy(i, _player)
			get_viewport().set_input_as_handled()
			return


## Buys OFFERS[index]: costs cash, heals (food), raises trust. Returns success.
func buy(index: int, player: Player) -> bool:
	if player == null or index < 0 or index >= OFFERS.size():
		return false
	var offer: Array = OFFERS[index]
	if Game.cash < int(offer[1]):
		Sfx.ui(&"error", -4.0)
		Game.notify("Not enough cash for the %s ($%d)." % [String(offer[0]).to_lower(), offer[1]], 3.0)
		return false
	Game.add_cash(-int(offer[1]))
	if float(offer[2]) > 0.0:
		player.heal(float(offer[2]))
	if Game.district:
		Game.district.trust += float(offer[3])
	Game.count("market")
	Sfx.ui(&"cash")
	Game.notify("Bought %s.%s The neighbors appreciate it." % [String(offer[0]).to_lower(),
		(" +%d health." % int(offer[2])) if float(offer[2]) > 0.0 else ""], 3.0)
	purchased.emit(offer[0])
	_refresh()
	return true


func _refresh() -> void:
	if not is_open:
		Game.set_info("shop", "")
		return
	var parts: Array[String] = []
	for i in OFFERS.size():
		var offer: Array = OFFERS[i]
		parts.append("[%d] %s $%d" % [i + 1, offer[0], offer[1]])
	Game.set_info("shop", "FARMER'S MARKET   " + "   ".join(parts))
