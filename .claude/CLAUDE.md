# Wrestling Game — Claude 開発ガイド

## 基本情報
- **エンジン**: Godot 4.6 (Forward Plus, Jolt Physics, 1920×1080)
- **言語**: GDScript
- **ゲームジャンル**: 近接視点 3D プロレス/MMA アクション（1vs1 対戦）
- **メインシーン**: `res://scenes/ui/title.tscn`（起動時）→ char_select → main

---

## ディレクトリ構造

```
wrestling/
├── assets/
│   ├── animations/characters/player/  ← FBX + コンパイル済み .res
│   ├── audio/bgm/                     ← MP3 (gitignore済)
│   ├── models/characters/             ← .glb / .vrm (gitignore済)
│   └── textures/characters/player/   ← PNG テクスチャ群
├── resources/
│   ├── attacks/        ← AttackData .tres × 6 (punch/kick/grapple各2種)
│   ├── characters/     ← CharacterStats .tres × 3 (balanced/striker/grappler)
│   ├── ai_profiles/    ← AIProfile .tres × 3 (balanced/striker/grappler)
│   ├── difficulty/     ← DifficultyProfile .tres × 5 (easy/normal/hard/expert/legend)
│   └── combos/         ← combo_tree_root.tres (15 ComboNode 埋め込み)
├── scenes/
│   ├── characters/     ← player.tscn (character_base.tscn / cpu_opponent.tscn は空)
│   ├── game/           ← main.tscn, ring_stage.tscn
│   └── ui/             ← title.tscn, char_select.tscn, hud.tscn, settings.tscn
└── scripts/
    ├── autoload/     ← GameEnums, AudioManager, GameManager, SceneManager
    ├── ai/           ← AIBrain, AIStateBase, ai_states/, MoveSelector, SpatialAwareness
    ├── characters/   ← CharacterBase, PlayerController, CPUController
    ├── combat/       ← GrappleSystem(旧互換スタブ), HitboxController(旧互換スタブ)
    ├── data/         ← AttackData, GrappleData, CharacterStats, ComboNode,
    │                    AIProfile, DifficultyProfile
    ├── debug/        ← DebugOverlay
    ├── game/         ← main.gd
    ├── managers/     ← FightManager, InputHandler, KOSequenceManager
    ├── states/       ← BaseState + 11個のStateクラス
    ├── systems/      ← CombatController, ComboManager, DamageCalculator,
    │                    GrappleManager, HealthComponent, HitboxManager
    └── ui/           ← HUDController, CharSelect, TitleScreen, SettingsMenu
```

---

## AutoLoad (project.godot)

| 名前 | スクリプト | 役割 |
|------|-----------|------|
| GameEnums | `scripts/autoload/GameEnums.gd` | 全列挙型定義 |
| AudioManager | uid参照 | BGM再生・バス管理・ダッキング |
| GameManager | uid参照 | 試合状態・ポーズ・設定保存 |
| SceneManager | uid参照 | フェード付きシーン遷移 |
| GrappleSystem | `scripts/combat/GrappleSystem.gd` | 旧互換スタブ (実処理はGrappleManager) |

---

## 主要列挙型 (GameEnums)

```gdscript
ActionType    : NONE, PUNCH, KICK, GRAPPLE, GUARD
HitResult     : WHIFF, BLOCKED, HIT, COUNTER_HIT, GRAPPLE_SUCCESS, GRAPPLE_FAIL
DamageLayer   : RECOVERABLE, PERMANENT
CharacterState: IDLE, WALKING, RUNNING, ATTACKING, GUARDING, GRAPPLING,
                GRAPPLED, HIT_STUN, KNOCKDOWN, GETTING_UP, INCAPACITATED, KO
GrapplePosition: NEUTRAL, DOMINANT, SUBDUED
RoundState    : WAITING, FIGHTING, ROUND_END, MATCH_END
PlayerID      : PLAYER_ONE, PLAYER_TWO
```

---

## コアシステムアーキテクチャ

### キャラクター構成（実行時に動的構築 — main.gd `_attach_combat_system()`）

```
Player (CharacterBody3D) ← scripts/characters/PlayerController.gd
│   ← player.tscn に存在: CollisionShape3D, AnimationPlayer, AnimationTree,
│     HitboxRight(旧互換Area3D), SpringArm3D/Camera3D, test/GeneralSkeleton/...
│
├── CombatController (Node3D) ← scripts/systems/CombatController.gd
│   ├── HealthComponent        ← scripts/systems/HealthComponent.gd
│   ├── HitboxManager          ← scripts/systems/HitboxManager.gd
│   │   ├── Hitbox (Area3D)    Layer4(hitbox) → mask Layer5(hurtbox)
│   │   └── Hurtbox (Area3D)   Layer5(hurtbox) monitorable=true
│   ├── ComboManager           ← scripts/systems/ComboManager.gd
│   ├── StateIdle / StateWalking / StateAttacking / StateGuarding
│   ├── StateGrappling / StateGrappled / StateHitStun
│   ├── StateKnockdown / StateGettingUp / StateIncapacitated / StateKO
└── InputHandler (P1のみ)     ← scripts/managers/InputHandler.gd
```

