class_name BattleState
extends RefCounted

var tick: int = 0
var next_event_sequence: int = 0
var next_work_sequence: int = 0
var entities: Array[BattleEntityState] = []
var effect_sources: Array[EffectSourceState] = []
var events: Array[BattleEvent] = []
var run_mutation_proposals: Array[RunMutationProposal] = []
var rng_snapshot: RngSnapshot
var _triggered_boss_phases: Dictionary = {}
var _damage_contributions: Dictionary = {}
var _damage_first_sequences: Dictionary = {}
var _global_effect_use_lookup: Dictionary = {}

func has_triggered_boss_phase(source_id: StringName, phase_index: int) -> bool:
	return _triggered_boss_phases.has(_boss_phase_key(source_id, phase_index))

func mark_boss_phase_triggered(source_id: StringName, phase_index: int) -> void:
	_triggered_boss_phases[_boss_phase_key(source_id, phase_index)] = true

func _boss_phase_key(source_id: StringName, phase_index: int) -> String:
	return "%s/%010d" % [String(source_id), phase_index]

func record_damage_contribution(
	target_id: StringName,
	source_id: StringName,
	health_damage: int
) -> void:
	if health_damage <= 0 or source_id.is_empty():
		return
	var target_key := String(target_id)
	var source_key := String(source_id)
	var values: Dictionary = _damage_contributions.get(target_key, {})
	values[source_key] = int(values.get(source_key, 0)) + health_damage
	_damage_contributions[target_key] = values
	var sequence_key := target_key + "/" + source_key
	if not _damage_first_sequences.has(sequence_key):
		_damage_first_sequences[sequence_key] = next_work_sequence
		next_work_sequence += 1

func killer_for(target_id: StringName) -> OptionalStringNameValue:
	var target_key := String(target_id)
	var values: Dictionary = _damage_contributions.get(target_key, {})
	var best_source := ""
	var best_damage := -1
	var best_sequence := 2147483647
	var sources: Array[String] = []
	for source_value: Variant in values.keys():
		sources.append(str(source_value))
	sources.sort()
	for source_key: String in sources:
		var amount := int(values[source_key])
		var sequence := int(_damage_first_sequences.get(
			target_key + "/" + source_key, 2147483647
		))
		if amount > best_damage or (amount == best_damage and (
			source_key < best_source or (
				source_key == best_source and sequence < best_sequence
			)
		)):
			best_source = source_key
			best_damage = amount
			best_sequence = sequence
	return OptionalStringNameValue.of(StringName(best_source)) \
		if not best_source.is_empty() else null

func clear_damage_contributions(target_id: StringName) -> void:
	var target_key := String(target_id)
	_damage_contributions.erase(target_key)
	var prefix := target_key + "/"
	var keys: Array = _damage_first_sequences.keys()
	for key: Variant in keys:
		if str(key).begins_with(prefix):
			_damage_first_sequences.erase(key)

func global_effect_use_count(source_token: String, effect_id: StringName) -> int:
	return int(_global_effect_use_lookup.get(
		source_token + "/" + String(effect_id), 0
	))

func record_global_effect_use(
	source_token: String,
	effect_id: StringName,
	count: int
) -> void:
	_global_effect_use_lookup[source_token + "/" + String(effect_id)] = count

func deep_clone() -> BattleState:
	var copied := BattleState.new()
	copied.tick = tick
	copied.next_event_sequence = next_event_sequence
	copied.next_work_sequence = next_work_sequence
	for entity: BattleEntityState in entities:
		copied.entities.append(entity.deep_clone())
	for source: EffectSourceState in effect_sources:
		copied.effect_sources.append(source.deep_clone())
	for event: BattleEvent in events:
		copied.events.append(event.deep_clone())
	for proposal: RunMutationProposal in run_mutation_proposals:
		copied.run_mutation_proposals.append(proposal.deep_clone())
	copied.rng_snapshot = rng_snapshot.deep_clone() if rng_snapshot != null else null
	copied._triggered_boss_phases = _triggered_boss_phases.duplicate(true)
	copied._damage_contributions = _damage_contributions.duplicate(true)
	copied._damage_first_sequences = _damage_first_sequences.duplicate(true)
	copied._global_effect_use_lookup = _global_effect_use_lookup.duplicate(true)
	return copied
