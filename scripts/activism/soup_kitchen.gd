class_name SoupKitchen
extends Node3D
## A shift at the soup kitchen (placed at the building's lot origin: +Z out
## the door, the serving counter along the back). [E] at the counter puts on
## an apron; then hungry neighbors come in one at a time, and [E] ladles each
## one a bowl. They eat at the long tables and head out. Serving
## `bowls_needed` completes the deed. Walking away pauses the line.

signal served(count: int)
signal shift_done

@export var bowls_needed := 6
@export var reach := 2.8
## Seconds between neighbors coming in.
@export var arrival_gap := 0.8
## Where the server stands (behind the counter) and where diners wait (local).
@export var server_spot := Vector3(0.0, 0.0, -4.2)
@export var window_spot := Vector3(0.0, 0.0, -2.3)
@export var door_spot := Vector3(0.0, 0.0, 4.8)

const OUTFITS := ["resident_a", "resident_b", "resident_c", "resident_d", "old_lady", "townsperson", "kid"]
const THANKS := ["Bless you.", "First hot meal this week.", "Smells amazing!", "Thank you, neighbor.",
	"The water bill ate my grocery money.", "You're a good one."]

var on_shift := false
var bowls := 0
var is_done := false

var _waiting: CharacterModel = null
var _walking := false
var _next_left := 0.0
var _player: Player


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("soup_kitchens")
	set_meta(&"poi", "S")
	set_meta(&"poi_color", Color(0.5, 0.85, 0.45))
	add_to_group("map_pois")
	# Steam off the pots.
	Vfx.steam_jet(self, window_spot + Vector3(0.0, 1.5, -1.0), 1.2).emitting = true


func in_reach(player: Node3D) -> bool:
	if is_done:
		return false
	var counter := global_transform * Vector3(0.0, 0.0, -3.3)
	return player.global_position.distance_to(counter) <= reach


func offer_text(_player: Player) -> String:
	if not on_shift:
		return "[E] Put on an apron and serve a shift at the soup kitchen"
	if _waiting and not _walking:
		return "[E] Ladle a bowl of soup (%d/%d)" % [bowls, bowls_needed]
	return "Serving... (%d/%d) next neighbor coming in" % [bowls, bowls_needed]


func interact(player: Player) -> void:
	_player = player
	if not on_shift:
		start_shift()
	elif _waiting and not _walking:
		serve()


func start_shift() -> void:
	if on_shift or is_done:
		return
	on_shift = true
	_next_left = 0.5
	Sfx.ui(&"open", -4.0)
	Game.notify("Apron on. Neighbors are lining up: [E] to serve each one.", 4.0)
	Game.tip("soup", "Soup kitchen: stay by the counter and press E as each neighbor steps up. Six bowls finishes the shift.")


## Ladles a bowl for whoever is at the window. Returns true if someone was served.
func serve() -> bool:
	if not on_shift or _waiting == null or _walking:
		return false
	var diner := _waiting
	_waiting = null
	bowls += 1
	Sfx.play(&"hit_soft", global_transform * window_spot, -6.0, 1.4)
	diner.play_action(&"yes")
	var line := Label3D.new()
	line.text = THANKS.pick_random()
	line.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	line.pixel_size = 0.006
	line.outline_size = 8
	line.position.y = 2.1
	diner.add_child(line)
	HudOverlay.as_bubble(line)
	if Game.district:
		Game.district.trust += 0.008
	# A bowl in hand, then a seat at a table, eat, and out the door.
	Models.cylinder(diner.anchor(&"hand_r"), 0.08, 0.06, Vector3.ZERO, Models.mat(Color(0.95, 0.95, 0.92), &"paint"), 10)
	var seat := Vector3(-3.2 if bowls % 2 == 0 else 3.2, 0.0, 0.4 + (bowls % 3) * 1.2) + Vector3(0.9 if bowls % 2 == 0 else -0.9, 0.0, 0.0)
	var tween := diner.create_tween()
	_walk(tween, diner, diner.position, seat)
	tween.tween_callback(func() -> void:
		line.queue_free()
		diner.set_upper(&"consume"))
	tween.tween_interval(6.0)
	tween.tween_callback(func() -> void: diner.set_upper(&"", 0.0))
	_walk(tween, diner, seat, door_spot)
	tween.tween_callback(diner.queue_free)
	served.emit(bowls)
	_next_left = arrival_gap
	if bowls >= bowls_needed:
		on_shift = false
		is_done = true
		shift_done.emit()
	return true


## The neighbor at the window (tests serve them directly).
func waiting_diner() -> CharacterModel:
	return _waiting if not _walking else null


func _process(delta: float) -> void:
	if not on_shift:
		return
	if _player and is_instance_valid(_player) and _player.global_position.distance_to(global_transform * server_spot) > 9.0:
		return  # the line waits for the server
	if _waiting == null:
		_next_left -= delta
		if _next_left <= 0.0:
			_admit()


## Next neighbor walks in from the door to the window.
func _admit() -> void:
	var diner := CharacterModel.create(OUTFITS.pick_random())
	diner.position = door_spot
	add_child(diner)
	_waiting = diner
	_walking = true
	var tween := diner.create_tween()
	_walk(tween, diner, door_spot, window_spot)
	tween.tween_callback(func() -> void:
		_walking = false
		diner.rotation.y = 0.0)  # characters face -Z: toward the counter


## Tween a walk (facing the way, walk clip), then stand.
func _walk(tween: Tween, diner: CharacterModel, from: Vector3, to: Vector3) -> void:
	var flat := to - from
	flat.y = 0.0
	tween.tween_callback(func() -> void:
		if flat.length() > 0.01:
			diner.rotation.y = atan2(-flat.x, -flat.z)
		diner.set_motion(0.6))
	tween.tween_property(diner, "position", to, maxf(flat.length() / 2.4, 0.1))
	tween.tween_callback(func() -> void: diner.set_motion(0.0))