**Player2** は player.tscn を `set_script(CPUController)` で差し替えて使用。
CPUController は `is_dummy = true` を設定し、さらに AIBrain ノードを動的生成して add_child。

### シーン構成 (main.tscn)

```
Main (Node3D) ← scripts/game/main.gd
├── FightManager ← scripts/managers/FightManager.gd
│   └── GrappleManager ← scripts/systems/GrappleManager.gd
├── KOSequenceManager ← scripts/managers/KOSequenceManager.gd
│   └── KO_Overlay (CanvasLayer)
│       └── KO_Label
└── [環境・リング・照明群]
    ← Player1/Player2 は main.gd._spawn_characters() で動的生成
```

### SpringArm カメラ（P1専用）

SpringArm3D は player.tscn に存在するが、`_defer_detach_camera()` でシーンルートの直接子として切り離される（キャラの回転に連動しないため）。毎フレーム `_update_spring_arm_position()` で数学的に追従させる。

```
SpringArm3D (シーンルート直下に cut)
  └── Camera3D  ← cam.current = true (P1のみ)
```

**カメラパラメータ（PlayerController エクスポート）**
- `camera_distance = 1.5`m : spring_length（_defer_detach_camera() で設定）
- `camera_side_offset = 0.7`m : pivot を `-basis.x`（スクリーン右）方向にずらし、プレイヤーを画面左寄りに配置して相手エリアを確保
- pivot 高さ: `global_position + (0, 1.2, 0) + (-basis.x) * camera_side_offset`
- pitch: `-25°`（見下ろし固定）
- yaw: `rotation.y + PI`（キャラ背後）

---

## データ定義クラス

### AttackData (`resources/attacks/*.tres`)
```
attack_name, action_type (ActionType)
startup_frames, active_frames, recovery_frames  ← 60fps基準
recoverable_damage, permanent_damage, stamina_cost
hitbox_size (Vector3), hitbox_offset (Vector3)
counter_hit_multiplier (1.5)
hit_stun_frames, block_stun_frames
max_range, animation_name, cancel_into (Array[ActionType])
```
**既存リソース**: punch_light, punch_heavy, kick_light, kick_heavy,
               grapple_basic, grapple_power

### CharacterStats (`resources/characters/stats_*.tres`)
```
max_recoverable_hp, max_permanent_hp
recoverable_hp_regen_rate, recoverable_hp_regen_delay
punch_damage_multiplier, kick_damage_multiplier, grapple_damage_multiplier
defense_multiplier, incapacitated_dominance_penalty
incapacitated_duration
```

### GrappleData
```
startup_frames, active_frames, recovery_frames
recoverable_damage, permanent_damage, stamina_cost
hitbox_size, hitbox_offset, max_range
initiator_animation, receiver_animation
dominance_damage_threshold, dominant_damage_multiplier
```

### ComboNode (`resources/combos/combo_tree_root.tres`)
```
attack_data (AttackData), branches (Dictionary {"PUNCH": ComboNode, "KICK": ComboNode})
hit_count, is_ender (bool), ender_damage_multiplier (1.3), window_frames (30)
```

### AIProfile (`resources/ai_profiles/ai_*.tres`)
```
aggression, grapple_preference, risk_taking, showmanship, discretion (0.0〜1.0)
weights_early/mid/late/critical: Dictionary {action_key: weight}
  action_key: "punch_light","punch_heavy","kick_light","kick_heavy","grapple","guard"
  ※ "circle","stall" は MoveSelector 内でフォールバック処理（実質無効）
preferred_combo_routes: Array[String]  例: ["PPP", "PPK"]
combo_attempt_rate, pattern_frequency
signature_pattern: "none" | "strike_strike_grapple" | "grapple_after_guard" | "heavy_opener"
```

### DifficultyProfile (`resources/difficulty/difficulty_*.tres`)
```
reaction_delay_min/max (sec)
counter_probability           (0.0〜1.0)
grapple_counter_probability   (0.0〜1.0)
combo_execution_rate          (0.0〜1.0)
optimal_move_selection        (0.0〜1.0)
enables_body_part_targeting   (Hard以上: true)
enables_pattern_adaptation    (Expert以上: true)
input_read_probability
grapple_mash_rate             (0.0〜1.0)
reposition_duration (sec)     ← REPOSITION フェーズの持続時間
```

---

## 戦闘フロー

