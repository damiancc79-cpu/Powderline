extends Node

## Lightweight procedural soundscape. Every required cue has a generated fallback,
## while the bundled CC0 Kenney clips are used opportunistically when present.

const SAMPLE_RATE := 22_050
const ONE_SHOT_POOL_SIZE := 10
const SILENCE_DB := -72.0

var _ski_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _carve_player: AudioStreamPlayer
var _one_shot_players: Array[AudioStreamPlayer] = []
var _cue_streams: Dictionary = {}
var _pool_cursor: int = 0

var _master_volume: float = 0.82
var _sfx_volume: float = 0.88
var _ambient_volume: float = 0.72
var _target_speed_ratio: float = 0.0
var _target_carve: float = 0.0
var _target_brake: float = 0.0
var _is_airborne: bool = false
var _surface: StringName = &"powder"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()
	_build_procedural_library()
	_load_optional_cc0_clips()
	_connect_settings()
	set_process(true)


func _process(delta: float) -> void:
	var response := clampf(delta * 5.5, 0.0, 1.0)
	var snow_loudness := lerpf(0.035, 0.82, _target_speed_ratio)
	if _is_airborne:
		snow_loudness *= 0.06
	match _surface:
		&"ice":
			snow_loudness *= 0.72
		&"packed", &"tracked":
			snow_loudness *= 0.88
		_:
			snow_loudness *= 1.0
	var wind_loudness := lerpf(0.01, 0.95, pow(_target_speed_ratio, 1.35))
	if _is_airborne:
		wind_loudness = minf(wind_loudness + 0.15, 1.0)
	var carve_loudness := maxf(_target_carve * (0.25 + _target_speed_ratio * 0.75), _target_brake * 0.8)
	_set_player_level(_ski_player, snow_loudness * _ambient_volume, response)
	_set_player_level(_wind_player, wind_loudness * _ambient_volume, response)
	_set_player_level(_carve_player, carve_loudness * _ambient_volume, response)
	_ski_player.pitch_scale = lerpf(_ski_player.pitch_scale, 0.78 + _target_speed_ratio * 0.68, response)
	_wind_player.pitch_scale = lerpf(_wind_player.pitch_scale, 0.72 + _target_speed_ratio * 0.78, response)
	_carve_player.pitch_scale = lerpf(_carve_player.pitch_scale, 0.72 + _target_speed_ratio * 0.55 + _target_brake * 0.16, response)


func update_ski_audio(
	speed_mps: float,
	surface: StringName = &"powder",
	carve_amount: float = 0.0,
	brake_amount: float = 0.0,
	is_airborne: bool = false
) -> void:
	_target_speed_ratio = clampf(speed_mps / 38.0, 0.0, 1.0)
	_surface = surface
	_target_carve = clampf(absf(carve_amount), 0.0, 1.0)
	_target_brake = clampf(brake_amount, 0.0, 1.0)
	_is_airborne = is_airborne


func play_cue(cue: StringName, intensity: float = 1.0, pitch_variation: float = 0.045) -> void:
	var canonical := _canonical_cue(cue)
	var stream: AudioStream = _cue_streams.get(canonical) as AudioStream
	if stream == null:
		stream = _cue_streams.get(&"score") as AudioStream
	if stream == null:
		return
	var player := _next_one_shot_player()
	player.stream = stream
	player.volume_db = _level_to_db(clampf(intensity, 0.05, 1.5) * _sfx_volume)
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func stop_all() -> void:
	for player: AudioStreamPlayer in _one_shot_players:
		player.stop()
	_ski_player.stop()
	_wind_player.stop()
	_carve_player.stop()


