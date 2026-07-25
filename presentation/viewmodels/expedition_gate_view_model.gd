class_name ExpeditionGateViewModel
extends RefCounted

## T07 / S5-AC-001、S5-AC-010（specs/meta-progression/design.md §3、§4.4、§6.3）：遠征門
## （五設施之一）的唯讀投影——開局前（建立遠征之前）呈現「最近選擇」「各指揮官最高通關」與
## 「指揮官／挑戰組合下實際生效的詞綴清單（含分軌標籤）」。
##
## 只持 ProfileState 中真正讀得到的兩個欄位的 deep_clone（同 collection_view_model.gd 的既定
## 慣例），不跨操作保留可變 domain 物件引用；registry／manifest_digest 是唯讀內容查詢依賴
## （同 trait_preview_view_model.gd 持 catalog 的慣例），不受「只持 clone」的限制。

var _last_selection: ProfileLastSelectionState
var _records: Array[CommanderChallengeRecordState] = []
var _registry: ContentRegistryService
var _manifest_digest: String
var _resolver: ChallengeAffixResolver

func _init(
	profile: ProfileState,
	registry: ContentRegistryService,
	manifest_digest: String,
	resolver: ChallengeAffixResolver = null
) -> void:
	if profile != null:
		if profile.last_selection != null:
			_last_selection = profile.last_selection.deep_clone()
		for record: CommanderChallengeRecordState in profile.commander_challenge_records:
			_records.append(record.deep_clone())
	_registry = registry
	_manifest_digest = manifest_digest
	_resolver = resolver if resolver != null else ChallengeAffixResolver.new()

## 建構當下的最近選擇 clone；此 profile 從未開過遠征時為 null。
func last_selection() -> ProfileLastSelectionState:
	return _last_selection.deep_clone() if _last_selection != null else null

## 該指揮官的最高通關挑戰階級；無紀錄＝未挑戰過＝0。
func highest_cleared_level(commander_id: StringName) -> int:
	for record: CommanderChallengeRecordState in _records:
		if record.commander_id == commander_id:
			return record.highest_cleared_level
	return 0

## 指定挑戰階級下 1..N 累積的生效詞綴清單（含 track 分類標籤）。W4-F9 修正（2026-07-25）：
## 直接回傳 resolver 的具名結果（ChallengeAffixResolveResult），不再把「世代不符/內容缺失」
## 等結構性解析失敗吞成空陣列——ok=true 且 entries=[] 才是 Challenge 0「真的無詞綴」；
## ok=false 是解析失敗，呼叫端可用 .ok/.error 區分兩者，不再與「真的無詞綴」混淆
## （REQ-TECH-006：可失敗操作須回具名 result/error，不得 silent-null）。
func affix_entries(challenge_level: int) -> ChallengeAffixResolveResult:
	return _resolver.resolve(_registry, _manifest_digest, challenge_level)