### 入力 → ダメージまでの流れ
```
InputHandler._input()
  → is_stepping() チェック（ステップ中は戦闘入力を無効化）
  → CombatController.receive_input(action)
    → _current_state_node.handle_input(action)

[StateIdle/StateWalking.handle_input]
  → ComboManager.try_input(action)  ← combo_tree_root から AttackData を解決
  → CombatController._pending_attack = attack
  → transition_to(ATTACKING)
  ※ ATTACKINGへの遷移により PlayerController._handle_movement() が速度を0にリセット

[StateAttacking.update]
  startup → active: hitbox_manager.activate_hitbox(attack)
  active → recovery: hitbox_manager.deactivate_hitbox()
                     combo_manager.open_combo_window()
  recovery完了: combo_manager.close_combo_window()
               transition_to(IDLE)

[HitboxManager._on_hitbox_area_entered]
  → hit_landed シグナル → CombatController._on_hit_landed()
    → FightManager.process_hit(attacker_ctrl, target, attack, result)
      → DamageCalculator.calculate_attack_damage() × _ender_damage_multiplier
      → target_health.take_damage()
      → target_ctrl.transition_to(HIT_STUN)

      【BLOCKED の場合（ガード成功報酬）】
      → attacker_health.take_damage(attack.recoverable_damage * 0.5, RECOVERABLE)
      → attacker_node.velocity += kb_dir.normalized() * 4.0  (ノックバック)
      → attacker_ctrl._pending_hit_stun_frames = max(ceil(block_stun * 0.5), 5)
      → attacker_ctrl.transition_to(HIT_STUN)
```

### コンボシステム
```
ROOT → P(punch_light) → PP(punch_heavy) → PPP(kick_heavy×1.3✦) / PPK(kick_light×1.3✦)
                      → PK(kick_light)  → PKP(punch_heavy×1.3✦) / PKK(kick_heavy×1.3✦)
     → K(kick_light)  → KP(punch_light) → KPP(punch_heavy×1.3✦) / KPK(kick_heavy×1.3✦)
                      → KK(kick_heavy)  → KKP(punch_heavy×1.3✦) / KKK(kick_heavy×1.3✦)
✦ = is_ender=true, ender_damage_multiplier=1.3, window_frames=30
```
- コンボウィンドウ: recovery フェーズ開始時に `open_combo_window()` を呼ぶ
- エンダー倍率: `CombatController._ender_damage_multiplier` に保持 → FightManager で適用後リセット

### 二層 HP システム
```
回復可能HP (白バー): 打撃ダメージ先。スタミナも兼ねる（ステップ消費）。時間回復あり。
                    枯渇 → INCAPACITATED（行動不可、一定時間後20%で復活）
回復不可能HP (赤バー): グラップルダメージ先。回復なし。
                      枯渇 → KO → round_end
行動不可中の追加ダメージ: take_damage(PERMANENT) × 1.3
```

### ステップシステム (PlayerController)
```
発動: Shift キー（run アクション）just_pressed かつ クールダウン終了かつ スタミナ足りる
  ↓
consume_stamina(step_stamina_cost=8.0)  ← 回復可能HPから差し引き
  ↓
移動キーあり → その方向にステップ
移動キーなし → 後方（-basis.z）にステップ
  ↓
STEP 状態へ（duration=0.15s、distance=1.2m → speed=8m/s）
  前半(50%): Hurtbox.monitorable = false（無敵）
  後半(50%): Hurtbox.monitorable = true
  終了時:    is_stamina_regen_active = true（回復再開）
  ↓
エフェクト: 3本の BoxMesh 残像（0.2秒フェードアウト）

制約:
  - ステップ中は戦闘入力を無効化（InputHandler.is_stepping() チェック）
  - クールダウン: 0.4秒
  - スタミナ不足の場合は発動しない
```

### グラップルシステム (dominance型)
```
GrappleManager (FightManager の子)
dominance: 0.5スタート → GRAPPLEボタン連打で +0.08/入力（攻め側のみ）
CPU は AIBrain._handle_grapple_mashing() で grapple_mash_rate 確率で register_input

【終了条件】
  dominance = 1.0 → 攻め側勝利: 受け側の回復不可能HPに -20
  dominance = 0.0 → 受け側勝利: 攻め側の回復不可能HPに -20
  ※ タイムアウトなし

【decay レート（/sec）: diff = 攻め側HP − 受け側HP】
  diff < -30      : 0.25   diff < -1     : 0.15
  -1 ≤ diff ≤ 1   : 0.1    diff ≤ 30    : 0.05
  diff > 30       : 0.03

【グラップル中カメラ】
  GrappleManager が専用 Camera3D を動的生成（シーンルート直下に add_child）
  位置: 両者の中点から横方向（X 側）に cam_dist = max(fighters_dist * 2.2, 3.5)
  FOV: 55度
  終了時: SpringArm 内の Camera3D を current=true に戻し、専用カメラを queue_free
```

---

## アニメーションシステム

### AnimationTree ステート名（player.tscn内）
```
Idle, Walk, Run, AttackLight, AttackHeavy, Grapple, Block, Hit, Down
※ Jump/JumpDown は player.tscn に存在するがジャンプ機能は削除済み（未使用）
```

