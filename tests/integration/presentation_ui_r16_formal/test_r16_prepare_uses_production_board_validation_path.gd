extends GutTest

## R16 審查缺口 2（2026-07-30 補洞）：test_r16_formal_screen_contract.gd 裡
## test_prepare_uses_authoritative_report_and_exposes_the_player_loop 直接往
## RunPresentationSnapshot 注入 fabricated BoardValidationReport(12, [...]),從未走
## run_presentation_session.gd:539-547 -> run_command_factory.gd:175-201 的正式計算路徑
## ——把 session.gd:544 改回固定的 BoardValidationReport.new(0, []) 全測試仍綠。
##
## 本測試改用真正的 RunController + RunCommandFactory(帶指揮官人口加成),讓
## RunPresentationSession._init() 觸發的第一次 _build_snapshot() 經
## RunCommandFactory.board_validation_report() 對 SaveRootFixture 的真實 roster/economy
## 跑 BoardPreparationValidator,斷言 derived_capacity 等於「economy.level + 指揮官
## population_bonus」這個獨立算出來的期望值,而不是被固定寫死的 0。


func test_prepare_snapshot_board_validation_report_reflects_real_economy_level_and_commander_bonus() -> void:
	var save_root := SaveRootFixture.create_valid_root()
	assert_eq(
		save_root.run.economy_state.level, 1,
		"test setup: fixture economy level must be the known baseline this test reasons about"
	)
	var commander_population_bonus := 3
	var expected_capacity := save_root.run.economy_state.level + commander_population_bonus

	var run_session := RunSession.new(save_root.profile, save_root.run, null)
	var controller := RunController.new(run_session, null)
	var factory := RunCommandFactory.new(
		null, null, null, [],
		save_root.run.commander_id, commander_population_bonus
	)
	var session := RunPresentationSession.new(controller, factory)
	var snapshot := session.snapshot()

	assert_not_null(snapshot.board_validation_report)
	if snapshot.board_validation_report == null:
		return
	assert_eq(
		snapshot.board_validation_report.derived_capacity,
		expected_capacity,
		(
			"PREPARE's board_validation_report must come from the production " +
			"BoardPreparationValidator path (base economy level + commander population " +
			"bonus), not a fabricated/fixed report"
		)
	)
	assert_true(
		snapshot.board_validation_report.valid,
		"fixture roster has no placements, so the real validator must report no issues"
	)

	# Cross-check against a second, differently-bonused factory: if the report were a
	# fixed/fabricated value, changing the commander bonus would not move the capacity.
	var other_factory := RunCommandFactory.new(
		null, null, null, [],
		save_root.run.commander_id, commander_population_bonus + 5
	)
	var other_session := RunPresentationSession.new(controller, other_factory)
	var other_snapshot := other_session.snapshot()
	assert_eq(
		other_snapshot.board_validation_report.derived_capacity,
		expected_capacity + 5
	)
