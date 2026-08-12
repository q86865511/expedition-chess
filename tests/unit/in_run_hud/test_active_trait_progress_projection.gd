extends GutTest

const MANIFEST := "manifest.active_trait_progress"
const TRAIT_ID: StringName = &"trait.progress_test"


func test_projection_copies_active_authority_and_full_pinned_thresholds() -> void:
	var projected := _project(_snapshot(MANIFEST), _catalog(MANIFEST, true))
	assert_eq(projected.size(), 1)
	var progress: TraitProgressPresentationSnapshot = projected[0]
	assert_eq(progress.trait_id, TRAIT_ID)
	assert_eq(progress.current_tier, 2)
	assert_eq(progress.member_count, 4)
	assert_eq(progress.thresholds.size(), 3)
	assert_eq(progress.thresholds[0].tier, 1)
	assert_eq(progress.thresholds[0].required_count, 2)
	assert_eq(progress.thresholds[0].effect_ids, [&"effect.progress_1"])
	assert_eq(progress.thresholds[1].tier, 2)
	assert_eq(progress.thresholds[1].required_count, 4)
	assert_eq(progress.thresholds[1].effect_ids, [&"effect.progress_2"])
	assert_eq(progress.thresholds[2].tier, 3)
	assert_eq(progress.thresholds[2].required_count, 6)
	assert_eq(progress.thresholds[2].effect_ids, [&"effect.progress_3"])


func test_manifest_mismatch_and_missing_active_rule_fail_closed() -> void:
	assert_true(
		_project(_snapshot(MANIFEST), _catalog("different.manifest", true))
		.is_empty()
	)
	assert_true(
		_project(_snapshot(MANIFEST), _catalog(MANIFEST, false)).is_empty()
	)


func test_snapshot_clone_isolates_nested_thresholds_and_effect_ids() -> void:
	var source := _snapshot(MANIFEST)
	source.active_trait_progress.assign(
		_project(source, _catalog(MANIFEST, true))
	)
	var first := source.deep_clone()
	first.active_trait_progress[0].thresholds[0].required_count = 999
	first.active_trait_progress[0].thresholds[0].effect_ids.append(
		&"effect.injected"
	)

	var second := source.deep_clone()
	assert_eq(
		second.active_trait_progress[0].thresholds[0].required_count,
		2
	)
	assert_false(
		second.active_trait_progress[0].thresholds[0].effect_ids.has(
			&"effect.injected"
		)
	)


func _project(
	snapshot: RunPresentationSnapshot,
	catalog: BattleRuleCatalog
) -> Array[TraitProgressPresentationSnapshot]:
	var session := RunPresentationSession.new()
	session.set(&"_battle_catalog", catalog.deep_clone())
	var result: Array[TraitProgressPresentationSnapshot] = []
	var projected: Variant = session.call(
		&"_build_active_trait_progress", snapshot
	)
	if projected is Array:
		result.assign(projected)
	return result


func _snapshot(manifest_digest: String) -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	result.manifest_digest = manifest_digest
	var active := TraitBattleSnapshot.new()
	active.trait_id = TRAIT_ID
	active.tier = 2
	active.member_instance_ids = [
		&"unit.member_1",
		&"unit.member_2",
		&"unit.member_3",
		&"unit.member_4",
	]
	result.active_trait_previews.append(active)
	return result


func _catalog(
	manifest_digest: String,
	include_trait_rule: bool
) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	if include_trait_rule:
		var rule := BattleTraitRule.new()
		rule.trait_id = TRAIT_ID
		rule.thresholds.append(_threshold(2, &"effect.progress_1"))
		rule.thresholds.append(_threshold(4, &"effect.progress_2"))
		rule.thresholds.append(_threshold(6, &"effect.progress_3"))
		traits.append(rule)
	return BattleRuleCatalog.new(
		manifest_digest,
		units,
		traits,
		abilities,
		effects,
		encounters,
		equipment,
		configs
	)


func _threshold(
	required_count: int,
	effect_id: StringName
) -> BattleTraitThresholdRule:
	var result := BattleTraitThresholdRule.new()
	result.required_count = required_count
	result.effect_ids = [effect_id]
	return result