### CombatController.play_anim() マッピング
```gdscript
"idle"              → "Idle"
"walk"              → "Walk"
"guard"             → "Block"
"hit_stun"          → "Hit"
"knockdown"/"ko"    → "Down"
"grapple_initiator" → "Grapple"
"grapple_receiver"  → "Idle"  ← 未実装（モーションなし）
"getting_up"        → "Idle"  ← 未実装（モーションなし）
その他              → そのまま渡す (AttackLight, AttackHeavy 等)
```

### 重要: アニメーション競合防止
`PlayerController._update_animation()` は毎フレーム呼ばれるが、
CombatController が IDLE/WALKING/RUNNING 以外の場合はスキップ（return）して
CombatController のアニメーション制御に委ねる。

---

## 入力マッピング

| アクション | キー | コントローラー |
|-----------|------|-------------|
| move_forward/back/left/right | WASD | 左スティック |
| attack light (PUNCH) | J | ボタン2 |
| attack heavy (KICK) | K | ボタン0 |
| grapple | L | ボタン3 |
| block | I | ボタン10 |
| step (run) | Shift | RT(axis5) |
| ui_pause | Esc | ボタン6 |
| ~~jump~~ | ~~Space~~ | ~~ボタン1~~ | ← 削除済み

**移動の基準軸（重要）**
- 両キャラは常に相手の方向を向く（`_face_opponent()` が毎フレーム `rotation.y` を lerp）
- W / 左スティック前：相手方向へ前進（`-input_dir.y * basis.z`）
- S / 左スティック後：相手と逆方向へ後退
- A / D：横移動（`input_dir.x * (-basis.x)`）
- `basis.z` = モデル前方 = 相手方向（+Z）
- `-basis.x` = スクリーン右方向
- カメラはキャラ背後に自動追従（`_camera_yaw = rotation.y + PI`）

**移動禁止条件（PlayerController._handle_movement）**
- CombatController が ATTACKING / GRAPPLING / GRAPPLED の状態 → velocity.x/z = 0, return
- PlayerController が STEP 状態 → ステップ速度で上書き（通常移動ブロック）

---

## キャラクタースクリプト継承関係

```
CharacterBody3D
  └── CharacterBase (scripts/characters/CharacterBase.gd)
        ├── player_id: int, is_dead (→CombatController.KO参照)
        ├── is_stamina_regen_active: bool
        ├── consume_stamina() → CombatController/HealthComponent.consume_stamina()
        └── PlayerController (scripts/characters/PlayerController.gd)
              ← 移動・ステップ・カメラ・アニメーション制御
              ├── walk_speed = 2.0, gravity_scale = 2.0
              ├── camera_distance = 1.5, camera_side_offset = 0.7
              ├── step_distance = 1.2, step_duration = 0.15,
              │   step_cooldown = 0.4, step_stamina_cost = 8.0
              ├── opponent: CharacterBody3D  ← main.gd で代入
              ├── _face_opponent(delta): lerp_angle で毎フレーム相手方向へ
              ├── _update_spring_arm_position(): カメラ追従（切り離し済み SpringArm）
              ├── _set_hurtbox_enabled(bool): ステップ無敵
              ├── is_stepping() → bool: InputHandler が参照
              ├── State enum: IDLE, WALK, RUN, JUMP, FALL,
              │              ATTACK_LIGHT, ATTACK_HEAVY, GRAPPLE,
              │              BLOCK, HIT, DOWN, GRAPPLE_LOCK, STEP
              │   ※ JUMP/FALL は enum に残るが入力トリガーは削除済み
              └── CPUController (scripts/characters/CPUController.gd)
                    ← AI思考（AIPhaseステートマシン）
                    ← is_dummy=true で SpringArm カメラ追従をスキップ
                    ├── cpu_walk_speed = 3.5 (walk_speed=2.0 より速い)
                    ├── cpu_step_duration = 0.15, cpu_step_cooldown = 0.8
                    ├── cpu_step_chance = 0.30 (APPROACH 中 1秒あたり確率)
                    └── AIBrain (動的生成, CPUController の子)
                          ├── SpatialAwareness (動的生成)
                          └── MoveSelector (動的生成)
```

---

## 主要スクリプト: メソッド/シグナル一覧

### PlayerController
- `_face_opponent(delta)`: 毎フレーム相手方向に `rotation.y` を lerp
- `_update_spring_arm_position()`: SpringArm の pivot と向きを毎フレーム計算
- `_set_hurtbox_enabled(bool)`: `CombatController/HitboxManager/Hurtbox` の monitorable 切替
- `is_stepping() → bool`: STEP 状態かどうか（InputHandler が参照）
- `exit_grapple_lock()`: FightManager._on_grapple_ended() からの旧互換呼び出し
- `_spawn_step_effect(pos, dir)`: ステップ時の残像エフェクト生成

