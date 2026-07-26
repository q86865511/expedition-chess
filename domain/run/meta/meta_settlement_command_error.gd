class_name MetaSettlementCommandError
extends RefCounted

## design.md §13 「META_SETTLEMENT_*」— MetaSettlementCommand 的具名錯誤。
## NO_ACTIVE_RUN：load 成功但無 active run 可結算（零變動）。
## SAVE_FAILED：結算存檔交易未完成——涵蓋 load 前置失敗與 save 各故障點失敗（皆
##   「尚未提交、run 維持 active」，重載重試決定性重算、零重發，§5.2）。
const NO_ACTIVE_RUN: StringName = &"META_SETTLEMENT_NO_ACTIVE_RUN"
## RUN_NOT_TERMINAL：active run 尚未進入 RESULTS。拒絕發放 meta 獎勵與清除 run；
## command 在此分支不建 SaveRoot、不呼叫 save()，因此持久狀態逐位元組不變。
const RUN_NOT_TERMINAL: StringName = &"META_SETTLEMENT_RUN_NOT_TERMINAL"
const SAVE_FAILED: StringName = &"META_SETTLEMENT_SAVE_FAILED"
## KEY_FAILED：MetaSettlementService.settle() 無法為 terminal_run.run_id 建置
##   settlement receipt key（不可達防禦路徑——合法 run_id 恆可編碼）。dispatch()
##   回此碼時尚未組 SaveRoot、尚未呼叫 save()，run 維持 active、profile 未變
##   （與 SAVE_FAILED 相同「尚未提交、可重載重試」語意）。
const KEY_FAILED: StringName = &"META_SETTLEMENT_KEY_FAILED"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> MetaSettlementCommandError:
	return MetaSettlementCommandError.new(code, field_path)
