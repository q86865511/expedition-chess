class_name DiscardActiveRunCommand
extends RefCounted

## S5-AC-008：玩家明示棄置無法組裝的 active run。
##
## expected_run_id 是 compare-and-clear 的版本戳；CampController 必須在交易當下重新
## load 持久化資料並比對，避免玩家確認舊畫面後誤刪一局已被替換的新遠征。

var expected_run_id: String


func _init(p_expected_run_id: String) -> void:
	expected_run_id = p_expected_run_id


func is_concrete() -> bool:
	return not expected_run_id.is_empty()