### CombatController
- `receive_input(action: ActionType)` — 外部から入力を渡す
- `transition_to(state: CharacterState)` — ステート遷移
- `get_current_state() → CharacterState`
- `play_anim(name: String)` — AnimationTree に travel()
- `_pending_attack: AttackData`, `_pending_grapple_data: GrappleData`
- `_ender_damage_multiplier: float` — コンボエンダー時の倍率(1.3)、使用後リセット
- **シグナル**: `state_changed(new_state)`

### ComboManager
- `try_input(action) → AttackData` — コンボツリーを辿り次の攻撃を返す
- `open_combo_window()` — active→recovery 遷移時に呼ぶ
- `close_combo_window()` — recovery 終了時に呼ぶ
- `reset_combo()`
- `combo_tree_root: ComboNode` — エクスポート変数。main.gd で代入
- **シグナル**: `combo_attack_resolved(attack, is_ender, multiplier)`, `combo_reset()`

### HealthComponent
- `take_damage(amount, layer: DamageLayer)`
- `consume_stamina(amount) → bool` — 回復可能HPから差し引き。ステップ発動時も使用
- `reset()` — ラウンド開始時
- `is_incapacitated() → bool`
- `set_regen_paused(paused: bool)` — グラップル中に GrappleManager から呼ぶ
- **シグナル**: `recoverable_hp_changed(val, max)`, `permanent_hp_changed(val, max)`,
  `recoverable_hp_depleted()`, `permanent_hp_depleted()`, `incapacitation_ended()`

### HitboxManager
- `activate_hitbox(attack: AttackData)` / `activate_grapple_hitbox(grapple)`
- `deactivate_hitbox()`
- Hurtbox.monitorable: ステップ無敵中は PlayerController が false に設定
- **シグナル**: `hit_landed(target, attack_data, result)`, `grapple_initiated(target, grapple_data)`

### GrappleManager
- `start_grapple(initiator, receiver, grapple_data)`
- `register_input(player_id)` — 各キャラからの入力ボタン押下
- `is_active: bool`
- **シグナル**: `grapple_ended(winner, loser)`, `dominance_changed(val)`
- `_create_grapple_camera()`: 専用 Camera3D をシーンルートに動的生成
- `_destroy_grapple_camera()`: SpringArm の Camera3D を current=true に戻して専用カメラ破棄

### FightManager
- `set_fighters(p1, p2)` — キャラ設定後に start_round() を呼ぶ
- `process_hit(attacker_ctrl, target, attack, result)` — ガード成功報酬含む
- `process_grapple_start(initiator_ctrl, target, grapple)` — HitboxManager.grapple_initiated 経由
- `start_round()`
- **シグナル**: `round_started(n)`, `round_ended(winner_id)`, `match_ended(winner_id)`,
  `ko_triggered(loser)`, `timer_updated(time_remaining)`

### InputHandler (P1専用)
- `_input(event)` でイベントドリブン検出 → `_send()` → `CombatController.receive_input()`
- `_send()`: 先頭で `parent.is_stepping()` チェック。ステップ中は戦闘入力を破棄
- **シグナル**: `input_received(action)` (DebugOverlay が接続)

### AIBrain
- `initialize(owner, opponent, own_ctrl, opp_ctrl, profile, difficulty)`
- `request_attack() → String` — CPUController の ENGAGE フェーズから同期呼び出し
- `notify_attack_executed(action_key)` — コンボ追跡開始
- `action_decided` シグナル — リアクティブガード時に CPUController へ通知
- 子コンポーネント: `spatial: SpatialAwareness`, `move_selector: MoveSelector`

### SpatialAwareness
- 毎フレーム更新する公開プロパティ:
  - `distance_to_opponent`, `direction_to_opponent`
  - `is_opponent_in_strike_range` (≤2.0m), `is_opponent_in_grapple_range` (≤1.2m)
  - `is_in_corner`, `is_opponent_in_corner`, `is_near_ropes`, `is_opponent_near_ropes`
  - `opponent_facing_us`

---

## CPU AI システム

### AIPhase ステートマシン（CPUController）

```
APPROACH  → 毎フレーム相手方向へ cpu_walk_speed(3.5) で歩く
            30%/秒の確率で前方ステップ接近（クールダウン 0.8s）
            is_opponent_in_strike_range → ENGAGE

ENGAGE    → 30% 確率で横ステップ回避（_circle_dir で左右交互）
            攻撃実行 → WAIT
            _is_combat_busy → WAIT（_wait_timer リセット）
            射程外 → APPROACH

WAIT      → 停止。CC が IDLE に戻った瞬間 OR 2秒タイムアウトで次フェーズ判定
            射程内 → ENGAGE、射程外 → APPROACH

REPOSITION→ 後退ステップを試みる（クールダウン中は cpu_walk_speed で通常歩行）
            _reposition_timer 満了 → APPROACH
            _reposition_dir = ZERO（ガードモード）の場合は停止
```

**割り込み処理**
- HIT_STUN 発生（前フレームと状態変化した瞬間）→ 即 REPOSITION
  - 回復可能HP < 40% かつ射程内 → ガード発動 + `_reposition_dir = ZERO`
  - それ以外 → 相手から遠ざかる方向 + わずかに横成分（`_circle_dir` で交互）

