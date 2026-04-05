extends Node

# ============================================================
#  GameEnums.gd
#  AutoLoad として登録。全シーンからアクセス可能なグローバル列挙型。
# ============================================================

enum ActionType {
	NONE,
	PUNCH,      # パンチ：発生速い・判定普通
	KICK,       # キック：発生遅い・判定強い
	GRAPPLE,    # グラップリング：発生遅い・ガード貫通
	GUARD       # ガード：発生速い・打撃2種を止める
}

enum HitResult {
	WHIFF,           # 空振り
	BLOCKED,         # ガード成功
	HIT,             # 通常ヒット
	COUNTER_HIT,     # カウンターヒット（相手行動中にヒット）
	GRAPPLE_SUCCESS, # グラップル成立
	GRAPPLE_FAIL     # グラップル失敗
}

enum DamageLayer {
	RECOVERABLE,  # 回復可能HP（打撃によるダメージ先）
	PERMANENT     # 回復不可能HP（グラップルによるダメージ先）
}

enum CharacterState {
	IDLE,
	WALKING,
	RUNNING,
	ATTACKING,       # 打撃モーション中
	GUARDING,        # ガード中
	GRAPPLING,       # グラップル中（攻め側）
	GRAPPLED,        # グラップル中（受け側）
	HIT_STUN,        # ヒットスタン（のけぞり中）
	KNOCKDOWN,       # ダウン中
	GETTING_UP,      # 起き上がり中
	INCAPACITATED,   # 行動不可状態（回復可能HP枯渇）
	KO               # KO（回復不可能HP枯渇）
}

enum GrapplePosition {
	NEUTRAL,   # 初期ロックアップ
	DOMINANT,  # 完全優位（攻め側が技をかけられる状態）
	SUBDUED    # 完全劣位（受け側）
}

enum RoundState {
	WAITING,
	FIGHTING,
	ROUND_END,
	MATCH_END
}

enum PlayerID {
	PLAYER_ONE,
	PLAYER_TWO
}
