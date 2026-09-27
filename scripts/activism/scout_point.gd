class_name ScoutPoint
extends Node3D
## A vantage point overlooking one datacenter: a big tree with a treehouse
## platform, or a utility building's roof. [E] at the ladder climbs up (and
## back down); staying on the platform for `watch_time` seconds scouts that
## site: each of its cooling units gets a marker visible through walls.

signal scouted(point: ScoutPoint)

enum Style { TREE, ROOFTOP }

@export var style := Style.TREE
## The site this perch overlooks (its cooling units get marked).
@export var site_id := &"felsa"
@export var watch_time := 2.0
## How close to the top spot counts as "on the perch".
@export var radius := 2.2

var is_scouted := false
var watched := 0.0

var _height := 6.5
var _ladder := Vector3.ZERO
var _top := Vector3.ZERO
var _label: Label3D
var _beacon_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("scout_points")
	add_to_group("interactables")
	if style == Style.TREE:
		_build_tree()
	else:
		_build_rooftop()
	_label = Label3D.new()
	_label.text = "Scout %s" % _site_name()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.012
	_label.outline_size = 8
	_label.position = _ladder + Vector3.UP * 2.6
	HudOverlay.as_bubble(_label)
	add_child(_label)


## Top of the perch and the foot of the ladder, in world space.
func top_spot() -> Vector3:
	return global_transform * _top


func base_spot() -> Vector3:
	return global_transform * _ladder


func in_reach(player: Node3D) -> bool:
	return player.global_position.distance_to(base_spot()) <= 2.4 or on_perch(player)


func offer_text(player: Player) -> String:
	return "[E] Climb down" if on_perch(player) else "[E] Climb up to scout %s" % _site_name()


func interact(player: Player) -> void:
	player.velocity = Vector3.ZERO
	if on_perch(player):
		player.global_position = base_spot() + Vector3.UP * 0.2
	else:
		player.global_position = top_spot() + Vector3.UP * 0.2
		Game.tip("scout_perch", "Up here you can see the whole site. Stay a moment to mark its cooling units, then [E] to climb down.")
	Sfx.play(&"hit_wood", player.global_position, -6.0, 0.8)


func on_perch(player: Node3D) -> bool:
	var offset := player.global_position - top_spot()
	return absf(offset.y) < 1.6 and Vector2(offset.x, offset.z).length() <= radius


func _physics_process(delta: float) -> void:
	if is_scouted:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.is_visible_in_tree() or not on_perch(player):
		watched = 0.0
		return
	watched += delta
	_label.text = "Scouting %s... %d%%" % [_site_name(), roundi(watched / watch_time * 100.0)]
	if watched >= watch_time:
		_complete()


func _complete() -> void:
	is_scouted = true
	_label.text = "%s scouted" % _site_name()
	if _beacon_mat:
		_beacon_mat.albedo_color = Color(0.3, 0.9, 0.4)
		_beacon_mat.emission = Color(0.3, 0.9, 0.4)
	mark_cooling_units(get_tree(), site_id)
	scouted.emit(self)


## Puts a see-through "COOLING UNIT" marker over each of the site's cooling
## units (once; scout perches and drone recon both use it). Returns how many
## got a new marker.
static func mark_cooling_units(tree: SceneTree, site: StringName) -> int:
	var marked := 0
	for node in tree.get_nodes_in_group("cooling_units"):
		var unit := node as Destructible
		if unit == null or unit.site_id != site or unit.has_meta(&"marked"):
			continue
		unit.set_meta(&"marked", true)
		var marker := Label3D.new()
		marker.text = "v COOLING UNIT v"
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.pixel_size = 0.012
		marker.outline_size = 10
		marker.modulate = Color(1.0, 0.35, 0.3)
		marker.position.y = 5.0
		unit.add_child(marker)
		marked += 1
	return marked


func _site_name() -> String:
	for node in get_tree().get_nodes_in_group("datacenter_sites"):
		var site := node as DatacenterSite
		if site.site_id == site_id:
			return site.display_name
	return "the datacenter"


