class_name RunScreen
extends Control

## S5 wave5 修正 A4 灰盒（specs/meta-progression/design.md §4.4）：RUN 狀態的開發用畫面。
## 比照 camp_screen／build_lab 慣例——只把 RunLabSession 的唯讀投影排版出來、把按鈕接到
## 它的操作方法，不自帶第二資料源、不自行改任何 run 狀態；正式 UI 歸 Codex（HANDOFF.md）。
##
## 一局的操作順序：生成地圖 → 進入可達節點 →（戰鬥節點：刷新/買棋 → 備戰 → 開戰 → 結算
## → 領獎；非戰鬥節點：解決節點）→ 回地圖…… 直到 run_phase == RESULTS，按「結算遠征」
## 交給 composition root 做 meta 結算（AppRoot.settle_active_run()）並換場到 Results。

@onready var summary_label: RichTextLabel = %SummaryLabel
@onready var status_label: Label = %StatusLabel
@onready var settle_run_button: Button = %SettleRunButton

var _root: ApplicationRoot
var _session: RunLabSession


func _ready() -> void:
	%GenerateMapButton.pressed.connect(func() -> void: _run("生成地圖", _session.generate_map))
	%EnterNodeButton.pressed.connect(
		func() -> void: _run("進入節點", _session.enter_first_reachable_node)
	)
	%RefreshShopButton.pressed.connect(func() -> void: _run("刷新商店", _session.refresh_shop))
	%BuyOfferButton.pressed.connect(func() -> void: _run("購買棋子", _session.buy_first_offer))
	%CommitBoardButton.pressed.connect(func() -> void: _run("提交備戰", _session.commit_board))
	%StartCombatButton.pressed.connect(func() -> void: _run("開戰", _session.start_combat))
	%SettleBattleButton.pressed.connect(func() -> void: _run("結算戰鬥", _session.settle_battle))
	%ResolveRewardButton.pressed.connect(func() -> void: _run("領取獎勵", _session.resolve_rewards))
	%ResolveNodeButton.pressed.connect(
		func() -> void: _run("解決非戰鬥節點", _session.resolve_non_combat_node)
	)
	%AbandonButton.pressed.connect(
		func() -> void: _run("放棄 Boss 重戰", _session.abandon_boss_retry)
	)
	settle_run_button.pressed.connect(_settle_run)
	_render()


## composition root 於換場後注入；session 為 null＝沒有 active run（不該發生，畫面會明說）。
func bind(root: ApplicationRoot, session: RunLabSession) -> void:
	_root = root
	_session = session
	_render()


func _run(label: String, action: Callable) -> void:
	if _session == null:
		status_label.text = "尚未接上 active run"
		return
	var error: StringName = action.call()
	status_label.text = (
		"%s：完成" % label if error.is_empty() else "%s 失敗：%s" % [label, String(error)]
	)
	_render()


func _settle_run() -> void:
	if _root == null:
		return
	var result := _root.settle_active_run()
	if not result.ok:
		status_label.text = "結算遠征失敗：%s" % String(
			result.error.source_code
		)
		_render()


func _render() -> void:
	if summary_label == null:
		return
	summary_label.clear()
	if _session == null or not _session.is_concrete():
		summary_label.append_text("（尚未接上 active run）")
		settle_run_button.disabled = true
		return
	var state := _session.view()
	settle_run_button.disabled = state.run_phase != RunState.RunPhase.RESULTS
	var lines: Array[String] = [
		"run_id：%s" % state.run_id,
		"階段：%s｜幕 %d｜挑戰詞綴已隨 run 凍結" % [_phase_text(state.run_phase), state.act_index],
		"遠征 HP：%d｜金幣：%d｜等級 %d（xp %d）" % [
			state.expedition_hp, state.economy.gold, state.economy.level, state.economy.xp
		],
		"目前節點：%s" % _current_node_text(),
		"可進入節點：%s" % _reachable_text(),
		"商店報價：%s" % _offer_text(),
	]
	summary_label.append_text("\n".join(lines))


func _phase_text(phase: RunState.RunPhase) -> String:
	match phase:
		RunState.RunPhase.MAP:
			return "地圖"
		RunState.RunPhase.PREPARE:
			return "備戰"
		RunState.RunPhase.COMBAT:
			return "戰鬥"
		RunState.RunPhase.REWARD:
			return "獎勵"
		RunState.RunPhase.RESULTS:
			return "終局（可結算）"
	return "未知"


func _current_node_text() -> String:
	var node := _session.current_node()
	if node == null:
		return "（無）"
	return "%s｜幕 %d 層 %d｜%s" % [
		node.node_id.substr(0, 8), node.act_index, node.layer_index,
		String(MapNodeState.node_kind_to_token(node.node_kind)),
	]


func _reachable_text() -> String:
	var reachable := _session.reachable_node_ids()
	if reachable.is_empty():
		return "（無）"
	var values: Array[String] = []
	for node_id: String in reachable:
		var node := _session.try_node(node_id)
		values.append("%s(%s)" % [
			node_id.substr(0, 8),
			String(MapNodeState.node_kind_to_token(node.node_kind)) if node != null else "?",
		])
	return ", ".join(values)


func _offer_text() -> String:
	var offers := _session.economy().shop_offers
	if offers.is_empty():
		return "（無）"
	var values: Array[String] = []
	for offer: ShopOffer in offers:
		values.append("%s(%d 金)" % [String(offer.unit_def_id), offer.cost])
	return ", ".join(values)
