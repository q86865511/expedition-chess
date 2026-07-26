class_name MetaSettlementCommandResult
extends RefCounted

## MetaSettlementCommand.dispatch() 的具名 typed result（最小殼，比照
## expedition_action_result.gd）。成功不攜帶 profile payload——結算後的 profile' 由呼叫端經
## repository.load() 讀回驗證（§5.1）；失敗攜帶具名 MetaSettlementCommandError。
##
## T11（design.md §4.4）新增唯讀欄位 `save_result`：成功時＝該次 SaveRepository.save()
## 實際回傳的物件。AppStateMachine.transition_after_save(FINISH_RUN, ...) 消費的是那次
## save() 親自發出的一次性能力 token（save_repository.gd:230-242，偽造或重用都會被拒），
## composition root 無法自行造一個，只能原樣轉呈。刻意**不** deep_clone（複本不帶能力、
## 會被拒），失敗時為 null。這是新增欄位而非改簽章：success() 的既有零參數呼叫仍可用。
var ok: bool
var save_result: SaveResult
var error: MetaSettlementCommandError

static func success(p_save_result: SaveResult = null) -> MetaSettlementCommandResult:
	return MetaSettlementCommandResult.new(true, p_save_result, null)

static func failure(code: StringName, field_path: StringName) -> MetaSettlementCommandResult:
	return MetaSettlementCommandResult.new(
		false, null, MetaSettlementCommandError.new(code, field_path)
	)

func _init(
	p_ok: bool,
	p_save_result: SaveResult,
	p_error: MetaSettlementCommandError
) -> void:
	ResultInvariant.require(p_ok, p_error, true, p_save_result == null)
	ok = p_ok
	save_result = p_save_result
	error = p_error.deep_clone() if p_error != null else null
