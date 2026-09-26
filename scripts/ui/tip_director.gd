class_name TipDirector
extends Node
## Contextual help. A short tutorial runs through the first minute, then
## one-time tips fire when the player first gets near something (props, enemy
## types, bosses) or a phase begins. Tips go through Game.tip(), so each shows
## once per session and the settings menu can turn them all off.
## The level adds this as a child; `level` must expose `phase` (TestBlock).

const SCAN_INTERVAL := 0.5
## Proximity tips wait this long into Phase 1 so the tutorial's basics come first.
const SCAN_DELAY := 12.0

## [seconds into Phase 1, key, text]
const TUTORIAL := [
	[2.0, "move", "WASD moves, the mouse aims, Shift sprints, Space jumps. Left click shoots; Q or the mouse wheel switches weapons."],
	[16.0, "deeds", "Help the neighborhood first: the good deeds at the top pay cash and raise TRUST. Trust unlocks the bulldozer and brings more neighbors to help later."],
	[32.0, "cars", "Every car on the block is drivable: walk up to one and press E."],
	[48.0, "grock", "Grock AI cameras watch the block from poles. Shoot them down for cash and goodwill."],
	[64.0, "menus", "V opens the bribe menu. Esc pauses: settings and the full controls list live there."],
]

## Enemy script -> [key, radius, text]. Checked against live hostiles.
static var UNIT_TIPS := {
	SecurityGuard: ["guards", 30.0, "Security guards shoot on sight but miss a lot at range. Break line of sight behind walls, cars, and houses."],
	Police: ["police", 25.0, "Riot police: their shields block most frontal fire. Flank them, stun them, or use explosives and fire."],
	Frost: ["frost", 30.0, "FROST agents abduct neighbors and carry them off. Kill the agent to free its captive before it escapes (trust drops if it does)."],
	FelsaCar: ["felsa", 30.0, "Felsa Cyberdouche: a self-driving truck that rams people. Sidestep it, and an EMP trap sets its battery on fire."],
	SentryTurret: ["sentries", 30.0, "Crapya's roof sentries run on the gas turbines' power. Knock out all three turbines and they shut down."],
	ShamCrapman: ["sham", 40.0, "Sham Crapman hides in a force field fed by projection drones. Shoot the drones first; blast damage breaks the pylons."],
	FarkPod: ["fark", 40.0, "Fark's pod: glass halves bullets and surveillance drones track you. Kill the drones, ignore the holo clones."],
	HarryPerckerson: ["harry", 45.0, "Harry hides behind a glass boardroom. Only heavy explosives (rockets, grenades, C4) crack it; then he's exposed."],
	ReplyGuy: ["reply_guy_seen", 20.0, "Reply Guys: slow, soft, and loud. They swarm whoever bothers Elmo and log off the moment he goes down."],
}

var level: Node

var _elapsed := 0.0
var _scan_left := 0.0
var _tutorial_index := 0
var _last_phase := -1


func _process(delta: float) -> void:
	if level == null or not is_instance_valid(level):
		return
	var phase: int = level.get("phase")
	if phase == 0:  # ACTIVISM
		_elapsed += delta
		while _tutorial_index < TUTORIAL.size() and _elapsed >= float(TUTORIAL[_tutorial_index][0]):
			var step: Array = TUTORIAL[_tutorial_index]
			Game.tip(step[1], step[2])
			_tutorial_index += 1
	if phase != _last_phase:
		_last_phase = phase
		_phase_tip(phase)
	_scan_left -= delta
	if _scan_left <= 0.0 and (phase != 0 or _elapsed >= SCAN_DELAY):
		_scan_left = SCAN_INTERVAL
		_scan()


func _phase_tip(phase: int) -> void:
	match phase:
		1:
			Game.tip("assault", "The assault is on. Plant C4 [G] on the cooling units east of the building, then get clear. Guards and dogs will come for you.")
		3:
			Game.tip("build", "Build phase: B opens the build menu, 1-4 picks a structure, R rotates, left click places. Turrets won't fire near protesters; talk those down with E.")
			Game.tip("repair", "Hold F near a damaged structure to repair it ($1 per 5 hp). Neighbors repair too, but not while hostiles are close. N starts the wave early.")
		4:
			Game.tip("waves", "Hostiles march on the green core. If a wave drags on they rush it, so keep turrets covering every approach.")


func _scan() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var eye: Vector3 = player.vehicle.global_position if player.vehicle else player.global_position
	_near_group(eye, "strays", 10.0, "stray", "This stray won't bite. Give it a treat [T] and it will follow you and guard the block.")
	_near_group(eye, "fixables", 10.0, "water_main", "A sabotaged water main. Hold F next to it to fix it.")
	_near_group(eye, "grock_cameras", 18.0, "grock_near", "A Grock camera. Shoot it down: cash, and the neighbors trust you more.")
	_near_group(eye, "gas_turbines", 26.0, "turbines", "Gas turbines power the datacenter and pour out smog. Small arms bounce off: use the rifle, explosives, or the bulldozer.")
	_near_group(eye, "cooling_units", 22.0, "cooling", "Destroy all three cooling units to collapse the datacenter. Crapya's control room shields them until you break it.")
	_near_group(eye, "protesters", 16.0, "orange_hats", "Orange Hat protesters picket your structures and body-block bullets. Don't shoot them (trust drops); press E to talk them down.")
	_near_group(eye, "scout_points", 12.0, "scout", "Stand in the ring to scout the datacenter: it marks the cooling units through walls.")
	for node in get_tree().get_nodes_in_group("interactables"):
		var thing := node as Node3D
		if thing is SecurityCache and eye.distance_to(thing.global_position) < 14.0:
			Game.tip("cache", "Corporate security keeps a weapons cache here. Walk up and press E to take the rocket launcher.")
		elif thing is GunShow and eye.distance_to(thing.global_position) < 12.0:
			Game.tip("gunshow", "The weekend gun show: press E at the stall to buy a machine gun, then grenade packs.")
	var fence_center := Vector3(0.0, 0.0, -31.0)
	if level.get("phase") == 0 and Vector2(eye.x - fence_center.x, eye.z - fence_center.z).length() < 32.0:
		Game.tip("fence", "The datacenter fence. Ram it with a car at speed or plant C4 [G] on a panel. Breaching it starts the assault.")
	for node in get_tree().get_nodes_in_group("hostiles"):
		var unit := node as Enemy
		if unit == null:
			continue
		for kind: Script in UNIT_TIPS:
			if is_instance_of(unit, kind):
				var info: Array = UNIT_TIPS[kind]
				if not Game.has_seen_tip(info[0]) and eye.distance_to(unit.global_position) < float(info[1]):
					Game.tip(info[0], info[2])
	if player.health < player.max_health * 0.3:
		Game.tip("low_health", "Low health! Break line of sight and let the fight come to you. Driving a car soaks a lot of damage.")


func _near_group(eye: Vector3, group: String, radius: float, key: String, text: String) -> void:
	if Game.has_seen_tip(key):
		return
	for node in get_tree().get_nodes_in_group(group):
		var thing := node as Node3D
		if thing and thing.is_visible_in_tree() and eye.distance_to(thing.global_position) < radius:
			Game.tip(key, text)
			return
