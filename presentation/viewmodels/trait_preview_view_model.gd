class_name TraitPreviewViewModel
extends RefCounted

## T10 / S4-AC-013 (specs/build-systems/design.md §8) -- 羈絆面板 ViewModel:
## 純預覽(design §8 表格:「無（純預覽）」),讀端與實戰同源 -- 直接複用
## BattleSetupSourceCompiler.compile() 對「RunController 已提交 roster
## snapshot ＋ pinned BattleRuleCatalog」的編譯結果,不另生一套預覽邏輯。
## 只持 clone/snapshot,不跨操作快取可變 domain 物件(design §8)。

var _controller: RunController
var _catalog: BattleRuleCatalog
var _compiler: BattleSetupSourceCompiler

func _init(
	controller: RunController,
	catalog: BattleRuleCatalog,
	compiler: BattleSetupSourceCompiler = null
) -> void:
	_controller = controller
	_catalog = catalog.deep_clone() if catalog != null else null
	_compiler = compiler if compiler != null else BattleSetupSourceCompiler.new()

## 目前已提交 roster 在 pinned catalog 下達門檻的 trait 清單 -- 逐欄位與直接
## 呼叫 BattleSetupSourceCompiler.compile() 的 player_active_traits 相同。
func trait_snapshots() -> Array[TraitBattleSnapshot]:
	var roster := _controller.roster_snapshot()
	var bundle := _compiler.compile(roster, _catalog)
	return bundle.player_active_traits
