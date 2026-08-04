extends GutTest

## rewrite-plan.md §5.2（action apply）：bot 每一類 PREPARE 期 command 送出後，
## 對應的 canonical snapshot 必須真的改變（金幣扣款、roster 增減、商店供給更新），
## 不是像 BP-IR-003 那樣「決策一次、什麼都沒發生」。
## 驗證方式：在正式 driver 的 PREPARE 入口攔一次，拿到那一刻的真實
## RunPresentationSession，逐一 dispatch bot 的四類 command 並比對前後 snapshot。
##
## 涵蓋範圍說明（做不到的部分不假裝）：driver 的 bot 動作集只有
## refresh／buy_unit／buy_xp／sell_unit 四類（balance_production_case_driver.gd:368-381），
## 不含 forge／equip；而正式 content 的 reward table 只發 gold／heal／relic
## （content/packs/vertical_slice/reward_tables/），一整局 roster 的 item_instances 恆為 0，
## 因此 forge／equip 在 balance 鏈路上沒有可觸發的狀態。這兩個 command 的交易語意
## 由 tests/integration/build_items/ 既有整合測試覆蓋。

const Support = preload(
	"res://tests/integration/balance_playtest/balance_driver_test_support.gd"
)
const PrepareProbeDriver = preload(
	"res://tests/integration/balance_playtest/prepare_probe_driver.gd"
)

## 板凳容量與經濟等級上限沿用 driver 的 bot 觀測慣例
## （balance_production_case_driver.gd:406 的板凳滿位判定、:429 的等級上限）。
const BENCH_CAPACITY: int = 9
const MAX_ECONOMY_LEVEL: int = 9

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


func test_prepare_commands_change_canonical_snapshot() -> void:
	assert_true(_content != null and _content.ok, "正式內容 bootstrap 必須成功")
	if _content == null or not _content.ok:
		return
	var recorder := Support.StorageRecorder.new()
	var driver: PrepareProbeDriver = PrepareProbeDriver.new(_content, recorder.factory())
	driver.probe_ready = func(
		session: RunPresentationSession, _result: BalanceBotCaseResult
	) -> bool:
		return _probe_ready(session.snapshot())
	driver.probe = func(
		session: RunPresentationSession, _result: BalanceBotCaseResult
	) -> void:
		_exercise_prepare_commands(session)
	var value: BalanceBotCaseResult = driver.run_case(
		BalanceBotStrategy.TEMPO, Support.SEED_VICTORY
	)

	assert_true(
		driver.probe_fired,
		"整局內必須出現可送出四類 command 的 PREPARE 狀態（板凳有餘裕、等級未滿、金幣足夠）"
	)
	assert_true(
		value.failure_codes.has(PrepareProbeDriver.PROBE_STOP),
		"探針必須以哨兵碼中止該 case：%s" % str(value.failure_codes)
	)


## 上面「涵蓋範圍說明」的守門員：正式 reward table 一旦開始發零件／裝備，
## roster 就會出現 item，forge／equip 也就必須補進 bot 動作集與本檔的斷言。
## 這條測試在那一刻轉紅，避免說明文字默默過期。
func test_production_reward_tables_still_yield_no_items() -> void:
	assert_true(_content != null and _content.ok, "正式內容 bootstrap 必須成功")
	if _content == null or not _content.ok:
		return
	var item_tables: Array[String] = []
	for table: RewardTableRule in _content.economy_catalog.reward_tables():
		for candidate: RewardCandidateRule in table.candidates:
			if candidate.kind == &"item":
				item_tables.append(String(table.table_id))
	assert_eq(
		item_tables, [] as Array[String],
		"reward table 開始發物品時，forge／equip 必須補進 bot 動作集與 §5.2 測試"
	)


