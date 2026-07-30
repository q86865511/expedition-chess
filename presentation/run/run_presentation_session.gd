class_name RunPresentationSession
extends RefCounted

signal snapshot_committed(snapshot: RunPresentationSnapshot)
signal presentation_error(error: DiagnosticError)

const NOT_IMPLEMENTED: StringName = &"RUN_PRESENTATION_SESSION_NOT_IMPLEMENTED"
const DEPENDENCY_MISSING: StringName = &"RUN_PRESENTATION_DEPENDENCY_MISSING"
const INTENT_INVALID: StringName = &"RUN_PRESENTATION_INTENT_INVALID"
const PLAYBACK_NOT_AVAILABLE: StringName = &"PLAYBACK_NOT_AVAILABLE"
const PENDING_TRANSCRIPT_REVOKED: StringName = &"PENDING_TRANSCRIPT_REVOKED"
const PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED: StringName = \
	&"PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED"
const COMBAT_STEP_LIMIT: StringName = &"RUN_PRESENTATION_COMBAT_STEP_LIMIT"
## commit-before-present（design.md §10）：START_OR_RESUME_COMBAT 一定把 canonical
## simulation 跑到 result 提交才回應，presentation 之後只重播已提交 transcript。
const COMBAT_COMMIT_STEP_LIMIT: int = 100000
const MapNodePresentationType = preload(
	"res://presentation/run/map_node_presentation.gd"
)

var _controller: RunController
var _factory: RunCommandFactory
var _combat: CombatCoordinator
var _battle_catalog: BattleRuleCatalog
var _commander_passive_effect_ids: Array[StringName] = []
var _snapshot := RunPresentationSnapshot.new()
var _combat_result_already_committed: bool = false
var _battle_transcript_buffer: BattleTranscriptBuffer
var _battle_playback_controller: BattlePlaybackController
var _committed_summary_only: bool = false
var _playback_warning: DiagnosticError
## 戰鬥檢視只能由 COMBAT_PENDING 的 battle_setup 建；result 提交後 canonical 只留
## BattleResultPendingResolutionState（無 setup），故 COMBAT 期間保留最後一份投影。
var _retained_combat_inspections: Array[CombatUnitInspectionSnapshot] = []


func _init(
	p_controller: RunController = null,
	p_factory: RunCommandFactory = null,
	p_battle_catalog: BattleRuleCatalog = null,
	p_commander_passive_effect_ids: Array[StringName] = [],
	p_combat: CombatCoordinator = null
) -> void:
	_controller = p_controller
	_factory = p_factory
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_commander_passive_effect_ids.assign(p_commander_passive_effect_ids)
	_combat = p_combat if p_combat != null else (
		CombatCoordinator.new(_controller) if _controller != null else null
	)
	if _combat != null and _combat.has_method(&"bind_presentation_session"):
		_combat.call(&"bind_presentation_session", self)
	if _controller != null:
		_snapshot = _build_snapshot()


func is_concrete() -> bool:
	return _controller != null and _factory != null and _factory.is_concrete()


func snapshot() -> RunPresentationSnapshot:
	return _snapshot.deep_clone()


func reachable_nodes() -> Array:
	var result: Array = []
	if _snapshot.map == null:
		return result
	for node: MapNodeState in _snapshot.map.nodes:
		var reachable := node_is_reachable(_snapshot.map, node)
		if reachable:
			result.append(MapNodePresentationType.from_state(node, true))
	return result


