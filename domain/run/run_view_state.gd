class_name RunViewState
extends RefCounted

var publication_serial: U64Bits
var run_id: String
var content_manifest_digest: String
var act_index: int
var current_node_id: OptionalStringValue
var run_phase: RunState.RunPhase
var expedition_hp: int
var economy: EconomyViewState
var roster: RosterViewState
var resolution_kind: ResolutionState.Kind

func _init(
	p_publication_serial: U64Bits,
	p_run_id: String,
	p_content_manifest_digest: String,
	p_act_index: int,
	p_current_node_id: OptionalStringValue,
	p_run_phase: RunState.RunPhase,
	p_expedition_hp: int,
	p_economy: EconomyViewState,
	p_roster: RosterViewState,
	p_resolution_kind: ResolutionState.Kind
) -> void:
	publication_serial = p_publication_serial.deep_clone()
	run_id = p_run_id
	content_manifest_digest = p_content_manifest_digest
	act_index = p_act_index
	current_node_id = p_current_node_id.deep_clone() if p_current_node_id != null else null
	run_phase = p_run_phase
	expedition_hp = p_expedition_hp
	economy = p_economy.deep_clone()
	roster = p_roster.deep_clone()
	resolution_kind = p_resolution_kind

static func from_run(state: RunState, p_publication_serial: U64Bits) -> RunViewState:
	return RunViewState.new(
		p_publication_serial,
		state.run_id,
		state.content_snapshot.manifest_digest_value(),
		state.act_index,
		state.current_node_id,
		state.run_phase,
		state.expedition_hp,
		EconomyViewState.from_state(state.economy_state),
		RosterViewState.from_state(state.roster_state),
		state.resolution_state.kind
	)

func deep_clone() -> RunViewState:
	return RunViewState.new(
		publication_serial, run_id, content_manifest_digest, act_index,
		current_node_id, run_phase, expedition_hp, economy, roster, resolution_kind
	)
