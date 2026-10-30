extends Node
## Music (crossfaded, looped OGG) and pooled SFX on dedicated buses.
## Browser audio starts only after the first user gesture (title "press any key").

const MUSIC_DIR := "res://assets/audio/music/%s.ogg"
const SFX_DIR := "res://assets/audio/sfx/%s.wav"
const POOL := 8

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current: AudioStreamPlayer
var _current_id: String = ""
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _cache: Dictionary = {}
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_current = _music_a
	for i in POOL:
		_sfx.append(_make_player("SFX"))
	apply_volumes()
	Settings.changed.connect(func(k: String) -> void:
		if k.ends_with("_volume"):
			apply_volumes())


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _lin_db(float(Settings.get_value("music_volume")) * 0.8))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _lin_db(float(Settings.get_value("sfx_volume")) * 0.8))


func _lin_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	_cache[path] = s
	return s


func play_music(id: String, fade: float = 0.8) -> void:
	if id == _current_id:
		return
	_current_id = id
	var stream: AudioStream = _load(MUSIC_DIR % id) if id != "" else null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var old := _current
	var nxt := _music_b if _current == _music_a else _music_a
	_current = nxt
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if stream:
		nxt.stream = stream
		nxt.volume_db = -40.0
		nxt.play()
		_tween.tween_property(nxt, "volume_db", 0.0, fade)
	if old.playing:
		_tween.tween_property(old, "volume_db", -40.0, fade)
		_tween.chain().tween_callback(old.stop)
	else:
		_tween.tween_interval(0.01)


func current_music() -> String:
	return _current_id


func stop_music(fade: float = 0.6) -> void:
	play_music("", fade)


func sfx(id: String, pitch: float = 1.0) -> void:
	var stream := _load(SFX_DIR % id)
	if stream == null:
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = pitch
	p.play()
