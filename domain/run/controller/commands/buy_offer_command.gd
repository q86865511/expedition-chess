class_name BuyOfferCommand
extends RunCommand

var _offer_id: String
var _catalog: EconomyExpeditionCatalog
var _battle_catalog: BattleRuleCatalog
var _service: ShopService

func _init(
	p_offer_id: String, p_catalog: EconomyExpeditionCatalog,
	p_battle_catalog: BattleRuleCatalog, p_service: ShopService = null
) -> void:
	_offer_id = p_offer_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_service = p_service if p_service != null else ShopService.new()

func is_concrete() -> bool:
	return not _offer_id.is_empty() and _catalog != null and _battle_catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.run_phase != RunState.RunPhase.PREPARE:
		return _failure(ShopError.INPUT_INVALID, &"run_phase")
	if draft.content_snapshot == null or _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value() \
		or _battle_catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _failure(ShopError.GENERATION_MISMATCH, &"content_snapshot.manifest_digest")
	var result := _service.quote_buy(BuyOfferRequest.new(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft), _offer_id,
		draft.economy_state, draft.unit_pool_state, draft.roster_state,
		draft.reservation_owners, EconomyCommandSupport.try_shop_rng(draft),
		draft.next_transaction_serial, draft.next_unit_serial, _catalog, _battle_catalog
	))
	if not result.ok: return _failure(result.error.code, result.error.field_path)
	EconomyCommandSupport.apply_shop_transaction(draft, result.transaction)
	return CommandApplyResult.success(draft)

func _failure(code: StringName, path: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [DiagnosticValue.from_string(&"source_code", String(code))]
	return CommandApplyResult.failure(CommandApplyError.new(CommandApplyError.APPLY_REJECTED, path, null, diagnostics))
