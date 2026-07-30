extends GutTest

const BattleFixture = preload(
	"res://tests/fixtures/combat/battle_simulation_fixture.gd"
)


func test_committed_setup_projects_through_real_session_and_lease_port() -> void:
	var save_root := SaveRootFixture.create_valid_root()
	var inputs: BattleSetupInputs = BattleFixture.create_inputs()
	var player := inputs.player_units[0]
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	var target_assignment := enemy.effect_assignments[0]
	target_assignment.target_ids = [player.instance_id]
	var setup := BattleFixture.build_setup(inputs, save_root.run.run_seed)
	assert_not_null(setup)
	if setup == null:
		return
	save_root.run.run_phase = RunState.RunPhase.COMBAT
	save_root.run.resolution_state = CombatPendingResolutionState.new(setup)
	var run_session := RunSession.new(
		save_root.profile,
		save_root.run,
		null
	)
	var controller := RunController.new(run_session, null)
	var presentation := RunPresentationSession.new(
		controller,
		RunCommandFactory.new(null, null),
		null,
		[],
		CombatCoordinator.new(controller)
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 1602)
	var port := LiveScreenInspectionPort.new(
		lease,
		registry,
		presentation
	)

	var ally := port.inspect_combat_unit(1)
	var foe := port.inspect_combat_unit(2)

	assert_true(ally.ok)
	assert_true(foe.ok)
	if not ally.ok or not foe.ok:
		return
	assert_eq(ally.snapshot.source_id, &"unit.hero")
	assert_eq(ally.snapshot.side_id, &"player")
	assert_eq(ally.snapshot.equipment_ids, [&"equipment.test"])
	assert_eq(ally.snapshot.trait_ids, [&"trait.test"])
	assert_eq(foe.snapshot.source_id, &"unit.foe")
	assert_eq(foe.snapshot.side_id, &"enemy")
	assert_eq(foe.snapshot.target_serial, 1)
	assert_eq(foe.snapshot.trait_ids, [])
	assert_true(foe.snapshot.status_ids.has(&"effect.test"))

	ally.snapshot.equipment_ids.clear()
	assert_eq(
		port.inspect_combat_unit(1).snapshot.equipment_ids,
		[&"equipment.test"],
		"inspection port must return a fresh clone on every read"
	)
	registry.revoke_active()
	var stale := port.inspect_combat_unit(1)
	assert_false(stale.ok)
	if stale.error != null:
		assert_eq(stale.error.source_code, &"SCREEN_NOT_ACTIVE")
