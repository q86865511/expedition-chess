class_name GenerateExpeditionMapCommand
extends RunCommand

var _catalog: EconomyExpeditionCatalog
var _service: MapService
var _relic_table: RunRelicTable

func _init(
	p_catalog: EconomyExpeditionCatalog, p_service: MapService = null,
	p_relic_table: RunRelicTable = null
) -> void:
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_service = p_service if p_service != null else MapService.new()
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null

func is_concrete() -> bool:
	return _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.map_state == null \
		or draft.run_phase != RunState.RunPhase.MAP \
		or draft.current_node_id != null or not draft.map_state.nodes.is_empty() \
		or draft.resolution_state == null \
		or draft.resolution_state.kind != ResolutionState.Kind.IDLE:
		return _failure(&"MAP_GENERATION_STATE_INVALID", &"map_state")
	if draft.content_snapshot == null \
		or _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _failure(ShopError.GENERATION_MISMATCH, &"content_snapshot.manifest_digest")
	# 路線遺物依作用中槽位（slot_index 升序）佔用 branch anchor，由 draft roster 推導。
	var active_relic_ids := RunRelicActivation.active_ids_in_slot_order(
		draft.roster_state.active_relic_slots
	)
	var result := _service.generate_map(MapGenerationRequest.new(
		StringName(draft.run_id), draft.run_seed, _catalog,
		_relic_table, active_relic_ids
	))
	if not result.ok:
		return _failure(result.error.code, result.error.field_path)
	draft.map_state = result.map_state.deep_clone()
	EconomyCommandSupport.set_named_rng(
		draft, NamedRngState.StreamName.MAP, result.next_map_rng_snapshot
	)
	return CommandApplyResult.success(draft)

func _failure(code: StringName, path: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(code)),
	]
	return CommandApplyResult.failure(CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, path, null, diagnostics
	))
