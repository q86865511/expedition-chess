extends GutTest

const LIFECYCLE_ISSUE: StringName = &"CONTENT_EFFECT_SOURCE_LIFECYCLE"


func test_all_global_reference_kinds_reject_self_target() -> void:
	for source_kind: StringName in [
		&"relic", &"trait", &"commander", &"encounter_affix", &"challenge",
	]:
		var input := _empty_input()
		var effect_id := StringName("effect.probe_%s_self" % source_kind)
		input.definitions.append(_modify_stat_effect(
			effect_id, &"battle_start", &"attack", &"self"
		))
		_append_global_reference(input, source_kind, effect_id)
		var report := ContentValidator.new().validate(input)
		assert_true(
			_has_issue_for(report, LIFECYCLE_ISSUE, effect_id),
			"global source %s 的 target=self 必須 fail-closed: %s" % [
				source_kind, _issue_text(report),
			]
		)


func test_all_global_reference_kinds_accept_all_allies_lifecycle() -> void:
	for source_kind: StringName in [
		&"relic", &"trait", &"commander", &"encounter_affix", &"challenge",
	]:
		var input := _empty_input()
		var effect_id := StringName("effect.probe_%s_allies" % source_kind)
		input.definitions.append(_modify_stat_effect(
			effect_id, &"battle_start", &"attack", &"all_allies"
		))
		_append_global_reference(input, source_kind, effect_id)
		var report := ContentValidator.new().validate(input)
		assert_false(
			_has_issue_for(report, LIFECYCLE_ISSUE, effect_id),
			"global source %s 的 battle_start/all_allies 應合法: %s" % [
				source_kind, _issue_text(report),
			]
		)


func test_unit_scoped_self_target_remains_legal() -> void:
	var input := _empty_input()
	var effect_id := &"effect.probe_unit_self"
	input.definitions.append(_modify_stat_effect(
		effect_id, &"battle_start", &"attack", &"self"
	))
	var unit := UnitDef.new()
	unit.id = &"unit.probe_unit_self"
	unit.schema_version = 1
	unit.display_name_key = &"loc.unit_probe_unit_self"
	unit.effect_refs = [effect_id]
	input.definitions.append(unit)
	var report := ContentValidator.new().validate(input)
	assert_false(
		_has_issue_for(report, LIFECYCLE_ISSUE, effect_id),
		"unit-scoped source 的 target=self 必須維持合法: %s" % _issue_text(report)
	)


func test_global_hit_trigger_and_challenge_dual_track_run_operation_are_rejected() -> void:
	var hit_input := _empty_input()
	var hit_effect_id := &"effect.probe_global_hit"
	hit_input.definitions.append(_modify_stat_effect(
		hit_effect_id, &"hit", &"attack", &"all_allies"
	))
	_append_global_reference(hit_input, &"relic", hit_effect_id)
	var hit_report := ContentValidator.new().validate(hit_input)
	assert_true(
		_has_issue_for(hit_report, LIFECYCLE_ISSUE, hit_effect_id),
		"global source trigger=hit 必須被拒絕: %s" % _issue_text(hit_report)
	)

	# DC-REQ-006（BP-SI-001 已解除，combat-core/design.md:117/:236）：RunOperation 禁令的
	# 作用域限於進入 BattleSetup 的 EffectSourceState——本效果同時帶 battle_operations
	# （因此會被 pin 進 battle catalog）又帶 run_operations，屬雙軌，仍必須被拒絕。
	var run_input := _empty_input()
	var run_effect_id := &"effect.probe_challenge_run"
	var run_effect := _modify_stat_effect(run_effect_id, &"battle_start", &"attack", &"all_allies")
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = 1
	operation.claim_scope = &"always"
	run_effect.run_operations = [operation]
	run_input.definitions.append(run_effect)
	_append_global_reference(run_input, &"challenge", run_effect_id)
	var run_report := ContentValidator.new().validate(run_input)
	assert_true(
		_has_issue_for(run_report, LIFECYCLE_ISSUE, run_effect_id),
		"雙軌（battle_operations＋run_operations）challenge global source 必須被拒絕: %s" % _issue_text(run_report)
	)


## DC-REQ-006：純 run_operations（無 battle_operations）的 challenge global source 不進
## BattleSetup，不受本檔其餘案例的 RunOperation 禁令限制——這是 slice_challenge_affix_01
## （ShopSurcharge）／_03（DrainExpeditionHp）能回鏈的前提。
func test_challenge_pure_run_operation_without_battle_operations_is_accepted() -> void:
	var run_input := _empty_input()
	var run_effect_id := &"effect.probe_challenge_pure_run"
	var run_effect := _base_effect(run_effect_id, &"battle_start")
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = 1
	operation.claim_scope = &"always"
	run_effect.run_operations = [operation]
	run_input.definitions.append(run_effect)
	_append_global_reference(run_input, &"challenge", run_effect_id)
	var run_report := ContentValidator.new().validate(run_input)
	assert_false(
		_has_issue_for(run_report, LIFECYCLE_ISSUE, run_effect_id),
		"純 run_operations 的 challenge global source 不進 BattleSetup，不應被 lifecycle 規則拒絕: %s" % _issue_text(run_report)
	)