func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
	if not is_concrete():
		return _precommit_failure(_error(
			DEPENDENCY_MISSING, &"error.presentation.run_dependency_missing"
		))
	if intent == null:
		return _precommit_failure(_error(
			INTENT_INVALID, &"error.presentation.run_intent_invalid"
		))
	match intent.kind:
		RunPresentationIntent.Kind.GENERATE_MAP:
			return _dispatch_command(_factory.generate_expedition_map_command())
		RunPresentationIntent.Kind.ENTER_NODE:
			return _dispatch_transition(_factory.enter_node_event(intent.target_node_id))
		RunPresentationIntent.Kind.REFRESH_SHOP:
			return _dispatch_command(_factory.refresh_shop_command())
		RunPresentationIntent.Kind.BUY_UNIT:
			return _dispatch_command(_factory.buy_offer_command(intent.offer_id))
		RunPresentationIntent.Kind.BUY_XP:
			return _dispatch_command(_factory.buy_xp_command())
		RunPresentationIntent.Kind.SELL_UNIT:
			return _dispatch_command(_factory.sell_unit_command(intent.unit_instance_id))
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT:
			return _dispatch_command(_factory.commit_board_layout_command(
				intent.board, intent.bench_unit_instance_ids
			))
		RunPresentationIntent.Kind.FORGE_EQUIPMENT:
			return _dispatch_command(_factory.forge_equipment_command(
				intent.item_instance_id, intent.secondary_item_instance_id
			))
		RunPresentationIntent.Kind.EQUIP_ITEM:
			return _dispatch_command(_factory.equip_item_command(
				intent.unit_instance_id, intent.item_instance_id
			))
		RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT:
			return _dispatch_command(_factory.dismantle_equipment_command(
				intent.item_instance_id, intent.secondary_item_instance_id
			))
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT:
			return _start_or_resume_combat(intent)
		RunPresentationIntent.Kind.SETTLE_BATTLE:
			return _dispatch_command(_factory.settle_battle_result_command())
		RunPresentationIntent.Kind.RESOLVE_NON_COMBAT:
			return _dispatch_command(_factory.resolve_non_combat_node_command())
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD:
			return _dispatch_command(_factory.choose_reward_command(intent.choice_id))
		RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD:
			return _dispatch_command(_factory.resolve_unit_reward_command(intent.accept))
		RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD:
			return _dispatch_command(_factory.resolve_item_reward_command(
				intent.item_instance_id, intent.abandon
			))
		RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD:
			return _dispatch_command(_factory.resolve_relic_reward_command(
				intent.relic_slot_index
			))
		RunPresentationIntent.Kind.ADVANCE_REWARD:
			return _dispatch_command(_factory.advance_reward_command())
		RunPresentationIntent.Kind.RESOLVE_UNIT_OVERFLOW:
			return _dispatch_command(_factory.resolve_unit_overflow_command(
				intent.item_instance_id
			))
		RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW:
			return _dispatch_command(_factory.resolve_item_overflow_command(
				intent.item_instance_id, intent.target_unit_instance_id
			))
		RunPresentationIntent.Kind.REPLACE_RELIC:
			return _dispatch_command(_factory.replace_relic_command(intent.relic_slot_index))
		RunPresentationIntent.Kind.ABANDON_RELIC:
			return _dispatch_command(_factory.abandon_relic_command())
		RunPresentationIntent.Kind.ABANDON_BOSS_RETRY:
			return _dispatch_command(_factory.abandon_boss_retry_command())
		RunPresentationIntent.Kind.SETTLE_TERMINAL_RUN:
			return _dispatch_command(_factory.settle_terminal_run_command())
	return _precommit_failure(_error(
		INTENT_INVALID, &"error.presentation.run_intent_invalid"
	))


func try_playback() -> BattlePlaybackStateResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattlePlaybackStateResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	return BattlePlaybackStateResult.new(
		true,
		_battle_playback_controller.snapshot(),
		null
	)


func set_playback_speed(multiplier: int) -> BattlePlaybackCommandResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattlePlaybackCommandResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	return _battle_playback_controller.set_speed(multiplier)


func set_playback_paused(paused: bool) -> BattlePlaybackCommandResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattlePlaybackCommandResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	return _battle_playback_controller.set_paused(paused)


func drain_playback_window(
	expected_identity: BattleTranscriptIdentity,
	max_count: int
) -> BattleEventWindowResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattleEventWindowResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	var cursor := _battle_playback_controller.snapshot().cursor
	var result := _battle_transcript_buffer.drain_window(
		expected_identity,
		max_count,
		cursor
	)
	if result.ok:
		_battle_playback_controller._consume_events(result.window.events.size())
	return result