func _exercise_prepare_commands(session: RunPresentationSession) -> void:
	var config := _content.economy_catalog.config()

	# 1) refresh shop：扣 reroll 成本、推進 refresh index、供給整批換新。
	var before := session.snapshot()
	var refreshed := session.dispatch(
		RunPresentationIntent.new(RunPresentationIntent.Kind.REFRESH_SHOP)
	)
	assert_true(refreshed.ok, "refresh_shop 必須成功：%s" % Support.dispatch_error(refreshed))
	var after := session.snapshot()
	assert_eq(
		after.economy.gold, before.economy.gold - config.reroll_cost,
		"refresh 必須扣掉 reroll 成本"
	)
	assert_eq(
		after.economy.shop_refresh_index, before.economy.shop_refresh_index + 1,
		"refresh 必須推進 shop_refresh_index"
	)
	assert_ne(_offer_ids(after), _offer_ids(before), "refresh 後的商店供給必須換新")

	# 2) buy unit：扣 offer 成本，roster 真的長出單位（或合成升星）。
	before = session.snapshot()
	var offer := _affordable_offer(before)
	assert_not_null(offer, "PREPARE 期必須至少有一個買得起的供給")
	if offer == null:
		return
	var buy := RunPresentationIntent.new(RunPresentationIntent.Kind.BUY_UNIT)
	buy.offer_id = offer.offer_id
	var bought := session.dispatch(buy)
	assert_true(bought.ok, "buy_offer 必須成功：%s" % Support.dispatch_error(bought))
	after = session.snapshot()
	assert_eq(
		after.economy.gold, before.economy.gold - offer.cost, "買棋必須扣掉 offer 成本"
	)
	assert_gt(
		_roster_weight(after), _roster_weight(before),
		"買棋必須讓 roster 增加單位或提升星等"
	)
	assert_eq(
		_offer_ids(after).size(), _offer_ids(before).size() - 1,
		"買走的供給必須從商店移除"
	)

	# 3) buy xp：扣 xp 成本，等級或經驗值前進。
	before = session.snapshot()
	var bought_xp := session.dispatch(
		RunPresentationIntent.new(RunPresentationIntent.Kind.BUY_XP)
	)
	assert_true(bought_xp.ok, "buy_xp 必須成功：%s" % Support.dispatch_error(bought_xp))
	after = session.snapshot()
	assert_eq(
		after.economy.gold, before.economy.gold - config.xp_buy_cost,
		"買經驗必須扣掉 xp 成本"
	)
	assert_true(
		after.economy.level > before.economy.level or after.economy.xp > before.economy.xp,
		"買經驗必須推進等級或經驗值"
	)

	# 4) sell unit：roster 減一、金幣回收。
	before = session.snapshot()
	var sell_target := _sellable_unit_id(before)
	assert_ne(sell_target, "", "必須有可出售的單位")
	if sell_target.is_empty():
		return
	var sell := RunPresentationIntent.new(RunPresentationIntent.Kind.SELL_UNIT)
	sell.unit_instance_id = sell_target
	var sold := session.dispatch(sell)
	assert_true(sold.ok, "sell_unit 必須成功：%s" % Support.dispatch_error(sold))
	after = session.snapshot()
	assert_eq(
		after.roster.unit_instances.size(), before.roster.unit_instances.size() - 1,
		"出售必須讓 roster 少一隻"
	)
	assert_gt(after.economy.gold, before.economy.gold, "出售必須回收金幣")


## 探針落點條件：四類 command 全部要能合法送出——板凳未滿、等級未滿、
## 有可出售的單位、金幣足夠付 reroll＋買棋＋買經驗。
func _probe_ready(snapshot: RunPresentationSnapshot) -> bool:
	if snapshot.roster == null or snapshot.economy == null:
		return false
	if snapshot.roster.bench_unit_instance_ids.is_empty():
		return false
	if snapshot.roster.bench_unit_instance_ids.size() >= BENCH_CAPACITY:
		return false
	if snapshot.economy.level >= MAX_ECONOMY_LEVEL:
		return false
	var config := _content.economy_catalog.config()
	var offer := _affordable_offer(snapshot)
	if offer == null:
		return false
	return snapshot.economy.gold >= config.reroll_cost + config.xp_buy_cost + offer.cost


func _offer_ids(snapshot: RunPresentationSnapshot) -> Array[String]:
	var ids: Array[String] = []
	for offer: ShopOffer in snapshot.economy.shop_offers:
		ids.append(offer.offer_id)
	return ids


func _affordable_offer(snapshot: RunPresentationSnapshot) -> ShopOffer:
	for offer: ShopOffer in snapshot.economy.shop_offers:
		if offer.cost <= snapshot.economy.gold:
			return offer
	return null


## 單位數與星等的合併權重：買棋可能是新增一隻，也可能是三合一升星。
func _roster_weight(snapshot: RunPresentationSnapshot) -> int:
	var weight := 0
	for unit: UnitInstance in snapshot.roster.unit_instances:
		weight += unit.star
	return weight


func _sellable_unit_id(snapshot: RunPresentationSnapshot) -> String:
	if not snapshot.roster.bench_unit_instance_ids.is_empty():
		return snapshot.roster.bench_unit_instance_ids[0]
	if not snapshot.roster.unit_instances.is_empty():
		return snapshot.roster.unit_instances[0].instance_id
	return ""
