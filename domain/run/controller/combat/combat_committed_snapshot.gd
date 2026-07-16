class_name CombatCommittedSnapshot
extends RefCounted

var publication_serial: U64Bits
var run_phase: RunState.RunPhase
var run_seed: U64Bits
var resolution_state: ResolutionState

func _init(
	p_publication_serial: U64Bits,
	p_run_phase: RunState.RunPhase,
	p_run_seed: U64Bits,
	p_resolution_state: ResolutionState
) -> void:
	publication_serial = p_publication_serial.deep_clone()
	run_phase = p_run_phase
	run_seed = p_run_seed.deep_clone()
	resolution_state = p_resolution_state.deep_clone()

func deep_clone() -> CombatCommittedSnapshot:
	return CombatCommittedSnapshot.new(
		publication_serial,
		run_phase,
		run_seed,
		resolution_state
	)