## 每 frame 的播放推進：presentation 時鐘走到哪個 canonical tick，就取到哪裡的事件，
## 再由同一個 private cursor 前進。暫停時不推進時鐘也不回 exhausted，故暫停不會結算。
func advance_playback(delta_ms: float) -> BattleEventWindowResult:
	if _battle_playback_controller == null or _battle_transcript_buffer == null:
		return BattleEventWindowResult.failure(_error(
			PLAYBACK_NOT_AVAILABLE, &"error.presentation.playback_not_available"
		))
	if _battle_playback_controller.is_paused():
		return BattleEventWindowResult.new(true, _idle_playback_window(false), null)
	var max_tick := _battle_playback_controller._advance_presentation_tick(delta_ms)
	var state := _battle_playback_controller.snapshot()
	var budget := _battle_transcript_buffer._events_through_tick(state.cursor, max_tick)
	if budget <= 0:
		return BattleEventWindowResult.new(
			true,
			_idle_playback_window(_battle_playback_controller.has_reached_end()),
			null
		)
	var result := _battle_transcript_buffer.drain_window(
		state.transcript_identity,
		budget,
		state.cursor
	)
	if result.ok:
		_battle_playback_controller._consume_events(result.window.events.size())
	return result


func _idle_playback_window(exhausted: bool) -> BattleEventWindow:
	var window := BattleEventWindow.new()
	window.identity = _battle_playback_controller.snapshot().transcript_identity
	window.exhausted = exhausted
	return window


## 離開 run 範疇時的顯式解綁。session 與 CombatCoordinator 互持強引用（皆為
## RefCounted），沒有這一步整組 run 物件圖永不釋放。
func release() -> void:
	release_playback(&"run_scope_released")
	if _combat != null and _combat.has_method(&"unbind_presentation_session"):
		_combat.call(&"unbind_presentation_session")
	_combat = null
	_controller = null
	_factory = null
	_battle_catalog = null
	_retained_combat_inspections.clear()
	_snapshot = RunPresentationSnapshot.new()


## Internal final-save boundary called only by CombatCoordinator. This method
## receives the sole precommit owner, seals/transfers its storage, and never
## exposes the buffer or raw array through the returned result.
func _accept_committed_transcript(
	accumulator: Variant,
	transcript_identity: BattleTranscriptIdentity,
	encoded_byte_count: int
) -> BattleTranscriptInstallResult:
	if (
		accumulator == null
		or not accumulator.has_method(&"is_revoked")
		or not accumulator.has_method(&"event_budget")
		or not accumulator.has_method(&"_seal_and_transfer")
		or bool(accumulator.call(&"is_revoked"))
	):
		return BattleTranscriptInstallResult.failure(_error(
			PENDING_TRANSCRIPT_REVOKED,
			&"error.presentation.pending_transcript_revoked"
		))
	var event_budget: int = int(accumulator.call(&"event_budget"))
	var transferred: Array = accumulator.call(&"_seal_and_transfer")
	release_playback(&"committed_transcript_replaced")
	var candidate := BattleTranscriptBuffer.new(
		transcript_identity,
		transferred,
		event_budget,
		encoded_byte_count
	)
	if not candidate.is_within_budget():
		candidate.revoke()
		_committed_summary_only = true
		_playback_warning = _error(
			PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED,
			&"warning.presentation.transcript_memory_budget_exceeded"
		)
		return BattleTranscriptInstallResult.summary_fallback(_playback_warning)
	_battle_transcript_buffer = candidate
	_battle_playback_controller = BattlePlaybackController.new(
		transcript_identity,
		candidate.event_count()
	)
	_committed_summary_only = false
	_playback_warning = null
	return BattleTranscriptInstallResult.installed()


func release_playback(_reason: StringName = &"") -> void:
	if _battle_transcript_buffer != null:
		_battle_transcript_buffer.revoke()
	_battle_transcript_buffer = null
	_battle_playback_controller = null
	_committed_summary_only = false
	_playback_warning = null


func is_committed_summary_only() -> bool:
	return _committed_summary_only


func playback_warning() -> DiagnosticError:
	return _playback_warning.deep_clone() if _playback_warning != null else null


func inspect_combat_unit(unit_serial: int) -> CombatUnitInspectionResult:
	if (
		unit_serial <= 0
		or _snapshot == null
		or _snapshot.app_phase != &"COMBAT"
		or unit_serial > _snapshot.combat_inspections.size()
	):
		return CombatUnitInspectionResult.failure(_error(
			&"COMBAT_UNIT_NOT_FOUND",
			&"error.presentation.combat_unit_not_found"
		))
	var inspection := _snapshot.combat_inspections[unit_serial - 1]
	if inspection == null or inspection.unit_serial != unit_serial:
		return CombatUnitInspectionResult.failure(_error(
			&"COMBAT_UNIT_NOT_FOUND",
			&"error.presentation.combat_unit_not_found"
		))
	return CombatUnitInspectionResult.new(
		true,
		inspection.deep_clone(),
		null
	)


