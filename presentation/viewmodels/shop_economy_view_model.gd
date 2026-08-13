class_name ShopEconomyViewModel
extends RefCounted

## IRH-REQ-011／IRH-REQ-014（specs/in-run-hud）-- 商店與經濟資訊列的唯讀報價 ViewModel。
##
## 存在理由：經濟資訊列要顯示「刷新／買經驗／出售各要多少、能不能按、不能按的具名原因」，
## 而這些數字全部是 domain 規則（reroll 挑戰加價、xp 升級折算、星級售價、gold_cap 夾擠）。
## spec §10.3 禁止呈現層複製這些公式，因此本 ViewModel 一律呼叫 ShopService.quote_*，
## 只做兩件事：把 quote 前後的 economy_state 差額轉成面板欄位、把 ShopError 具名碼原樣轉呈。
##
## 讀取紀律（HANDOFF §2 第 1、7 條）：
## - 每次查詢都重新向 RunSession 取 run_snapshot()（deep clone），不快取 domain 物件；
##   RunSession 的公開讀取面（run_snapshot／profile_snapshot／view_state）全是 deep clone。
## - catalog／relic_table 在建構時各留一份私有 clone；catalog 世代更換時請重建本物件。
## - 全程唯讀：quote_* 只回傳 transaction 候選，本 ViewModel 從不 dispatch、不寫 RunState。
##
## 價格怎麼來（零公式）：以「把金幣暫時抬到 gold_cap 的 economy clone」再報一次價，
## 用兩次 quote 的 gold 差額得到實際價格——因為金幣只影響 quote 的 affordability 檢查，
## 不影響定價路徑。因此金幣不足時仍能顯示正確價格，且挑戰加價自動包含在內。
## 可行性與具名原因則一律取自「用真實金幣」那一次的 quote。
##
## 範圍界線：本 ViewModel 回報的是 ShopService quote 層的可行性與 catalog 世代一致性。
## 命令層的 run_phase 前置條件（RefreshShopCommand／BuyXpCommand 限 PREPARE、
## SellUnitCommand 限 PREPARE／REWARD 的解算子階段）由畫面出現時機保證，不在此重複實作。

const ACTION_REFRESH: StringName = &"shop_refresh"
const ACTION_SELL: StringName = &"shop_sell"

var _session: RunSession
var _catalog: EconomyExpeditionCatalog
var _relic_table: RunRelicTable
var _service: ShopService


## relic_table 必須是本 run 由 RunCommandFactory 注入的同一份（S5-AC-014）：
## 少了它，reroll 的挑戰加價會在報價中靜默消失，面板價格與實際扣款不一致。
func _init(
	session: RunSession,
	catalog: EconomyExpeditionCatalog,
	relic_table: RunRelicTable = null,
	service: ShopService = null
) -> void:
	_session = session
	_catalog = catalog.deep_clone() if catalog != null else null
	_relic_table = relic_table.deep_clone() if relic_table != null else null
	_service = service if service != null else ShopService.new()


## 經濟資訊列（金幣／等級經驗／連勝連敗／目前等級的費用機率）。
## 無 run 或無 catalog 時回傳全零快照（欄位語意即「沒有可顯示的經濟狀態」）。
func economy_status() -> ShopEconomySnapshot:
	var snapshot := ShopEconomySnapshot.new()
	var run := _try_run()
	if run == null or _catalog == null:
		return snapshot
	var economy := run.economy_state
	var config := _catalog.config()
	snapshot.gold = economy.gold
	snapshot.gold_cap = config.gold_cap
	snapshot.level = economy.level
	snapshot.xp = economy.xp
	snapshot.win_streak = economy.win_streak
	snapshot.loss_streak = economy.loss_streak
	snapshot.shop_refresh_index = economy.shop_refresh_index
	snapshot.xp_required_for_next_level = config.value_for(
		config.xp_thresholds, economy.level, -1
	)
	snapshot.at_max_level = snapshot.xp_required_for_next_level < 0
	var odds := config.try_odds_for_level(economy.level)
	if odds != null:
		snapshot.odds_level = odds.level
		snapshot.odds_tier_basis_points = odds.tier_basis_points.duplicate()
	return snapshot


## 刷新商店的報價：實際扣款金額、金幣是否足夠、不可用時的 domain 具名原因。
func refresh_quote() -> ShopQuoteSnapshot:
	var snapshot := ShopQuoteSnapshot.new()
	snapshot.action = ACTION_REFRESH
	var run := _try_run()
	var guard := _generation_guard(run)
	if not guard.is_empty():
		snapshot.rejection_code = guard
		return snapshot
	snapshot.gold_before = run.economy_state.gold
	var actual := _service.quote_refresh(_refresh_request(run, run.economy_state))
	snapshot.available = actual.ok
	snapshot.rejection_code = &"" if actual.ok else actual.error.code
	var probe_economy := _probe_economy(run)
	var probe := _service.quote_refresh(_refresh_request(run, probe_economy))
	if probe.ok:
		snapshot.quotable = true
		snapshot.gold_cost = probe_economy.gold - probe.transaction.economy_state.gold
		snapshot.affordable = snapshot.gold_before >= snapshot.gold_cost
	return snapshot


