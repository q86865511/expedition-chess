class_name EffectResolution
extends RefCounted

var matched: bool = false
var battle_operations: Array[BattleOperation] = []
var run_effect_intents: Array[RunMutationProposal] = []
var event_proposals: Array[BattleEventProposal] = []
var budget: BattleTickBudget
var rng_snapshot: RngSnapshot
var use_count_delta: int = 0

func deep_clone() -> EffectResolution:
	var copied := EffectResolution.new()
	copied.matched = matched
	for operation: BattleOperation in battle_operations:
		copied.battle_operations.append(operation.deep_clone())
	for proposal: RunMutationProposal in run_effect_intents:
		copied.run_effect_intents.append(proposal.deep_clone())
	for proposal: BattleEventProposal in event_proposals:
		copied.event_proposals.append(proposal.deep_clone())
	copied.budget = budget.deep_clone() if budget != null else null
	copied.rng_snapshot = rng_snapshot.deep_clone() if rng_snapshot != null else null
	copied.use_count_delta = use_count_delta
	return copied
