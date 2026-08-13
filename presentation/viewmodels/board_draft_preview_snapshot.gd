class_name BoardDraftPreviewSnapshot
extends RefCounted

## 拖曳草稿佈局的唯讀預覽（IRH-REQ-008）：人口、合法性、羈絆進度三者一次到位。
##
## 全部欄位來自 domain：derived_capacity／valid／issues 是 BoardPreparationValidator
## 報告的原樣轉發，trait_progress 是 BattleSetupSourceCompiler.compile_trait_progress()
## 的產物。呈現層不得自行判斷人口上限或羈絆門檻（spec §10.3）。
##
## used_population 是草稿自己的 placements 數（輸入規模，不是規則）；
## derived_capacity 為 -1 表示人口無法計算，此時 issues 內必有 POPULATION_INVALID
## 或 REQUEST_INVALID。

var used_population: int = 0
var derived_capacity: int = -1
var valid: bool = false
var issues: Array[BoardValidationIssue] = []
var trait_progress: Array[TraitProgressSnapshot] = []


## issues 的具名碼清單（原序）；面板只需要分流訊息時用這個，需要格位資訊時讀 issues。
func issue_codes() -> Array[StringName]:
	var result: Array[StringName] = []
	for issue: BoardValidationIssue in issues:
		if issue != null:
			result.append(issue.code)
	return result


func deep_clone() -> BoardDraftPreviewSnapshot:
	var copied := BoardDraftPreviewSnapshot.new()
	copied.used_population = used_population
	copied.derived_capacity = derived_capacity
	copied.valid = valid
	for issue: BoardValidationIssue in issues:
		copied.issues.append(issue.deep_clone() if issue != null else null)
	for progress: TraitProgressSnapshot in trait_progress:
		copied.trait_progress.append(
			progress.deep_clone() if progress != null else null
		)
	return copied
