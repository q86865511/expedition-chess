class_name BattleResult
extends RefCounted

var outcome: StringName = &""
var final_tick: int = 0
var survivor_instance_ids: Array[StringName] = []
var expedition_damage: int = 0
var summary_hash: StringName = &""
var run_mutation_proposals: Array[RunMutationProposal] = []

func deep_clone() -> BattleResult:
	var copied := BattleResult.new()
	copied.outcome = outcome
	copied.final_tick = final_tick
	copied.survivor_instance_ids = survivor_instance_ids.duplicate()
	copied.expedition_damage = expedition_damage
	copied.summary_hash = summary_hash
	for proposal: RunMutationProposal in run_mutation_proposals:
		copied.run_mutation_proposals.append(proposal.deep_clone())
	return copied
