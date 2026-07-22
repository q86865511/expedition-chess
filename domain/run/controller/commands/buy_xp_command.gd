class_name BuyXpCommand
extends RunCommand

var _catalog: EconomyExpeditionCatalog
var _service: ShopService

func _init(p_catalog: EconomyExpeditionCatalog, p_service: ShopService = null) -> void:
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else ShopService.new()

func is_concrete() -> bool:
	return _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.run_phase != RunState.RunPhase.PREPARE:
		return _failure(ShopError.INPUT_INVALID, &"run_phase")
	if draft.content_snapshot == null or _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _failure(ShopError.GENERATION_MISMATCH, &"content_snapshot.manifest_digest")
	var result := _service.quote_buy_xp(BuyXpRequest.new(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
		draft.economy_state, draft.unit_pool_state, draft.roster_state,
		draft.reservation_owners, EconomyCommandSupport.try_shop_rng(draft),
		draft.next_transaction_serial, draft.next_unit_serial, _catalog
	))
	if not result.ok: return _failure(result.error.code, result.error.field_path)
	EconomyCommandSupport.apply_shop_transaction(draft, result.transaction)
	return CommandApplyResult.success(draft)

func _failure(code: StringName, path: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [DiagnosticValue.from_string(&"source_code", String(code))]
	return CommandApplyResult.failure(CommandApplyError.new(CommandApplyError.APPLY_REJECTED, path, null, diagnostics))
