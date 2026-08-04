extends GutTest

const BOSS_ENCOUNTER_ID: StringName = &"encounter.slice_boss_0"
const NODE_ID: StringName = &"node_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


func test_real_pack_boss_setup_passes_battle_input_validation() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var content := ProjectContentBootstrap.new().run(registry)
	assert_true(content.ok, "production content bootstrap 必須成功")
	if not content.ok:
		return

	var roots: Array[StringName] = []
	roots.append_array(content.unit_ids)
	roots.append_array(content.equipment_ids)
	roots.append_array(content.battle_relic_ids)
	roots.append_array(content.encounter_ids)
	var built := BattleRuleCatalogBuilder.new().build(
		registry,
		content.manifest_digest,
		RunCompositionSupport.required_battle_ids(roots, 0)
	)
	assert_true(built.ok, _catalog_error(built))
	if not built.ok:
		return

	var request := EncounterCompileRequest.new()
	request.manifest_digest = content.manifest_digest
	request.encounter_id = BOSS_ENCOUNTER_ID
	request.node_id = NODE_ID
	request.act_index = 1
	request.depth = 6
	request.challenge_level = 0
	var compiled := EncounterCompiler.new().compile(request, built.catalog)
	assert_true(compiled.ok, _encounter_error(compiled))
	if not compiled.ok:
		return

	var roster := _single_unit_roster(content.player_unit_ids[0])
	var sources := BattleSetupSourceCompiler.new().compile(roster, built.catalog)
	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 2
	inputs.content_version = content.content_version
	inputs.manifest_digest = StringName(content.manifest_digest)
	inputs.encounter_snapshot = compiled.preview.deep_clone()
	for unit: UnitBattleSnapshot in sources.player_units:
		inputs.player_units.append(unit.deep_clone())
	for trait_snapshot: TraitBattleSnapshot in sources.player_active_traits:
		inputs.player_active_traits.append(trait_snapshot.deep_clone())
	var rules := BattleRulesSnapshotBuilder.new().build(
		built.catalog, inputs, 1, &"boss"
	)
	assert_true(rules.ok, _rules_error(rules))
	if not rules.ok:
		return
	inputs.battle_rules = rules.snapshot
	var validation := BattleSetupInputsValidator.new().validate_for_build(inputs)
	assert_true(
		validation.ok,
		"真實 pack Boss BattleSetup 必須通過 validator: %s:%s" % [
			String(validation.error.code) if not validation.ok else "",
			String(validation.error.field_path) if not validation.ok else "",
		]
	)
	if not validation.ok:
		return
	var seed := U64Bits.zero()
	var setup := BattleSetupHashBuilder.new(seed).build_from_validated(
		inputs, validation.receipt
	)
	assert_true(setup.ok, "真實 pack Boss BattleSetup hash build 必須成功")
	if not setup.ok:
		return
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.COMBAT
	run.run_seed = seed
	run.resolution_state = CombatPendingResolutionState.new(setup.battle_setup)
	var coordinator := CombatCoordinator.new(FakeCombatRunController.new(run))
	var begun := coordinator.begin_or_resume()
	assert_true(begun.ok, _coordinator_error(begun.error))
	if not begun.ok:
		return
	var first_tick := coordinator.advance()
	assert_true(
		first_tick.ok,
		"真實 pack Boss 首 tick 必須通過 EffectResolver: %s" % _coordinator_error(
			first_tick.error
		)
	)


func _single_unit_roster(unit_id: StringName) -> RosterState:
	var instance := UnitInstance.new(
		"u_0000000000000001", unit_id, 1, [] as Array[String], U64Bits.one()
	)
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	var units: Array[UnitInstance] = [instance]
	return RosterState.new(
		BoardState.new([BoardPlacementState.new(0, 0, instance.instance_id)]),
		[] as Array[String], units, [] as Array[ItemInstanceState],
		[] as Array[String], [] as Array[String], relics
	)


func _catalog_error(result: BattleRuleCatalogBuildResult) -> String:
	return "" if result.ok else "%s:%s" % [result.error.code, result.error.field_path]


func _encounter_error(result: EncounterCompileResult) -> String:
	return "" if result.ok else "%s:%s" % [result.error.code, result.error.field_path]


func _rules_error(result: BattleRulesSnapshotBuildResult) -> String:
	return "" if result.ok else "%s:%s" % [result.error.code, result.error.field_path]


func _coordinator_error(error: CombatCoordinatorError) -> String:
	return "" if error == null else "%s:%s:%s" % [
		error.code, error.field_path, error.source_code,
	]