func _first_target_serial(
	source: UnitBattleSnapshot,
	serial_by_instance: Dictionary
) -> int:
	for assignment: BattleEffectSnapshot in source.effect_assignments:
		for target_id: StringName in assignment.target_ids:
			if serial_by_instance.has(target_id):
				return int(serial_by_instance[target_id])
	return 0


## COMBAT 期間的檢視投影：COMBAT_PENDING 有 battle_setup 時重建並保留，result 提交後
## canonical 只剩 BattleResultPendingResolutionState，改用保留的同一份；離開 COMBAT 即清空。
func _resolve_combat_inspections(
	view: RunViewState
) -> Array[CombatUnitInspectionSnapshot]:
	var result: Array[CombatUnitInspectionSnapshot] = []
	if view == null or view.run_phase != RunState.RunPhase.COMBAT:
		_retained_combat_inspections.clear()
		return result
	var built := _build_combat_inspections()
	if not built.is_empty():
		_retained_combat_inspections = built
	for inspection: CombatUnitInspectionSnapshot in _retained_combat_inspections:
		result.append(inspection.deep_clone())
	return result


func _build_combat_inspections() -> Array[CombatUnitInspectionSnapshot]:
	var result: Array[CombatUnitInspectionSnapshot] = []
	if _controller == null:
		return result
	var committed := _controller.committed_combat_snapshot()
	if (
		committed == null
		or committed.run_phase != RunState.RunPhase.COMBAT
		or not committed.resolution_state is CombatPendingResolutionState
	):
		return result
	var pending := committed.resolution_state as CombatPendingResolutionState
	if (
		pending.battle_setup == null
		or pending.battle_setup.inputs == null
		or pending.battle_setup.inputs.encounter_snapshot == null
	):
		return result
	var inputs := pending.battle_setup.inputs.deep_clone()
	var units: Array[UnitBattleSnapshot] = []
	# 陣營旗標與單位同步 append：以索引界線判陣營會在跳過 null 後把敵方誤判成我方。
	var player_flags: Array[bool] = []
	for player: UnitBattleSnapshot in inputs.player_units:
		if player != null:
			units.append(player.deep_clone())
			player_flags.append(true)
	for enemy: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		if enemy != null:
			units.append(enemy.deep_clone())
			player_flags.append(false)
	var serial_by_instance: Dictionary = {}
	for index: int in units.size():
		var unit := units[index]
		if not unit.instance_id.is_empty():
			serial_by_instance[unit.instance_id] = index + 1
	var empty_equipment_effects: Array[BattleEffectSnapshot] = []
	for index: int in units.size():
		var unit := units[index]
		var is_player := player_flags[index]
		var traits: Array[TraitBattleSnapshot] = (
			inputs.player_active_traits
			if is_player
			else inputs.encounter_snapshot.active_traits
		)
		var equipment_effects: Array[BattleEffectSnapshot] = (
			inputs.player_equipment_effects
			if is_player
			else empty_equipment_effects
		)
		result.append(_build_combat_inspection(
			index + 1,
			unit,
			traits,
			equipment_effects,
			serial_by_instance
		))
	return result


func _build_combat_inspection(
	unit_serial: int,
	unit: UnitBattleSnapshot,
	trait_snapshots: Array[TraitBattleSnapshot],
	equipment_effects: Array[BattleEffectSnapshot],
	serial_by_instance: Dictionary
) -> CombatUnitInspectionSnapshot:
	var inspection := CombatUnitInspectionSnapshot.new()
	inspection.unit_serial = unit_serial
	inspection.source_id = unit.unit_id
	inspection.side_id = unit.side
	inspection.target_serial = _first_target_serial(
		unit,
		serial_by_instance
	)
	inspection.stats = {
		"star": unit.star,
		"health": unit.health,
		"attack": unit.attack,
		"armor": unit.armor,
		"magic_resist": unit.magic_resist,
		"attack_speed_milli": unit.attack_speed_milli,
		"attack_range_cells": unit.attack_range_cells,
		"start_mana": unit.start_mana,
		"max_mana": unit.max_mana,
		"move_speed_milli": unit.move_speed_milli,
	}
	_append_equipment_ids(
		inspection.equipment_ids,
		equipment_effects,
		unit.instance_id
	)
	_append_equipment_ids(
		inspection.equipment_ids,
		unit.effect_assignments,
		unit.instance_id
	)
	for trait_entry: TraitBattleSnapshot in trait_snapshots:
		if (
			trait_entry != null
			and trait_entry.member_instance_ids.has(unit.instance_id)
			and not inspection.trait_ids.has(trait_entry.trait_id)
		):
			inspection.trait_ids.append(trait_entry.trait_id)
	inspection.status_ids.assign(unit.effect_ids)
	for assignment: BattleEffectSnapshot in unit.effect_assignments:
		if (
			assignment != null
			and not assignment.effect_id.is_empty()
			and not inspection.status_ids.has(assignment.effect_id)
		):
			inspection.status_ids.append(assignment.effect_id)
	inspection.equipment_ids.sort()
	inspection.trait_ids.sort()
	inspection.status_ids.sort()
	return inspection