func _build_players() -> void:
	_ski_player = _make_loop_player("SkiSnowLoop")
	_wind_player = _make_loop_player("WindLoop")
	_carve_player = _make_loop_player("CarveLoop")
	for index: int in range(ONE_SHOT_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Cue%02d" % index
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_one_shot_players.append(player)
	_ski_player.stream = _make_noise_loop(&"snow")
	_wind_player.stream = _make_noise_loop(&"wind")
	_carve_player.stream = _make_noise_loop(&"carve")
	for loop_player: AudioStreamPlayer in [_ski_player, _wind_player, _carve_player]:
		loop_player.volume_db = SILENCE_DB
		loop_player.play()


func _make_loop_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func _build_procedural_library() -> void:
	_cue_streams[&"jump"] = _make_tone_clip(420.0, 0.18, 0.12, 510.0, 5.5)
	_cue_streams[&"airtime"] = _make_tone_clip(570.0, 0.16, 0.05, 700.0, 5.0)
	_cue_streams[&"trick"] = _make_tone_clip(760.0, 0.16, 0.03, 1020.0, 7.0)
	_cue_streams[&"landing"] = _make_tone_clip(115.0, 0.24, 0.72, 70.0, 9.0)
	_cue_streams[&"perfect_landing"] = _make_tone_clip(640.0, 0.40, 0.06, 960.0, 4.8)
	_cue_streams[&"crash"] = _make_tone_clip(84.0, 0.55, 0.92, 48.0, 4.5)
	_cue_streams[&"score"] = _make_tone_clip(720.0, 0.18, 0.02, 880.0, 8.5)
	_cue_streams[&"checkpoint"] = _make_tone_clip(520.0, 0.32, 0.02, 780.0, 5.5)
	_cue_streams[&"finish"] = _make_tone_clip(430.0, 0.72, 0.025, 1120.0, 2.8)
	_cue_streams[&"near_miss"] = _make_tone_clip(920.0, 0.13, 0.16, 630.0, 8.0)


func _load_optional_cc0_clips() -> void:
	var optional := {
		&"crash": "res://assets/external/kenney_impact_sounds/audio/impactSoft_heavy_000.ogg",
		&"score": "res://assets/external/kenney_impact_sounds/audio/impactGeneric_light_000.ogg",
		&"finish": "res://assets/external/kenney_impact_sounds/audio/impactBell_heavy_000.ogg",
	}
	for cue: StringName in optional:
		var path := String(optional[cue])
		if not ResourceLoader.exists(path):
			continue
		var resource := ResourceLoader.load(path)
		if resource is AudioStream:
			_cue_streams[cue] = resource


func _make_noise_loop(kind: StringName) -> AudioStreamWAV:
	var frames := SAMPLE_RATE
	var data := PackedByteArray()
	data.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = hash(kind)
	var filtered := 0.0
	var previous_noise := 0.0
	for frame: int in range(frames):
		var noise := random.randf_range(-1.0, 1.0)
		var sample := 0.0
		match kind:
			&"wind":
				filtered = lerpf(filtered, noise, 0.025)
				sample = filtered * 2.4 + sin(float(frame) * TAU / float(SAMPLE_RATE) * 76.0) * 0.025
			&"carve":
				sample = (noise - previous_noise) * 0.24 + noise * 0.09
			_:
				filtered = lerpf(filtered, noise, 0.32)
				sample = filtered * 0.30 + (noise - previous_noise) * 0.11
		previous_noise = noise
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


func _make_tone_clip(
	start_frequency: float,
	duration: float,
	noise_amount: float,
	end_frequency: float,
	decay_rate: float
) -> AudioStreamWAV:
	var frames := maxi(int(duration * float(SAMPLE_RATE)), 1)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = int(start_frequency * 100.0 + duration * 10_000.0)
	var phase := 0.0
	for frame: int in range(frames):
		var progress := float(frame) / float(frames)
		var frequency := lerpf(start_frequency, end_frequency, progress)
		phase += TAU * frequency / float(SAMPLE_RATE)
		var envelope := exp(-progress * decay_rate)
		var attack := smoothstep(0.0, 0.035, progress)
		var tone := sin(phase) * (1.0 - noise_amount)
		var noise := random.randf_range(-1.0, 1.0) * noise_amount
		var sample := (tone + noise) * envelope * attack * 0.72
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _next_one_shot_player() -> AudioStreamPlayer:
	for offset: int in range(_one_shot_players.size()):
		var index := (_pool_cursor + offset) % _one_shot_players.size()
		if not _one_shot_players[index].playing:
			_pool_cursor = (index + 1) % _one_shot_players.size()
			return _one_shot_players[index]
	var player := _one_shot_players[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _one_shot_players.size()
	return player


func _set_player_level(player: AudioStreamPlayer, linear_level: float, response: float) -> void:
	var target := _level_to_db(linear_level)
	player.volume_db = lerpf(player.volume_db, target, response)


func _level_to_db(level: float) -> float:
	if level <= 0.0001 or _master_volume <= 0.0001:
		return SILENCE_DB
	return maxf(linear_to_db(level * _master_volume), SILENCE_DB)


func _canonical_cue(cue: StringName) -> StringName:
	match cue:
		&"takeoff", &"pop":
			return &"jump"
		&"trick_milestone", &"spin", &"flip", &"grab":
			return &"trick"
		&"perfect", &"perfect_landing":
			return &"perfect_landing"
		&"bank", &"score_bank":
			return &"score"
	return cue


func _connect_settings() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null:
		return
	if save_manager.has_method("get_setting"):
		_master_volume = float(save_manager.call("get_setting", &"master_volume", _master_volume))
		_sfx_volume = float(save_manager.call("get_setting", &"sfx_volume", _sfx_volume))
		_ambient_volume = float(save_manager.call("get_setting", &"ambient_volume", _ambient_volume))
	if save_manager.has_signal("setting_changed"):
		save_manager.connect("setting_changed", Callable(self, "_on_setting_changed"))


func _on_setting_changed(key: StringName, value: Variant) -> void:
	match key:
		&"master_volume":
			_master_volume = float(value)
		&"sfx_volume":
			_sfx_volume = float(value)
		&"ambient_volume":
			_ambient_volume = float(value)
