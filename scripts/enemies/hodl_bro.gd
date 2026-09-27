class_name HodlBro
extends ReplyGuy
## Chad Hodler's crypto faithful: neon tees, laser-eye profile pics, and the
## same waddle and slap as Elmo's reply guys. They log off when Chad pulls
## the rug (or goes down).

const HODL_LINES := [
	"WAGMI!",
	"Buy the dip!",
	"Have fun staying poor!",
	"Not financial advice!",
	"Diamond hands!",
	"To the moon!",
	"Wen lambo?",
]
const MAX_BROS := 8


func _init() -> void:
	outfit = "hodl_bro"
	voice_pitch = 1.3


func _ready() -> void:
	super()
	remove_from_group("reply_guys")  # Elmo's fans log off with Elmo, not these
	add_to_group("hodl_bros")


func _lines() -> Array:
	return HODL_LINES


## Out of the fight (logged off or down): no longer one of Chad's bros, so
## the summon cap and the rug pull only count the active ones.
func log_off() -> void:
	remove_from_group("hodl_bros")
	super()


func _on_death() -> void:
	remove_from_group("hodl_bros")
	super()


## Spawns up to `count` bros in a ring around `host` (at most MAX_BROS on
## the map). Returns how many showed up.
static func summon_bros(host: Node3D, count: int) -> int:
	var tree := host.get_tree()
	var room := MAX_BROS - tree.get_nodes_in_group("hodl_bros").size()
	var spawned := 0
	var nav_map := host.get_world_3d().navigation_map
	for i in mini(count, room):
		var angle := randf() * TAU
		var spot := host.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(5.0, 8.0)
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			spot = NavigationServer3D.map_get_closest_point(nav_map, spot)
		var bro := HodlBro.new()
		bro.site = (host as Enemy).site if host is Enemy else &""
		bro.position = (host.get_parent() as Node3D).to_local(spot + Vector3.UP * 0.1)
		host.get_parent().add_child(bro)
		Vfx.dust(host.get_parent(), spot, 1.0)
		spawned += 1
	return spawned
