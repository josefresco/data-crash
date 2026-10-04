class_name Mom
extends Enemy
## A playground mom (the playground deed brings three). She never fights:
## she marches up to the nearest awake police officer near the player with
## her sign and gives them a piece of her mind, which keeps them busy
## (Enemy.distract) instead of chasing you. With an order (AllyOrders) she
## protests at that spot. Otherwise she tags along. Nobody targets her
## (group `moms`, not `allies`).

const SIGNS := ["MOMS AGAINST\nDATACENTERS", "OUR KIDS\nCAN'T BREATHE", "WATER FOR\nKIDS, NOT CHIPS", "I WILL SPEAK\nTO YOUR MANAGER"]
const LINES := ["I'd like to speak to your manager!", "My kids drink this water!", "Shame! Shame!",
	"Do you know what's in this air?", "I have a PTA meeting at four, make this quick!"]

## How close to the player (or her order point) she looks for police.
@export var watch_radius := 40.0
@export var distract_seconds := 4.0

var _line_left := 3.0


func _init() -> void:
	faction = Faction.ALLY
	max_health = 60.0
	move_speed = 3.6
	sight_range = 0.0
	attack_range = 0.0
	bounty = 0
	hospital_share = 0.4
	outfit = ["resident_a", "resident_c", "resident_d"].pick_random()


func _faction_group() -> String:
	return "moms"


func _think() -> void:
	if _hospital_visit():
		return
	var cop := _nearest_cop()
	if cop:
		target = null
		_nav.target_position = cop.global_position + (global_position - cop.global_position).normalized() * 2.0
		if global_position.distance_to(cop.global_position) < 4.0:
			cop.distract(self, distract_seconds)
			_line_left -= THINK_INTERVAL
			if _line_left <= 0.0:
				_line_left = randf_range(3.0, 5.0)
				speak(LINES.pick_random())
				_act(&"no")
		return
	_idle()


## The nearest awake, undistracted-or-hers police officer near the player
## (or her order point).
func _nearest_cop() -> Enemy:
	var center: Vector3 = order_point
	if center == Vector3.INF:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return null
		center = player.global_position
	var best: Enemy = null
	for node in get_tree().get_nodes_in_group("hostiles"):
		var cop := node as Police
		if cop == null or not cop.is_alive() or cop.is_dormant():
			continue
		if cop.global_position.distance_to(center) > watch_radius:
			continue
		if best == null or cop.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = cop
	return best


func _upper_pose() -> StringName:
	return &"carry_walk"


func _decorate(_visual_root: Node3D) -> void:
	# A picket sign held high.
	var hand := _anchor(&"hand_r")
	var stick := _add_box(hand, Vector3(0.04, 1.4, 0.04), Vector3(0.0, 0.5, 0.0), _solid(Color(0.6, 0.48, 0.35)))
	var board := _add_box(stick, Vector3(0.8, 0.55, 0.03), Vector3(0.0, 0.8, 0.0), _solid(Color(0.98, 0.9, 0.95)))
	for side: float in [-1.0, 1.0]:
		var text := Label3D.new()
		text.text = SIGNS.pick_random()
		text.modulate = Color(0.75, 0.1, 0.4)
		text.outline_size = 0
		text.position = Vector3(0.0, 0.0, side * 0.02)
		text.rotation.y = 0.0 if side > 0.0 else PI
		board.add_child(text)
		Models.fit_label(text, Vector2(0.75, 0.5))
