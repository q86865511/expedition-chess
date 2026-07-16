class_name StartCombatEvent
extends RunEvent

const SOURCE_UNAVAILABLE: StringName = &"BATTLE_SOURCE_UNAVAILABLE"
const PHASE_INVALID: StringName = &"START_COMBAT_PHASE_INVALID"
const RESOLUTION_INVALID: StringName = &"START_COMBAT_RESOLUTION_INVALID"
const GENERATION_MISMATCH: StringName = &"START_COMBAT_CATALOG_GENERATION_MISMATCH"
const CURRENT_NODE_MISSING: StringName = &"START_COMBAT_CURRENT_NODE_MISSING"
const PREVIEW_MISSING: StringName = &"START_COMBAT_PREVIEW_MISSING"
const PLAYER_SOURCE_MISMATCH: StringName = &"START_COMBAT_PLAYER_SOURCE_MISMATCH"
const ENCOUNTER_KIND_INVALID: StringName = &"START_COMBAT_ENCOUNTER_KIND_INVALID"

var _catalog: BattleRuleCatalog
var _sources: BattleSetupSourceBundle
var _rules_builder: BattleRulesSnapshotBuilder
var _inputs_validator: BattleSetupInputsValidator

func _init(
	p_catalog: BattleRuleCatalog,
	p_sources: BattleSetupSourceBundle,
	p_rules_builder: BattleRulesSnapshotBuilder = null,
	p_inputs_validator: BattleSetupInputsValidator = null
) -> void:
	super(RunState.RunPhase.COMBAT)
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_sources = p_sources.deep_clone() if p_sources != null else null
	_rules_builder = (
		p_rules_builder if p_rules_builder != null else BattleRulesSnapshotBuilder.new()
	)
	_inputs_validator = (
		p_inputs_validator if p_inputs_validator != null else BattleSetupInputsValidator.new()
	)

func is_concrete() -> bool:
	return _catalog != null and _sources != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.content_snapshot == null \
		or draft.roster_state == null or draft.map_state == null:
		return _rejected(&"run", SOURCE_UNAVAILABLE)
	if draft.run_phase != RunState.RunPhase.PREPARE:
		return _rejected(&"run.run_phase", PHASE_INVALID)
	if draft.resolution_state == null \
		or draft.resolution_state.kind != ResolutionState.Kind.IDLE:
		return _rejected(&"run.resolution_state", RESOLUTION_INVALID)
	var manifest_digest := draft.content_snapshot.manifest_digest_value()
	if _catalog.manifest_digest_value() != manifest_digest \
		or _sources.manifest_digest != manifest_digest:
		return _rejected(
			&"run.content_snapshot.manifest_digest",
			GENERATION_MISMATCH
		)
	if not _sources.all_sources_resolved():
		return _rejected(&"battle_setup.sources", SOURCE_UNAVAILABLE)
	var node := _current_node(draft)
	if node == null:
		return _rejected(&"run.current_node_id", CURRENT_NODE_MISSING)
	if node.encounter_preview == null:
		return _rejected(&"run.map_state.encounter_preview", PREVIEW_MISSING)
	if String(node.encounter_preview.manifest_digest) != manifest_digest:
		return _rejected(
			&"run.map_state.encounter_preview.manifest_digest",
			GENERATION_MISMATCH
		)
	if not _player_sources_match_committed_roster(draft):
		return _rejected(&"battle_setup.player_units", PLAYER_SOURCE_MISMATCH)
	var encounter_kind := _encounter_kind(node.node_kind)
	if encounter_kind.is_empty():
		return _rejected(&"run.map_state.node_kind", ENCOUNTER_KIND_INVALID)
	var inputs := _inputs_from_committed_state(draft, node.encounter_preview)
	var rules_result := _rules_builder.build(
		_catalog,
		inputs,
		draft.act_index,
		encounter_kind
	)
	if not rules_result.ok:
		return _rejected(
			StringName("battle_setup.battle_rules.%s" % String(rules_result.error.field_path)),
			rules_result.error.code,
			rules_result.error.source_id
		)
	inputs.battle_rules = rules_result.snapshot.deep_clone()
	var validation := _inputs_validator.validate_for_build(inputs)
	if not validation.ok:
		return _rejected(
			StringName("battle_setup.inputs.%s" % String(validation.error.field_path)),
			validation.error.code,
			_optional_source_name(validation.error.source_id)
		)
	var setup_result := BattleSetupHashBuilder.new(draft.run_seed).build_from_validated(
		inputs,
		validation.receipt
	)
	if not setup_result.ok:
		return _rejected(
			StringName("battle_setup.%s" % String(setup_result.error.field_path)),
			setup_result.error.code
		)
	var envelope_result := BattleSetupEnvelopeVerifier.new().verify(
		setup_result.battle_setup,
		draft.run_seed
	)
	if not envelope_result.ok:
		return _rejected(
			StringName("battle_setup.%s" % String(envelope_result.error.field_path)),
			envelope_result.error.code
		)
	draft.resolution_state = CombatPendingResolutionState.new(setup_result.battle_setup)
	return CommandApplyResult.success(draft)

