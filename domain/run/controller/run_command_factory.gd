class_name RunCommandFactory
extends RefCounted

## T11 (specs/meta-progression/design.md §3、§4.4；requirements.md S5-AC-014)：
## GenerateExpeditionMapCommand／RefreshShopCommand／SettleBattleResultCommand／
## EnterNodeEvent 的唯一建構點，一律注入本 run 的**非 null** RunRelicTable
## （§6.1 含指揮官被動與 challenge 規則）。
##
## 為什麼需要這個型別：四個命令的 relic_table 參數各自帶預設 null（見
## refresh_shop_command.gd:8-12 等），忘傳不會報錯、只會讓 always-active 貢獻靜默消失
## （HANDOFF §3 的「S5 接手檢查項」）。relic_table 在此為**必要參數、無預設值**——
## 這是「一律注入非 null relic_table」在型別層面能給的最強保證。
##
## battle_catalog 只有 enter_node_event()／commit_board_layout_command() 需要，故給
## 預設 null，避免另外三個建構方法為不相關欄位被迫傳值。
##
## 世代一致性（tasks.md T11 末句）：本 factory 只是原樣轉呈建構子收到的 catalog／
## relic_table／battle_catalog，不自行重指世代——四個命令因此必然共用呼叫端（composition
## root）挑定的那一個 content_snapshot.manifest_digest。

var _catalog: EconomyExpeditionCatalog
var _relic_table: RunRelicTable
var _battle_catalog: BattleRuleCatalog
var _challenge_affix_effect_ids: Array[StringName] = []
## 缺口 2（commit_board_layout_command.gd:71-76）：RunState 不持久化 population source
## 台帳，故由建構命令的人依 (run.commander_id, pinned CommanderDef.population_bonus)
## 決定性重建。兩者皆為可選——只建構前四個命令的呼叫端不必知道指揮官人口加成。
var _commander_id: StringName
var _commander_population_bonus: int

func _init(
	p_catalog: EconomyExpeditionCatalog,
	p_relic_table: RunRelicTable,
	p_battle_catalog: BattleRuleCatalog = null,
	p_challenge_affix_effect_ids: Array[StringName] = [],
	p_commander_id: StringName = &"",
	p_commander_population_bonus: int = 0
) -> void:
	# clone in：factory 存活整個 run，不能保留呼叫端可變物件的引用（同 RunController
	# 對 battle_catalog 的既有慣例，run_controller.gd:31）。四個命令建構子自己還會再
	# clone 一次，故命令之間也不共用同一份物件圖。
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null
	_challenge_affix_effect_ids = p_challenge_affix_effect_ids.duplicate()
	_commander_id = p_commander_id
	_commander_population_bonus = p_commander_population_bonus

## 建構出來的命令是否具備完整的注入依賴（catalog 與 relic_table 皆非 null）。
func is_concrete() -> bool:
	return _catalog != null and _relic_table != null

func generate_expedition_map_command() -> GenerateExpeditionMapCommand:
	return GenerateExpeditionMapCommand.new(_catalog, null, _relic_table)

func refresh_shop_command() -> RefreshShopCommand:
	return RefreshShopCommand.new(_catalog, null, _relic_table)

func settle_battle_result_command() -> SettleBattleResultCommand:
	return SettleBattleResultCommand.new(_catalog, null, _relic_table)

func enter_node_event(target_node_id: String) -> EnterNodeEvent:
	return EnterNodeEvent.new(
		target_node_id, _catalog, _battle_catalog, null, _relic_table,
		_challenge_affix_effect_ids
	)

## 缺口 2 的正式建構點：PREPARE 階段的 board commit 必須帶上指揮官人口加成來源，
## 否則 board population cap 只有 base level（design.md §4.2）。
func commit_board_layout_command(
	board: BoardState,
	bench_unit_instance_ids: Array[String]
) -> CommitBoardLayoutCommand:
	return CommitBoardLayoutCommand.new(
		board,
		bench_unit_instance_ids,
		_battle_catalog,
		RunCompositionSupport.population_sources(_commander_id, _commander_population_bonus)
	)
