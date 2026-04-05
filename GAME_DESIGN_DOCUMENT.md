# プロレス/MMAアクションゲーム 詳細設計計画書
## Godot 4 実装用エージェント向け仕様書

> **本書の使い方**：各フェーズを順番にAIエージェントへ渡して実装を依頼すること。フェーズ間の依存関係は「前提フェーズ」として明記してある。コード要件はGDScript（Godot 4.x）を前提とする。

---

## 目次

1. [ゲーム概要とアーキテクチャ方針](#1-ゲーム概要とアーキテクチャ方針)
2. [フェーズ1：コアデータ構造とリソース定義](#フェーズ1-コアデータ構造とリソース定義)
3. [フェーズ2：体力・スタミナ管理システム（二層HP）](#フェーズ2-体力スタミナ管理システム二層hp)
4. [フェーズ3：打撃システム（三すくみ）](#フェーズ3-打撃システム三すくみ)
5. [フェーズ4：グラップリングシステム（dominance型）](#フェーズ4-グラップリングシステムdominance型)
6. [フェーズ5：コンボシステム（コンボツリー）](#フェーズ5-コンボシステムコンボツリー)
7. [フェーズ6：キャラクターステートマシン](#フェーズ6-キャラクターステートマシン)
8. [フェーズ7：試合管理・ラウンドシステム](#フェーズ7-試合管理ラウンドシステム)
9. [フェーズ8：HUD・UI](#フェーズ8-hudui)
10. [フェーズ9：KO演出・ラウンド終了処理](#フェーズ9-ko演出ラウンド終了処理)
11. [全体ノード構成図](#全体ノード構成図)
12. [定数・列挙型一覧](#定数列挙型一覧)

---

## 1. ゲーム概要とアーキテクチャ方針

### 1.1 ゲームコンセプト

- **ジャンル**：3D MMA/プロレスアクション（俯瞰視点）
- **プレイスタイル**：1vs1、ラウンド制
- **プラットフォーム**：PC（Godot 4.x）

### 1.2 コアゲームループ

```
ラウンド開始
  └→ 三すくみ入力（パンチ / キック / グラップリング / ガード）
	   └→ ヒット判定 → ダメージ計算 → HP更新
			└→ [回復可能HP枯渇] → 行動不可状態（一時）
			└→ [回復不可能HP枯渇] → KO演出 → ラウンド終了
  └→ コンボ継続判定（最大3ヒット）
  └→ グラップリング中：dominance争い → ダメージ or ポジション遷移
ラウンド終了 → 次ラウンド or 試合終了
```

### 1.3 アーキテクチャ方針

- **シングルトン禁止**：GameManagerのみAutoloadで許可
- **リソースベース設計**：ゲームデータはすべて`Resource`サブクラスで定義
- **ステートマシン**：キャラクターの状態遷移は専用ステートマシンで管理
- **シグナル駆動**：システム間通信はシグナルで疎結合を維持
- **物理処理**：`_physics_process(delta)` 60fps固定 (`Engine.physics_ticks_per_second = 60`)

### 1.4 フォルダ構成（前提）

```
res://
├── scenes/
│   ├── main.tscn               # ルートシーン（既存）
│   ├── characters/
│   │   ├── player.tscn         # プレイヤーキャラ（既存）
│   │   └── opponent.tscn       # 対戦相手
│   └── ui/
│       └── hud.tscn
├── scripts/
│   ├── resources/              # Resourceサブクラス群
│   ├── states/                 # ステートマシン関連
│   ├── systems/                # 各ゲームシステム
│   ├── managers/               # 管理クラス
│   └── ui/                     # HUD・UIスクリプト
└── resources/                  # .tres / .res ファイル群
	├── characters/
	├── attacks/
	└── combos/
```

---

## フェーズ1：コアデータ構造とリソース定義

**前提フェーズ**：なし（最初に実装）

### 1-A. グローバル列挙型定義

**ファイル**：`res://scripts/globals/GameEnums.gd`

このファイルはAutoloadとして登録すること（Project Settings > Autoload）。
クラス名は持たせず、`extends Node`として全シーンからアクセス可能にする。

```gdscript
# 以下の列挙型をすべて定義すること

enum ActionType {
	NONE,
	PUNCH,      # パンチ：発生速い・判定普通
	KICK,       # キック：発生遅い・判定強い
	GRAPPLE,    # グラップリング：発生遅い・ガード貫通
	GUARD       # ガード：発生速い・打撃2種を止める
}

enum HitResult {
	WHIFF,          # 空振り
	BLOCKED,        # ガード成功
	HIT,            # 通常ヒット
	COUNTER_HIT,    # カウンターヒット（相手行動中にヒット）
	GRAPPLE_SUCCESS,# グラップル成立
	GRAPPLE_FAIL    # グラップル失敗（ガード中の相手に試みた等）
}

enum DamageLayer {
	RECOVERABLE,    # 回復可能HP（打撃によるダメージ先）
	PERMANENT       # 回復不可能HP（グラップルによるダメージ先）
}

enum CharacterState {
	IDLE,
	WALKING,
	ATTACKING,      # 打撃モーション中
	GUARDING,       # ガード中
	GRAPPLING,      # グラップル中（攻め側）
	GRAPPLED,       # グラップル中（受け側）
	HIT_STUN,       # ヒットスタン（のけぞり中）
	KNOCKDOWN,      # ダウン中（回復可能HP枯渇後）
	GETTING_UP,     # 起き上がり中
	INCAPACITATED,  # 行動不可状態（回復可能HP枯渇）
	KO              # KO（回復不可能HP枯渇）
}

enum GrapplePosition {
	NEUTRAL,        # 初期ロックアップ
	DOMINANT,       # 完全優位（攻め側が技をかけられる状態）
	SUBDUED         # 完全劣位（受け側）
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
```

---

### 1-B. AttackData リソース

**ファイル**：`res://scripts/resources/AttackData.gd`

攻撃1種類のすべての数値・設定を格納するリソース。`.tres`ファイルとしてエディタから値を設定できるようにすること。

```gdscript
class_name AttackData
extends Resource

# === 基本情報 ===
@export var attack_name: String = ""
@export var action_type: GameEnums.ActionType = GameEnums.ActionType.PUNCH

# === フレームデータ（60fps基準） ===
@export var startup_frames: int = 5    # 発生フレーム（入力→判定発生まで）
@export var active_frames: int = 3     # 判定持続フレーム
@export var recovery_frames: int = 10  # 硬直フレーム（判定消滅→次行動可能まで）

# === ダメージ ===
@export var recoverable_damage: float = 10.0   # 回復可能HPへのダメージ
@export var permanent_damage: float = 0.0      # 回復不可能HPへのダメージ（基本0、グラップルで使用）
@export var stamina_cost: float = 5.0          # 回復可能HP消費（行動コスト）

# === ヒットボックス（CharacterBody3D相対位置） ===
@export var hitbox_size: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var hitbox_offset: Vector3 = Vector3(0.0, 0.0, 0.8)

# === カウンター倍率 ===
@export var counter_hit_multiplier: float = 1.5  # カウンターヒット時のダメージ倍率

# === ヒットスタン ===
@export var hit_stun_frames: int = 12   # 被弾側の硬直フレーム数
@export var block_stun_frames: int = 5  # ガード成功側の硬直フレーム数

# === 有効距離 ===
@export var max_range: float = 1.5  # この距離以内でのみ判定が発生する

# === アニメーション ===
@export var animation_name: String = ""  # AnimationPlayerで再生するアニメ名

# === コンボキャンセル ===
# このAttackDataの後にキャンセルして連携できるActionType一覧
@export var cancel_into: Array[GameEnums.ActionType] = []
```

**作成する `.tres` ファイル一覧**（エディタで値を入力して保存）：

| ファイル名 | action_type | startup_frames | active_frames | recovery_frames | recoverable_damage | stamina_cost |
|---|---|---|---|---|---|---|
| `punch_light.tres` | PUNCH | 4 | 3 | 8 | 8.0 | 3.0 |
| `punch_heavy.tres` | PUNCH | 6 | 4 | 14 | 15.0 | 6.0 |
| `kick_light.tres` | KICK | 10 | 4 | 12 | 12.0 | 5.0 |
| `kick_heavy.tres` | KICK | 14 | 5 | 18 | 20.0 | 8.0 |

---

### 1-C. GrappleData リソース

**ファイル**：`res://scripts/resources/GrappleData.gd`

```gdscript
class_name GrappleData
extends Resource

@export var grapple_name: String = ""

# === フレームデータ ===
@export var startup_frames: int = 18   # グラップルはパンチより発生が遅い
@export var active_frames: int = 5     # 掴み判定持続
@export var recovery_frames: int = 20  # 失敗時の硬直

# === ダメージ（成立時） ===
@export var permanent_damage: float = 15.0   # 回復不可能HPへのダメージ
@export var recoverable_damage: float = 5.0  # 回復可能HPへも若干ダメージ
@export var stamina_cost: float = 12.0        # 行動コスト

# === dominanceへの影響 ===
@export var dominance_gain: float = 0.25  # 成立時に攻め側が得るdominance
@export var dominance_damage_threshold: float = 0.7  # この値以上でダメージ発生

# === グラップル判定 ===
@export var max_range: float = 1.2          # 有効距離（パンチより短い）
@export var can_bypass_guard: bool = true   # ガード貫通フラグ（常にtrue）
@export var hitbox_size: Vector3 = Vector3(0.6, 0.8, 0.6)
@export var hitbox_offset: Vector3 = Vector3(0.0, 0.5, 0.8)

# === アニメーション ===
@export var initiator_animation: String = ""  # 攻め側のアニメ
@export var receiver_animation: String = ""   # 受け側のアニメ

# === dominance中の追加ダメージ倍率 ===
@export var dominant_damage_multiplier: float = 1.4
```

**作成する `.tres` ファイル一覧**：

| ファイル名 | startup_frames | permanent_damage | dominance_gain |
|---|---|---|---|
| `grapple_basic.tres` | 18 | 15.0 | 0.25 |
| `grapple_power.tres` | 22 | 25.0 | 0.35 |

---

### 1-D. CharacterStats リソース

**ファイル**：`res://scripts/resources/CharacterStats.gd`

```gdscript
class_name CharacterStats
extends Resource

@export var character_name: String = "Fighter"

# === 体力設定 ===
@export var max_recoverable_hp: float = 100.0
@export var max_permanent_hp: float = 100.0

# === 回復設定 ===
@export var recoverable_hp_regen_rate: float = 5.0      # 毎秒回復量
@export var recoverable_hp_regen_delay: float = 2.5     # 最後にダメージを受けてから回復開始するまでの秒数

# === 行動不可状態設定 ===
@export var incapacitated_duration: float = 3.0         # 行動不可状態の継続秒数
@export var incapacitated_dominance_penalty: float = 0.6 # 行動不可中のgrapple dominance倍率（大幅低下）

# === 基礎ステータス ===
@export var punch_damage_multiplier: float = 1.0
@export var kick_damage_multiplier: float = 1.0
@export var grapple_damage_multiplier: float = 1.0
@export var defense_multiplier: float = 1.0      # 受けるダメージへの乗数（1.0=等倍）
@export var dominance_gain_rate: float = 1.0     # dominance蓄積速度の倍率
```

**作成する `.tres` ファイル一覧**：

| ファイル名 | character_name | max_recoverable_hp | max_permanent_hp |
|---|---|---|---|
| `stats_balanced.tres` | "Balanced" | 100.0 | 100.0 |
| `stats_grappler.tres` | "Grappler" | 80.0 | 120.0 |
| `stats_striker.tres` | "Striker" | 110.0 | 80.0 |

---

## フェーズ2：体力・スタミナ管理システム（二層HP）

**前提フェーズ**：フェーズ1（CharacterStats, GameEnums）

### 2-A. HealthComponent

**ファイル**：`res://scripts/systems/HealthComponent.gd`

キャラクターノードの子ノードとしてアタッチするコンポーネントノード。

```gdscript
class_name HealthComponent
extends Node

# === 設定 ===
@export var stats: CharacterStats  # エディタでCharacterStatsリソースを割り当てる

# === 現在値（外部からは読み取りのみ。変更はメソッド経由） ===
var current_recoverable_hp: float = 0.0
var current_permanent_hp: float = 0.0

# === 内部タイマー ===
var _regen_timer: float = 0.0     # 回復待機タイマー
var _is_incapacitated: bool = false

# === シグナル定義 ===
signal recoverable_hp_changed(new_value: float, max_value: float)
signal permanent_hp_changed(new_value: float, max_value: float)
signal recoverable_hp_depleted()         # 回復可能HP枯渇 → 行動不可
signal permanent_hp_depleted()           # 回復不可HP枯渇 → KO
signal incapacitation_ended()            # 行動不可状態終了
signal recoverable_hp_recovered(amount: float)  # 回復発生通知

func _ready() -> void:
	# statsが割り当てられていなければエラーログを出してデフォルト値で初期化
	if stats == null:
		push_error("HealthComponent: stats is not assigned on " + get_parent().name)
		stats = CharacterStats.new()
	_reset()

func _physics_process(delta: float) -> void:
	_process_regen(delta)

# --- 公開メソッド ---

func _reset() -> void:
	current_recoverable_hp = stats.max_recoverable_hp
	current_permanent_hp = stats.max_permanent_hp
	_regen_timer = 0.0
	_is_incapacitated = false

## ダメージを受ける。DamageLayerによって対象HPが変わる。
func take_damage(amount: float, layer: GameEnums.DamageLayer) -> void:
	if _is_incapacitated and layer == GameEnums.DamageLayer.PERMANENT:
		# 行動不可中はpermanentダメージを追加で受ける（弱体化表現）
		amount *= 1.3
	
	_regen_timer = 0.0  # ダメージを受けたら回復タイマーリセット
	
	match layer:
		GameEnums.DamageLayer.RECOVERABLE:
			current_recoverable_hp = max(0.0, current_recoverable_hp - amount)
			recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
			if current_recoverable_hp <= 0.0 and not _is_incapacitated:
				_on_recoverable_depleted()
		
		GameEnums.DamageLayer.PERMANENT:
			current_permanent_hp = max(0.0, current_permanent_hp - amount)
			permanent_hp_changed.emit(current_permanent_hp, stats.max_permanent_hp)
			if current_permanent_hp <= 0.0:
				permanent_hp_depleted.emit()

## 行動コスト（スタミナ消費）。回復可能HPから差し引く。
## 戻り値：消費できたかどうか（HPが足りない場合はfalse）
func consume_stamina(amount: float) -> bool:
	# 最低値を1.0に抑える（完全枯渇による行動不可はtake_damageに任せる）
	if current_recoverable_hp <= amount:
		return false  # スタミナ不足で行動不可
	current_recoverable_hp -= amount
	recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
	return true

## 現在行動不可状態かどうかを返す
func is_incapacitated() -> bool:
	return _is_incapacitated

## 現在のgrapple dominance倍率を返す（行動不可中は低下）
func get_dominance_modifier() -> float:
	if _is_incapacitated:
		return stats.incapacitated_dominance_penalty
	return 1.0

# --- 内部メソッド ---

func _on_recoverable_depleted() -> void:
	_is_incapacitated = true
	current_recoverable_hp = 0.0
	recoverable_hp_depleted.emit()
	# 行動不可継続タイマーをセット
	var timer = get_tree().create_timer(stats.incapacitated_duration)
	timer.timeout.connect(_on_incapacitation_end)

func _on_incapacitation_end() -> void:
	_is_incapacitated = false
	# 回復可能HPを最大値の20%で復活させる
	current_recoverable_hp = stats.max_recoverable_hp * 0.2
	recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
	incapacitation_ended.emit()

func _process_regen(delta: float) -> void:
	# 行動不可中・枯渇中・満タン時は回復しない
	if _is_incapacitated:
		return
	if current_recoverable_hp >= stats.max_recoverable_hp:
		return
	
	_regen_timer += delta
	if _regen_timer >= stats.recoverable_hp_regen_delay:
		var regen_amount = stats.recoverable_hp_regen_rate * delta
		var old_hp = current_recoverable_hp
		current_recoverable_hp = min(stats.max_recoverable_hp, current_recoverable_hp + regen_amount)
		if current_recoverable_hp != old_hp:
			recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
			recoverable_hp_recovered.emit(current_recoverable_hp - old_hp)
```

---

## フェーズ3：打撃システム（三すくみ）

**前提フェーズ**：フェーズ1（AttackData, GameEnums）、フェーズ2（HealthComponent）

### 三すくみのルール整理

| 攻撃側 | 防御側 | 結果 |
|---|---|---|
| PUNCH | GUARD中 | BLOCKED（ガード成功）|
| KICK | GUARD中 | BLOCKED（ガード成功）|
| GRAPPLE | GUARD中 | GRAPPLE_SUCCESS（ガード貫通）|
| PUNCH/KICK | 何もしていない | HIT |
| PUNCH/KICK/GRAPPLE | 相手が行動中 | COUNTER_HIT（ヒット＋ダメージ1.5倍）|
| GRAPPLE | 相手がGUARDしていない | GRAPPLE_SUCCESS（通常成立）|

### 3-A. HitboxManager

**ファイル**：`res://scripts/systems/HitboxManager.gd`

キャラクターの子ノードとしてアタッチ。攻撃のヒットボックス有効/無効化と判定を管理。

```gdscript
class_name HitboxManager
extends Node3D

# === ノード参照 ===
# Hitbox: 自分の攻撃判定（攻撃中のみ有効）
# Hurtbox: 相手の攻撃を受ける判定（常時有効）
@onready var hitbox: Area3D = $Hitbox      # 子ノード "Hitbox" (Area3D)
@onready var hurtbox: Area3D = $Hurtbox    # 子ノード "Hurtbox" (Area3D)
@onready var hitbox_shape: CollisionShape3D = $Hitbox/CollisionShape3D
@onready var hurtbox_shape: CollisionShape3D = $Hurtbox/CollisionShape3D

# === 現在有効な攻撃データ ===
var _active_attack: AttackData = null
var _active_grapple: GrappleData = null
var _owner_id: GameEnums.PlayerID

# === シグナル ===
signal hit_landed(target: Node, attack_data: AttackData, result: GameEnums.HitResult)
signal grapple_initiated(target: Node, grapple_data: GrappleData)

func _ready() -> void:
	# Hitboxは初期状態で無効
	hitbox.monitoring = false
	hitbox.monitorable = false
	# Hurtboxは常時有効
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	
	# コリジョンレイヤー設定
	# Layer 1: Player1のHurtbox, Layer 2: Player2のHurtbox
	# Mask 1: Player1のHitboxはLayer2を検出, Mask 2: 逆
	# エディタで設定するか、ここでコードで設定
	hitbox.area_entered.connect(_on_hitbox_area_entered)

## 攻撃判定を有効化する（AnimationPlayerのコールバックから呼ぶ）
func activate_hitbox(attack: AttackData) -> void:
	_active_attack = attack
	_active_grapple = null
	# HitboxのCollisionShapeをAttackDataのサイズに合わせる
	var box_shape = BoxShape3D.new()
	box_shape.size = attack.hitbox_size
	hitbox_shape.shape = box_shape
	hitbox_shape.position = attack.hitbox_offset
	hitbox.monitoring = true

## グラップル判定を有効化する
func activate_grapple_hitbox(grapple: GrappleData) -> void:
	_active_grapple = grapple
	_active_attack = null
	var box_shape = BoxShape3D.new()
	box_shape.size = grapple.hitbox_size
	hitbox_shape.shape = box_shape
	hitbox_shape.position = grapple.hitbox_offset
	hitbox.monitoring = true

## 攻撃判定を無効化する（AnimationPlayerのコールバックから呼ぶ）
func deactivate_hitbox() -> void:
	hitbox.monitoring = false
	_active_attack = null
	_active_grapple = null

func _on_hitbox_area_entered(area: Area3D) -> void:
	# 相手のHurtboxに当たったときのみ処理
	var target_character = area.get_parent().get_parent()  # HurtboxのAreaの親の親＝キャラクターノード
	
	if _active_attack != null:
		var result = _calculate_hit_result(target_character, _active_attack.action_type)
		hit_landed.emit(target_character, _active_attack, result)
		deactivate_hitbox()
	elif _active_grapple != null:
		grapple_initiated.emit(target_character, _active_grapple)
		deactivate_hitbox()

## ヒット結果を計算する
func _calculate_hit_result(target: Node, action_type: GameEnums.ActionType) -> GameEnums.HitResult:
	# ターゲットのCombatControllerからステートを取得
	var target_controller = target.get_node_or_null("CombatController")
	if target_controller == null:
		return GameEnums.HitResult.HIT
	
	var target_state = target_controller.get_current_state()
	
	# ガード判定
	if target_state == GameEnums.CharacterState.GUARDING:
		if action_type == GameEnums.ActionType.GRAPPLE:
			return GameEnums.HitResult.GRAPPLE_SUCCESS  # ガード貫通
		else:
			return GameEnums.HitResult.BLOCKED
	
	# カウンターヒット判定（相手が攻撃モーション中）
	if target_state == GameEnums.CharacterState.ATTACKING:
		return GameEnums.HitResult.COUNTER_HIT
	
	# ヒットスタン中・行動不可中はカウンター扱い
	if target_state == GameEnums.CharacterState.HIT_STUN or \
	   target_state == GameEnums.CharacterState.INCAPACITATED:
		return GameEnums.HitResult.COUNTER_HIT
	
	return GameEnums.HitResult.HIT
```

### 3-B. DamageCalculator（静的クラス）

**ファイル**：`res://scripts/systems/DamageCalculator.gd`

```gdscript
class_name DamageCalculator
extends RefCounted

## AttackData + HitResult + 両者のCharacterStats からダメージを計算して返す
## 戻り値: { "recoverable": float, "permanent": float }
static func calculate_attack_damage(
	attack: AttackData,
	result: GameEnums.HitResult,
	attacker_stats: CharacterStats,
	defender_stats: CharacterStats
) -> Dictionary:
	
	var rec_dmg: float = attack.recoverable_damage
	var perm_dmg: float = attack.permanent_damage
	
	# 攻撃者のステータス倍率
	match attack.action_type:
		GameEnums.ActionType.PUNCH:
			rec_dmg *= attacker_stats.punch_damage_multiplier
		GameEnums.ActionType.KICK:
			rec_dmg *= attacker_stats.kick_damage_multiplier
	
	# カウンターヒット倍率
	if result == GameEnums.HitResult.COUNTER_HIT:
		rec_dmg *= attack.counter_hit_multiplier
		perm_dmg *= attack.counter_hit_multiplier
	
	# ガード時はダメージなし（ブロックスタンのみ）
	if result == GameEnums.HitResult.BLOCKED:
		return {"recoverable": 0.0, "permanent": 0.0}
	
	# 防御者のステータス倍率
	rec_dmg *= defender_stats.defense_multiplier
	perm_dmg *= defender_stats.defense_multiplier
	
	return {"recoverable": rec_dmg, "permanent": perm_dmg}

## GrappleDataからダメージを計算
static func calculate_grapple_damage(
	grapple: GrappleData,
	dominance: float,  # 0.0〜1.0
	attacker_stats: CharacterStats,
	defender_stats: CharacterStats
) -> Dictionary:
	
	var perm_dmg: float = grapple.permanent_damage
	var rec_dmg: float = grapple.recoverable_damage
	
	perm_dmg *= attacker_stats.grapple_damage_multiplier
	
	# dominanceが閾値以上の場合のみダメージ倍率適用
	if dominance >= grapple.dominance_damage_threshold:
		perm_dmg *= grapple.dominant_damage_multiplier
	
	perm_dmg *= defender_stats.defense_multiplier
	rec_dmg *= defender_stats.defense_multiplier
	
	return {"recoverable": rec_dmg, "permanent": perm_dmg}
```

---

## フェーズ4：グラップリングシステム（dominance型）

**前提フェーズ**：フェーズ1、2、3

### 設計概要

- 2キャラクターがGRAPPLING/GRAPPLEDステートに同時遷移
- `dominance`（0.0〜1.0）を共有変数として管理
  - 0.5がニュートラル
  - 1.0に近づくほど攻め側が有利
  - 0.0に近づくほど受け側が逆転可能
- 両者がグラップルボタン入力で競り合い（`dominance`が変動）
- `dominance >= grapple.dominance_damage_threshold` でダメージ発生
- `dominance <= (1.0 - grapple.dominance_damage_threshold)` で相手が逆転成功

### 4-A. GrappleManager

**ファイル**：`res://scripts/systems/GrappleManager.gd`

FightManagerの子ノードとして存在。グラップル中の2キャラクターを管理。

```gdscript
class_name GrappleManager
extends Node

# === グラップルの参加者 ===
var grapple_initiator: Node = null   # グラップルを開始したキャラクター
var grapple_receiver: Node = null    # グラップルを受けたキャラクター
var active_grapple_data: GrappleData = null

# === dominance値（攻め側基準で1.0に近いほど攻め側有利） ===
var dominance: float = 0.5

# === 定数 ===
const DOMINANCE_GAIN_PER_INPUT: float = 0.08   # グラップル入力1回あたりのdominance変動量
const DOMINANCE_DECAY_RATE: float = 0.05        # 入力がないときの中立への戻り速度（毎秒）
const DOMINANCE_DAMAGE_THRESHOLD: float = 0.75  # この値以上でダメージ発生
const DOMINANCE_REVERSE_THRESHOLD: float = 0.25 # この値以下で受け側が逆転

# === タイマー ===
var _damage_interval_timer: float = 0.0
const DAMAGE_INTERVAL: float = 1.0  # グラップル中のダメージ間隔（秒）

# === 入力フラグ（各_physics_processフレームでリセット） ===
var _initiator_input_this_frame: bool = false
var _receiver_input_this_frame: bool = false

# === グラップル状態かどうか ===
var is_active: bool = false

# === シグナル ===
signal grapple_damage_dealt(target: Node, rec_dmg: float, perm_dmg: float)
signal grapple_ended(winner: Node, loser: Node)
signal dominance_changed(new_dominance: float)

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	
	_process_dominance(delta)
	_process_damage(delta)
	_reset_frame_inputs()

## グラップル開始
func start_grapple(initiator: Node, receiver: Node, grapple_data: GrappleData) -> void:
	grapple_initiator = initiator
	grapple_receiver = receiver
	active_grapple_data = grapple_data
	dominance = 0.5
	_damage_interval_timer = 0.0
	is_active = true
	
	# 両キャラのポジション固定（受け側を攻め側の正面に移動）
	var initiator_pos = initiator.global_position
	var initiator_forward = -initiator.global_transform.basis.z
	receiver.global_position = initiator_pos + initiator_forward * 1.0
	receiver.look_at(initiator_pos, Vector3.UP)
	
	# 両者のステート遷移はFightManagerが行う

## グラップル入力登録（各キャラクターのInputHandlerから呼ぶ）
func register_input(player_id: GameEnums.PlayerID) -> void:
	if not is_active:
		return
	
	# 行動不可中はdominance変動量を削減
	var initiator_health = grapple_initiator.get_node("HealthComponent")
	var receiver_health = grapple_receiver.get_node("HealthComponent")
	
	if player_id == _get_initiator_player_id():
		var modifier = initiator_health.get_dominance_modifier()
		dominance = min(1.0, dominance + DOMINANCE_GAIN_PER_INPUT * modifier)
		_initiator_input_this_frame = true
	else:
		var modifier = receiver_health.get_dominance_modifier()
		dominance = max(0.0, dominance - DOMINANCE_GAIN_PER_INPUT * modifier)
		_receiver_input_this_frame = true
	
	dominance_changed.emit(dominance)

func _process_dominance(delta: float) -> void:
	# 入力がないフレームは中立（0.5）に向かって収束
	if not _initiator_input_this_frame:
		dominance = move_toward(dominance, 0.5, DOMINANCE_DECAY_RATE * delta)
	if not _receiver_input_this_frame:
		dominance = move_toward(dominance, 0.5, DOMINANCE_DECAY_RATE * delta)
	
	# 逆転判定
	if dominance >= DOMINANCE_DAMAGE_THRESHOLD:
		pass  # _process_damageで処理
	elif dominance <= DOMINANCE_REVERSE_THRESHOLD:
		_on_receiver_reversal()

func _process_damage(delta: float) -> void:
	_damage_interval_timer += delta
	if _damage_interval_timer < DAMAGE_INTERVAL:
		return
	_damage_interval_timer = 0.0
	
	if dominance >= DOMINANCE_DAMAGE_THRESHOLD:
		var initiator_stats: CharacterStats = grapple_initiator.get_node("HealthComponent").stats
		var receiver_stats: CharacterStats = grapple_receiver.get_node("HealthComponent").stats
		var dmg = DamageCalculator.calculate_grapple_damage(
			active_grapple_data, dominance, initiator_stats, receiver_stats
		)
		grapple_damage_dealt.emit(grapple_receiver, dmg["recoverable"], dmg["permanent"])

func _on_receiver_reversal() -> void:
	# 受け側が逆転成功 → グラップル終了、受け側が有利
	var winner = grapple_receiver
	var loser = grapple_initiator
	_end_grapple(winner, loser)

func end_grapple_by_timeout() -> void:
	# タイムアウト等で強制終了
	_end_grapple(null, null)

func _end_grapple(winner: Node, loser: Node) -> void:
	is_active = false
	grapple_ended.emit(winner, loser)
	grapple_initiator = null
	grapple_receiver = null
	active_grapple_data = null

func _reset_frame_inputs() -> void:
	_initiator_input_this_frame = false
	_receiver_input_this_frame = false

func _get_initiator_player_id() -> GameEnums.PlayerID:
	# initiatorのPlayerIDを取得する（CombatControllerが持つ）
	return grapple_initiator.get_node("CombatController").player_id
```

---

## フェーズ5：コンボシステム（コンボツリー）

**前提フェーズ**：フェーズ1（AttackData, GameEnums）

### 設計概要

- パンチ（P）とキック（K）を最大3回組み合わせたコンボ
- 入力パターン：PP、PK、KP、KK、PPP、PPK、PKP、PKK、KPP、KPK、KKP、KKK の12種
- コンボツリーをデータ構造で定義し、ComboManagerが追跡
- 各コンボ入力にタイミングウィンドウを設定（前の攻撃のactive_frames終了後から一定フレーム）
- コンボ3ヒット目（エンダー）は自動的に追加ダメージ倍率

### 5-A. ComboNode リソース

**ファイル**：`res://scripts/resources/ComboNode.gd`

```gdscript
class_name ComboNode
extends Resource

# このノードの攻撃データ
@export var attack_data: AttackData = null

# このノードの後に繋げられる次のコンボノード
# Key: "PUNCH" or "KICK"（入力文字列）
# Value: ComboNode
@export var branches: Dictionary = {}

# コンボの何ヒット目か（1始まり）
@export var hit_count: int = 1

# このノードがコンボエンダー（最終ヒット）かどうか
@export var is_ender: bool = false

# エンダーの場合のダメージ倍率
@export var ender_damage_multiplier: float = 1.3

# コンボウィンドウ（前の攻撃のactive_frames終了後から受け付けるフレーム数）
@export var window_frames: int = 20
```

**コンボツリーの構築**（`res://resources/combos/combo_tree_root.tres`として保存）：

コンボツリーは以下の構造で定義すること。エディタのリソースエディタで組み立てる。
各葉ノードの `is_ender = true`、`ender_damage_multiplier = 1.3`。

```
ROOT（AttackData=null, branches={P:node_P, K:node_K}）
├── P（punch_light.tres, branches={P:node_PP, K:node_PK}, hit_count=1）
│   ├── PP（punch_heavy.tres, branches={P:node_PPP, K:node_PPK}, hit_count=2）
│   │   ├── PPP（kick_heavy.tres, is_ender=true, hit_count=3）
│   │   └── PPK（kick_light.tres, is_ender=true, hit_count=3）
│   └── PK（kick_light.tres, branches={P:node_PKP, K:node_PKK}, hit_count=2）
│       ├── PKP（punch_heavy.tres, is_ender=true, hit_count=3）
│       └── PKK（kick_heavy.tres, is_ender=true, hit_count=3）
└── K（kick_light.tres, branches={P:node_KP, K:node_KK}, hit_count=1）
	├── KP（punch_light.tres, branches={P:node_KPP, K:node_KPK}, hit_count=2）
	│   ├── KPP（punch_heavy.tres, is_ender=true, hit_count=3）
	│   └── KPK（kick_heavy.tres, is_ender=true, hit_count=3）
	└── KK（kick_heavy.tres, branches={P:node_KKP, K:node_KKK}, hit_count=2）
		├── KKP（punch_heavy.tres, is_ender=true, hit_count=3）
		└── KKK（kick_heavy.tres, is_ender=true, hit_count=3）
```

### 5-B. ComboManager

**ファイル**：`res://scripts/systems/ComboManager.gd`

キャラクターノードの子ノードとしてアタッチ。

```gdscript
class_name ComboManager
extends Node

# === 設定 ===
@export var combo_tree_root: ComboNode  # エディタでrootノードを割り当て

# === 内部状態 ===
var _current_node: ComboNode = null   # 現在のコンボツリー位置（nullなら未開始）
var _window_timer: int = 0            # 現在のコンボウィンドウ残りフレーム
var _window_open: bool = false        # コンボ受付中かどうか

# === シグナル ===
signal combo_attack_resolved(attack: AttackData, is_ender: bool, ender_multiplier: float)
signal combo_reset()

func _physics_process(_delta: float) -> void:
	if _window_open and _window_timer > 0:
		_window_timer -= 1
		if _window_timer <= 0:
			_reset_combo()

## コンボウィンドウを開く（AnimationPlayerのコールバックから呼ぶ）
func open_combo_window() -> void:
	if _current_node == null:
		return
	var window = _current_node.window_frames
	_window_timer = window
	_window_open = true

## コンボウィンドウを閉じる（AnimationPlayerのコールバックから呼ぶ）
func close_combo_window() -> void:
	_window_open = false
	if _current_node != null and not _current_node.is_ender:
		# ウィンドウが閉じたがエンダーでなければリセット
		_reset_combo()

## 打撃入力を受け付ける
## 戻り値: 実行すべきAttackData（コンボ継続）またはnull（コンボ外単発）
func try_input(action: GameEnums.ActionType) -> AttackData:
	var key = _action_to_key(action)
	if key == "":
		return null
	
	if _current_node == null:
		# コンボ未開始 → ルートのbranchesを確認
		if combo_tree_root.branches.has(key):
			_current_node = combo_tree_root.branches[key]
			var atk = _current_node.attack_data
			if _current_node.is_ender:
				combo_attack_resolved.emit(atk, true, _current_node.ender_damage_multiplier)
				_reset_combo()
			else:
				combo_attack_resolved.emit(atk, false, 1.0)
			return atk
	else:
		# コンボ継続中 → ウィンドウが開いているかチェック
		if _window_open and _current_node.branches.has(key):
			_current_node = _current_node.branches[key]
			var atk = _current_node.attack_data
			if _current_node.is_ender:
				combo_attack_resolved.emit(atk, true, _current_node.ender_damage_multiplier)
				_reset_combo()
			else:
				combo_attack_resolved.emit(atk, false, 1.0)
			return atk
		else:
			# ウィンドウ外 or 繋がらない入力 → リセットして単発として処理
			_reset_combo()
			return try_input(action)  # 再試行（単発として）
	
	return null

func _reset_combo() -> void:
	_current_node = null
	_window_open = false
	_window_timer = 0
	combo_reset.emit()

func _action_to_key(action: GameEnums.ActionType) -> String:
	match action:
		GameEnums.ActionType.PUNCH: return "PUNCH"
		GameEnums.ActionType.KICK: return "KICK"
	return ""
```

---

## フェーズ6：キャラクターステートマシン

**前提フェーズ**：フェーズ1〜5

### 6-A. ステートマシンの基底クラス

**ファイル**：`res://scripts/states/BaseState.gd`

```gdscript
class_name BaseState
extends Node

# このステートが属するキャラクターのCombatControllerへの参照
var combat_controller: Node = null

# ステート開始時に呼ばれる
func enter(_prev_state: GameEnums.CharacterState) -> void:
	pass

# ステート終了時に呼ばれる
func exit(_next_state: GameEnums.CharacterState) -> void:
	pass

# _physics_process相当（CombatControllerから呼ばれる）
func update(_delta: float) -> void:
	pass

# 入力を受け取る（CombatControllerから呼ばれる）
func handle_input(_action: GameEnums.ActionType) -> void:
	pass
```

### 6-B. CombatController（ステートマシン本体）

**ファイル**：`res://scripts/systems/CombatController.gd`

各キャラクターノードの子ノードとしてアタッチ。キャラクターの状態遷移を一元管理。

```gdscript
class_name CombatController
extends Node

# === 設定 ===
@export var player_id: GameEnums.PlayerID = GameEnums.PlayerID.PLAYER_ONE

# === 子ノード参照（各ステートノード） ===
@onready var state_idle: BaseState = $StateIdle
@onready var state_walking: BaseState = $StateWalking
@onready var state_attacking: BaseState = $StateAttacking
@onready var state_guarding: BaseState = $StateGuarding
@onready var state_grappling: BaseState = $StateGrappling
@onready var state_grappled: BaseState = $StateGrappled
@onready var state_hit_stun: BaseState = $StateHitStun
@onready var state_knockdown: BaseState = $StateKnockdown
@onready var state_getting_up: BaseState = $StateGettingUp
@onready var state_incapacitated: BaseState = $StateIncapacitated
@onready var state_ko: BaseState = $StateKO

# === 現在のステート ===
var _current_state: GameEnums.CharacterState = GameEnums.CharacterState.IDLE
var _current_state_node: BaseState = null

# === コンポーネント参照 ===
@onready var health: HealthComponent = $HealthComponent
@onready var combo_manager: ComboManager = $ComboManager
@onready var hitbox_manager: HitboxManager = $HitboxManager
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# === シグナル ===
signal state_changed(new_state: GameEnums.CharacterState)
signal action_requested(action: GameEnums.ActionType)

func _ready() -> void:
	# 各ステートにcombat_controllerを設定
	for child in get_children():
		if child is BaseState:
			child.combat_controller = self
	
	# HealthComponentのシグナル接続
	health.recoverable_hp_depleted.connect(_on_recoverable_hp_depleted)
	health.permanent_hp_depleted.connect(_on_permanent_hp_depleted)
	health.incapacitation_ended.connect(_on_incapacitation_ended)
	
	# HitboxManagerのシグナル接続
	hitbox_manager.hit_landed.connect(_on_hit_landed)
	hitbox_manager.grapple_initiated.connect(_on_grapple_initiated)
	
	transition_to(GameEnums.CharacterState.IDLE)

func _physics_process(delta: float) -> void:
	if _current_state_node:
		_current_state_node.update(delta)

## 外部からの入力受付（InputHandlerから呼ぶ）
func receive_input(action: GameEnums.ActionType) -> void:
	if _current_state_node:
		_current_state_node.handle_input(action)

## ステート遷移（外部・内部どちらからでも呼べる）
func transition_to(new_state: GameEnums.CharacterState) -> void:
	if _current_state == new_state:
		return
	
	var prev = _current_state
	if _current_state_node:
		_current_state_node.exit(new_state)
	
	_current_state = new_state
	_current_state_node = _get_state_node(new_state)
	
	if _current_state_node:
		_current_state_node.enter(prev)
	
	state_changed.emit(new_state)

func get_current_state() -> GameEnums.CharacterState:
	return _current_state

# --- シグナルハンドラ ---

func _on_recoverable_hp_depleted() -> void:
	transition_to(GameEnums.CharacterState.INCAPACITATED)

func _on_permanent_hp_depleted() -> void:
	transition_to(GameEnums.CharacterState.KO)

func _on_incapacitation_ended() -> void:
	transition_to(GameEnums.CharacterState.GETTING_UP)

func _on_hit_landed(target: Node, attack: AttackData, result: GameEnums.HitResult) -> void:
	# FightManagerにhit情報を伝達
	var fight_manager = get_tree().get_first_node_in_group("fight_manager")
	if fight_manager:
		fight_manager.process_hit(self, target, attack, result)

func _on_grapple_initiated(target: Node, grapple: GrappleData) -> void:
	var fight_manager = get_tree().get_first_node_in_group("fight_manager")
	if fight_manager:
		fight_manager.process_grapple_start(self, target, grapple)

func _get_state_node(state: GameEnums.CharacterState) -> BaseState:
	match state:
		GameEnums.CharacterState.IDLE: return state_idle
		GameEnums.CharacterState.WALKING: return state_walking
		GameEnums.CharacterState.ATTACKING: return state_attacking
		GameEnums.CharacterState.GUARDING: return state_guarding
		GameEnums.CharacterState.GRAPPLING: return state_grappling
		GameEnums.CharacterState.GRAPPLED: return state_grappled
		GameEnums.CharacterState.HIT_STUN: return state_hit_stun
		GameEnums.CharacterState.KNOCKDOWN: return state_knockdown
		GameEnums.CharacterState.GETTING_UP: return state_getting_up
		GameEnums.CharacterState.INCAPACITATED: return state_incapacitated
		GameEnums.CharacterState.KO: return state_ko
	return null
```

### 6-C. 各ステートの実装

**ファイル**（各ファイルを作成）：

#### `StateIdle.gd`
```gdscript
class_name StateIdle
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.anim_player.play("idle")

func handle_input(action: GameEnums.ActionType) -> void:
	match action:
		GameEnums.ActionType.PUNCH, GameEnums.ActionType.KICK:
			# スタミナ確認してからAttackへ
			var attack = combat_controller.combo_manager.try_input(action)
			if attack != null:
				combat_controller.transition_to(GameEnums.CharacterState.ATTACKING)
		GameEnums.ActionType.GRAPPLE:
			if combat_controller.health.consume_stamina(12.0):  # GrappleDataのstamina_costに合わせる
				combat_controller.transition_to(GameEnums.CharacterState.ATTACKING)  # グラップル開始
		GameEnums.ActionType.GUARD:
			combat_controller.transition_to(GameEnums.CharacterState.GUARDING)
```

#### `StateAttacking.gd`
```gdscript
class_name StateAttacking
extends BaseState

var _current_attack: AttackData = null
var _frame_counter: int = 0
var _phase: String = "startup"  # "startup" / "active" / "recovery"

func enter(_prev: GameEnums.CharacterState) -> void:
	_frame_counter = 0
	_phase = "startup"
	# ComboManagerから現在の攻撃データを取得（CombatControllerが保持）
	_current_attack = combat_controller._pending_attack
	if _current_attack == null:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)
		return
	combat_controller.anim_player.play(_current_attack.animation_name)

func update(_delta: float) -> void:
	_frame_counter += 1
	match _phase:
		"startup":
			if _frame_counter >= _current_attack.startup_frames:
				_phase = "active"
				_frame_counter = 0
				combat_controller.hitbox_manager.activate_hitbox(_current_attack)
		"active":
			if _frame_counter >= _current_attack.active_frames:
				_phase = "recovery"
				_frame_counter = 0
				combat_controller.hitbox_manager.deactivate_hitbox()
				combat_controller.combo_manager.open_combo_window()
		"recovery":
			if _frame_counter >= _current_attack.recovery_frames:
				combat_controller.combo_manager.close_combo_window()
				combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func handle_input(action: GameEnums.ActionType) -> void:
	# コンボウィンドウ中のみ次の入力を受け付ける
	if _phase == "recovery":
		var next_attack = combat_controller.combo_manager.try_input(action)
		if next_attack != null:
			combat_controller._pending_attack = next_attack
			# 次のAttackステートへ（リセットして再enter）
			combat_controller.transition_to(GameEnums.CharacterState.IDLE)
			combat_controller.transition_to(GameEnums.CharacterState.ATTACKING)
```

#### `StateGuarding.gd`
```gdscript
class_name StateGuarding
extends BaseState

var _guard_timer: float = 0.0
const MAX_GUARD_HOLD: float = 3.0  # 最大ガード継続時間

func enter(_prev: GameEnums.CharacterState) -> void:
	_guard_timer = 0.0
	combat_controller.anim_player.play("guard")

func update(delta: float) -> void:
	_guard_timer += delta
	# スタミナをじわじわ消費（ガードは体力を使う）
	combat_controller.health.take_damage(2.0 * delta, GameEnums.DamageLayer.RECOVERABLE)
	if _guard_timer >= MAX_GUARD_HOLD:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func handle_input(action: GameEnums.ActionType) -> void:
	if action != GameEnums.ActionType.GUARD:
		# ガードボタン離し相当
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func exit(_next: GameEnums.CharacterState) -> void:
	pass
```

#### `StateHitStun.gd`
```gdscript
class_name StateHitStun
extends BaseState

var _stun_frames: int = 0
var _frame_counter: int = 0

func enter(_prev: GameEnums.CharacterState) -> void:
	_frame_counter = 0
	_stun_frames = combat_controller._pending_hit_stun_frames
	combat_controller.anim_player.play("hit_stun")

func update(_delta: float) -> void:
	_frame_counter += 1
	if _frame_counter >= _stun_frames:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

# ヒットスタン中は入力を受け付けない
func handle_input(_action: GameEnums.ActionType) -> void:
	pass
```

#### `StateIncapacitated.gd`
```gdscript
class_name StateIncapacitated
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.anim_player.play("knockdown")
	# HealthComponentのタイマーが終了すると自動でincapacitation_ended → GETTING_UP

# 行動不可中は一切の入力を無効化
func handle_input(_action: GameEnums.ActionType) -> void:
	pass
```

#### `StateGettingUp.gd`
```gdscript
class_name StateGettingUp
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.anim_player.play("getting_up")
	# アニメ終了でIdleへ
	combat_controller.anim_player.animation_finished.connect(_on_anim_finished, CONNECT_ONE_SHOT)

func _on_anim_finished(_anim_name: String) -> void:
	combat_controller.transition_to(GameEnums.CharacterState.IDLE)
```

#### `StateKO.gd`
```gdscript
class_name StateKO
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.anim_player.play("ko")
	# KO演出はFightManagerが管理するため、ここではアニメ再生のみ

func handle_input(_action: GameEnums.ActionType) -> void:
	pass  # KO中は一切の入力無効
```

#### `StateGrappling.gd` / `StateGrappled.gd`
```gdscript
# StateGrappling.gd（攻め側）
class_name StateGrappling
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.anim_player.play("grapple_initiator")

func handle_input(action: GameEnums.ActionType) -> void:
	# グラップルボタン入力でdominance変動
	if action == GameEnums.ActionType.GRAPPLE:
		var grapple_mgr = get_tree().get_first_node_in_group("grapple_manager")
		if grapple_mgr:
			grapple_mgr.register_input(combat_controller.player_id)

# StateGrappled.gd（受け側）
class_name StateGrappled
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.anim_player.play("grapple_receiver")

func handle_input(action: GameEnums.ActionType) -> void:
	if action == GameEnums.ActionType.GRAPPLE:
		var grapple_mgr = get_tree().get_first_node_in_group("grapple_manager")
		if grapple_mgr:
			grapple_mgr.register_input(combat_controller.player_id)
```

---

## フェーズ7：試合管理・ラウンドシステム

**前提フェーズ**：フェーズ1〜6

### 7-A. FightManager

**ファイル**：`res://scripts/managers/FightManager.gd`

`main.tscn`の子ノードとしてアタッチ。`fight_manager`グループに追加すること。

```gdscript
class_name FightManager
extends Node

# === 設定 ===
@export var max_rounds: int = 3
@export var round_time: float = 99.0  # ラウンド制限時間（秒）

# === ノード参照 ===
@export var player1: CharacterBody3D  # エディタで割り当て
@export var player2: CharacterBody3D  # エディタで割り当て
@onready var grapple_manager: GrappleManager = $GrappleManager

# === 試合状態 ===
var current_round: int = 1
var round_state: GameEnums.RoundState = GameEnums.RoundState.WAITING
var round_timer: float = 0.0
var p1_wins: int = 0
var p2_wins: int = 0

# === シグナル ===
signal round_started(round_number: int)
signal round_ended(winner_id: GameEnums.PlayerID)
signal match_ended(winner_id: GameEnums.PlayerID)
signal ko_triggered(loser: Node)

func _ready() -> void:
	add_to_group("fight_manager")
	grapple_manager.grapple_damage_dealt.connect(_on_grapple_damage)
	grapple_manager.grapple_ended.connect(_on_grapple_ended)
	
	# KO検知（各キャラのHealthComponent.permanent_hp_depleted）
	var p1_health = player1.get_node("HealthComponent")
	var p2_health = player2.get_node("HealthComponent")
	p1_health.permanent_hp_depleted.connect(func(): _on_ko(player1, player2))
	p2_health.permanent_hp_depleted.connect(func(): _on_ko(player2, player1))
	
	start_round()

func _physics_process(delta: float) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	round_timer -= delta
	if round_timer <= 0.0:
		_on_round_timeout()

func start_round() -> void:
	round_timer = round_time
	round_state = GameEnums.RoundState.FIGHTING
	
	# 両者をリセット
	_reset_character(player1)
	_reset_character(player2)
	
	# 開始位置をリセット
	player1.global_position = Vector3(-2.0, 0.0, 0.0)
	player2.global_position = Vector3(2.0, 0.0, 0.0)
	player2.look_at(player1.global_position, Vector3.UP)
	
	round_started.emit(current_round)

## 打撃ヒット処理（CombatControllerから呼ばれる）
func process_hit(attacker: Node, target: Node, attack: AttackData, result: GameEnums.HitResult) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	
	var attacker_stats = attacker.get_node("HealthComponent").stats
	var target_stats = target.get_node("HealthComponent").stats
	var dmg = DamageCalculator.calculate_attack_damage(attack, result, attacker_stats, target_stats)
	
	var target_health = target.get_node("HealthComponent")
	var target_controller = target.get_node("CombatController")
	
	if dmg["recoverable"] > 0.0:
		target_health.take_damage(dmg["recoverable"], GameEnums.DamageLayer.RECOVERABLE)
	if dmg["permanent"] > 0.0:
		target_health.take_damage(dmg["permanent"], GameEnums.DamageLayer.PERMANENT)
	
	# ヒットスタンをセット
	if result != GameEnums.HitResult.BLOCKED:
		target_controller._pending_hit_stun_frames = attack.hit_stun_frames
		target_controller.transition_to(GameEnums.CharacterState.HIT_STUN)
	else:
		# ブロックスタン
		target_controller._pending_hit_stun_frames = attack.block_stun_frames
		target_controller.transition_to(GameEnums.CharacterState.HIT_STUN)

## グラップル開始処理（CombatControllerから呼ばれる）
func process_grapple_start(initiator_ctrl: Node, target: Node, grapple: GrappleData) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	if grapple_manager.is_active:
		return  # 既にグラップル中なら無視
	
	var initiator_char = initiator_ctrl.get_parent()
	grapple_manager.start_grapple(initiator_char, target, grapple)
	
	initiator_ctrl.transition_to(GameEnums.CharacterState.GRAPPLING)
	target.get_node("CombatController").transition_to(GameEnums.CharacterState.GRAPPLED)

func _on_grapple_damage(target: Node, rec_dmg: float, perm_dmg: float) -> void:
	var target_health = target.get_node("HealthComponent")
	if rec_dmg > 0.0:
		target_health.take_damage(rec_dmg, GameEnums.DamageLayer.RECOVERABLE)
	if perm_dmg > 0.0:
		target_health.take_damage(perm_dmg, GameEnums.DamageLayer.PERMANENT)

func _on_grapple_ended(winner: Node, loser: Node) -> void:
	# 両キャラをIDLEに戻す
	if player1.get_node("CombatController").get_current_state() == GameEnums.CharacterState.GRAPPLING or \
	   player1.get_node("CombatController").get_current_state() == GameEnums.CharacterState.GRAPPLED:
		player1.get_node("CombatController").transition_to(GameEnums.CharacterState.IDLE)
	if player2.get_node("CombatController").get_current_state() == GameEnums.CharacterState.GRAPPLING or \
	   player2.get_node("CombatController").get_current_state() == GameEnums.CharacterState.GRAPPLED:
		player2.get_node("CombatController").transition_to(GameEnums.CharacterState.IDLE)

func _on_ko(loser: Node, winner: Node) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	round_state = GameEnums.RoundState.ROUND_END
	ko_triggered.emit(loser)
	
	# 勝敗カウント
	if winner == player1:
		p1_wins += 1
		round_ended.emit(GameEnums.PlayerID.PLAYER_ONE)
	else:
		p2_wins += 1
		round_ended.emit(GameEnums.PlayerID.PLAYER_TWO)
	
	# 最大ラウンド到達 or 必要勝利数到達
	var wins_needed = (max_rounds / 2) + 1
	if p1_wins >= wins_needed:
		match_ended.emit(GameEnums.PlayerID.PLAYER_ONE)
	elif p2_wins >= wins_needed:
		match_ended.emit(GameEnums.PlayerID.PLAYER_TWO)
	else:
		current_round += 1
		# KO演出終了後に次ラウンド開始（KOManagerが管理）

func _on_round_timeout() -> void:
	# 時間切れ：回復不可能HP残量で判定
	round_state = GameEnums.RoundState.ROUND_END
	var p1_hp = player1.get_node("HealthComponent").current_permanent_hp
	var p2_hp = player2.get_node("HealthComponent").current_permanent_hp
	if p1_hp > p2_hp:
		round_ended.emit(GameEnums.PlayerID.PLAYER_ONE)
	elif p2_hp > p1_hp:
		round_ended.emit(GameEnums.PlayerID.PLAYER_TWO)
	else:
		round_ended.emit(GameEnums.PlayerID.PLAYER_ONE)  # 同点はPlayer1勝ち（暫定）

func _reset_character(character: Node) -> void:
	character.get_node("HealthComponent")._reset()
	character.get_node("CombatController").transition_to(GameEnums.CharacterState.IDLE)
	character.get_node("ComboManager")._reset_combo()
```

### 7-B. InputHandler

**ファイル**：`res://scripts/managers/InputHandler.gd`

各キャラクターノードの子ノードとしてアタッチ。入力をCombatControllerに渡す。

```gdscript
class_name InputHandler
extends Node

@export var player_id: GameEnums.PlayerID = GameEnums.PlayerID.PLAYER_ONE
@onready var combat_controller: CombatController = get_parent().get_node("CombatController")

# === InputMap設定（Project Settings > InputMapで定義すること） ===
# PLAYER_ONE: p1_punch / p1_kick / p1_grapple / p1_guard / p1_move_left / p1_move_right / p1_move_up / p1_move_down
# PLAYER_TWO: p2_punch / p2_kick / p2_grapple / p2_guard / p2_move_left / p2_move_right / p2_move_up / p2_move_down

var _prefix: String = "p1_"

func _ready() -> void:
	_prefix = "p1_" if player_id == GameEnums.PlayerID.PLAYER_ONE else "p2_"

func _physics_process(_delta: float) -> void:
	_process_movement()
	_process_actions()

func _process_actions() -> void:
	if Input.is_action_just_pressed(_prefix + "punch"):
		combat_controller.receive_input(GameEnums.ActionType.PUNCH)
	elif Input.is_action_just_pressed(_prefix + "kick"):
		combat_controller.receive_input(GameEnums.ActionType.KICK)
	elif Input.is_action_just_pressed(_prefix + "grapple"):
		combat_controller.receive_input(GameEnums.ActionType.GRAPPLE)
	
	# ガードは押し続けている間有効
	if Input.is_action_pressed(_prefix + "guard"):
		combat_controller.receive_input(GameEnums.ActionType.GUARD)

func _process_movement() -> void:
	var state = combat_controller.get_current_state()
	# 移動可能なステートのみ
	if state not in [GameEnums.CharacterState.IDLE, GameEnums.CharacterState.WALKING]:
		return
	
	var move_dir = Input.get_vector(
		_prefix + "move_left", _prefix + "move_right",
		_prefix + "move_up", _prefix + "move_down"
	)
	var character = get_parent() as CharacterBody3D
	if move_dir.length() > 0.1:
		# 既存のPlayerController.gd と統合すること
		# velocity.x = move_dir.x * SPEED
		# velocity.z = move_dir.y * SPEED
		if state == GameEnums.CharacterState.IDLE:
			combat_controller.transition_to(GameEnums.CharacterState.WALKING)
	else:
		if state == GameEnums.CharacterState.WALKING:
			combat_controller.transition_to(GameEnums.CharacterState.IDLE)
```

---

## フェーズ8：HUD・UI

**前提フェーズ**：フェーズ2、7

### 8-A. HUDController

**ファイル**：`res://scripts/ui/HUDController.gd`

`hud.tscn`のルートノードにアタッチ。

**ノード構成（hud.tscn）**：

```
HUD (CanvasLayer)
├── P1_Panel (HBoxContainer, 左寄せ)
│   ├── P1_Name (Label)
│   ├── P1_PermanentHP (TextureProgressBar)  ← 外側（赤）
│   └── P1_RecoverableHP (TextureProgressBar) ← 内側（緑）
├── P2_Panel (HBoxContainer, 右寄せ)
│   ├── P2_Name (Label)
│   ├── P2_PermanentHP (TextureProgressBar)
│   └── P2_RecoverableHP (TextureProgressBar)
├── Center_Panel (VBoxContainer, 中央)
│   ├── RoundTimer (Label)
│   └── RoundCounter (Label)
└── GrapplePanel (HBoxContainer, 中央下部, 非表示)
	├── DominanceBar (TextureProgressBar)  ← グラップル中のみ表示
	└── DominanceLabel (Label)
```

```gdscript
class_name HUDController
extends CanvasLayer

@onready var p1_permanent_bar: TextureProgressBar = $P1_Panel/P1_PermanentHP
@onready var p1_recoverable_bar: TextureProgressBar = $P1_Panel/P1_RecoverableHP
@onready var p2_permanent_bar: TextureProgressBar = $P2_Panel/P2_PermanentHP
@onready var p2_recoverable_bar: TextureProgressBar = $P2_Panel/P2_RecoverableHP
@onready var round_timer_label: Label = $Center_Panel/RoundTimer
@onready var round_counter_label: Label = $Center_Panel/RoundCounter
@onready var grapple_panel: HBoxContainer = $GrapplePanel
@onready var dominance_bar: TextureProgressBar = $GrapplePanel/DominanceBar

@export var fight_manager: FightManager

func _ready() -> void:
	# TextureProgressBarの設定
	p1_permanent_bar.min_value = 0
	p1_permanent_bar.max_value = 100
	p1_permanent_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	
	p1_recoverable_bar.min_value = 0
	p1_recoverable_bar.max_value = 100
	p1_recoverable_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	
	# P2は右→左方向に減る
	p2_permanent_bar.fill_mode = TextureProgressBar.FILL_RIGHT_TO_LEFT
	p2_recoverable_bar.fill_mode = TextureProgressBar.FILL_RIGHT_TO_LEFT
	
	dominance_bar.min_value = 0.0
	dominance_bar.max_value = 1.0
	dominance_bar.value = 0.5
	grapple_panel.visible = false
	
	_connect_signals()

func _connect_signals() -> void:
	if fight_manager == null:
		return
	
	var p1_health = fight_manager.player1.get_node("HealthComponent")
	var p2_health = fight_manager.player2.get_node("HealthComponent")
	
	p1_health.permanent_hp_changed.connect(func(val, mx): _update_bar(p1_permanent_bar, val, mx))
	p1_health.recoverable_hp_changed.connect(func(val, mx): _update_bar(p1_recoverable_bar, val, mx))
	p2_health.permanent_hp_changed.connect(func(val, mx): _update_bar(p2_permanent_bar, val, mx))
	p2_health.recoverable_hp_changed.connect(func(val, mx): _update_bar(p2_recoverable_bar, val, mx))
	
	fight_manager.round_started.connect(func(rn): round_counter_label.text = "ROUND %d" % rn)
	
	var grapple_mgr = fight_manager.get_node("GrappleManager")
	grapple_mgr.dominance_changed.connect(_on_dominance_changed)
	grapple_mgr.grapple_ended.connect(func(_w, _l): grapple_panel.visible = false)

func _physics_process(_delta: float) -> void:
	if fight_manager:
		var t = fight_manager.round_timer
		round_timer_label.text = "%02d" % int(ceil(t))

func _update_bar(bar: TextureProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = value

func _on_dominance_changed(new_dominance: float) -> void:
	grapple_panel.visible = true
	dominance_bar.value = new_dominance
```

---

## フェーズ9：KO演出・ラウンド終了処理

**前提フェーズ**：フェーズ7、8

### 9-A. KOSequenceManager

**ファイル**：`res://scripts/managers/KOSequenceManager.gd`

`main.tscn`の子ノードとしてアタッチ。KO演出の一連の流れを管理。

```gdscript
class_name KOSequenceManager
extends Node

@export var fight_manager: FightManager

# === KO演出設定 ===
const SLOWMO_DURATION: float = 0.8      # スローモーション継続秒数
const SLOWMO_TIME_SCALE: float = 0.15   # スロー中のEngine.time_scale
const FREEZE_DURATION: float = 0.3      # ヒットストップ（完全停止）秒数
const KO_TEXT_DURATION: float = 2.0    # KOテキスト表示秒数
const NEXT_ROUND_DELAY: float = 3.0    # 次ラウンドまでの待機秒数

# === HUDオーバーレイ参照（シーンに KO_Overlay (CanvasLayer) を追加すること） ===
@onready var ko_overlay: CanvasLayer = $KO_Overlay  # KO_Overlayノードを子に追加
@onready var ko_label: Label = $KO_Overlay/KO_Label
@onready var ko_camera_tween: Tween = null

func _ready() -> void:
	ko_overlay.visible = false
	fight_manager.ko_triggered.connect(_on_ko_triggered)
	fight_manager.round_ended.connect(_on_round_ended)
	fight_manager.match_ended.connect(_on_match_ended)

func _on_ko_triggered(loser: Node) -> void:
	# Step 1: ヒットストップ（完全停止）
	Engine.time_scale = 0.0
	await get_tree().create_timer(FREEZE_DURATION, true, false, true).timeout
	
	# Step 2: スローモーション
	Engine.time_scale = SLOWMO_TIME_SCALE
	
	# カメラをloserに向けるTween（WorldEnvironmentやCameraへのアクセスは既存実装に依存）
	# SpringArm3DカメラをKOキャラクターにフォーカスするコードをここに追加
	
	await get_tree().create_timer(SLOWMO_DURATION, true, false, true).timeout
	Engine.time_scale = 1.0
	
	# Step 3: KOテキスト表示
	ko_label.text = "K.O."
	ko_overlay.visible = true
	# KOラベルのアニメーション（Tweenでスケールアップ）
	var tween = create_tween()
	tween.tween_property(ko_label, "scale", Vector2(1.5, 1.5), 0.3).from(Vector2(0.5, 0.5))
	
	await get_tree().create_timer(KO_TEXT_DURATION).timeout
	ko_overlay.visible = false

func _on_round_ended(winner_id: GameEnums.PlayerID) -> void:
	await get_tree().create_timer(NEXT_ROUND_DELAY).timeout
	fight_manager.start_round()

func _on_match_ended(winner_id: GameEnums.PlayerID) -> void:
	ko_label.text = "PLAYER %d WINS!" % (1 if winner_id == GameEnums.PlayerID.PLAYER_ONE else 2)
	ko_overlay.visible = true
	# タイトル画面に戻るボタン等を表示（実装は別途）
```

---

## 全体ノード構成図

```
main.tscn
├── WorldEnvironment（既存）
├── DirectionalLight3D（既存）
├── Stage（3Dステージメッシュ）
├── FightManager（Node）
│   └── GrappleManager（Node）
├── KOSequenceManager（Node）
├── Player1（CharacterBody3D）  ← player.tscn
│   ├── MeshInstance3D（視覚的なキャラクター）
│   ├── CollisionShape3D
│   ├── SpringArm3D（カメラ、既存）
│   ├── AnimationPlayer
│   ├── HealthComponent（Node）  ← CharacterStatsリソース割り当て
│   ├── CombatController（Node）
│   │   ├── StateIdle
│   │   ├── StateWalking
│   │   ├── StateAttacking
│   │   ├── StateGuarding
│   │   ├── StateGrappling
│   │   ├── StateGrappled
│   │   ├── StateHitStun
│   │   ├── StateKnockdown
│   │   ├── StateGettingUp
│   │   ├── StateIncapacitated
│   │   └── StateKO
│   ├── ComboManager（Node）  ← ComboNodeリソース割り当て
│   ├── HitboxManager（Node3D）
│   │   ├── Hitbox（Area3D）  ← Layer:2, Mask:4
│   │   │   └── CollisionShape3D
│   │   └── Hurtbox（Area3D）  ← Layer:4, Mask:2
│   │       └── CollisionShape3D
│   └── InputHandler（Node）
│
├── Player2（CharacterBody3D）  ← opponent.tscn（player.tscnと同構成）
│   └── ...（同上）
│
└── HUD（hud.tscn、CanvasLayer）
	└── KO_Overlay（CanvasLayer）
		└── KO_Label（Label）
```

---

## 定数・列挙型一覧

### InputMap登録が必要なアクション名

| アクション名 | デフォルトキー（P1） | デフォルトキー（P2） |
|---|---|---|
| `p1_punch` | J | テンキー1 |
| `p1_kick` | K | テンキー2 |
| `p1_grapple` | L | テンキー3 |
| `p1_guard` | I | テンキー0 |
| `p1_move_left` | A | 左矢印 |
| `p1_move_right` | D | 右矢印 |
| `p1_move_up` | W | 上矢印 |
| `p1_move_down` | S | 下矢印 |
| `p2_punch` | テンキー1 | （P2用） |
| `p2_kick` | テンキー2 | （P2用） |
| `p2_grapple` | テンキー3 | （P2用） |
| `p2_guard` | テンキー0 | （P2用） |

### コリジョンレイヤー割り当て

| レイヤー番号 | 用途 |
|---|---|
| Layer 1 | ワールド（ステージ・床） |
| Layer 2 | Player1 Hitbox（攻撃判定） |
| Layer 3 | Player2 Hitbox（攻撃判定） |
| Layer 4 | Player1 Hurtbox（被弾判定） |
| Layer 5 | Player2 Hurtbox（被弾判定） |

Player1のHitbox Mask → Layer 5（Player2 Hurtboxを検出）
Player2のHitbox Mask → Layer 4（Player1 Hurtboxを検出）

### Engine設定（Project Settings）

```
physics/common/physics_ticks_per_second = 60
```

### 主要なシグナル一覧

| 発信元 | シグナル名 | 引数 | 受信先 |
|---|---|---|---|
| HealthComponent | recoverable_hp_depleted | なし | CombatController |
| HealthComponent | permanent_hp_depleted | なし | CombatController, FightManager |
| HealthComponent | incapacitation_ended | なし | CombatController |
| HealthComponent | recoverable_hp_changed | float, float | HUDController |
| HealthComponent | permanent_hp_changed | float, float | HUDController |
| HitboxManager | hit_landed | Node, AttackData, HitResult | CombatController |
| HitboxManager | grapple_initiated | Node, GrappleData | CombatController |
| CombatController | state_changed | CharacterState | HUDController（任意） |
| ComboManager | combo_attack_resolved | AttackData, bool, float | CombatController |
| GrappleManager | dominance_changed | float | HUDController |
| GrappleManager | grapple_damage_dealt | Node, float, float | FightManager |
| GrappleManager | grapple_ended | Node, Node | FightManager |
| FightManager | round_started | int | HUDController, KOSequenceManager |
| FightManager | round_ended | PlayerID | KOSequenceManager |
| FightManager | match_ended | PlayerID | KOSequenceManager |
| FightManager | ko_triggered | Node | KOSequenceManager |

---

## 実装順序の推奨

1. **フェーズ1**：GameEnums（AutoLoad登録まで）→ AttackData.gd → GrappleData.gd → CharacterStats.gd → `.tres`ファイル作成
2. **フェーズ2**：HealthComponent.gd → player.tscnに追加してテスト
3. **フェーズ3**：DamageCalculator.gd → HitboxManager.gd（HitboxノードとHurtboxノードもシーンに追加）
4. **フェーズ5**：ComboNode.gd → コンボツリー`.tres`作成 → ComboManager.gd
5. **フェーズ6**：BaseState.gd → 全StateXxx.gd → CombatController.gd → player.tscnのノード構成更新
6. **フェーズ4**：GrappleManager.gd（main.tscnに追加）
7. **フェーズ7**：InputHandler.gd → FightManager.gd（main.tscnに追加）
8. **フェーズ8**：hud.tscn作成 → HUDController.gd
9. **フェーズ9**：KOSequenceManager.gd（KO_Overlayシーンも作成）

---

> **エージェントへの注意事項**：各フェーズの実装完了後は、Godot 4エディタでスクリプトにエラーがないことを確認してから次フェーズに進むこと。GDScriptの構文エラーは`@onready`の参照先ノードが存在しない場合に多く発生するため、シーンのノード構成とスクリプトのノードパスが一致しているか必ず確認すること。
```
