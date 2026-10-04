class_name Storefront
extends Node3D
## A local business open for trade: a chalkboard A-frame by the door. [E]
## opens the menu, [1-3] buys. Food and first aid heal; everything spends
## money on the block, which raises trust and builds goodwill: the level
## turns goodwill into Regulars, locals who join you and fight (see
## Level.on_purchase). Walking away closes the menu. `kind` picks the menu
## from the sign ("diner", "pizza", "pharmacy", "laundromat", "bait").

signal purchased(store: Storefront, item: String)

## [item, price, health restored, trust gained, effect ("" | "party" | "disguise")]
const MENUS := {
	"diner": [["Coffee", 5, 10.0, 0.005, ""], ["Pancake stack", 12, 35.0, 0.01, ""], ["Blue plate special", 20, 60.0, 0.015, ""]],
	"pizza": [["Slice", 6, 15.0, 0.005, ""], ["Whole pie", 25, 60.0, 0.012, ""], ["Pizza party for your crew", 40, 20.0, 0.02, "party"]],
	"pharmacy": [["Bandages", 10, 25.0, 0.005, ""], ["First aid kit", 30, 80.0, 0.01, ""], ["Inhalers for the block", 25, 0.0, 0.03, ""]],
	"laundromat": [["Donate quarters", 5, 0.0, 0.01, ""], ["Wash a neighbor's load", 12, 0.0, 0.02, ""], ["Fresh hoodie (sneakier for 2 min)", 15, 0.0, 0.01, "disguise"]],
	"cafe": [["Drip coffee", 4, 8.0, 0.005, ""], ["Latte and a muffin", 9, 25.0, 0.008, ""], ["Coffee for the picket line", 22, 0.0, 0.03, ""]],
	"grocery": [["Apples", 5, 12.0, 0.005, ""], ["Sandwich fixings", 14, 40.0, 0.01, ""], ["Fill the food pantry box", 30, 0.0, 0.035, ""]],
	"bakery": [["Day-old donut", 3, 8.0, 0.004, ""], ["Loaf of sourdough", 9, 30.0, 0.008, ""], ["Sheet cake for the block party", 35, 15.0, 0.02, "party"]],
	"auto": [["Air for a neighbor's tires", 5, 0.0, 0.01, ""], ["Jump a dead battery", 12, 0.0, 0.02, ""], ["Brake job for the school van", 40, 0.0, 0.045, ""]],
	"barber": [["Tip the apprentice", 5, 0.0, 0.01, ""], ["Hot towel shave", 12, 20.0, 0.01, ""], ["A whole new look (sneakier for 2 min)", 18, 0.0, 0.01, "disguise"]],
	"bait": [["Nightcrawlers", 5, 0.0, 0.01, ""], ["Cooler of snacks", 15, 30.0, 0.01, ""], ["Fishing license (the river's coming back)", 20, 0.0, 0.025, ""]],
}

@export var kind := "diner"
@export var store_name := "the diner"
@export var reach := 3.0

var is_open := false
var _player: Player


## The menu for a sign's text: DINER, PIZZA, PHARMACY, LAUNDROMAT / SPIN /
## SUDS, BAIT. "" for signs that aren't shops (police, town hall).
static func kind_for(sign_text: String) -> String:
	var upper := sign_text.to_upper()
	for pair in [["DINER", "diner"], ["PIZZA", "pizza"], ["PHARMACY", "pharmacy"], ["LAUNDROMAT", "laundromat"],
			["SPIN CYCLE", "laundromat"], ["SUDS", "laundromat"], ["BAIT", "bait"], ["COFFEE", "cafe"],
			["GROCER", "grocery"], ["BAKERY", "bakery"], ["AUTO", "auto"], ["BARBER", "barber"]]:
		if pair[0] in upper:
			return pair[1]
	return ""


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("storefronts")
	# Chalkboard A-frame on the sidewalk.
	var wood := Models.mat(Color(0.55, 0.42, 0.3), &"wood")
	var slate := Models.mat(Color(0.12, 0.14, 0.13), &"paint")
	for side: float in [-1.0, 1.0]:
		var leaf := Models.box(self, Vector3(0.6, 0.9, 0.04), Vector3(0.0, 0.45, side * 0.14), wood)
		leaf.rotation.x = side * 0.28
		Models.box(leaf, Vector3(0.5, 0.75, 0.01), Vector3(0.0, 0.0, side * 0.025), slate)
	var chalk := Label3D.new()
	chalk.text = "OPEN\n" + String(menu()[0][0]).to_upper()
	chalk.modulate = Color(0.95, 0.95, 0.9)
	chalk.outline_size = 0
	chalk.position = Vector3(0.0, 0.47, 0.3)
	chalk.rotation.x = -0.28
	add_child(chalk)
	Models.fit_label(chalk, Vector2(0.45, 0.6))


func menu() -> Array:
	return MENUS.get(kind, MENUS["diner"])


func in_reach(player: Node3D) -> bool:
	return player.global_position.distance_to(global_position) <= reach


func offer_text(_player_node: Player) -> String:
	return "[1-3] Buy   [E] Close" if is_open else "[E] Shop at %s (spending local builds goodwill)" % store_name


func interact(player: Player) -> void:
	is_open = not is_open
	_player = player
	Sfx.ui(&"open" if is_open else &"close", -4.0)
	if is_open:
		Game.tip("storefront", "Spending money at local shops raises trust, and every few purchases a regular joins you in the fight.")
	_refresh()


func _process(_delta: float) -> void:
	if is_open and (_player == null or not in_reach(_player) or not _player.is_visible_in_tree()):
		is_open = false
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	for i in menu().size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			buy(i, _player)
			get_viewport().set_input_as_handled()
			return


## Buys menu()[index]. Returns success.
func buy(index: int, player: Player) -> bool:
	var items := menu()
	if player == null or index < 0 or index >= items.size():
		return false
	var item: Array = items[index]
	var price := int(item[1])
	if Game.cash < price:
		Sfx.ui(&"error", -4.0)
		Game.notify("Not enough cash for the %s ($%d)." % [String(item[0]).to_lower(), price], 3.0)
		return false
	Game.add_cash(-price)
	if float(item[2]) > 0.0:
		player.heal(float(item[2]))
	if Game.district:
		Game.district.trust += float(item[3])
	match String(item[4]):
		"party":
			for node in get_tree().get_nodes_in_group("allies"):
				var ally := node as Enemy
				if ally and ally.is_alive():
					ally.health = ally.max_health
		"disguise":
			player.disguise(120.0)
	Game.count("purchases")
	Sfx.ui(&"cash")
	Game.notify("Bought: %s at %s.%s" % [String(item[0]).to_lower(), store_name,
		(" +%d health." % int(item[2])) if float(item[2]) > 0.0 else ""], 3.0)
	purchased.emit(self, item[0])
	_refresh()
	return true


func _refresh() -> void:
	if not is_open:
		Game.set_info("shop", "")
		return
	var parts: Array[String] = []
	var items := menu()
	for i in items.size():
		parts.append("[%d] %s $%d" % [i + 1, items[i][0], items[i][1]])
	Game.set_info("shop", store_name.to_upper() + "   " + "   ".join(parts))
