extends GutTest

## T01(specs/meta-progression) — meta_reward_tables/slice_default.tres 對齊 §7.3／S5-AC-006。
## Covers：REQ-META-004、S5-AC-006（資料對齊段）；tasks.md T01 驗收：
##   「`meta_reward_tables/slice_default.tres` 對齊 §7.3（elite 2→3、
##   merchant/event/treasure 1→0、failure 2→0；normal1/boss5/completion10/
##   bps 10000..15000 不變）」。
## 對應 design.md §9:184「slice_default.tres 對齊 §7.3／S5-AC-006（TUNE）：elite 2→3、
## merchant/event/treasure 1→0、failure_reward 2→0；completion 10、boss 5、normal 1、
## bps 10000..15000 不變」。
##
## 本檔只驗證磁碟上這份 .tres 的資料內容（載入方式比照既有
## tests/unit/content_validation/test_vertical_slice_content_pack.gd 直接 load() 單一
## Resource 的慣例），不驗證 MetaRewardComputeService 的計算行為——那部分見同目錄
## test_meta_reward_compute_service.gd。

const SLICE_DEFAULT_PATH := "res://content/packs/vertical_slice/meta_reward_tables/slice_default.tres"

func test_slice_default_meta_reward_table_matches_section_7_3_alignment() -> void:
	var resource: Resource = load(SLICE_DEFAULT_PATH)
	assert_true(resource is MetaRewardTableDef, "slice_default.tres 應為 MetaRewardTableDef")
	if not resource is MetaRewardTableDef:
		return
	var table := resource as MetaRewardTableDef

	var scores := _scores_by_key(table)
	assert_eq(int(scores.get(&"normal", -1)), 1, "normal 應維持 1")
	assert_eq(int(scores.get(&"elite", -1)), 3, "elite 應由 2 對齊為 3")
	assert_eq(int(scores.get(&"merchant", -1)), 0, "merchant 應由 1 對齊為 0")
	assert_eq(int(scores.get(&"event", -1)), 0, "event 應由 1 對齊為 0")
	assert_eq(int(scores.get(&"rest", -1)), 0, "rest 應維持 0")
	assert_eq(int(scores.get(&"treasure", -1)), 0, "treasure 應由 1 對齊為 0")
	assert_eq(int(scores.get(&"boss", -1)), 5, "boss 應維持 5")

	assert_eq(table.completion_reward, 10, "completion_reward 應維持 10")
	assert_eq(table.failure_reward, 0, "failure_reward 應由 2 對齊為 0")

	var bps := _bps_by_level(table)
	assert_eq(bps.size(), 6, "challenge_multiplier_bps 應涵蓋 level 0..5 共 6 筆，不變")
	var expected_bps := {0: 10000, 1: 11000, 2: 12000, 3: 13000, 4: 14000, 5: 15000}
	for level: int in expected_bps.keys():
		assert_eq(
			int(bps.get(level, -1)), int(expected_bps[level]),
			"challenge_level %d 的 basis_points 應維持 %d 不變" % [level, expected_bps[level]]
		)

func _scores_by_key(table: MetaRewardTableDef) -> Dictionary:
	var result: Dictionary = {}
	for pair: EnumIntPairDef in table.node_scores:
		result[pair.enum_key] = pair.value_i32
	return result

func _bps_by_level(table: MetaRewardTableDef) -> Dictionary:
	var result: Dictionary = {}
	for entry: ChallengeMultiplierDef in table.challenge_multiplier_bps:
		result[entry.challenge_level] = entry.basis_points
	return result
