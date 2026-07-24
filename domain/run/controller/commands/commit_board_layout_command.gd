class_name CommitBoardLayoutCommand
extends RunCommand

var _board: BoardState
var _bench_unit_instance_ids: Array[String] = []
var _catalog: BattleRuleCatalog
var _board_validator: BoardPreparationValidator
var _bench_compactor: BenchCompactor
var _merge_service: UnitMergeService

func _init(
	p_board: BoardState,
	p_bench_unit_instance_ids: Array[String],
	p_catalog: BattleRuleCatalog,
	p_board_validator: BoardPreparationValidator = null,
	p_bench_compactor: BenchCompactor = null,
	p_merge_service: UnitMergeService = null
) -> void:
	_board = p_board.deep_clone() if p_board != null else null
	_bench_unit_instance_ids.assign(p_bench_unit_instance_ids)
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_board_validator = (
		p_board_validator if p_board_validator != null else BoardPreparationValidator.new()
	)
	_bench_compactor = p_bench_compactor if p_bench_compactor != null else BenchCompactor.new()
	_merge_service = p_merge_service if p_merge_service != null else UnitMergeService.new()

func is_concrete() -> bool:
	return _board != null and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.roster_state == null \
		or draft.economy_state == null or draft.content_snapshot == null:
		return _rejected(&"run.roster_state", &"BOARD_LAYOUT_DRAFT_INVALID")
	if _catalog.manifest_digest_value() \
		!= draft.content_snapshot.manifest_digest_value():
		return _rejected(
			&"run.content_snapshot.manifest_digest",
			&"BOARD_LAYOUT_CATALOG_GENERATION_MISMATCH"
		)
	if draft.run_phase != RunState.RunPhase.PREPARE:
		return _rejected(&"run.run_phase", &"BOARD_LAYOUT_PHASE_INVALID")
	var placements := _board.placements
	_sort_placements(placements)
	draft.roster_state.board = BoardState.new(placements)
	var unit_ids: Array[String] = []
	for unit: UnitInstance in draft.roster_state.unit_instances:
		unit_ids.append(unit.instance_id)
	var board_ids: Array[String] = []
	for placement: BoardPlacementState in draft.roster_state.board.placements:
		board_ids.append(placement.unit_instance_id)
	draft.roster_state.bench_unit_instance_ids = _bench_compactor.compact(
		_bench_unit_instance_ids,
		unit_ids,
		board_ids
	)
	var merge_result := _merge_service.merge_all(draft.roster_state, _catalog)
	if not merge_result.ok:
		return _rejected(
			merge_result.error.field_path,
			merge_result.error.code
		)
	draft.roster_state = merge_result.roster.deep_clone()
	if not _copy_ledger_matches_pool(merge_result.copy_ledger, draft.unit_pool_state):
		return _rejected(&"run.unit_pool_state.held_copies", &"UNIT_POOL_HELD_COPY_MISMATCH")
	# S2 has no persisted authoritative population-source ledger.  Extra sources
	# remain disabled here until the pinned S4 builder can derive them from run state.
	var no_population_sources: Array[PopulationSourceSnapshot] = []
	var report := _board_validator.validate(
		BoardPreparationRequest.new(
			draft.roster_state.board,
			draft.roster_state.bench_unit_instance_ids,
			draft.roster_state.unit_instances,
			draft.economy_state.level,
			no_population_sources
		)
	)
	if not report.valid:
		var first_code := report.issues[0].code if not report.issues.is_empty() else &"BOARD_INVALID"
		return _rejected(&"run.roster_state.board", first_code)
	# T09 / S5-AC-012 (design.md §8): 上場 -> every unit deployed on the final
	# board is discovered in the same copy-validate-save-swap transaction
	# (idempotent for units already discovered earlier this run).
	for placement: BoardPlacementState in draft.roster_state.board.placements:
		var boarded := _find_unit(draft.roster_state.unit_instances, placement.unit_instance_id)
		if boarded != null:
			RunDiscoveryLog.mark(draft, boarded.def_id)
	return CommandApplyResult.success(draft)

func _find_unit(units: Array[UnitInstance], instance_id: String) -> UnitInstance:
	for unit: UnitInstance in units:
		if unit.instance_id == instance_id:
			return unit
	return null

func _copy_ledger_matches_pool(
	ledger: Array[UnitCopyLedgerEntry],
	pool: UnitPoolState
) -> bool:
	if pool == null:
		return false
	var pool_definition_ids: Array[StringName] = []
	for pool_entry: UnitPoolEntryState in pool.entries:
		if pool_entry == null or pool_entry.held_copies < 0 \
			or pool_definition_ids.has(pool_entry.unit_def_id):
			return false
		pool_definition_ids.append(pool_entry.unit_def_id)
	for entry: UnitCopyLedgerEntry in ledger:
		var matched := false
		for pool_entry: UnitPoolEntryState in pool.entries:
			if pool_entry.unit_def_id == entry.unit_def_id:
				matched = pool_entry.held_copies == entry.weighted_copies
				break
		if not matched:
			return false
	for pool_entry: UnitPoolEntryState in pool.entries:
		if pool_entry.held_copies <= 0:
			continue
		var matched := false
		for entry: UnitCopyLedgerEntry in ledger:
			if entry.unit_def_id == pool_entry.unit_def_id:
				matched = true
				break
		if not matched:
			return false
	return true

func _sort_placements(placements: Array[BoardPlacementState]) -> void:
	for index: int in range(1, placements.size()):
		var cursor := index
		while cursor > 0 and _placement_precedes(placements[cursor], placements[cursor - 1]):
			var temporary := placements[cursor - 1]
			placements[cursor - 1] = placements[cursor]
			placements[cursor] = temporary
			cursor -= 1

func _placement_precedes(left: BoardPlacementState, right: BoardPlacementState) -> bool:
	if left.logical_y != right.logical_y:
		return left.logical_y < right.logical_y
	if left.logical_x != right.logical_x:
		return left.logical_x < right.logical_x
	return left.unit_instance_id < right.unit_instance_id

func _rejected(field_path: StringName, source_code: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(source_code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(
			CommandApplyError.APPLY_REJECTED,
			field_path,
			null,
			diagnostics
		)
	)
