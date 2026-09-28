class_name ScoutPoint
extends Node3D
## A vantage point overlooking one datacenter (outside its front-right fence
## corner, where the cooling units are in view): a big tree with a treehouse
## platform, or a utility building's roof. [E] at the ladder climbs up (and
## back down). Up top, hold [Z] for the binoculars and spot the site's
## pieces (see Spotting); every cooling unit spotted scouts the site.

signal scouted(point: ScoutPoint)

enum Style { TREE, ROOFTOP }

@export var style := Style.TREE
## The site this perch overlooks (its cooling units get marked).
@export var site_id := &"felsa"
## How close to the top spot counts as "on the perch".
@export var radius := 2.2

var is_scouted := false

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
	_label.text = "Scout %s\n[Z] binoculars" % _site_name()
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
		Game.tip("scout_perch", "Up here you can see the whole site. Hold Z for your binoculars and keep the reticle on each cooling unit to mark it, then [E] to climb down.")
	Sfx.play(&"hit_wood", player.global_position, -6.0, 0.8)


func on_perch(player: Node3D) -> bool:
	var offset := player.global_position - top_spot()
	return absf(offset.y) < 1.6 and Vector2(offset.x, offset.z).length() <= radius


func _process(_delta: float) -> void:
	if is_scouted or Engine.get_process_frames() % 20 != 0:
		return
	var done := Spotting.progress(get_tree(), site_id)
	if done.x > 0:
		_label.text = "Scouting %s: %d/%d spotted" % [_site_name(), done.x, done.y]


func _complete() -> void:
	is_scouted = true
	_label.text = "%s scouted" % _site_name()
	if _beacon_mat:
		_beacon_mat.albedo_color = Color(0.3, 0.9, 0.4)
		_beacon_mat.emission = Color(0.3, 0.9, 0.4)
	mark_cooling_units(get_tree(), site_id)
	scouted.emit(self)


## Spots every one of the site's cooling units (a see-through marker and a
## minimap target; drone recon uses it). Returns how many were new.
static func mark_cooling_units(tree: SceneTree, site: StringName) -> int:
	var marked := 0
	for node in tree.get_nodes_in_group("cooling_units"):
		var unit := node as Destructible
		if unit == null or unit.site_id != site or Spotting.is_spotted(unit):
			continue
		if not unit.has_meta(&"scout_site"):
			unit.set_meta(&"scout_site", site)
			unit.set_meta(&"scout_label", "Cooling unit")
		if Spotting.spot(unit):
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
	var plank := Models.mat(Color(0.8, 0.68, 0.55), &"wood")
	Models.cylinder(self, 0.55, _height + 2.5, Vector3(0.0, (_height + 2.5) * 0.5, 0.0), bark, 10)
	Models.collider(self, Vector3(1.1, _height + 2.5, 1.1), Vector3(0.0, (_height + 2.5) * 0.5, 0.0))
	# The canopy sits above the platform so the view from it is clear.
	var crown := Models.model("res://assets/kenney/nature/tree_oak.glb", 8.0)
	crown.position = Vector3(0.0, _height + 0.6, 0.0)
	add_child(crown)
	# Platform on the site side of the trunk (-Z: local +Z faces the street),
	# with low rails on the far side and the left.
	var deck := Vector3(0.0, _height, -1.6)
	Models.box(self, Vector3(3.2, 0.15, 3.2), deck, plank)
	Models.collider(self, Vector3(3.2, 0.15, 3.2), deck)
	for rail in [[Vector3(3.2, 0.9, 0.08), Vector3(0.0, 0.5, -1.6)], [Vector3(0.08, 0.9, 3.2), Vector3(-1.6, 0.5, 0.0)]]:
		Models.box(self, rail[0], deck + rail[1], plank)
		Models.collider(self, rail[0], deck + rail[1])
	# Rope ladder down the right side of the platform.
	_ladder = Vector3(2.5, 0.0, -1.6)
	var rope := Models.mat(Color(0.7, 0.6, 0.4), &"cloth")
	for z: float in [-1.9, -1.3]:
		Models.box(self, Vector3(0.05, _height, 0.05), Vector3(1.65, _height * 0.5, z), rope)
	for k in int(_height / 0.4):
		Models.box(self, Vector3(0.07, 0.05, 0.6), Vector3(1.65, 0.3 + k * 0.4, -1.6), plank)
	_top = deck + Vector3.UP * 0.1
	_add_beacon(deck + Vector3(-1.4, 1.2, -1.4))


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
