extends BalanceProductionCaseDriver

## rewrite-plan.md §5.4 的對照組：正式 driver 在走完第 7 個節點時會做一次
## 「存檔 → repository.load() → 重新 composition」（balance_production_case_driver.gd:155-168）。
## 本子類別只覆寫 `_compose`，讓第二次（重載）composition 直接沿用第一次的
## session／controller —— 也就是「完全沒有中斷、續用記憶體狀態」的那一條路徑。
## 其餘一切（路線選擇、shop 動作、戰鬥、結算、獎勵）都仍走 driver 本體。
##
## 兩個 case 的最終狀態逐欄相同 ＝ save-reload 等價；不同 ＝ 存檔往返有損。
## 這個 seam 完全在測試側，driver 本體不需要為測試留鉤子。

var reused_composition: bool = false

var _first_composition: Dictionary = {}


func _compose(
	profile: ProfileState,
	run: RunState,
	repository: SaveRepository,
	root_factory: RunSaveRootFactory
) -> Dictionary:
	if not _first_composition.is_empty():
		reused_composition = true
		return _first_composition
	_first_composition = super(profile, run, repository, root_factory)
	return _first_composition