## 購買經驗的報價：花費、獲得經驗、折算後等級／經驗，以及 MAX 狀態。
func buy_xp_quote() -> ShopXpQuoteSnapshot:
	var snapshot := ShopXpQuoteSnapshot.new()
	var run := _try_run()
	var guard := _generation_guard(run)
	if not guard.is_empty():
		snapshot.rejection_code = guard
		return snapshot
	var economy := run.economy_state
	snapshot.gold_before = economy.gold
	snapshot.level_before = economy.level
	snapshot.xp_before = economy.xp
	snapshot.level_after = economy.level
	snapshot.xp_after = economy.xp
	snapshot.xp_gain = _catalog.config().xp_buy_amount
	var actual := _service.quote_buy_xp(_buy_xp_request(run, economy))
	snapshot.available = actual.ok
	snapshot.rejection_code = &"" if actual.ok else actual.error.code
	snapshot.at_max_level = not actual.ok and actual.error.code == ShopError.LEVEL_MAX
	if snapshot.at_max_level:
		return snapshot
	var probe_economy := _probe_economy(run)
	var probe := _service.quote_buy_xp(_buy_xp_request(run, probe_economy))
	if probe.ok:
		snapshot.quotable = true
		snapshot.gold_cost = probe_economy.gold - probe.transaction.economy_state.gold
		snapshot.affordable = snapshot.gold_before >= snapshot.gold_cost
		snapshot.level_after = probe.transaction.economy_state.level
		snapshot.xp_after = probe.transaction.economy_state.xp
	return snapshot


## 指定單位的出售報價：實際入袋金幣（含 gold_cap 夾擠）。未知 instance id 不回 null，
## 而是回傳 available=false ＋ domain 的 SHOP_UNIT_MISSING，讓面板有具名原因可顯示。
func sell_quote(unit_instance_id: String) -> ShopQuoteSnapshot:
	var snapshot := ShopQuoteSnapshot.new()
	snapshot.action = ACTION_SELL
	var run := _try_run()
	var guard := _generation_guard(run)
	if not guard.is_empty():
		snapshot.rejection_code = guard
		return snapshot
	snapshot.gold_before = run.economy_state.gold
	if unit_instance_id.is_empty():
		snapshot.rejection_code = ShopError.INPUT_INVALID
		return snapshot
	var quote := _service.quote_sell(_sell_request(run, unit_instance_id))
	snapshot.available = quote.ok
	snapshot.rejection_code = &"" if quote.ok else quote.error.code
	if quote.ok:
		snapshot.quotable = true
		# 出售不花錢；gold_cap 夾擠已包含在 domain 算出的 gold 裡（shop_service.gd）。
		snapshot.affordable = true
		snapshot.gold_gain = quote.transaction.economy_state.gold - snapshot.gold_before
	return snapshot


# ---------------------------------------------------------------------------
# request 組裝：欄位來源與 RefreshShopCommand／BuyXpCommand／SellUnitCommand 相同，
# 差別只在讀的是 RunSession 的 clone 而非交易 draft。
# ---------------------------------------------------------------------------

func _refresh_request(run: RunState, economy: EconomyState) -> RefreshShopRequest:
	return RefreshShopRequest.new(
		StringName(run.run_id),
		EconomyCommandSupport.current_node_id(run),
		economy,
		run.unit_pool_state,
		run.roster_state,
		run.reservation_owners,
		EconomyCommandSupport.try_shop_rng(run),
		run.next_transaction_serial,
		run.next_unit_serial,
		_catalog,
		_relic_table,
		RunRelicActivation.active_ids_in_slot_order(run.roster_state.active_relic_slots)
	)


func _buy_xp_request(run: RunState, economy: EconomyState) -> BuyXpRequest:
	return BuyXpRequest.new(
		StringName(run.run_id),
		EconomyCommandSupport.current_node_id(run),
		economy,
		run.unit_pool_state,
		run.roster_state,
		run.reservation_owners,
		EconomyCommandSupport.try_shop_rng(run),
		run.next_transaction_serial,
		run.next_unit_serial,
		_catalog
	)


func _sell_request(run: RunState, unit_instance_id: String) -> SellUnitRequest:
	return SellUnitRequest.new(
		StringName(run.run_id),
		EconomyCommandSupport.current_node_id(run),
		unit_instance_id,
		run.economy_state,
		run.unit_pool_state,
		run.roster_state,
		run.reservation_owners,
		EconomyCommandSupport.try_shop_rng(run),
		run.next_transaction_serial,
		run.next_unit_serial,
		_catalog
	)


## 定價探針：金幣抬到 gold_cap（不低於目前金幣）的 economy clone。金幣只參與 quote 的
## affordability 檢查，不參與定價，所以差額即實際價格。
func _probe_economy(run: RunState) -> EconomyState:
	var economy := run.economy_state.deep_clone()
	economy.gold = maxi(economy.gold, _catalog.config().gold_cap)
	return economy


## 無 run／無 catalog／catalog 世代與 run 的 content_snapshot 不符時的具名拒絕碼；
## 可報價時回空字串名。世代守衛與四個 shop 命令的 _preflight 同一判準
## （refresh_shop_command.gd），避免面板顯示「可按」但命令一定被拒。
func _generation_guard(run: RunState) -> StringName:
	if run == null or _catalog == null:
		return ShopError.INPUT_INVALID
	if run.content_snapshot == null \
		or _catalog.manifest_digest_value() != run.content_snapshot.manifest_digest_value():
		return ShopError.GENERATION_MISMATCH
	return &""


func _try_run() -> RunState:
	return _session.run_snapshot() if _session != null else null
