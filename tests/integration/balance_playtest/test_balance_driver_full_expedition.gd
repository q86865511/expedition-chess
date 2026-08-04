extends GutTest

## rewrite-plan.md §5.1（full expedition smoke）與 §5.4（save-reload 等價），
## 外加 §5.5 三 terminal 中的 victory exactly-once。
## 被測物：application/balance/balance_production_case_driver.gd 的主迴圈——
## 它必須以正式 RunController 鏈路把一局遠征從 CAMP 開局打到 RESULTS，
## 且同 seed 的三個策略必須落在同一個世界（cohort，關 BP-IR-002）。

const Support = preload(
	"res://tests/integration/balance_playtest/balance_driver_test_support.gd"
)
const InMemoryContinuationDriver = preload(
	"res://tests/integration/balance_playtest/in_memory_continuation_driver.gd"
)

var _registry: ContentRegistryService
var _content: ProjectContentBootstrapResult
var _driver: BalanceProductionCaseDriver
var _cases: Dictionary = {}


func before_all() -> void:
	_registry = ContentRegistryService.new()
	add_child(_registry)
	_content = ProjectContentBootstrap.new().run(_registry)
	# recorder 由 factory Callable 持有參考；本檔的斷言全部取自 case result，
	# 不需要再回頭讀 storage。
	var recorder := Support.StorageRecorder.new()
	_driver = BalanceProductionCaseDriver.new(_content, recorder.factory())


func after_all() -> void:
	_driver = null
	_cases.clear()
	if _registry != null:
		remove_child(_registry)
		_registry.free()
		_registry = null


func test_three_strategies_share_one_cohort_world_and_reach_results() -> void:
	if not _assert_content_ready():
		return
	var tempo := _case(BalanceBotStrategy.TEMPO)
	var economy := _case(BalanceBotStrategy.ECONOMY)
	var synergy := _case(BalanceBotStrategy.SYNERGY)

	for value: BalanceBotCaseResult in [tempo, economy, synergy]:
		var label := String(value.strategy_id)
		assert_eq(
			value.failure_codes.size(), 0,
			"%s 不得帶 failure code：%s" % [label, str(value.failure_codes)]
		)
		assert_true(value.terminal, "%s 必須跑到 terminal" % label)
		assert_eq(String(value.final_phase), "RESULTS", "%s 終局 phase" % label)
		assert_eq(
			value.completed_node_count, value.route_ids.size(),
			"%s 走訪節點數必須等於 route 長度" % label
		)
		# difficulty-curve 之後敗局是合法結果（DC-REQ-001~003）：勝局仍必須走滿
		# 21 節點（關 BP-IR-001 的 3 戰版病徵）；敗局必須是真淘汰（HP 歸零），
		# 且走訪數與 route 長度一致（上一條斷言）——排除「跑一半就停」的病徵。
		if value.won:
			assert_eq(
				value.completed_node_count,
				BalanceProductionCaseDriver.EXPECTED_FULL_ROUTE_NODES,
				"%s 勝局必須走完整條 21 節點路線" % label
			)
		else:
			assert_eq(value.ending_hp, 0, "%s 敗局必須是遠征 HP 歸零的真淘汰" % label)
			assert_lt(
				value.completed_node_count,
				BalanceProductionCaseDriver.EXPECTED_FULL_ROUTE_NODES,
				"%s 敗局走訪數應少於完整路線" % label
			)
		assert_gt(
			value.battle_wins + value.battle_losses, 0,
			"%s 必須真的打過戰鬥" % label
		)
		# victory terminal 的 exactly-once（§5.5）
		assert_eq(
			value.settlement_receipt_digests.size(),
			value.battle_wins + value.battle_losses,
			"%s 每場戰鬥必須恰有一筆結算 receipt" % label
		)
		assert_eq(
			Support.duplicate_of(value.settlement_receipt_digests), "",
			"%s 結算 receipt 不得重複" % label
		)
		if value.battle_wins > 0:
			assert_gt(
				value.reward_receipt_digests.size(), 0,
				"%s 有勝場就必須有獎勵 receipt" % label
			)
		assert_eq(
			Support.duplicate_of(value.reward_receipt_digests), "",
			"%s 獎勵 receipt 不得重複（無重複發獎）" % label
		)
		assert_true(value.ending_gold >= 0 and value.ending_hp >= 0, "%s 資源不得為負" % label)

	var best_progress: int = 0
	var total_wins: int = 0
	for value: BalanceBotCaseResult in [tempo, economy, synergy]:
		best_progress = max(best_progress, value.completed_node_count)
		total_wins += value.battle_wins
	assert_gt(
		best_progress, 7,
		"至少一個策略必須突破 Act 1（7 節點）——難度曲線不得是全滅牆"
	)
	assert_gt(total_wins, 0, "至少一個策略必須贏過戰鬥（獎勵鏈才有覆蓋）")

	assert_eq(economy.run_id, tempo.run_id, "同 seed 三策略必須同一個 run_id（cohort）")
	assert_eq(synergy.run_id, tempo.run_id, "同 seed 三策略必須同一個 run_id（cohort）")
	assert_eq(economy.world_digest, tempo.world_digest, "同 cohort 的地圖世界必須相同")
	assert_eq(synergy.world_digest, tempo.world_digest, "同 cohort 的地圖世界必須相同")


