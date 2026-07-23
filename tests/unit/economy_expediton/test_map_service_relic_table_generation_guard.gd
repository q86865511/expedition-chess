extends GutTest

## T12（specs/build-systems）— W3-F7 補充規則：MapService 收到 relic_table 時，須比對其
## manifest digest 與呼叫端 catalog 的 manifest digest；不符須具名拒絕，比照 forge/equip
## 慣例（forge_equipment_command.gd:44-48）。與 income/shop/battle_settlement 三個 service
## 的對應案例拆開存放於獨立檔（test_relic_table_generation_guard.gd）——理由見本檔假設聲明。
## Covers：REQ-RELIC-001（W3-F7，tasks.md T12 補充：wave2 雙審延後項，使用者裁決 2026-07-23）。
##
## 假設聲明（本檔新增，非既有慣例）：
## MapService.generate_map() 只收 catalog（不直接持有 content_snapshot），比對基準取
## relic_table.manifest_digest_value() 對 catalog.manifest_digest_value()（catalog 本身與
## content_snapshot 的一致性已由呼叫端 RunCommand 在更早一步驗證，如
## generate_expedition_map_command.gd:21-23，故 catalog 可視為 content_snapshot 的可信代理，
## 比照 income/shop 兩個 service 的斷言基準）。MapGenerationError 目前只有
## INPUT_INVALID/RNG_FAILED/RULE_MISSING/KEY_FAILED/DIGEST_FAILED 五個常數，沒有任何
## GENERATION_MISMATCH 一類的錯誤碼——本檔假設實作段會新增
## `MapGenerationError.GENERATION_MISMATCH`（比照 ShopError/ExpeditionActionError 的命名慣例）。
## 此常數今日不存在，故本檔在 GDScript 載入/編譯階段就會 Parse Error（腳本整檔無法載入），
## 屬本任務簡報允許的紅證據型態之一（import/模組不存在類），與斷言失敗型的紅分開存放
## 才不會互相蓋掉彼此的失敗訊息。

const _OTHER_DIGEST: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

func test_map_service_rejects_a_relic_table_whose_manifest_digest_does_not_match_the_catalog() -> void:
	var catalog := EconomyTestFixture.catalog()
	var table := RunRelicTable.new(_OTHER_DIGEST, [_route_rule(&"relic.route_a")])
	var seed := U64Bits.from_hex("0123456789abcdef").value
	var result := MapService.new().generate_map(MapGenerationRequest.new(
		&"run_fixture", seed, catalog, table, [&"relic.route_a"]
	))
	assert_false(result.ok, "a relic_table pinned to a stale manifest digest must never be allowed to author map generation")
	if result.ok:
		return
	assert_eq(result.error.code, MapGenerationError.GENERATION_MISMATCH)

func _route_rule(relic_id: StringName) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = 0
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"route"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule
