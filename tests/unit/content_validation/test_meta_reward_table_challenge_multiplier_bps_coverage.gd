extends GutTest

## T10 (specs/meta-progression) — MetaRewardTableDef.challenge_multiplier_bps 覆蓋規則
## （design.md §7.2「挑戰乘數表：MetaRewardTableDef.challenge_multiplier_bps 覆蓋 level
## 0..5、basis_points ≥ 10000」；tasks.md T10 驗收欄「challenge_multiplier_bps 覆蓋 0..5
## 且 ≥10000」）：新增 ContentValidator 規則，要求 challenge_multiplier_bps 恰好覆蓋 level
## 0..5（不重複、不缺漏）且每筆 basis_points >= 10000（design.md §9「乘數單一權威＝表內 bps
## 欄」、§7.3「Challenge 1–5 最後乘以 100%+10%×challenge_level」——100% 即 10000 bps 是
## 下限，沒有折扣乘數的合理理由）。
##
## ============================== 假設聲明 ==============================
## 1. 新 issue code：CONTENT_CHALLENGE_MULTIPLIER_COVERAGE（本檔發明，design/tasks 未指定
##    字面 code；比照既有 CONTENT_CHALLENGE_CHAIN／CONTENT_MINIMUM_COUNTS 等「覆蓋範圍」類
##    issue 的命名慣例）。source_id 本檔統一使用該 MetaRewardTableDef 的 id、field_path 用
##    &"challenge_multiplier_bps"——實作代理若採不同但語意等價的具名方式，非測試爭議。
## 2. 觸發條件（兩種違規各自獨立可測，任一成立即應回報）：
##    a. 缺漏或重複：{entry.challenge_level for entry in challenge_multiplier_bps} 這個
##       集合不等於 {0,1,2,3,4,5}（即缺少某個 level，或有 level 落在範圍外，或有重複 level
##       佔用了名額導致某個必要 level 缺席）。
##    b. 任一 entry.basis_points < 10000。
##    只要有一個 MetaRewardTableDef 觸發任一子條件即回一筆聚合 issue（比照
##    CONTENT_ECONOMY_CONFIG_INCOMPLETE 的聚合風格，不必每個違規細節各自一筆）。
## 3. 本檔完全自建最小 ContentValidationInput（只含一個 MetaRewardTableDef），不依賴
##    SyntheticContentFixture——已逐一核對 ContentValidator.validate() 的其餘各條
##    _validate_* 規則在缺少 units/relics/traits/...等分類時只會各自新增自己的「數量不足」
##    類 issue，不會因為欄位缺失而 crash（皆為 for 迴圈掃描空陣列、以及對 configs.size()!=1
##    等計數的 early return，見 content_validator.gd:656-658 的 _validate_combat_config、
##    :515-517 的 _validate_unlock_graph 等處），故本檔只斷言
##    CONTENT_CHALLENGE_MULTIPLIER_COVERAGE 存在與否，不要求 report.valid 整體為 true。
## ========================================================================

func test_missing_challenge_level_is_rejected() -> void:
	var input := _input_with_bps(_full_valid_bps_map({5: true}))

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_CHALLENGE_MULTIPLIER_COVERAGE"),
		"缺少 challenge_level=5 的 bps 表必須被拒絕: %s" % _issue_text(report)
	)


func test_basis_points_below_10000_is_rejected() -> void:
	var bps_map := _full_valid_bps_map({})
	bps_map[3] = 9999
	var input := _input_with_bps(bps_map)

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_CHALLENGE_MULTIPLIER_COVERAGE"),
		"basis_points<10000 必須被拒絕: %s" % _issue_text(report)
	)


func test_full_zero_to_five_coverage_with_minimum_10000_is_accepted() -> void:
	var input := _input_with_bps(_full_valid_bps_map({}))

	var report := ContentValidator.new().validate(input)

	assert_false(
		_has_issue(report, &"CONTENT_CHALLENGE_MULTIPLIER_COVERAGE"),
		"level 0..5 全覆蓋且 bps 皆 >=10000 不應被拒絕（正對照組）: %s" % _issue_text(report)
	)


## 回傳 {level: basis_points}，預設對齊 slice_default.tres 的形狀（10000+1000*level）；
## `skip_levels`（Dictionary，key=level, value=true 表示跳過）供刻意製造缺漏的測試使用。
func _full_valid_bps_map(skip_levels: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for level in range(0, 6):
		if bool(skip_levels.get(level, false)):
			continue
		result[level] = 10000 + level * 1000
	return result


func _input_with_bps(bps_by_level: Dictionary) -> ContentValidationInput:
	var table := MetaRewardTableDef.new()
	table.id = &"meta_reward.test_table"
	table.display_name_key = &"loc.meta_reward_test_table"
	table.completion_reward = 10
	table.failure_reward = 0
	var score := EnumIntPairDef.new()
	score.enum_key = &"normal"
	score.value_i32 = 1
	table.node_scores = [score]
	for level in bps_by_level.keys():
		var multiplier := ChallengeMultiplierDef.new()
		multiplier.challenge_level = int(level)
		multiplier.basis_points = int(bps_by_level[level])
		table.challenge_multiplier_bps.append(multiplier)
	var definitions: Array[ContentDefinition] = [table]
	return ContentValidationInput.new(definitions, [], [], FakeContentDependencyPort.new(), 9)


func _has_issue(report: ContentValidationReport, code: StringName) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code:
			return true
	return false


func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
