class_name Regular
extends Canuck
## A regular from a local business (the cook, the pharmacist, the pizza
## guy...) who joins the fight once enough money has been spent on the
## block (Level.on_purchase). Fights like a recruited Canadian (follows the
## player, holds the core during the defense, patches up at the hospital)
## but lives here: never goes home after a wave. Group `regulars`.

const JOIN_LINES := {
	"diner": "Mabel says you're good people. I'm in.",
	"pizza": "Extra cheese on their heads, coming up!",
	"pharmacy": "I've got bandages and a bad attitude.",
	"laundromat": "I've been folding their towels for years. Let's go.",
	"bait": "I know a thing or two about hooks. Let's go.",
}
const FIGHTS := ["Get off our block!", "This one's on the house!", "Shop local!", "Not in my neighborhood!",
	"You're cut off!", "Order up!"]
const OUTFITS := {"diner": "vendor", "pizza": "resident_b", "pharmacy": "resident_c", "laundromat": "resident_a", "bait": "gardener"}

## The shop they come from (Storefront.kind).
var shop := "diner"


func _init() -> void:
	super()
	max_health = 90.0
	stick_damage = 16.0


## Call before add_child.
func setup_regular(shop_kind: String) -> void:
	shop = shop_kind
	outfit = OUTFITS.get(shop_kind, "townsperson")


func _ready() -> void:
	super()
	remove_from_group("canadians")
	add_to_group("regulars")
	state = State.LOST
	join()


func _join_line() -> String:
	return JOIN_LINES.get(shop, "The block's got your back.")


func _fight_line() -> String:
	return FIGHTS.pick_random()


func _on_death() -> void:
	if Game.district:
		Game.district.trust -= 0.02
	Game.notify("One of the regulars went down. The block won't forget it.", 3.0)


func _decorate(_visual_root: Node3D) -> void:
	_hold_weapon(&"bat", Color(0, 0, 0, 0), 1.2)
