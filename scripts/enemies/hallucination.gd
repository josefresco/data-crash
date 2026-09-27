class_name Hallucination
extends HoloClone
## A chatbot kiosk's hallucinated copy of Brad Hypewell: his turtleneck, as
## a flickering hologram. Pops in one hit, shoots weakly, fades.


func _init() -> void:
	outfit = "brad"
	body_color = Color(0.2, 0.95, 0.85)
	lifetime = 20.0


func _base_color() -> Color:
	return Color(0.2, 0.95, 0.85, 0.45)


func _ready() -> void:
	super()
	_material.albedo_color = _base_color()
	_material.emission = Color(0.15, 0.8, 0.7)
	if randf() < 0.5:
		speak(["As a large language model...", "I'm the real Brad!", "Water is a hallucination."].pick_random())