**ステップ実装の注意点（`_update_ai_phase` の構造）**
- ステップ中でも early return せず phase match を常に実行する
- `is_stepping_now` フラグで速度を末尾で上書き
- 理由: early return すると `_last_cc_state` の更新が欠落し、
  WAIT フェーズの「IDLE 遷移検出」が誤動作してフリーズが発生する

**WAIT フリーズ対策**
- 正常脱出: `cc_state == IDLE and _last_cc_state != IDLE`（CC の状態遷移検出）
- タイムアウト脱出: `_wait_timer > 2.0 and cc_state == IDLE`
- `_wait_timer` は WAIT 移行時（`_phase_engage` 内）にリセット

### リアクティブガード（AIBrain）
- opponent.state_changed → ATTACKING or GRAPPLING → `counter_probability` でガード予約
- reaction_delay 後に `action_decided("guard")` シグナル → CPUController が GUARD 実行 → APPROACH

### グラップル連打（AIBrain）
- GRAPPLING/GRAPPLED 状態中: 0.1秒ごとに `grapple_mash_rate` 確率で `register_input()` 呼び出し

### 戦略ステート遷移
```
opportunistic(初期) → aggressive(相手被ダメ>60%) / defensive(自HP<25%)
aggressive         → defensive(自HP<25%) / opportunistic(相手ATTACKING)
defensive          → opportunistic(自HP>50%) / aggressive(相手KNOCKDOWN/INCAPACITATED)
recovery           → opportunistic(自HP>40%, 最低3sec) / defensive(自HP>25%, 最低3sec)
```

---

## State 実装早見表

| クラス | enter() | update() | handle_input() |
|--------|---------|----------|---------------|
| StateIdle | play_anim("idle") | — | PUNCH/KICK→ComboManager, GRAPPLE→ATTACKING, GUARD→GUARDING |
| StateWalking | — | — | IDLEと同じ戦闘入力を受け付け |
| StateAttacking | play_anim(attack/grapple) | startup→active→recovery フレーム管理 | recovery中のみ combo継続入力を受付 |
| StateGuarding | play_anim("guard") | block_stun終了でIDLEへ | — |
| StateGrappling | play_anim("grapple_initiator") | GrappleManager.register_input()を毎フレーム | — |
| StateGrappled | play_anim("grapple_receiver") | 同上(受け側) | — |
| StateHitStun | play_anim("hit_stun") | pending_hit_stun_framesカウントダウン→IDLE | — |
| StateKnockdown | play_anim("knockdown") | 180f後にGETTING_UP | — |
| StateGettingUp | play_anim("getting_up")=Idle | 60f後にIDLE | — |
| StateIncapacitated | — | HealthComponent.incapacitation_ended→GETTING_UP | — |
| StateKO | play_anim("ko")=Down | — | — |

---

## DamageCalculator (static class)

```gdscript
calculate_attack_damage(attack, result, atk_stats, def_stats) → {recoverable, permanent}
  - PUNCH/KICK → attacker_stats の倍率
  - COUNTER_HIT → counter_hit_multiplier(1.5)
  - BLOCKED → {0, 0}  ← ダメージなし（ガード報酬は FightManager 側で別途処理）
  - × def_stats.defense_multiplier
  ※ FightManager で _ender_damage_multiplier をさらに掛ける

calculate_grapple_damage(grapple, dominance, atk_stats, def_stats) → {recoverable, permanent}
  - dominance >= threshold → dominant_damage_multiplier
  - × attacker_stats.grapple_damage_multiplier, def_stats.defense_multiplier
  ※ GrappleData のダメージ値は現状未使用（終了時は GRAPPLE_FINISH_DAMAGE=20 固定）
```

---

## .tres リソースファイル一覧

| パス | クラス | 備考 |
|------|-------|------|
| resources/attacks/punch_light.tres | AttackData | startup4,active3,recovery8,dmg8,anim=AttackLight |
| resources/attacks/punch_heavy.tres | AttackData | startup6,active4,recovery14,dmg15,anim=AttackHeavy |
| resources/attacks/kick_light.tres | AttackData | startup10,active4,recovery12,dmg12,anim=AttackLight |
| resources/attacks/kick_heavy.tres | AttackData | startup14,active5,recovery18,dmg20,anim=AttackHeavy |
| resources/attacks/grapple_basic.tres | GrappleData | 基本グラップル |
| resources/attacks/grapple_power.tres | GrappleData | 強グラップル |
| resources/characters/stats_balanced.tres | CharacterStats | バランス型 |
| resources/characters/stats_striker.tres | CharacterStats | 打撃特化 |
| resources/characters/stats_grappler.tres | CharacterStats | グラップル特化 |
| resources/combos/combo_tree_root.tres | ComboNode | 15ノード全埋め込み |
| resources/ai_profiles/ai_balanced.tres | AIProfile | バランス型AI |
| resources/ai_profiles/ai_striker.tres | AIProfile | 打撃特化AI |
| resources/ai_profiles/ai_grappler.tres | AIProfile | グラップル特化AI |
| resources/difficulty/difficulty_easy.tres | DifficultyProfile | 易しい |
| resources/difficulty/difficulty_normal.tres | DifficultyProfile | 普通 |
| resources/difficulty/difficulty_hard.tres | DifficultyProfile | 難しい |
| resources/difficulty/difficulty_expert.tres | DifficultyProfile | エキスパート |
| resources/difficulty/difficulty_legend.tres | DifficultyProfile | 伝説 |

