extends Node
## Local-only audio (autoload: AudioManager).
## - Creates the Music / SFX / UI buses and applies volumes from Settings.
## - Pooled SFX players (no per-sound node allocation).
## - Music crossfade between two players.
## - SFX lookup order: explicit res:// path -> res://assets/audio/sfx/<id>.ogg|.wav -> procedural synth.
##   The synth gives usable offline placeholder sounds until real assets are dropped in.

const BUSES: Array[String] = ["Music", "SFX", "UI"]
const SFX_POOL_SIZE := 10
const MIX_RATE := 22050

## id: [start_hz, end_hz, seconds, wave, volume, noise_mix]
const SYNTH_SFX := {
	"ui_move": [880.0, 990.0, 0.05, "square", 0.25, 0.0],
	"ui_confirm": [660.0, 1320.0, 0.12, "square", 0.3, 0.0],
	"ui_back": [600.0, 300.0, 0.10, "square", 0.3, 0.0],
	"ui_error": [180.0, 140.0, 0.20, "saw", 0.3, 0.0],
	"punch": [180.0, 60.0, 0.12, "sine", 0.7, 0.35],
	"sword": [2400.0, 600.0, 0.14, "saw", 0.25, 0.6],
	"hit": [300.0, 90.0, 0.08, "square", 0.45, 0.3],
	"explosion": [120.0, 30.0, 0.60, "sine", 0.8, 0.8],
	"jump": [300.0, 700.0, 0.12, "square", 0.25, 0.0],
	"coin": [988.0, 1568.0, 0.18, "square", 0.25, 0.0],
	"level_up": [523.0, 1046.0, 0.45, "triangle", 0.35, 0.0],
	"splash_chime": [392.0, 784.0, 0.90, "triangle", 0.35, 0.0],
	"wave": [200.0, 120.0, 1.20, "sine", 0.3, 0.9],
}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _current_music_path := ""
var _music_tween: Tween
var _sfx_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	_music_a = _make_music_player("MusicA")
	_music_b = _make_music_player("MusicB")
	_active_music = _music_a
	apply_volumes()
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.settings_reloaded.connect(apply_volumes)


func _make_music_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = "Music"
	add_child(p)
	return p


func _ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func has_bus(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) != -1


func set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func apply_volumes() -> void:
	set_bus_volume_linear("Master", float(Settings.get_value("audio", "master_volume")))
	set_bus_volume_linear("Music", float(Settings.get_value("audio", "music_volume")))
	set_bus_volume_linear("SFX", float(Settings.get_value("audio", "sfx_volume")))
	set_bus_volume_linear("UI", float(Settings.get_value("audio", "ui_volume")))


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key.begins_with("audio/"):
		apply_volumes()


# --- SFX ---------------------------------------------------------------------

func play_sfx(id: String, pitch_jitter := 0.0, bus := "SFX") -> void:
	var stream := get_sfx_stream(id)
	if stream == null:
		return
	var p := _sfx_pool[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_pool.size()
	p.stop()
	p.stream = stream
	p.bus = bus
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_ui(id: String) -> void:
	play_sfx(id, 0.0, "UI")


func get_sfx_stream(id: String) -> AudioStream:
	if _sfx_cache.has(id):
		return _sfx_cache[id]
	var stream: AudioStream = null
	if id.begins_with("res://"):
		if ResourceLoader.exists(id):
			stream = load(id) as AudioStream
	else:
		for ext in ["ogg", "wav"]:
			var path := "res://assets/audio/sfx/%s.%s" % [id, ext]
			if ResourceLoader.exists(path):
				stream = load(path) as AudioStream
				break
		if stream == null and SYNTH_SFX.has(id):
			var d: Array = SYNTH_SFX[id]
			stream = synth(d[0], d[1], d[2], d[3], d[4], d[5])
	if stream == null:
		push_warning("Unknown SFX '%s'" % id)
		return null
	_sfx_cache[id] = stream
	return stream


## Generates a short 16-bit mono chiptune-style sound effect.
static func synth(start_hz: float, end_hz: float, seconds: float, wave: String,
		volume: float, noise_mix: float) -> AudioStreamWAV:
	var count := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var phase := 0.0
	var attack := int(MIX_RATE * 0.004)
	for i in count:
		var t := float(i) / float(count)
		phase += lerpf(start_hz, end_hz, t) / MIX_RATE
		var p := fmod(phase, 1.0)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if p < 0.5 else -1.0
			"saw":
				s = 2.0 * p - 1.0
			"triangle":
				s = 4.0 * absf(p - 0.5) - 1.0
			_:
				s = sin(TAU * p)
		if noise_mix > 0.0:
			s = lerpf(s, rng.randf_range(-1.0, 1.0), noise_mix)
		var env := pow(1.0 - t, 2.0) * minf(1.0, float(i) / maxf(attack, 1))
		data.encode_s16(i * 2, int(clampf(s * env * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


# --- Music -------------------------------------------------------------------

## Crossfades to a local music file. Missing files stop music with a warning (never crash).
func play_music(path: String, fade := 1.0) -> void:
	if path == _current_music_path and _active_music.playing:
		return
	if not ResourceLoader.exists(path):
		push_warning("Music not found: %s" % path)
		stop_music(fade)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		stop_music(fade)
		return
	_current_music_path = path
	var old := _active_music
	_active_music = _music_b if old == _music_a else _music_a
	_active_music.stream = stream
	_active_music.volume_db = -40.0
	_active_music.play()
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(_active_music, "volume_db", 0.0, fade)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -40.0, fade)
		_music_tween.chain().tween_callback(old.stop)


func stop_music(fade := 0.5) -> void:
	_current_music_path = ""
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		if p.playing:
			_music_tween.tween_property(p, "volume_db", -40.0, fade)
	_music_tween.chain().tween_callback(func() -> void:
		_music_a.stop()
		_music_b.stop())


func current_music() -> String:
	return _current_music_path
