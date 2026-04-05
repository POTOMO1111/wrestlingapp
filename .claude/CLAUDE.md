# Wrestling Game — Claude 開発ガイド

## 基本情報
- **エンジン**: Godot 4.6 (Forward Plus, Jolt Physics, 1920×1080)
- **言語**: GDScript
- **ゲームジャンル**: 俯瞰視点 3D プロレス/MMA アクション（1vs1 対戦）
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
│   ├── attacks/      ← AttackData .tres × 6 (punch/kick/grapple各2種)
│   ├── characters/   ← CharacterStats .tres × 3 (balanced/striker/grappler)
│   └── combos/       ← combo_tree_root.tres (15 ComboNode 埋め込み)
├── scenes/
│   ├── characters/   ← player.tscn (character_base.tscn / cpu_opponent.tscn は空)
│   ├── game/         ← main.tscn, ring_stage.tscn
│   └── ui/           ← title.tscn, char_select.tscn, hud.tscn, settings.tscn
└── scripts/
    ├── autoload/     ← GameEnums, AudioManager, GameManager, SceneManager
    ├── characters/   ← CharacterBase, PlayerController, CPUController, StateMachine
    ├── combat/       ← GrappleSystem(旧互換), HitboxController(旧互換)
    ├── data/         ← AttackData, GrappleData, CharacterStats, ComboNode
    ├── debug/        ← DebugOverlay
    ├── game/         ← main.gd
    ├── managers/     ← FightManager, InputHandler, KOSequenceManager
    ├── states/       ← BaseState + 10個のStateクラス
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
ActionType  : NONE, PUNCH, KICK, GRAPPLE, GUARD
HitResult   : WHIFF, BLOCKED, HIT, COUNTER_HIT, GRAPPLE_SUCCESS, GRAPPLE_FAIL
DamageLayer : RECOVERABLE, PERMANENT
CharacterState: IDLE, WALKING, RUNNING, ATTACKING, GUARDING, GRAPPLING,
                GRAPPLED, HIT_STUN, KNOCKDOWN, GETTING_UP, INCAPACITATED, KO
GrapplePosition: NEUTRAL, DOMINANT, SUBDUED
RoundState  : WAITING, FIGHTING, ROUND_END, MATCH_END
PlayerID    : PLAYER_ONE, PLAYER_TWO
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
│   ├── StateIdle
│   ├── StateWalking
│   ├── StateAttacking
│   ├── StateGuarding
│   ├── StateGrappling
│   ├── StateGrappled
│   ├── StateHitStun
│   ├── StateKnockdown
│   ├── StateGettingUp
│   ├── StateIncapacitated
│   └── StateKO
└── InputHandler (P1のみ)     ← scripts/managers/InputHandler.gd
```

**Player2** は player.tscn を `set_script(CPUController)` で差し替えて使用。

### シーン構成 (main.tscn)

```
Main (Node3D) ← scripts/game/main.gd
├── FightManager ← scripts/managers/FightManager.gd
│   └── GrappleManager ← scripts/systems/GrappleManager.gd
├── KOSequenceManager ← scripts/managers/KOSequenceManager.gd
│   └── KO_Overlay (CanvasLayer)
│       └── KO_Label
└── [環境・リング・観客ジオメトリ群]
    ← Player1/Player2 は main.gd._spawn_characters() で動的生成
```

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

---

## 戦闘フロー

### 入力 → ダメージまでの流れ
```
InputHandler._input()
  → CombatController.receive_input(action)
    → _current_state_node.handle_input(action)

[StateIdle.handle_input]
  → ComboManager.try_input(action)  ← combo_tree_root から AttackData を解決
  → CombatController._pending_attack = attack
  → transition_to(ATTACKING)

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
回復可能HP (白バー): 打撃ダメージ先。スタミナを兼ねる。時間回復あり。
                    枯渇 → INCAPACITATED（行動不可、一定時間後20%で復活）
回復不可能HP (赤バー): グラップルダメージ先。回復なし。
                      枯渇 → KO → round_end
行動不可中の追加ダメージ: take_damage(PERMANENT) × 1.3
```

### グラップルシステム (dominance型・改訂版)
```
GrappleManager (FightManager の子)
dominance: 0.5スタート → GRAPPLEボタン連打で +0.08/入力（攻め側のみ）
CPU は入力を行わず、decay のみで抵抗を表現する

【終了条件】
  dominance = 1.0 → 攻め側勝利: 受け側の回復不可能HPに -20 ダメージして grapple_ended
  dominance = 0.0 → 受け側勝利（CPU抵抗が上回った）: 攻め側の回復不可能HPに -20 ダメージして grapple_ended
  ※ タイムアウトなし（dominanceが0か1に達するまで継続）

【decay レート（/sec）: 常に 0.0 方向へ引き戻す。回復可能HP差 diff = 攻め側HP − 受け側HP で速度変化】
  diff < -30      : 0.25  (受け側が30以上有利 → 速く0へ)
  -30 ≤ diff < -1 : 0.15  (受け側がやや有利)
  -1 ≤ diff ≤ 1   : 0.1   (ほぼ互角)
  1 < diff ≤ 30   : 0.05  (攻め側がやや有利)
  diff > 30       : 0.03  (攻め側が30以上有利 → ゆっくり0へ)