---

## 未実装・既知課題

| 項目 | 状態 | 場所 |
|------|------|------|
| 起き上がりモーション | `play_anim("getting_up")` → "Idle"で代用 | CombatController.play_anim MAP |
| グラップル受け側モーション | `play_anim("grapple_receiver")` → "Idle"で代用 | 同上 |
| char_select → CharacterStats 接続 | character_id がセットされるがStats未読込 | main.gd hardcode "balanced" |
| P2入力アクション分離 | attack light/heavy/grapple が P1 と共有 | project.godot / InputHandler |
| character_base.tscn / cpu_opponent.tscn | 空ファイル | scenes/characters/ |
| ring_stage.tscn | 内容不明 | scenes/game/ |
| ステップ専用アニメーション | Walk モーションで代用中 | PlayerController._update_animation() |
| GrappleData のダメージ値 | 未使用（GRAPPLE_FINISH_DAMAGE 固定） | GrappleManager |

---

## コーディング規約

- `class_name` を必ず宣言する
- デバッグ出力: `if GameManager.debug_mode: print(...)`
- ノード探索: `get_node_or_null()` を使い null チェックを行う
- 動的ノード生成: `main.gd._attach_combat_system()` パターンに従う
- `.tres` ファイルのスクリプトパス: `res://scripts/data/` 以下
- アニメーション再生: 直接 `anim_state.travel()` ではなく `CombatController.play_anim()` 経由
- シグナルの接続は `_ready()` 内で行う
- `@onready` はシーンに配置されたノードのみ使用（動的生成ノードは `_ready()` 内で手動代入）
- GDScript 型推論注意: `get_node_or_null()` は Variant を返すため `:=` での型推論不可 → 明示型宣言
- `max()` も Variant 問題あり → `maxf()` / `maxi()` を使う
- float 配列の for ループ: `for i in [0.1, 0.2]` のような書き方は `i` が Variant になり
  `Vector3 * i` がコンパイルエラー → `for idx in 3: var val: float = ...` パターンを使う

---

## 開発時の注意事項

1. **player.tscn にはCombatController系ノードが存在しない** — すべて `main.gd` で動的生成

2. **アニメーション競合**: `PlayerController._update_animation()` は CombatController が
   IDLE/WALKING/RUNNING 以外のとき return する

3. **コンボ継続の遷移**: StateAttacking.handle_input → `transition_to(IDLE)` → `transition_to(ATTACKING)`
   （同一ステートへの直接遷移を避けるため IDLE を経由する）

4. **グラップル入力**: GrappleManager.register_input() は StateGrappling/StateGrappled の
   update() から毎フレーム呼ばれる（GRAPPLE ボタン押しっぱなし判定）

5. **HealthComponent.consume_stamina()**: 回復可能HPからスタミナを消費。残量不足なら false

6. **FightManager はグループ "fight_manager"** に追加済み → `get_first_node_in_group()` で取得

7. **SpringArm の扱い**: `_defer_detach_camera()` でシーンルートに切り離し済み。
   P1 は毎フレーム `_update_spring_arm_position()` で追従。P2(CPU) は `is_dummy=true` でスキップ。
   `_exit_tree()` でシーン終了時に SpringArm を queue_free する

8. **CPU の AIPhase ステップ early return 禁止**: `_update_ai_phase()` 内でステップ実行中でも
   phase match は必ず実行し `_last_cc_state` を末尾で更新する。
   そうしないと WAIT フェーズの IDLE 遷移検出が壊れてフリーズが発生する

9. **移動と戦闘の排他制御**:
   - `PlayerController._handle_movement()`: CC が ATTACKING/GRAPPLING/GRAPPLED → 速度ゼロ
   - `InputHandler._send()`: `is_stepping()` チェックで STEP 中の戦闘入力を無効化

10. **カメラ向き**: モデル前方 = +Z ローカル。SpringArm は -Z 方向に伸びるため
    キャラ背後に配置するには `rotation.y + PI` が必要

---

## 残タスク一覧（優先度順）

GAME_DESIGN_DOCUMENT との比較を元に、現在のコードを正として今後追加・修正すべき内容を整理。

### ★★★ 最優先（ゲームループとして必須）