func _append_equipment_ids(
	target: Array[StringName],
	effects: Array[BattleEffectSnapshot],
	unit_instance_id: StringName
) -> void:
	for effect: BattleEffectSnapshot in effects:
		if (
			effect == null
			or effect.source_category != &"equipment"
			or effect.source_stable_id.is_empty()
			or not effect.target_ids.has(unit_instance_id)
			or target.has(effect.source_stable_id)
		):
			continue
		target.append(effect.source_stable_id)


## Compatibility surface for the dev Run Lab. Production screens bind only typed
## lease ports; the dev wrapper is deliberately a consumer of this facade.
func view_state() -> RunViewState:
	return _controller.view_state() if _controller != null else null


func map_state() -> MapState:
	return _controller.map_snapshot() if _controller != null else null


func economy_state() -> EconomyState:
	return _controller.economy_snapshot() if _controller != null else null


func roster_state() -> RosterState:
	return _controller.roster_snapshot() if _controller != null else null


func pending_reward_state() -> PendingRewardState:
	return _controller.pending_reward_snapshot() if _controller != null else null


func drive_current_combat_to_commit(step_limit: int) -> StringName:
	if _combat == null:
		return DEPENDENCY_MISSING
	if _combat_result_already_committed:
		_combat_result_already_committed = false
		return &""
	var error_code := _drive_to_commit(step_limit)
	if error_code.is_empty():
		_snapshot = _build_snapshot()
		snapshot_committed.emit(_snapshot.deep_clone())
	return error_code


## 只跑 canonical simulation 到 result 提交為止，不發 snapshot signal——提交時機由
## 呼叫端決定（intent 路徑統一在 _commit_success 發一次）。
func _drive_to_commit(step_limit: int) -> StringName:
	for _step: int in range(step_limit):
		var advanced := _combat.advance()
		if not advanced.ok:
			return _combat_error_code(advanced.error)
		if advanced.result_committed:
			return &""
	return COMBAT_STEP_LIMIT


func _start_or_resume_combat(intent: RunPresentationIntent) -> RunPresentationResult:
	var view := _controller.view_state()
	var start_committed: bool = false
	if view.run_phase != RunState.RunPhase.COMBAT:
		var sources := intent.battle_sources
		if sources == null and _battle_catalog != null:
			sources = BattleSetupSourceCompiler.new().compile(
				_controller.roster_snapshot(),
				_battle_catalog,
				_commander_passive_effect_ids
			)
		var transitioned := _controller.transition(_factory.start_combat_event(sources))
		if not transitioned.ok:
			return _precommit_failure(_transition_error(transitioned.error))
		start_committed = true
	if _combat == null:
		var dependency_error := _error(
			DEPENDENCY_MISSING, &"error.presentation.combat_dependency_missing"
		)
		return (
			RunPresentationResult.postcommit_failure(dependency_error, _build_snapshot())
			if start_committed
			else _precommit_failure(dependency_error)
		)
	var begun := _combat.begin_or_resume()
	if not begun.ok:
		var combat_error := _error(
			_combat_error_code(begun.error), &"error.presentation.combat_start_failed"
		)
		if start_committed:
			_snapshot = _build_snapshot()
			presentation_error.emit(combat_error.deep_clone())
			return RunPresentationResult.postcommit_failure(combat_error, _snapshot)
		return _precommit_failure(combat_error)
	if not begun.resumed_committed_result:
		# 檢視投影只在 COMBAT_PENDING（有 battle_setup）時建得起來，驅動到 result 提交後
		# canonical 就只剩 BattleResultPendingResolutionState，故先取一份留給整個 COMBAT。
		_retained_combat_inspections = _build_combat_inspections()
		var drive_code := _drive_to_commit(COMBAT_COMMIT_STEP_LIMIT)
		if not drive_code.is_empty():
			var drive_error := _error(
				drive_code, &"error.presentation.combat_drive_failed"
			)
			# 驅動失敗前沒有 result 落檔；只有本次已提交的 COMBAT 轉場算 postcommit。
			if not start_committed:
				return _precommit_failure(drive_error)
			_snapshot = _build_snapshot()
			presentation_error.emit(drive_error.deep_clone())
			return RunPresentationResult.postcommit_failure(drive_error, _snapshot)
	# 灰盒 consumer 隨後仍會呼叫 drive_current_combat_to_commit()：旗標讓那一次成為
	# 冪等的 no-op，而不是對已結束的 simulation 再 advance。
	_combat_result_already_committed = true
	return _commit_success()