func _inputs_from_committed_state(
	draft: RunState,
	preview: EncounterPreviewSnapshot
) -> BattleSetupInputs:
	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 2
	inputs.content_version = draft.content_snapshot.content_version_value()
	inputs.manifest_digest = StringName(draft.content_snapshot.manifest_digest_value())
	inputs.encounter_snapshot = preview.deep_clone()
	for unit: UnitBattleSnapshot in _sources.player_units:
		inputs.player_units.append(unit.deep_clone() if unit != null else null)
	for trait_snapshot: TraitBattleSnapshot in _sources.player_active_traits:
		inputs.player_active_traits.append(
			trait_snapshot.deep_clone() if trait_snapshot != null else null
		)
	_append_effect_copies(
		inputs.player_equipment_effects,
		_sources.player_equipment_effects
	)
	_append_effect_copies(inputs.player_relic_effects, _sources.player_relic_effects)
	_append_effect_copies(inputs.commander_effects, _sources.commander_effects)
	_append_effect_copies(inputs.challenge_modifiers, _sources.challenge_modifiers)
	return inputs

func _player_sources_match_committed_roster(draft: RunState) -> bool:
	var placements := draft.roster_state.board.placements
	if _sources.player_units.size() != placements.size():
		return false
	var seen: Dictionary = {}
	for placement: BoardPlacementState in placements:
		if placement == null or seen.has(placement.unit_instance_id):
			return false
		var run_unit := _find_run_unit(
			draft.roster_state.unit_instances,
			placement.unit_instance_id
		)
		var snapshot := _find_player_snapshot(placement.unit_instance_id)
		if run_unit == null or snapshot == null \
			or snapshot.side != &"player" \
			or String(snapshot.instance_id) != run_unit.instance_id \
			or snapshot.unit_id != run_unit.def_id \
			or snapshot.star != run_unit.star \
			or snapshot.logical_y != placement.logical_y \
			or snapshot.logical_x != placement.logical_x \
			or _catalog.try_unit_rule(snapshot.unit_id) == null:
			return false
		seen[placement.unit_instance_id] = true
	return seen.size() == _sources.player_units.size()

func _current_node(draft: RunState) -> MapNodeState:
	if draft.current_node_id == null:
		return null
	for node: MapNodeState in draft.map_state.nodes:
		if node != null and node.node_id == draft.current_node_id.value:
			return node
	return null

func _find_run_unit(units: Array[UnitInstance], instance_id: String) -> UnitInstance:
	for unit: UnitInstance in units:
		if unit != null and unit.instance_id == instance_id:
			return unit
	return null

func _find_player_snapshot(instance_id: String) -> UnitBattleSnapshot:
	for unit: UnitBattleSnapshot in _sources.player_units:
		if unit != null and String(unit.instance_id) == instance_id:
			return unit
	return null

func _encounter_kind(kind: MapNodeState.NodeKind) -> StringName:
	match kind:
		MapNodeState.NodeKind.NORMAL:
			return &"normal"
		MapNodeState.NodeKind.ELITE:
			return &"elite"
		MapNodeState.NodeKind.BOSS:
			return &"boss"
	return &""

func _append_effect_copies(
	target: Array[BattleEffectSnapshot],
	source: Array[BattleEffectSnapshot]
) -> void:
	for effect: BattleEffectSnapshot in source:
		target.append(effect.deep_clone() if effect != null else null)

func _optional_source_name(source_id: StringName) -> OptionalStringNameValue:
	if source_id.is_empty():
		return null
	return OptionalStringNameValue.of(source_id)

func _rejected(
	field_path: StringName,
	source_code: StringName,
	source_id: OptionalStringNameValue = null
) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(source_code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(
			CommandApplyError.APPLY_REJECTED,
			field_path,
			source_id,
			diagnostics
		)
	)