| # | タスク | 説明 |
|---|--------|------|
| 1 | **HUD ドミナンスバー実装** | GrapplePanel に `dominance_changed` シグナルを接続し、グラップル中のドミナンス値をバーで表示。現在 GrapplePanel 自体が未接続の可能性あり |
| 2 | **HUDController の完全検証** | TextureProgressBar 2本（回復可能HP・回復不可能HP）が両プレイヤー分正しく更新されているか確認。GDD Phase 8 仕様と照合 |
| 3 | **ラウンド数設定（max_rounds=3）** | FightManager の `max_rounds` が現在デフォルト1。GDD は3ラウンド制。ラウンド間リセット（HP回復）の動作も確認 |
| 4 | **CharSelect → CharacterStats 接続** | main.gd が `character_id` を受け取っても stats を "balanced" ハードコードしている。selected_character_id を読んで stats_*.tres を動的ロードするよう修正 |

### ★★ 高優先（戦闘バランスに直結）

| # | タスク | 説明 |
|---|--------|------|
| 5 | **StateGuarding: ガード持続中のスタミナ消費** | GDD 仕様: ガード中 2.0/sec でスタミナ消費、最大 3.0 秒。現在の StateGuarding がこれを実装しているか要確認。未実装ならガードが無限に強すぎる |
| 6 | **StateGuarding: ブロックスタン終了後の IDLE 遷移** | block_stun_frames カウントダウンが正しく機能しているか検証。長押し中にスタミナ切れ → INCAPACITATED への遷移チェック |
| 7 | **グラップル: 終了時ダメージ以外のモデル整合** | 現在は終了時一括 20 ダメージ。GDD は 1 秒インターバル制（`_process_damage()`）だったが現行設計を優先。ただしドミナンス≥1.0/≤0.0 の終了条件と「逆転（reversal）」ロジックがきちんと実装されているか確認 |
| 8 | **起き上がりアニメーション** | `getting_up` → "Idle" で代用中。FBX に起き上がりモーションがあれば AnimationLibrary に追加して差し替え |
| 9 | **グラップル受け側アニメーション** | `grapple_receiver` → "Idle" で代用中。同上 |

### ★ 中優先（体験向上）

| # | タスク | 説明 |
|---|--------|------|
| 10 | **AIProfile/DifficultyProfile を CharSelect で選択可能にする** | 現在 CPUController が固定リソースをロード。キャラ選択 or 難易度選択画面から渡せるようにする |
| 11 | **AIBrain リアクティブガード精度向上** | `counter_probability` / `reaction_delay` が DifficultyProfile 通りに機能しているか実測。Legend で過剰にガードしていないか |
| 12 | **コンボウィンドウ中の CPU 攻撃継続** | CPU が ENGAGE → WAIT 後、コンボウィンドウ(30f) 内に再入力できているか確認。AIPhase サイクルが 30f 以内に回れているか計測 |
| 13 | **DebugOverlay の整備** | ダメージログ・AI フェーズ・HP 値を画面表示できるようにする（デバッグ効率化） |
| 14 | **設定の永続化確認** | SettingsMenu の音量・解像度設定が ConfigFile に保存・復元されているか確認 |

### ☆ 低優先（将来対応）

| # | タスク | 説明 |
|---|--------|------|
| 15 | **P2 ローカルマルチプレイヤー入力** | GDD は `p1_`/`p2_` プレフィックスで両プレイヤー別アクションを定義。現在は P1 のみキーボード・P2 は常に CPU。実装時は InputHandler を player_id で分岐 |
| 16 | **リング場外判定** | GDD に記述あり（場外 KO）。現在未実装。FightManager にエリア判定を追加 |
| 17 | **character_base.tscn / cpu_opponent.tscn 整備** | 現在空ファイル。実際には player.tscn + set_script() で運用しているため優先度低 |
| 18 | **エントリー演出の活用** | Entry.fbx が AnimationLibrary に存在するが未使用。ラウンド開始時に再生する演出として組み込み可能 |
| 19 | **モバイル/コントローラー UI 対応** | スマホ向けバーチャルパッドや UI ナビゲーション整備（将来プラットフォーム拡張時） |

### 実装済み確認リスト（GDD との照合結果）

以下は GDD 仕様と現行コードが一致していることを確認済み：

- GameEnums 全列挙型 ✓
- AttackData / GrappleData / CharacterStats リソース ✓
- HealthComponent（二層 HP、リジェン、行動不可） ✓
- HitboxManager（レイヤー4/5、グラップル射程チェック） ✓
- DamageCalculator（BLOCKED=0, COUNTER_HIT×1.5, defense_multiplier） ✓
- ComboNode / ComboManager（15 ノードツリー、エンダー×1.3） ✓
- 全 State クラス × 11 + CombatController ✓
- FightManager（ラウンド管理、KO 処理、タイムアウト） ✓
- GrappleManager（dominance 制、decay 率、カメラズーム） ✓
- KOSequenceManager ✓
- AIPhase ステートマシン（CPUController） ✓
- AIBrain / MoveSelector / SpatialAwareness / DifficultyProfile ✓
