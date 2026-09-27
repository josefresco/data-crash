class_name BribeMenu
extends Node
## At the Town Hall (within TOWN_HALL_RANGE of its door, Game meta
## "town_hall_door"), [V] opens the bribe menu; [1-3] buys. Walking away
## closes it; elsewhere the HUD line and [V] are off. Bribes are one-shot favors stored in
## Game.bribes and consumed by the systems they affect:
## - municipal_delay: next wave arrives without police or FROST (WaveSpawner)
## - supply_blockade: next wave is 30% smaller (WaveSpawner)
## - zoning_permit: Phase 3 starts with pre-built walls (level / BuildController)

signal bribe_bought(key: String)

const OFFERS := [
	{"key": "municipal_delay", "name": "Municipal delay", "cost": 200,
		"blurb": "no police or FROST next wave"},
	{"key": "supply_blockade", "name": "Supply blockade", "cost": 250,
		"blurb": "next wave 30% smaller"},
	{"key": "zoning_permit", "name": "Zoning permit", "cost": 300,
		"blurb": "pre-built walls around the green datacenter"},
]

const TOWN_HALL_RANGE := 9.0

var is_open := false

var _refresh_left := 0.0


func _ready() -> void:
	add_to_group("bribe_menu")


func _process(delta: float) -> void:
	# Pending bribes get consumed elsewhere (wave start), so refresh the line.
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		if is_open and not near_town_hall():
			set_open(false)
		if near_town_hall():
			Game.tip("town_hall", "The Town Hall. Officials here accept \"donations\": [V] opens the bribe menu.")
		_update_info()


## True when the player is at the Town Hall (the only place bribes happen).
func near_town_hall() -> bool:
	if not Game.has_meta(&"town_hall_door"):
		return false
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return false
	# While driving, the (hidden) player node stays where they got in: use the car.
	var at := player.vehicle.global_position if player.vehicle else player.global_position
	return at.distance_to(Game.get_meta(&"town_hall_door")) <= TOWN_HALL_RANGE


func set_open(value: bool) -> void:
	is_open = value
	if is_open:
		var build := get_tree().get_first_node_in_group("build_controller") as BuildController
		if build and build.active:
			build.set_active(false)
	_update_info()


## Buys offer `index` if affordable and not already pending. Returns success.
func buy(index: int) -> bool:
	if index < 0 or index >= OFFERS.size():
		return false
	var offer: Dictionary = OFFERS[index]
	var key: String = offer["key"]
	if Game.has_bribe(key) or Game.cash < int(offer["cost"]):
		Sfx.ui(&"error", -4.0)
		return false
	Game.add_cash(-int(offer["cost"]))
	Game.bribes[key] = true
	bribe_bought.emit(key)
	Sfx.ui(&"cash")
	set_open(false)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("bribe_menu"):
		if not is_open and not near_town_hall():
			return
		set_open(not is_open)
		Sfx.ui(&"open" if is_open else &"close", -4.0)
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	for i in OFFERS.size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			buy(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("cancel"):
		set_open(false)


func _update_info() -> void:
	if not is_open and not near_town_hall():
		Game.set_info("bribe", "")
		return
	if not is_open:
		var pending: PackedStringArray = []
		for offer: Dictionary in OFFERS:
			if Game.has_bribe(offer["key"]):
				pending.append(offer["name"])
		var suffix := "   (pending: %s)" % ", ".join(pending) if not pending.is_empty() else ""
		Game.set_info("bribe", "TOWN HALL   [V] Bribe officials" + suffix)
		return
	var parts: PackedStringArray = []
	for i in OFFERS.size():
		var offer: Dictionary = OFFERS[i]
		var status := "  PENDING" if Game.has_bribe(offer["key"]) else ""
		parts.append("[%d] %s $%d: %s%s" % [i + 1, offer["name"], offer["cost"], offer["blurb"], status])
	Game.set_info("bribe", "BRIBES   " + "   ".join(parts) + "   [V] close")
