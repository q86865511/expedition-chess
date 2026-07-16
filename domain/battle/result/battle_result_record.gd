class_name BattleResultRecord
extends RefCounted

var setup_schema_version: int = 2
var hash_version: int = 1
var rng_version: int = 1
var simulation_version: int = 1
var event_codec_version: int = 1
var result_codec_version: int = 1
var battle_setup_hash: StringName = &""
var outcome: StringName = &""
var final_tick: int = 0
var survivor_instance_ids: Array[StringName] = []
var expedition_damage: int = 0
var run_mutation_proposals: Array[RunMutationProposal] = []
var summary_hash: StringName = &""
var result_hash: StringName = &""

func deep_clone() -> BattleResultRecord:
	var copied := BattleResultRecord.new()
	copied.setup_schema_version = setup_schema_version
	copied.hash_version = hash_version
	copied.rng_version = rng_version
	copied.simulation_version = simulation_version
	copied.event_codec_version = event_codec_version
	copied.result_codec_version = result_codec_version
	copied.battle_setup_hash = battle_setup_hash
	copied.outcome = outcome
	copied.final_tick = final_tick
	copied.survivor_instance_ids = survivor_instance_ids.duplicate()
	copied.expedition_damage = expedition_damage
	for proposal: RunMutationProposal in run_mutation_proposals:
		copied.run_mutation_proposals.append(proposal.deep_clone())
	copied.summary_hash = summary_hash
	copied.result_hash = result_hash
	return copied
