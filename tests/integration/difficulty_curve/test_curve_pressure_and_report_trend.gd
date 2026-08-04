extends GutTest

## G2 difficulty-curve T09（快篩三層之 (b) 壓力斷言 + (c) 趨勢紀錄 read-back）：
## 走正式 RunController 鏈路（BalanceProductionCaseDriver），確認 T01-T03 疊加後
## 幕間曲線真的「咬人」，不是只在結構層生效卻沒有戰鬥後果。輕量版：只用 seed 0 的
## tempo／synergy 兩個已知會推進到 Act1 之外的組合（見
## tests/integration/balance_playtest/balance_driver_test_support.gd 的 SEED_VICTORY
## 註解），總計 2 個 case，不做大樣本。
##
## (b) DC-REQ-001~003 合力驗證：至少一個進入 Act2+ 的 case，在 Act2+ 出現真實傷害
##     訊號（該幕 battle_losses>0 或該幕結束 HP < 進入該幕時的 HP）。若全部 Act2+
##     快照都是零損傷，代表曲線在結構層生效但戰鬥層沒有梯度，判 FAIL。
## (c) DC-REQ-007 觀測性：不做 gate，只 read-back 確認 BalanceBotReport.to_json()
##     的 act1_reached/act2_reached/act3_reached 與逐案 act_snapshots 欄位完整，
##     供 3k 之後人工判讀幕間曲線趨勢。

const Support = preload(
	"res://tests/integration/balance_playtest/balance_driver_test_support.gd"
)
const PROBE_STRATEGIES: Array[StringName] = [
	BalanceBotStrategy.TEMPO, BalanceBotStrategy.SYNERGY,
]

var _content: ProjectContentBootstrapResult
var _registry: ContentRegistryService
var _cases: Array[BalanceBotCaseResult] = []


func before_all() -> void:
	_registry = ContentRegistryService.new()
	add_child(_registry)
	_content = ProjectContentBootstrap.new().run(_registry)
	if not _content.ok:
		return
	var recorder := Support.StorageRecorder.new()
	var driver := BalanceProductionCaseDriver.new(_content, recorder.factory())
	for strategy_id: StringName in PROBE_STRATEGIES:
		_cases.append(driver.run_case(strategy_id, Support.SEED_VICTORY))


func after_all() -> void:
	_cases.clear()
	if _registry != null:
		remove_child(_registry)
		_registry.free()
		_registry = null


func test_at_least_one_act2_plus_snapshot_shows_real_damage_from_curve() -> void:
	if not _assert_ready():
		return
	var act2_plus_snapshot_count := 0
	var damaged_snapshot_count := 0
	var evidence: Array[String] = []
	for value: BalanceBotCaseResult in _cases:
		assert_eq(
			value.failure_codes.size(), 0,
			"%s 不得帶 failure code：%s" % [String(value.strategy_id), str(value.failure_codes)]
		)
		var by_act: Dictionary = {}
		for snapshot: BalanceBotActSnapshot in value.act_snapshots:
			by_act[snapshot.act_index] = snapshot
		for act_index: int in [2, 3]:
			if not by_act.has(act_index):
				continue
			act2_plus_snapshot_count += 1
			var snapshot: BalanceBotActSnapshot = by_act[act_index]
			var entering_hp: int = by_act[act_index - 1].expedition_hp \
				if by_act.has(act_index - 1) else snapshot.expedition_hp
			var damaged := snapshot.battle_losses > 0 or snapshot.expedition_hp < entering_hp
			if damaged:
				damaged_snapshot_count += 1
			evidence.append(
				"%s act%d: losses=%d entering_hp=%d ending_hp=%d damaged=%s" % [
					String(value.strategy_id), act_index, snapshot.battle_losses,
					entering_hp, snapshot.expedition_hp, damaged,
				]
			)
	assert_gt(
		act2_plus_snapshot_count, 0,
		"seed 0 的 tempo／synergy 必須至少有一個 case 推進到 Act2 以上；否則找不到能驗證" \
		+ " 曲線戰鬥後果的組合（快篩樣本需重新挑選）"
	)
	assert_gt(
		damaged_snapshot_count, 0,
		"全部 Act2+ 快照都零損傷＝曲線在結構層生效但戰鬥層沒有梯度（訊號 FAIL）。證據：%s" % (
			"; ".join(evidence)
		)
	)


func test_report_exposes_per_act_reach_counts_and_act_snapshots_for_trend_reading() -> void:
	if not _assert_ready():
		return
	var candidate := BalanceCandidateDescriptor.new(
		&"", _content.content_version, _content.manifest_digest, 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, 1)
	for value: BalanceBotCaseResult in _cases:
		report.append(value)
	var parsed := JSON.parse_string(report.to_json(false)) as Dictionary
	assert_true(parsed != null, "report JSON 必須可解析")
	if parsed == null:
		return

	var strategy_rows := parsed["strategies"] as Array
	assert_gt(strategy_rows.size(), 0, "report 必須輸出至少一個策略列")
	for row_variant: Variant in strategy_rows:
		var row := row_variant as Dictionary
		assert_true(
			row.has("act1_reached") and row.has("act2_reached") and row.has("act3_reached"),
			"策略列必須含 act1_reached/act2_reached/act3_reached 供跨幕到達率判讀：%s" % (
				str(row)
			)
		)

	var case_proofs := parsed["case_proofs"] as Array
	assert_eq(
		case_proofs.size(), _cases.size(), "case_proofs 筆數必須等於送入的 case 數"
	)
	var any_act_snapshot_checked := false
	for proof_variant: Variant in case_proofs:
		var proof := proof_variant as Dictionary
		assert_true(proof.has("act_snapshots"), "每筆 case_proof 必須含 act_snapshots")
		for snapshot_variant: Variant in (proof["act_snapshots"] as Array):
			var snapshot := snapshot_variant as Dictionary
			for field: String in [
				"act_index", "gold", "expedition_hp", "battle_wins",
				"battle_losses", "elimination_node_id",
			]:
				assert_true(
					snapshot.has(field),
					"act_snapshots 逐幕紀錄必須含 %s 欄位（供人工判讀幕間趨勢）" % field
				)
			any_act_snapshot_checked = true
	assert_true(
		any_act_snapshot_checked,
		"至少要有一筆 act_snapshot 可供檢查，否則本測試沒有驗證到任何東西"
	)


func _assert_ready() -> bool:
	assert_true(
		_content != null and _content.ok,
		"正式內容 bootstrap 必須成功：%s" % (
			String(_content.error_code) if _content != null else "null"
		)
	)
	assert_eq(_cases.size(), PROBE_STRATEGIES.size(), "兩個 seed=0 case 都必須跑完")
	return _content != null and _content.ok and _cases.size() == PROBE_STRATEGIES.size()
