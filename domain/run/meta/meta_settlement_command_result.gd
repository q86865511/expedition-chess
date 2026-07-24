class_name MetaSettlementCommandResult
extends RefCounted

## MetaSettlementCommand.dispatch() 的具名 typed result（最小殼，比照
## expedition_action_result.gd）。成功不攜帶 payload——結算後的 profile' 由呼叫端經
## repository.load() 讀回驗證（§5.1）；失敗攜帶具名 MetaSettlementCommandError。
var ok: bool
var error: MetaSettlementCommandError

static func success() -> MetaSettlementCommandResult:
	return MetaSettlementCommandResult.new(true, null)

static func failure(code: StringName, field_path: StringName) -> MetaSettlementCommandResult:
	return MetaSettlementCommandResult.new(
		false, MetaSettlementCommandError.new(code, field_path)
	)

func _init(p_ok: bool, p_error: MetaSettlementCommandError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null
