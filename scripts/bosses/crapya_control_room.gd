class_name CrapyaControlRoom
extends Destructible
## Boss (Phase 2): Crapya Butella, Cloud Infrastructure Titan, runs the
## datacenter's automated defenses from a glass control room. While it
## stands: cooling units are shielded, roof sentries fire, steam vents blast,
## and rack crushers slam. Pistol and shotgun rounds bounce off the glass;
## use the rifle, explosives, or the bulldozer.

signal defenses_offline

const LINES := [
	"Uptime is a human right. For servers.",
	"My racks have better healthcare than you.",
	"Scaling... scaling... you're not in the SLA.",
	"Please hold. Your eviction is important to us.",
	"Five nines of availability. Zero nines of empathy.",
]
const SHIELD_META := &"crapya_shield"

@export var boss_name := "CRAPYA BUTELLA"
@export var shielded_group := "cooling_units"
@export var defenses_group := "crapya_defenses"
@export var cash_reward := 300

var _speech: Label3D
var _line_left := 0.0


func _init() -> void:
	size = Vector3(4.5, 3.2, 4.5)
	color = Color(0.55, 0.75, 0.85)
	opacity = 0.45
	max_health = 700.0
	damage_threshold = 20.0
	chunks = Vector3i(3, 2, 3)
	label = "Crapya's control room"


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	add_to_group("bosses")
	var crapya := CharacterModel.create("crapya", 1.75)
	crapya.position = Vector3(0.0, 0.0, 0.6)
	crapya.rotation.y = PI
	add_child(crapya)
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.3, 0.9, 0.6)
	screen.emission_enabled = true
	screen.emission = Color(0.2, 0.9, 0.5)
	Models.box(self, Vector3(2.5, 1.0, 0.6), Vector3(0.0, 0.5, 1.4), Models.mat(Color(0.15, 0.15, 0.18)))
	Models.box(self, Vector3(2.2, 0.8, 0.05), Vector3(0.0, 1.4, 1.65), screen)
	_speech = Label3D.new()
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.pixel_size = 0.012
	_speech.outline_size = 10
	_speech.no_depth_test = true
	_speech.position.y = size.y + 1.2
	add_child(_speech)
	_speech.text = LINES[0]
	destroyed.connect(_on_destroyed)
	_shield_targets.call_deferred()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or is_destroyed or (site_id != &"" and not Game.is_alarmed(site_id)):
		return
	_line_left -= delta
	if _line_left <= 0.0:
		_line_left = 7.0
		_speech.text = LINES.pick_random()


func _shield_targets() -> void:
	for node in get_tree().get_nodes_in_group(shielded_group):
		var unit := node as Destructible
		if unit == null or unit.has_meta(SHIELD_META) or unit.site_id != site_id:
			continue
		unit.set_meta(&"base_threshold", unit.damage_threshold)
		unit.damage_threshold = 1.0e9
		var bubble_mat := StandardMaterial3D.new()
		bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bubble_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.2)
		var bubble := Models.box(unit, unit.size * 1.15, Vector3.UP * unit.size.y * 0.55, bubble_mat)
		unit.set_meta(SHIELD_META, bubble)


func _on_destroyed(_room: Destructible) -> void:
	for node in get_tree().get_nodes_in_group(shielded_group):
		var unit := node as Destructible
		if unit == null or not unit.has_meta(SHIELD_META):
			continue
		unit.damage_threshold = unit.get_meta(&"base_threshold", 0.0)
		var bubble := unit.get_meta(SHIELD_META) as Node
		if is_instance_valid(bubble):
			bubble.queue_free()
		unit.remove_meta(SHIELD_META)
	for node in get_tree().get_nodes_in_group(defenses_group):
		if node.has_method("shut_down"):
			node.call(&"shut_down")
	Game.add_cash(cash_reward)
	defenses_offline.emit()
