extends GutTest

## rewrite-plan.md §5.3（Boss retry）與 §5.5 中的 failed／abandoned 兩個 terminal。
## - 附錄 C1-2 已把 driver 的 Boss 政策改成「HP>0 就重打」；本檔驗證它真的回到
##   PREPARE 重戰、HP 耗盡後落 failed terminal，且結算 receipt 每場恰一次。
## - abandoned 是 driver 自己不會採取的正式路徑（AbandonExpeditionCommand），
##   由探針在 Boss 重打狀態下走一次，驗證 abandon 結算恰好一次。
##
## Boss 敗局的構造方式：用 `force_empty_board_at_boss` 在 Boss 節點送出
## 「棋盤淨空、全員上板凳」的合法 layout，必敗。**不以特定 seed 的勝負當錨點**——
## 實測同一 seed 的勝負會隨同 process 內先跑過哪些測試而改變（見
## artifacts/test/balance-phase0-mutation-evidence.md 的「已回報缺口」），
## 用勝負錨點的測試會在 suite 組成改變時假紅。

const Support = preload(
	"res://tests/integration/balance_playtest/balance_driver_test_support.gd"
)
const PrepareProbeDriver = preload(
	"res://tests/integration/balance_playtest/prepare_probe_driver.gd"
)

var _registry: ContentRegistryService
var _content: ProjectContentBootstrapResult


func before_all() -> void:
	_registry = ContentRegistryService.new()
	add_child(_registry)
	_content = ProjectContentBootstrap.new().run(_registry)


func after_all() -> void:
	if _registry != null:
		remove_child(_registry)
		_registry.free()
		_registry = null


func test_boss_loss_retries_prepare_until_hp_exhausted_then_failed_terminal() -> void:
	if not _assert_content_ready():
		return
	var recorder := Support.StorageRecorder.new()
	var driver: PrepareProbeDriver = PrepareProbeDriver.new(_content, recorder.factory())
	driver.force_empty_board_at_boss = true
	var value: BalanceBotCaseResult = driver.run_case(
		BalanceBotStrategy.TEMPO, Support.SEED_VICTORY
	)

	assert_eq(
		value.failure_codes.size(), 0,
		"敗局也必須是乾淨的終局：%s" % str(value.failure_codes)
	)
	assert_gt(driver.forced_boss_battles, 1, "空板 Boss 戰必須被打過不只一次（＝有重打）")
	assert_true(value.terminal, "必須跑到 terminal")
	assert_eq(String(value.final_phase), "RESULTS", "終局 phase 必須是 RESULTS")
	assert_gt(
		value.boss_retry_count, 0,
		"Boss 敗且 HP>0 必須回到 PREPARE 重打（附錄 C1-2 的政策）"
	)
	assert_lte(
		value.boss_retry_count, BalanceProductionCaseDriver.BOSS_RETRY_LIMIT,
		"重打次數不得超過 driver 的防護上限"
	)
	assert_eq(
		value.boss_retry_count, driver.forced_boss_battles - 1,
		"每一次重打都必須對應一次真的重新開打"
	)
	assert_false(value.won, "HP 耗盡的局不得判為勝局")
	assert_eq(value.ending_hp, 0, "failed terminal 的遠征 HP 必須歸零")
	assert_lt(
		value.completed_node_count,
		BalanceProductionCaseDriver.EXPECTED_FULL_ROUTE_NODES,
		"死在 Boss 的局不可能走完整條路線"
	)

	# failed terminal 的 exactly-once
	assert_eq(
		value.settlement_receipt_digests.size(),
		value.battle_wins + value.battle_losses,
		"每場戰鬥（含每次 Boss 重打）必須恰有一筆結算 receipt"
	)
	assert_eq(
		Support.duplicate_of(value.settlement_receipt_digests), "",
		"結算 receipt 不得重複"
	)
	assert_eq(
		Support.duplicate_of(value.reward_receipt_digests), "",
		"獎勵 receipt 不得重複（無重複發獎）"
	)

	var run := Support.load_run(recorder.latest(), _registry)
	assert_not_null(run, "終局存檔必須可讀回")
	if run == null:
		return
	assert_eq(run.run_phase, RunState.RunPhase.RESULTS, "權威存檔必須停在 RESULTS")
	assert_eq(
		Support.receipt_proofs(run, Support.SETTLEMENT_RECEIPT_PREFIX).size(),
		value.battle_wins + value.battle_losses,
		"權威存檔的結算 receipt 數必須與戰鬥場次相符"
	)
	assert_eq(
		Support.receipt_proofs(run, Support.ABANDON_RECEIPT_KIND).size(), 0,
		"重打到 HP 耗盡不是 abandon，不得留下 abandon 結算"
	)


func test_abandon_boss_retry_settles_abandoned_terminal_exactly_once() -> void:
	if not _assert_content_ready():
		return
	var recorder := Support.StorageRecorder.new()
	var driver: PrepareProbeDriver = PrepareProbeDriver.new(_content, recorder.factory())
	driver.force_empty_board_at_boss = true
	driver.probe_ready = func(
		_session: RunPresentationSession, result: BalanceBotCaseResult
	) -> bool:
		return result.boss_retry_count >= 1
	driver.probe = func(
		session: RunPresentationSession, _result: BalanceBotCaseResult
	) -> void:
		_abandon_at_boss_retry(session)
	driver.run_case(BalanceBotStrategy.TEMPO, Support.SEED_VICTORY)

	assert_true(driver.probe_fired, "必須進到 Boss 重打狀態才驗得到 abandon")
	var run := Support.load_run(recorder.latest(), _registry)
	assert_not_null(run, "abandon 後的存檔必須可讀回")
	if run == null:
		return
	assert_eq(run.run_phase, RunState.RunPhase.RESULTS, "abandon 必須直接落 RESULTS")
	assert_eq(run.expedition_hp, 0, "abandon 必須把遠征 HP 歸零")
	assert_eq(
		Support.receipt_proofs(run, Support.ABANDON_RECEIPT_KIND).size(), 1,
		"abandon 結算 receipt 必須恰好一筆"
	)
	assert_eq(
		Support.duplicate_of(
			Support.receipt_proofs(run, Support.SETTLEMENT_RECEIPT_PREFIX)
		), "",
		"abandon 不得讓既有戰鬥結算重複記帳"
	)
	assert_eq(
		Support.duplicate_of(Support.receipt_proofs(run, Support.REWARD_RECEIPT_PREFIX)),
		"", "abandon 不得產生重複獎勵"
	)


func _abandon_at_boss_retry(session: RunPresentationSession) -> void:
	assert_eq(
		session.view_state().run_phase, RunState.RunPhase.PREPARE,
		"Boss 敗且 HP>0 必須回到 PREPARE"
	)
	assert_gt(session.view_state().expedition_hp, 0, "重打時遠征 HP 必須仍為正")
	var abandoned := session.dispatch(
		RunPresentationIntent.new(RunPresentationIntent.Kind.ABANDON_BOSS_RETRY)
	)
	assert_true(
		abandoned.ok, "abandon_boss_retry 必須成功：%s" % Support.dispatch_error(abandoned)
	)
	assert_eq(
		session.view_state().run_phase, RunState.RunPhase.RESULTS,
		"abandon 後必須進入 RESULTS"
	)


func _assert_content_ready() -> bool:
	assert_true(
		_content != null and _content.ok,
		"正式內容 bootstrap 必須成功：%s" % (
			String(_content.error_code) if _content != null else "null"
		)
	)
	return _content != null and _content.ok