func test_save_reload_equivalence_matches_in_memory_continuation() -> void:
	if not _assert_content_ready():
		return
	var normal := _case(BalanceBotStrategy.TEMPO)
	var baseline_recorder := Support.StorageRecorder.new()
	var baseline_driver: InMemoryContinuationDriver = InMemoryContinuationDriver.new(
		_content, baseline_recorder.factory()
	)
	var baseline: BalanceBotCaseResult = baseline_driver.run_case(
		BalanceBotStrategy.TEMPO, Support.SEED_VICTORY
	)

	assert_eq(
		baseline.failure_codes.size(), 0,
		"對照組不得帶 failure code：%s" % str(baseline.failure_codes)
	)
	assert_eq(normal.reload_count, 1, "正式路徑必須在局中做過一次存檔重載")
	assert_eq(baseline.reload_count, 1, "對照組必須走到同一個重載分支")
	assert_true(baseline_driver.reused_composition, "對照組必須確實續用記憶體 composition")

	assert_eq(baseline.ending_gold, normal.ending_gold, "重載後的終局金幣必須一致")
	assert_eq(baseline.ending_hp, normal.ending_hp, "重載後的終局遠征 HP 必須一致")
	assert_eq(baseline.completed_node_count, normal.completed_node_count, "走訪節點數必須一致")
	assert_eq(baseline.battle_wins, normal.battle_wins, "勝場數必須一致")
	assert_eq(baseline.battle_losses, normal.battle_losses, "敗場數必須一致")
	assert_eq(baseline.route_ids, normal.route_ids, "路線必須一致")
	assert_eq(
		baseline.settlement_receipt_digests, normal.settlement_receipt_digests,
		"結算 receipt 序列必須一致（存檔往返不得漏記或重記）"
	)
	assert_eq(
		baseline.reward_receipt_digests, normal.reward_receipt_digests,
		"獎勵 receipt 序列必須一致"
	)
	assert_eq(baseline.replay_digest, normal.replay_digest, "整局重播摘要必須一致")


func _case(strategy_id: StringName) -> BalanceBotCaseResult:
	if _cases.has(strategy_id):
		return _cases[strategy_id]
	var value: BalanceBotCaseResult = _driver.run_case(strategy_id, Support.SEED_VICTORY)
	_cases[strategy_id] = value
	return value


func _assert_content_ready() -> bool:
	assert_true(
		_content != null and _content.ok,
		"正式內容 bootstrap 必須成功：%s" % (
			String(_content.error_code) if _content != null else "null"
		)
	)
	return _content != null and _content.ok