func _dispatch_command(command: RunCommand) -> RunPresentationResult:
	var result := _controller.dispatch(command)
	if not result.ok:
		return _precommit_failure(_command_error(result.error))
	return _commit_success()


func _dispatch_transition(event: RunEvent) -> RunPresentationResult:
	var result := _controller.transition(event)
	if not result.ok:
		return _precommit_failure(_transition_error(result.error))
	return _commit_success()


func _commit_success() -> RunPresentationResult:
	_snapshot = _build_snapshot()
	snapshot_committed.emit(_snapshot.deep_clone())
	return RunPresentationResult.success(_snapshot)


func _precommit_failure(error: DiagnosticError) -> RunPresentationResult:
	presentation_error.emit(error.deep_clone())
	return RunPresentationResult.precommit_failure(error, _snapshot)


func _build_snapshot() -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	if _controller == null:
		return result
	var view := _controller.view_state()
	result.run_id = StringName(view.run_id)
	result.app_phase = StringName(RunState.RunPhase.keys()[view.run_phase])
	result.manifest_digest = view.content_manifest_digest
	result.view = view.deep_clone()
	result.map = _controller.map_snapshot()
	result.economy = _controller.economy_snapshot()
	result.roster = _controller.roster_snapshot()
	result.pending_reward = _controller.pending_reward_snapshot()
	if (
		_factory != null
		and result.roster != null
		and result.economy != null
	):
		result.board_validation_report = _factory.board_validation_report(
			result.roster,
			result.economy.level
		)
	result.combat_inspections = _resolve_combat_inspections(view)
	for kind_name: String in RunPresentationIntent.Kind.keys():
		result.available_actions.append(StringName(kind_name))
	return result


## Kept as a thin alias: the shared rule lives on MapNodePresentation
## (presentation/run/map_node_presentation.gd) so RunMapScreen can call it
## without a presentation/screens/*.gd file naming RunPresentationSession,
## which the PUI_SCREEN_WRITER_DEPENDENCY static gate treats as a canonical
## writer dependency.
static func node_is_reachable(map_state: MapState, node: MapNodeState) -> bool:
	return MapNodePresentationType.is_reachable(map_state, node)


func _command_error(value: CommandError) -> DiagnosticError:
	if value == null:
		return _error(&"RUN_COMMAND_FAILED", &"error.presentation.run_command_failed")
	return _error(
		_source_code(value.code, value.diagnostic_values),
		&"error.presentation.run_command_failed"
	)


func _transition_error(value: RunTransitionError) -> DiagnosticError:
	if value == null:
		return _error(&"RUN_TRANSITION_FAILED", &"error.presentation.run_transition_failed")
	return _error(
		_source_code(value.code, value.diagnostic_values),
		&"error.presentation.run_transition_failed"
	)


func _source_code(
	fallback: StringName,
	diagnostics: Array[DiagnosticValue]
) -> StringName:
	for diagnostic: DiagnosticValue in diagnostics:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return StringName("%s/%s" % [
				String(fallback), diagnostic.string_value.value
			])
	return fallback


func _combat_error_code(value: CombatCoordinatorError) -> StringName:
	if value == null:
		return &"COMBAT_COORDINATOR_FAILED"
	return value.source_code if not value.source_code.is_empty() else value.code


func _error(code: StringName, message_key: StringName) -> DiagnosticError:
	return DiagnosticError.new(code, message_key)
