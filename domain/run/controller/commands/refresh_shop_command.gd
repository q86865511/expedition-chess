class_name RefreshShopCommand
extends RunCommand

var _catalog: EconomyExpeditionCatalog
var _service: ShopService
var _relic_table: RunRelicTable

func _init(
	p_catalog: EconomyExpeditionCatalog, p_service: ShopService = null,
	p_relic_table: RunRelicTable = null
) -> void:
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else ShopService.new()
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null

func is_concrete() -> bool:
	return _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	var error := _preflight(draft)
	if error != null: return _failure(error.code, error.field_path)
	var active_relic_ids := RunRelicActivation.active_ids_in_slot_order(
		draft.roster_state.active_relic_slots
	)
	var result := _service.quote_refresh(RefreshShopRequest.new(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
		draft.economy_state, draft.unit_pool_state, draft.roster_state,
		draft.reservation_owners, EconomyCommandSupport.try_shop_rng(draft),
		draft.next_transaction_serial, draft.next_unit_serial, _catalog,
		_relic_table, active_relic_ids
	))
	if not result.ok: return _failure(result.error.code, result.error.field_path)
	EconomyCommandSupport.apply_shop_transaction(draft, result.transaction)
	return CommandApplyResult.success(draft)

func _preflight(draft: RunState) -> ShopError:
	if draft == null or draft.run_phase != RunState.RunPhase.PREPARE or EconomyCommandSupport.current_node_id(draft).is_empty():
		return ShopError.new(ShopError.INPUT_INVALID, &"run_phase")
	if draft.content_snapshot == null or _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return ShopError.new(ShopError.GENERATION_MISMATCH, &"content_snapshot.manifest_digest")
	return null

func _failure(code: StringName, path: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [DiagnosticValue.from_string(&"source_code", String(code))]
	return CommandApplyResult.failure(CommandApplyError.new(CommandApplyError.APPLY_REJECTED, path, null, diagnostics))
