extends Node

# ============================================================
#  GrappleSystem.gd
#  旧グラップルシステム。新システム（GrappleManager）に移行済み。
#  AutoLoad として残すが機能はスタブ化。
#  _spawn_text_effect のみ GrappleManager が持つようになった。
# ============================================================

enum GrappleState { IDLE, LOCKUP, EXECUTING }
var current_state : GrappleState = GrappleState.IDLE

# 旧互換スタブ（呼び出し元が残っている間はエラーを出さないためだけに存在）
func start_grapple(_initiator: Node3D, _receiver: Node3D) -> void:
	pass

func receive_input(_initiator: Node3D, _attack_type: String) -> void:
	pass
