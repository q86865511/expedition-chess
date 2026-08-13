class_name BoardDraftPreviewViewModel
extends RefCounted

## IRH-REQ-008（specs/in-run-hud）-- 拖曳期間的草稿佈局預覽 ViewModel。
##
## 存在理由：拖曳一顆棋子時，玩家要在放手前看到「人口會不會超、羈絆會怎麼變、這樣擺合不合法」。
## 這三件事的權威分別是 BoardPreparationValidator（人口與合法性，經 RunCommandFactory
## 注入本 run 的指揮官人口來源）與 BattleSetupSourceCompiler（羈絆進度）。
## 本 ViewModel 只把草稿套進 roster 的 clone 上再問這兩個權威，零公式複製（spec §10.3）。
##
## 全程唯讀：輸入的 placements／bench 清單一律 clone 進來，輸出一律是新建 snapshot，
## 不碰 canonical RunState、不 dispatch 任何 command——真正的提交走
## RunCommandFactory.commit_board_layout_command()。
##
## 草稿是**完整指派**：placements ＋ bench 必須涵蓋 roster 的全部單位，缺漏會由 validator
## 以 BOARD_UNIT_UNASSIGNED 如實回報（這正是拖曳中途狀態該被擋下的訊號），本 ViewModel
## 不替呼叫端補位。

var _controller: RunController
var _factory: RunCommandFactory
var _catalog: BattleRuleCatalog
var _compiler: BattleSetupSourceCompiler


func _init(
	controller: RunController,
	factory: RunCommandFactory,
	catalog: BattleRuleCatalog,
	compiler: BattleSetupSourceCompiler = null
) -> void:
	_controller = controller
	_factory = factory
	_catalog = catalog.deep_clone() if catalog != null else null
	_compiler = compiler if compiler != null else BattleSetupSourceCompiler.new()


## 假想佈局的預覽。placements／bench 為草稿內容（不必已提交），其餘單位資料沿用目前
## 已提交 roster 的 clone。
func preview(
	draft_placements: Array[BoardPlacementState],
	draft_bench_unit_instance_ids: Array[String]
) -> BoardDraftPreviewSnapshot:
	var snapshot := BoardDraftPreviewSnapshot.new()
	var draft := _draft_roster(draft_placements, draft_bench_unit_instance_ids)
	if draft == null:
		snapshot.issues.append(
			BoardValidationIssue.new(BoardValidationIssue.REQUEST_INVALID)
		)
		return snapshot
	var report := _factory.board_validation_report(draft, _economy_level())
	snapshot.used_population = draft.board.placements.size()
	snapshot.derived_capacity = report.derived_capacity
	snapshot.valid = report.valid
	for issue: BoardValidationIssue in report.issues:
		snapshot.issues.append(issue.deep_clone() if issue != null else null)
	snapshot.trait_progress = _compiler.compile_trait_progress(draft, _catalog)
	return snapshot


## 目前已提交佈局的同一組數字——拖曳前後對比（「人口 5/6 → 6/6」）的基準列。
func committed_preview() -> BoardDraftPreviewSnapshot:
	var roster := _committed_roster()
	if roster == null:
		var snapshot := BoardDraftPreviewSnapshot.new()
		snapshot.issues.append(
			BoardValidationIssue.new(BoardValidationIssue.REQUEST_INVALID)
		)
		return snapshot
	return preview(roster.board.placements, roster.bench_unit_instance_ids)


func _draft_roster(
	draft_placements: Array[BoardPlacementState],
	draft_bench_unit_instance_ids: Array[String]
) -> RosterState:
	var roster := _committed_roster()
	if roster == null or _factory == null:
		return null
	var placements: Array[BoardPlacementState] = []
	for placement: BoardPlacementState in draft_placements:
		if placement != null:
			placements.append(placement.deep_clone())
	roster.board = BoardState.new(placements)
	roster.bench_unit_instance_ids = draft_bench_unit_instance_ids.duplicate()
	return roster


## RunController.roster_snapshot() 已是 deep clone，直接當草稿底稿改寫。
func _committed_roster() -> RosterState:
	return _controller.roster_snapshot() if _controller != null else null


func _economy_level() -> int:
	if _controller == null:
		return 0
	var economy := _controller.economy_snapshot()
	return economy.level if economy != null else 0
