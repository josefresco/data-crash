class_name DistrictAudio
extends AudioStreamPlayer
## Procedural datacenter drone: low hum plus beating overtones and fan hiss.
## Loudness follows Game.district.noise, so taking down the datacenter
## audibly quiets the neighborhood. No audio assets needed.

@export var mix_rate := 22050.0
@export var base_frequency := 55.0
## Volume at noise = 1.
@export var max_volume := 0.5

var _playback: AudioStreamGeneratorPlayback
var _phases := PackedFloat32Array([0.0, 0.0, 0.0])
var _gain := 0.0
var _birds: AudioStreamPlayer


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = mix_rate
	generator.buffer_length = 0.15
	stream = generator
	bus = "Ambience"
	play()
	_birds = Sfx.loop_2d(self, &"birds_loop", -60.0)
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(delta: float) -> void:
	if _playback == null:
		return
	var noise := Game.district.noise if Game.district else 0.0
	var target_gain := noise * max_volume
	_gain = lerpf(_gain, target_gain, 1.0 - exp(-1.5 * delta))
	if _birds:
		# Birdsong only once the smog lifts.
		var smog := Game.district.smog if Game.district else 1.0
		var clean := clampf((0.55 - smog) / 0.45, 0.0, 1.0)
		_birds.volume_db = lerpf(_birds.volume_db, linear_to_db(maxf(clean * 0.8, 0.0001)), 1.0 - exp(-0.8 * delta))

	# Fundamental, octave, and a slightly detuned fifth that beats against it.
	var steps := PackedFloat32Array([
		base_frequency / mix_rate, base_frequency * 2.0 / mix_rate, base_frequency * 1.51 / mix_rate])
	for i in _playback.get_frames_available():
		var sample := sin(_phases[0] * TAU) * 0.55 + sin(_phases[1] * TAU) * 0.25 \
			+ sin(_phases[2] * TAU) * 0.15 + randf_range(-0.06, 0.06)
		for p in 3:
			_phases[p] = fmod(_phases[p] + steps[p], 1.0)
		var value := sample * _gain
		_playback.push_frame(Vector2(value, value))