func test_operation_enums_reject_illegal_stat_damage_type_and_target() -> void:
	var stat_input := _empty_input()
	stat_input.definitions.append(_modify_stat_effect(
		&"effect.probe_bad_stat", &"battle_start", &"health", &"self"
	))
	assert_true(
		_has_issue_for(
			ContentValidator.new().validate(stat_input),
			&"CONTENT_OPERATION_INVALID", &"effect.probe_bad_stat"
		),
		"modify_stat stat=health 必須被 content gate 拒絕"
	)

	var target_input := _empty_input()
	target_input.definitions.append(_modify_stat_effect(
		&"effect.probe_bad_target", &"battle_start", &"attack", &"owner"
	))
	assert_true(
		_has_issue_for(
			ContentValidator.new().validate(target_input),
			&"CONTENT_OPERATION_INVALID", &"effect.probe_bad_target"
		),
		"未知 operation target 必須被 content gate 拒絕"
	)

	var damage_input := _empty_input()
	var damage_effect := _base_effect(&"effect.probe_bad_damage_type", &"cast")
	var damage := DamageOperationDef.new()
	damage.operation_index = 0
	damage.base = 1
	damage.scaling = &"flat"
	damage.damage_type = &"magic"
	damage.target = &"target"
	damage_effect.battle_operations = [damage]
	damage_input.definitions.append(damage_effect)
	assert_true(
		_has_issue_for(
			ContentValidator.new().validate(damage_input),
			&"CONTENT_OPERATION_INVALID", &"effect.probe_bad_damage_type"
		),
		"damage_type=magic（canonical 應為 magical）必須被拒絕"
	)


func _empty_input() -> ContentValidationInput:
	return ContentValidationInput.new(
		[] as Array[ContentDefinition], [], [], FakeContentDependencyPort.new(), 9
	)


func _base_effect(effect_id: StringName, trigger: StringName) -> EffectDef:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.description_key = StringName("loc.%s_description" % String(effect_id))
	effect.trigger = trigger
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 20
	return effect


func _modify_stat_effect(
	effect_id: StringName,
	trigger: StringName,
	stat: StringName,
	target: StringName
) -> EffectDef:
	var effect := _base_effect(effect_id, trigger)
	var operation := ModifyStatOperationDef.new()
	operation.operation_index = 0
	operation.stat = stat
	operation.mode = &"add"
	operation.amount = 1
	operation.duration_ticks = 20
	operation.target = target
	effect.battle_operations = [operation]
	return effect


func _append_global_reference(
	input: ContentValidationInput,
	source_kind: StringName,
	effect_id: StringName
) -> void:
	match source_kind:
		&"relic":
			var relic := RelicDef.new()
			relic.id = StringName("relic.%s" % String(effect_id).get_slice(".", 1))
			relic.schema_version = 1
			relic.display_name_key = StringName("loc.%s" % String(relic.id))
			relic.category = &"battle"
			relic.effect_refs = [effect_id]
			relic.activation_limit = 1
			input.definitions.append(relic)
		&"trait":
			var threshold := TraitThresholdDef.new()
			threshold.required_count = 1
			threshold.effect_refs = [effect_id]
			var trait_definition := TraitDef.new()
			trait_definition.id = StringName(
				"trait.%s" % String(effect_id).get_slice(".", 1)
			)
			trait_definition.schema_version = 1
			trait_definition.display_name_key = StringName(
				"loc.%s" % String(trait_definition.id)
			)
			trait_definition.description_key = StringName(
				"loc.%s_description" % String(trait_definition.id)
			)
			trait_definition.trait_kind = &"faction"
			trait_definition.member_rule = &"distinct_unit_defs"
			trait_definition.thresholds = [threshold]
			input.definitions.append(trait_definition)
		&"commander":
			var commander := CommanderDef.new()
			commander.id = StringName("commander.%s" % String(effect_id).get_slice(".", 1))
			commander.schema_version = 1
			commander.display_name_key = StringName("loc.%s" % String(commander.id))
			commander.passive_effect_refs = [effect_id]
			input.definitions.append(commander)
		&"encounter_affix":
			var encounter := EncounterDef.new()
			encounter.id = StringName("encounter.%s" % String(effect_id).get_slice(".", 1))
			encounter.schema_version = 1
			encounter.display_name_key = StringName("loc.%s" % String(encounter.id))
			encounter.encounter_kind = &"elite"
			encounter.affix_refs = [effect_id]
			input.definitions.append(encounter)
		&"challenge":
			var unlock := UnlockDef.new()
			unlock.id = StringName("unlock.%s" % String(effect_id).get_slice(".", 1))
			unlock.schema_version = 1
			unlock.display_name_key = StringName("loc.%s" % String(unlock.id))
			unlock.unlock_kind = &"challenge"
			unlock.challenge_level = 99
			unlock.modifier_refs = [effect_id]
			input.definitions.append(unlock)


func _has_issue_for(
	report: ContentValidationReport,
	code: StringName,
	source_id: StringName
) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code and issue.source_id == source_id:
			return true
	return false


func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