## A big old tree with a plank platform, railings, and a rope ladder.
func _build_tree() -> void:
	_height = 6.5
	var bark := Models.mat(Color(0.35, 0.24, 0.15), &"rough")
	var plank := Models.mat(Color(0.55, 0.4, 0.25), &"rough")
	Models.cylinder(self, 0.55, _height + 2.5, Vector3(0.0, (_height + 2.5) * 0.5, 0.0), bark, 10)
	Models.collider(self, Vector3(1.1, _height + 2.5, 1.1), Vector3(0.0, (_height + 2.5) * 0.5, 0.0))
	var crown := Models.model("res://assets/kenney/nature/tree_oak.glb", 9.0)
	crown.position = Vector3(0.0, _height - 1.0, 0.0)
	add_child(crown)
	# Platform on the trunk, with low rails on three sides.
	var deck := Vector3(0.0, _height, 1.6)
	Models.box(self, Vector3(3.2, 0.15, 3.2), deck, plank)
	Models.collider(self, Vector3(3.2, 0.15, 3.2), deck)
	for rail in [[Vector3(3.2, 0.9, 0.08), Vector3(0.0, 0.5, 1.6)], [Vector3(0.08, 0.9, 3.2), Vector3(1.6, 0.5, 0.0)],
			[Vector3(0.08, 0.9, 3.2), Vector3(-1.6, 0.5, 0.0)]]:
		Models.box(self, rail[0], deck + rail[1], plank)
		Models.collider(self, rail[0], deck + rail[1])
	# Rope ladder down the front.
	_ladder = Vector3(0.0, 0.0, 3.4)
	var rope := Models.mat(Color(0.7, 0.6, 0.4), &"cloth")
	for x in [-0.3, 0.3]:
		Models.box(self, Vector3(0.05, _height, 0.05), Vector3(x, _height * 0.5, 3.25), rope)
	for k in int(_height / 0.4):
		Models.box(self, Vector3(0.6, 0.05, 0.07), Vector3(0.0, 0.3 + k * 0.4, 3.25), plank)
	_top = deck + Vector3.UP * 0.1
	_add_beacon(deck + Vector3(1.4, 1.2, 1.4))


## A squat utility building with a wall ladder and a railed roof.
func _build_rooftop() -> void:
	_height = 5.5
	var wall := Models.mat(Color(0.7, 0.7, 0.68), &"concrete")
	var steel := Models.mat(Color(0.35, 0.37, 0.4), &"metal")
	Models.box(self, Vector3(6.0, _height, 5.0), Vector3(0.0, _height * 0.5, 0.0), wall)
	Models.collider(self, Vector3(6.0, _height, 5.0), Vector3(0.0, _height * 0.5, 0.0))
	Models.box(self, Vector3(1.2, 2.2, 0.08), Vector3(-1.5, 1.1, 2.52), Models.mat(Color(0.3, 0.32, 0.35), &"metal"))  # door
	for rail in [[Vector3(6.0, 1.0, 0.08), Vector3(0.0, _height + 0.5, -2.5)], [Vector3(0.08, 1.0, 5.0), Vector3(3.0, _height + 0.5, 0.0)],
			[Vector3(0.08, 1.0, 5.0), Vector3(-3.0, _height + 0.5, 0.0)], [Vector3(4.0, 1.0, 0.08), Vector3(-1.0, _height + 0.5, 2.5)]]:
		Models.box(self, rail[0], rail[1], steel)
		Models.collider(self, rail[0], rail[1])
	# Rooftop clutter: an AC unit and a vent.
	Models.box(self, Vector3(1.4, 0.9, 1.0), Vector3(-1.8, _height + 0.45, -1.2), steel)
	Models.cylinder(self, 0.3, 0.8, Vector3(1.8, _height + 0.4, -1.5), steel, 10)
	# Steel ladder up the front, right of the door.
	_ladder = Vector3(2.2, 0.0, 3.3)
	for x in [1.95, 2.45]:
		Models.box(self, Vector3(0.06, _height + 1.0, 0.06), Vector3(x, (_height + 1.0) * 0.5, 2.6), steel)
	for k in int((_height + 0.8) / 0.35):
		Models.box(self, Vector3(0.5, 0.04, 0.05), Vector3(2.2, 0.3 + k * 0.35, 2.6), steel)
	_top = Vector3(1.0, _height + 0.05, 0.5)
	_add_beacon(Vector3(2.7, _height + 1.4, -2.2))


## A little lamp that shows it hasn't been scouted yet (turns green after).
func _add_beacon(at: Vector3) -> void:
	_beacon_mat = Models.glow(Color(1.0, 0.8, 0.2), 3.0).duplicate() as StandardMaterial3D
	Models.ball(self, 0.15, at, _beacon_mat)
