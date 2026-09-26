extends Node
## Sound effects. Cues are named after files in assets/audio/ (<cue>_<n>.wav or
## .ogg, n = random variants; see tools/generate_sfx.py). Positional one-shots
## come from a small pool, loops attach to their host, and each cue caps its
## simultaneous voices so a wave's worth of guards doesn't clip the mix.
## Buses: Master > Music, SFX, UI, Ambience (volumes in settings.cfg [audio]).

const AUDIO_DIR := "res://assets/audio/"
const BUSES: Array[String] = ["Music", "SFX", "UI", "Ambience"]
const MAX_VOICES_PER_CUE := 4
const POOL_SIZE := 40
const SETTINGS_PATH := "user://settings.cfg"

## Bus volumes, 0..1 linear. "Master" included.
var volumes := {"Master": 0.8, "Music": 0.7, "SFX": 0.9, "UI": 0.8, "Ambience": 0.8}

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _voices := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	_load_settings()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 90.0
		player.unit_size = 8.0
		player.attenuation_filter_cutoff_hz = 6000.0
		player.finished.connect(_on_voice_finished.bind(player))
		add_child(player)
		_pool.append(player)
	for i in 6:
		var ui_player := AudioStreamPlayer.new()
		ui_player.bus = "UI"
		add_child(ui_player)
		_ui_players.append(ui_player)


## Plays a random variant of `cue` at `at`. Returns the player, or null when
## the cue is missing or over its voice cap.
func play(cue: StringName, at: Vector3, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> AudioStreamPlayer3D:
	var stream := _pick(cue)
	if stream == null or _voices.get(cue, 0) >= MAX_VOICES_PER_CUE:
		return null
	var player := _free_voice()
	if player == null:
		return null
	player.stream = stream
	player.global_position = at
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter)), 0.05)
	player.set_meta(&"cue", cue)
	_voices[cue] = _voices.get(cue, 0) + 1
	player.play()
	return player


## Non-positional sound on the UI bus (clicks, jingles, tips).
func ui(cue: StringName, volume_db := 0.0, bus := "UI") -> void:
	var stream := _pick(cue)
	if stream == null:
		return
	for player in _ui_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.bus = bus
			player.play()
			return


## A looping positional sound parented to `host` (engines, turbines, fires).
## Stop it by freeing it or with .stop(); pitch/volume can be driven live.
func loop(host: Node3D, cue: StringName, volume_db := 0.0, bus := "SFX") -> AudioStreamPlayer3D:
	var stream := _pick(cue)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = _looping(stream)
	player.bus = bus
	player.volume_db = volume_db
	player.max_distance = 110.0
	player.unit_size = 10.0
	player.autoplay = true
	host.add_child(player)
	return player


## A looping non-positional sound (ambience beds).
func loop_2d(host: Node, cue: StringName, volume_db := 0.0, bus := "Ambience") -> AudioStreamPlayer:
	var stream := _pick(cue)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = _looping(stream)
	player.bus = bus
	player.volume_db = volume_db
	player.autoplay = true
	host.add_child(player)
	return player


func has_cue(cue: StringName) -> bool:
	return not _variants(cue).is_empty()


func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections
	for bus: String in volumes:
		config.set_value("audio", bus, volumes[bus])
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		for bus: String in volumes:
			volumes[bus] = float(config.get_value("audio", bus, volumes[bus]))
	for bus: String in volumes:
		_apply_volume(bus)


func _apply_volume(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var linear: float = volumes[bus]
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


func _pick(cue: StringName) -> AudioStream:
	var list := _variants(cue)
	return null if list.is_empty() else list.pick_random()


func _variants(cue: StringName) -> Array:
	if not _streams.has(cue):
		var list := []
		for n in 12:
			var found := false
			for ext in ["wav", "ogg"]:
				var path := "%s%s_%d.%s" % [AUDIO_DIR, cue, n, ext]
				if ResourceLoader.exists(path):
					list.append(load(path))
					found = true
					break
			if not found:
				break
		if list.is_empty():
			push_warning("Sfx: no sound files for cue '%s'" % cue)
		_streams[cue] = list
	return _streams[cue]


func _looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		return wav
	if stream is AudioStreamOggVorbis:
		var ogg := (stream as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		ogg.loop = true
		return ogg
	return stream


func _free_voice() -> AudioStreamPlayer3D:
	for player in _pool:
		if not player.playing:
			if player.has_meta(&"cue"):
				_release(player)
			return player
	return null


func _on_voice_finished(player: AudioStreamPlayer3D) -> void:
	_release(player)


func _release(player: AudioStreamPlayer3D) -> void:
	var cue: StringName = player.get_meta(&"cue", &"")
	player.remove_meta(&"cue")
	if _voices.get(cue, 0) > 0:
		_voices[cue] -= 1
