extends Node
## Звуки и музыка (автозагрузка «Sfx»). Файлы — assets/audio/*.ogg (синтезированы tools/gen_audio.py).

var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)


func _stream(n: String) -> AudioStream:
	if not _cache.has(n):
		var path := "res://assets/audio/%s.ogg" % n
		_cache[n] = load(path) if ResourceLoader.exists(path) else null
	return _cache[n]


## Короткий звук. pitch — высота (1 = обычная), vol — громкость в дБ.
func play(n: String, pitch: float = 1.0, vol: float = 0.0) -> void:
	if not Save.sound:
		return
	var s := _stream(n)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.volume_db = vol
	p.play()


## Фоновая музыка по кругу: "music_menu" или "music_level". Смена — с плавным переходом.
func music(n: String) -> void:
	if n == _music_name and _music.playing:
		return
	_music_name = n
	var s := _stream(n)
	if s is AudioStreamOggVorbis:
		s.loop = true
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, 0.3)
	tw.tween_callback(func() -> void:
		_music.stream = s
		_music.pitch_scale = 1.0
		if Save.music and s:
			_music.play()
		else:
			_music.stop())
	tw.tween_property(_music, "volume_db", -9.0, 0.4)


func refresh_music() -> void:
	if Save.music:
		if not _music.playing and _music.stream:
			_music.play()
	else:
		_music.stop()


## Ускорить музыку, когда мало ходов.
func tense(on: bool) -> void:
	create_tween().tween_property(_music, "pitch_scale", 1.12 if on else 1.0, 0.5)
