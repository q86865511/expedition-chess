extends BalanceProductionCaseDriver

## 測試用 seam：在正式 driver 的 PREPARE 迴圈入口（`_prepare`）攔截，
## 把「當下這個真實 session」交給測試。兩個互相獨立的用途：
##
## 1. `probe_ready`／`probe`：攔一次，讓整合測試對正式鏈路下 command 並驗證
##    snapshot 變化，或走 abandon 這條 driver 本身不會採取的正式路徑；
##    探針跑完即以哨兵碼中止該 case，不必付整局遠征的成本。
## 2. `force_empty_board_at_boss`：進 Boss 節點時改送「全員上板凳、棋盤淨空」的
##    合法 board layout，讓 Boss 戰必敗。這是構造 §5.3 Boss retry 情境的
##    **確定性**手段——不依賴任何 seed 的勝負結果（實測同一 seed 的勝負會隨
##    process 內先跑過哪些測試而變，見 artifacts/test/balance-phase0-mutation-evidence.md）。
##
## driver 本體不需要為測試留任何鉤子。

const PROBE_STOP: StringName = &"BALANCE_TEST_PREPARE_PROBE_STOP"

## func(session: RunPresentationSession, result: BalanceBotCaseResult) -> bool
var probe_ready: Callable
## func(session: RunPresentationSession, result: BalanceBotCaseResult) -> void
var probe: Callable
var probe_fired: bool = false
var force_empty_board_at_boss: bool = false
var forced_boss_battles: int = 0


func _prepare(
	session: RunPresentationSession,
	strategy: BalanceBotStrategy,
	result: BalanceBotCaseResult,
	replay_parts: Array[String]
) -> StringName:
	if not probe_fired and probe_ready.is_valid() \
		and bool(probe_ready.call(session, result)):
		probe_fired = true
		if probe.is_valid():
			probe.call(session, result)
		return PROBE_STOP
	if force_empty_board_at_boss and _at_boss(session):
		forced_boss_battles += 1
		return _commit_bench_only(session)
	return super(session, strategy, result, replay_parts)


func _at_boss(session: RunPresentationSession) -> bool:
	var current := session.view_state().current_node_id
	if current == null or current.value.is_empty():
		return false
	for node: MapNodeState in session.snapshot().map.nodes:
		if node.node_id == current.value:
			return node.node_kind == MapNodeState.NodeKind.BOSS
	return false


## 棋盤淨空、全員上板凳。板凳容量是 9 且每隻棋子都必須被指派
## （BoardPreparationValidator.BENCH_CAPACITY／UNIT_UNASSIGNED），
## 所以先用正式 sell command 把 roster 壓到容量內。
func _commit_bench_only(session: RunPresentationSession) -> StringName:
	while session.snapshot().roster.unit_instances.size() \
		> BoardPreparationValidator.BENCH_CAPACITY:
		var sell := RunPresentationIntent.new(RunPresentationIntent.Kind.SELL_UNIT)
		sell.unit_instance_id = session.snapshot().roster.unit_instances[0].instance_id
		var sold := session.dispatch(sell)
		if not sold.ok:
			return sold.error.source_code
	var bench: Array[String] = []
	for unit: UnitInstance in session.snapshot().roster.unit_instances:
		bench.append(unit.instance_id)
	bench.sort()
	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT)
	intent.board = BoardState.new([] as Array[BoardPlacementState])
	intent.bench_unit_instance_ids.assign(bench)
	var dispatched := session.dispatch(intent)
	return &"" if dispatched.ok else dispatched.error.source_code
