class_name BattleResult
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

func deep_clone() -> BattleResult:
	var copied := BattleResult.new()
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

func to_record() -> BattleResultRecord:
	var record := BattleResultRecord.new()
	record.setup_schema_version = setup_schema_version
	record.hash_version = hash_version
	record.rng_version = rng_version
	record.simulation_version = simulation_version
	record.event_codec_version = event_codec_version
	record.result_codec_version = result_codec_version
	record.battle_setup_hash = battle_setup_hash
	record.outcome = outcome
	record.final_tick = final_tick
	record.survivor_instance_ids = survivor_instance_ids.duplicate()
	record.expedition_damage = expedition_damage
	for proposal: RunMutationProposal in run_mutation_proposals:
		record.run_mutation_proposals.append(proposal.deep_clone())
	record.summary_hash = summary_hash
	record.result_hash = result_hash
	return record

static func from_record(record: BattleResultRecord) -> BattleResult:
	if record == null:
		return null
	var value := BattleResult.new()
	value.setup_schema_version = record.setup_schema_version
	value.hash_version = record.hash_version
	value.rng_version = record.rng_version
	value.simulation_version = record.simulation_version
	value.event_codec_version = record.event_codec_version
	value.result_codec_version = record.result_codec_version
	value.battle_setup_hash = record.battle_setup_hash
	value.outcome = record.outcome
	value.final_tick = record.final_tick
	value.survivor_instance_ids = record.survivor_instance_ids.duplicate()
	value.expedition_damage = record.expedition_damage
	for proposal: RunMutationProposal in record.run_mutation_proposals:
		value.run_mutation_proposals.append(proposal.deep_clone())
	value.summary_hash = record.summary_hash
	value.result_hash = record.result_hash
	return value

func validate() -> BattleResultCodecError:
	var encoded := BattleResultCodecV1.new().encode(to_record())
	return null if encoded.ok else encoded.error.deep_clone()
