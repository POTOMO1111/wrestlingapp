extends Node3D

func _ready() -> void:
	AudioManager.play_bgm("battle")
	
	# 動的スポーン処理
	_spawn_characters()
	
	# ゲームマネージャーに試合開始を通知
	GameManager.start_match()

func _spawn_characters() -> void:
	# 例外的に、両方同じモックアップモデルを使用（将来的に GameManager.p1_character_id で分岐する）
	var char_scene = load("res://scenes/characters/player.tscn")
	if char_scene == null:
		push_error("Failed to load character scene!")
		return
		
	# 1P (左下付近から右上向き)
	var p1 = char_scene.instantiate()
	p1.player_id = 1
	p1.is_dummy = false
	p1.name = "Player1_" + GameManager.p1_character_id
	p1.transform.origin = Vector3(0, 1, 3.0)
	add_child(p1)
	
	# 【重要】動的生成した場合は明示的にカメラをアクティブ化しないと画面が灰色になる
	var cam = p1.get_node_or_null("SpringArm3D/Camera3D")
	if cam:
		cam.current = true
		
	GameManager.register_fighter(p1)
	
	# 2P (右上付近から左下向き)
	var p2 = char_scene.instantiate()
	p2.player_id = 2
	p2.is_dummy = true # 当面はCPUダミーを配置
	p2.name = "Player2_" + GameManager.p2_character_id
	p2.transform.origin = Vector3(0, 1, -3.0)
	p2.rotation.y = PI # 向かい合わせる (180度回転)
	add_child(p2)
	
	GameManager.register_fighter(p2)