【グラップル中の追加挙動】
  - 両者の回復可能HPリジェン停止 (HealthComponent._is_regen_paused = true)
  - カメラを近距離専用視点にズームイン (SpringArm spring_length 5.0 → 2.0, 0.3秒)
  - 終了時にリジェン再開・カメラ復元 (0.4秒)

InputHandler の GRAPPLE 入力 → GrappleManager.register_input()
※ 毎秒ダメージ処理は廃止。GrappleData のダメージ値は未使用。
```

---

## アニメーションシステム

### AnimationTree ステート名（player.tscn内）
```
Idle, Walk, Run, JumpUp, JumpDown,
AttackLight, AttackHeavy, Grapple, Block, Hit, Down
```

### AnimationLibrary にある .res ファイルの対応
| ライブラリ名 | FBXソース | 用途 |
|------------|---------|------|
| Boxing | Boxing.fbx | AttackLight(パンチ) |
| Kicking | Kicking.fbx | AttackLight(キック) も同じ名前を使用 |
| Headbutt | Headbutt.fbx | 未アサイン（AttackHeavy候補） |
| PunchingBag | Punching Bag.fbx | 未アサイン |
| TakingPunch | Taking Punch.fbx | Hit |
| KnockedDown | Knocked Down.fbx | Down |
| BodyBlock | Body Block.fbx | Block |
| Entry | Entry.fbx | エントリー演出 |
| JumpUp / JumpDown | 対応FBX | ジャンプ上昇/下降 |
| LongLeftSideStep / LongRightSideStep / MediumStepForward / StepBackward | 各FBX | 移動 |

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
| jump | Space | ボタン1 |
| attack light (PUNCH) | J | ボタン2 |
| attack heavy (KICK) | K | ボタン0 |
| grapple | L | ボタン3 |
| block | I | ボタン10 |
| run | Shift | RT(axis5) |
| camera_left/right | ←→ | 右スティック |
| ui_pause | Esc | ボタン6 |

---

## キャラクタースクリプト継承関係

```
CharacterBody3D
  └── CharacterBase (scripts/characters/CharacterBase.gd)
        ├── player_id: int, is_dead (→CombatController.KO参照)
        ├── consume_stamina() → CombatController/HealthComponent.consume_stamina()
        └── PlayerController (scripts/characters/PlayerController.gd)
              ← 移動・カメラ・アニメーション制御
              ├── State enum: IDLE,WALK,RUN,JUMP,FALL,ATTACK_LIGHT,...
              └── CPUController (scripts/characters/CPUController.gd)
                    ← AI思考 (_ai_think, _decide_behavior)
                    ← is_dummy=true で PlayerController の入力を無効化
```

---

## 主要スクリプト: メソッド/シグナル一覧

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
- `consume_stamina(amount) → bool`
- `reset()` — ラウンド開始時
- `is_incapacitated() → bool`
- `set_regen_paused(paused: bool)` — グラップル中に GrappleManager から呼ぶ。再開時は regen_timer をリセット
- **シグナル**: `recoverable_hp_changed(val, max)`, `permanent_hp_changed(val, max)`,
  `recoverable_hp_depleted()`, `permanent_hp_depleted()`, `incapacitation_ended()`

### HitboxManager
- `activate_hitbox(attack: AttackData)` / `activate_grapple_hitbox(grapple)`
- `deactivate_hitbox()`
- **シグナル**: `hit_landed(target, attack_data, result)`, `grapple_initiated(target, grapple_data)`

### GrappleManager
- `start_grapple(initiator, receiver, grapple_data)`
- `register_input(player_id)` — 各キャラからの入力ボタン押下
- `is_active: bool`
- **シグナル**: `grapple_ended(winner, loser)`, `dominance_changed(val)`
- `set_regen_paused(bool)` ← HealthComponent に委譲（内部で呼ぶ）
- `_adjust_camera(bool)` ← SpringArm3D を scene root から探してズーム操作

### FightManager
- `set_fighters(p1, p2)` — キャラ設定後に start_round() を呼ぶ
- `process_hit(attacker_ctrl, target, attack, result)` — HitboxManager.hit_landed 経由
- `process_grapple_start(initiator_ctrl, target, grapple)` — HitboxManager.grapple_initiated 経由
- `start_round()`
- **シグナル**: `round_started(n)`, `round_ended(winner_id)`, `match_ended(winner_id)`,
  `ko_triggered(loser)`, `timer_updated(time_remaining)`

### InputHandler (P1専用)
- `_input(event)` でイベントドリブン検出 → `CombatController.receive_input()`
- **シグナル**: `input_received(action)` (DebugOverlay が接続)

---

## State 実装早見表

| クラス | enter() | update() | handle_input() |
|--------|---------|----------|---------------|
| StateIdle | play_anim("idle") | — | PUNCH/KICK→ComboManager, GRAPPLE→ATTACKING, GUARD→GUARDING |
| StateWalking | — | — | (IDLEと同じ戦闘入力を受け付け) |
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
  - BLOCKED → {0, 0}
  - × def_stats.defense_multiplier
  ※ FightManager で _ender_damage_multiplier をさらに掛ける

calculate_grapple_damage(grapple, dominance, atk_stats, def_stats) → {recoverable, permanent}
  - dominance >= threshold → dominant_damage_multiplier
  - × attacker_stats.grapple_damage_multiplier, def_stats.defense_multiplier
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
| StateWalking.handle_input | 未実装の可能性 | scripts/states/StateWalking.gd |

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
