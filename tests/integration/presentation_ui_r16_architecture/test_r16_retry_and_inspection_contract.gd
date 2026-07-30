extends GutTest

const TerminalSupport = preload(
	"res://tests/integration/presentation_ui_r13_terminal/"
	+ "r13_terminal_test_support.gd"
)


func test_results_retry_exposes_only_the_root_owned_atomic_surface() -> void:
	var port := ResultsFallbackNavigationPort.new()
	assert_true(port.has_method(&"retry_installed"))
	assert_false(
		port.has_method(&"prepare_retry"),
		"repository authority must never be issued by a public split prepare API"
	)
	assert_false(
		port.has_method(&"retry"),
		"retry consume/present must remain inside the root-owned atomic action"
	)


func test_atomic_retry_blocks_direct_app_root_camp_and_menu_at_all_three_phases() -> void:
	var repository := TerminalSupport.probed_retry_repository()
	add_child_autofree(repository)
	var installed := TerminalSupport.settle_for_retry(repository)
	assert_not_null(installed)
	if installed == null:
		return
	var root := ApplicationRoot.new()
	autofree(root)
	var leases := LiveScreenLeaseRegistry.new()
	leases.activate(AppStateMachine.State.RESULTS, 16)
	var observed_codes: Array[StringName] = []
	var observe_root_barrier := func() -> void:
		observed_codes.append(
			root.return_results_to_camp().error.source_code
		)
		observed_codes.append(
			root.return_results_to_menu().error.source_code
		)
	var port := ResultsFallbackNavigationPort.new()
	assert_eq(
		port.bind_installed_results(
			SaveRepositoryResultsRenderRetryAuthority.new(repository),
			func() -> ResultsPresentationSnapshot:
				return installed.deep_clone(),
			func(
				_candidate: ResultsPresentationSnapshot,
				_generation: int
			) -> AppActionResult:
				observe_root_barrier.call()
				return AppActionResult.success(false),
			func() -> AppActionResult:
				return AppActionResult.success(false),
			func() -> AppActionResult:
				return AppActionResult.success(false),
			leases,
			16,
			installed,
			Callable(root, "_begin_results_action"),
			Callable(root, "_end_results_action")
		),
		&""
	)
	repository.before_issue = func() -> void:
		observe_root_barrier.call()
	repository.after_consume = func() -> void:
		observe_root_barrier.call()

	assert_true(port.retry_installed().ok)
	assert_eq(
		observed_codes,
		[
			ApplicationRoot.RESULTS_ACTION_IN_PROGRESS,
			ApplicationRoot.RESULTS_ACTION_IN_PROGRESS,
			ApplicationRoot.RESULTS_ACTION_IN_PROGRESS,
			ApplicationRoot.RESULTS_ACTION_IN_PROGRESS,
			ApplicationRoot.RESULTS_ACTION_IN_PROGRESS,
			ApplicationRoot.RESULTS_ACTION_IN_PROGRESS,
		],
		"ownership entry, CAS consume, and candidate bind must all block direct "
		+ "AppRoot Camp/Menu reentry"
	)


func test_real_session_reads_clone_only_two_sided_combat_projection() -> void:
	var snapshot := RunPresentationSnapshot.new()
	assert_true(
		_has_property(snapshot, &"combat_inspections"),
		"the committed run snapshot must own a clone-only two-sided projection"
	)
	if not _has_property(snapshot, &"combat_inspections"):
		return
	var ally := _inspection(
		1,
		&"unit.ally.alpha",
		&"ally",
		2,
		[&"equipment.ember"],
		[&"trait.ally.guard"],
		[&"status.shielded"]
	)
	var enemy := _inspection(
		2,
		&"unit.enemy.alpha",
		&"enemy",
		1,
		[&"equipment.frost"],
		[&"trait.enemy.arcane"],
		[&"status.burning"]
	)
	snapshot.combat_inspections.append(ally)
	snapshot.combat_inspections.append(enemy)
	snapshot.app_phase = &"COMBAT"
	var session := RunPresentationSession.new()
	session.set(&"_snapshot", snapshot.deep_clone())

	var ally_result := session.inspect_combat_unit(1)
	var enemy_result := session.inspect_combat_unit(2)

	assert_true(ally_result.ok)
	assert_true(enemy_result.ok)
	if not ally_result.ok or not enemy_result.ok:
		return
	assert_eq(ally_result.snapshot.source_id, &"unit.ally.alpha")
	assert_eq(ally_result.snapshot.target_serial, 2)
	assert_eq(ally_result.snapshot.equipment_ids, [&"equipment.ember"])
	assert_eq(ally_result.snapshot.trait_ids, [&"trait.ally.guard"])
	assert_eq(ally_result.snapshot.status_ids, [&"status.shielded"])
	assert_eq(enemy_result.snapshot.source_id, &"unit.enemy.alpha")
	assert_eq(enemy_result.snapshot.target_serial, 1)
	assert_eq(enemy_result.snapshot.equipment_ids, [&"equipment.frost"])
	assert_eq(enemy_result.snapshot.trait_ids, [&"trait.enemy.arcane"])
	assert_eq(enemy_result.snapshot.status_ids, [&"status.burning"])

	ally_result.snapshot.equipment_ids.clear()
	var fresh := session.inspect_combat_unit(1)
	assert_true(fresh.ok)
	if fresh.ok:
		assert_eq(
			fresh.snapshot.equipment_ids,
			[&"equipment.ember"],
			"inspection callers must not alias the committed projection"
		)


func _inspection(
	serial: int,
	source_id: StringName,
	side_id: StringName,
	target_serial: int,
	equipment_ids: Array[StringName],
	trait_ids: Array[StringName],
	status_ids: Array[StringName]
) -> CombatUnitInspectionSnapshot:
	var value := CombatUnitInspectionSnapshot.new()
	value.unit_serial = serial
	value.source_id = source_id
	value.target_serial = target_serial
	value.stats = {"health": 100, "attack": 10}
	value.equipment_ids.assign(equipment_ids)
	value.trait_ids.assign(trait_ids)
	value.status_ids.assign(status_ids)
	if _has_property(value, &"side_id"):
		value.set(&"side_id", side_id)
	return value


func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
