class_name BattleTraitRule
extends RefCounted

var trait_id: StringName
var trait_kind: StringName
var member_rule: StringName
var thresholds: Array[BattleTraitThresholdRule] = []

func deep_clone() -> BattleTraitRule:
	var copied := BattleTraitRule.new()
	copied.trait_id = trait_id
	copied.trait_kind = trait_kind
	copied.member_rule = member_rule
	for threshold: BattleTraitThresholdRule in thresholds:
		copied.thresholds.append(threshold.deep_clone())
	return copied
