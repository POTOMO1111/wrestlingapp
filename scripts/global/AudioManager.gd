extends Node

# ============================================================
#  AudioManager.gd
#  オーディオ・BGM・効果音・バスを一元管理するシステム
# ============================================================

var master_bus_idx : int
var bgm_bus_idx : int
var sfx_bus_idx : int

var tracks : Dictionary = {}
var _current_bgm_player : AudioStreamPlayer = null
var _is_ducking : bool = false
var _normal_bgm_db : float = 0.0
var _ducked_bgm_db : float = -15.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # ポーズ中も音やフェードを行えるようにする
	_setup_audio_buses()
	_load_tracks()
	
	_current_bgm_player = AudioStreamPlayer.new()
	_current_bgm_player.bus = "BGM"
	add_child(_current_bgm_player)

# 起動時に自動でBGM・SFXバスを作成
func _setup_audio_buses() -> void:
	master_bus_idx = AudioServer.get_bus_index("Master")
	
	# BGM Bus
	bgm_bus_idx = AudioServer.get_bus_count()
	AudioServer.add_bus(bgm_bus_idx)
	AudioServer.set_bus_name(bgm_bus_idx, "BGM")
	AudioServer.set_bus_send(bgm_bus_idx, "Master")
	
	# SFX Bus
	sfx_bus_idx = AudioServer.get_bus_count()
	AudioServer.add_bus(sfx_bus_idx)
	AudioServer.set_bus_name(sfx_bus_idx, "SFX")
	AudioServer.set_bus_send(sfx_bus_idx, "Master")

# MP3ファイルをロードし、自動ループ設定を付与する
func _load_tracks() -> void:
	tracks["title"] = _load_mp3("res://audio/bgm/Pixel Dust Rodeo.mp3")
	tracks["select"] = _load_mp3("res://audio/bgm/Silver Cartridge Highway.mp3")
	tracks["battle"] = _load_mp3("res://audio/bgm/Silver Cartridge Highway2.mp3")
	
	for key in tracks.keys():
		if tracks[key] != null:
			tracks[key].loop = true

func _load_mp3(path: String) -> AudioStreamMP3:
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var stream = AudioStreamMP3.new()
		stream.data = file.get_buffer(file.get_length())
		return stream
	return null

# クロスフェード対応のBGM再生
func play_bgm(track_name: String, fade_time: float = 1.0) -> void:
	if not tracks.has(track_name):
		push_error("BGM Track not found: ", track_name)
		return
		
	var new_stream = tracks[track_name]
	
	# すでに同じ曲が流れているなら何もしない
	if _current_bgm_player.stream == new_stream and _current_bgm_player.playing:
		return
		
	# 前の曲が流れていればフェードアウト
	if _current_bgm_player.playing:
		var tween_out = create_tween()
		tween_out.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_out.tween_property(_current_bgm_player, "volume_db", -80.0, fade_time / 2.0).set_trans(Tween.TRANS_SINE)
		await tween_out.finished
		
	_current_bgm_player.stream = new_stream
	_current_bgm_player.play()
	
	# 新しい曲をフェードイン
	var target_db = _ducked_bgm_db if _is_ducking else _normal_bgm_db
	_current_bgm_player.volume_db = -80.0
	var tween_in = create_tween()
	tween_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween_in.tween_property(_current_bgm_player, "volume_db", target_db, fade_time / 2.0).set_trans(Tween.TRANS_SINE)

# ポーズ時などの音量ダッキング（一時低下）
func set_ducking(active: bool) -> void:
	if _is_ducking == active:
		return
		
	_is_ducking = active
	var target_db = _ducked_bgm_db if active else _normal_bgm_db
	
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_current_bgm_player, "volume_db", target_db, 0.4).set_trans(Tween.TRANS_SINE)
