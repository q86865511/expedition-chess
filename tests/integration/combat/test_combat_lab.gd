extends GutTest

func test_lab_builds_64_cells_nine_bench_slots_and_starts_proxy_battle() -> void:
	var scene := load("res://scenes/dev/combat_lab/combat_lab.tscn") as PackedScene
	assert_not_null(scene)
	var lab := scene.instantiate() as CombatLabScreen
	add_child_autofree(lab)
	await get_tree().process_frame
	var board := lab.get_node("Margin/Columns/Left/BoardGrid") as GridContainer
	var bench := lab.get_node("Margin/Columns/Left/BenchRow") as HBoxContainer
	assert_eq(board.get_child_count(), 64)
	assert_eq(bench.get_child_count(), 9)
	assert_eq(CombatLabProxySetupFactory.new().proxy_unit_ids().size(), 8)
	var first_bench := bench.get_child(0) as Button
	first_bench.pressed.emit()
	var destination := board.get_child(0) as Button
	destination.pressed.emit()
	assert_eq(destination.text, "van")
	var start := lab.get_node(
		"Margin/Columns/Left/Controls/StartButton"
	) as Button
	start.pressed.emit()
	assert_eq(start.text, "開戰")
	for _index: int in range(10):
		lab._process(0.05)
	var log := lab.get_node("Margin/Columns/Right/EventLog") as RichTextLabel
	assert_true(log.get_parsed_text().contains("spawn"))

func test_lab_proxy_factory_builds_normal_and_source_bound_two_phase_boss() -> void:
	var factory := CombatLabProxySetupFactory.new()
	var normal := factory.build(false)
	var boss := factory.build(true)
	assert_not_null(normal)
	assert_not_null(boss)
	assert_eq(normal.inputs.player_units.size(), 8)
	assert_eq(normal.inputs.encounter_snapshot.enemy_units.size(), 4)
	assert_eq(boss.inputs.player_units.size(), 8)
	assert_eq(boss.inputs.encounter_snapshot.boss_phases.size(), 2)
	assert_eq(boss.inputs.battle_rules.encounter_kind, &"boss")
	for phase: BossPhaseSnapshot in boss.inputs.encounter_snapshot.boss_phases:
		assert_eq(
			phase.source_instance_id,
			boss.inputs.encounter_snapshot.enemy_units[0].instance_id
		)
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
	]
	var deployed := factory.build(false, cells)
	assert_eq(deployed.inputs.player_units[0].logical_x, 0)
	assert_eq(deployed.inputs.player_units[7].logical_x, 7)

func test_presenter_returns_clone_isolated_setup_events_and_result() -> void:
	var setup := CombatLabProxySetupFactory.new().build()
	var presenter := CombatLabPresenter.new()
	presenter.present_setup(setup)
	var view := presenter.setup_view()
	view.inputs.player_units[0].health = 1
	assert_ne(presenter.setup_view().inputs.player_units[0].health, 1)
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(setup).ok)
	var stepped := simulation.step()
	presenter.present_events(stepped.events)
	var events := presenter.event_view()
	events[0].tick = 99
	assert_ne(presenter.event_view()[0].tick, 99)
