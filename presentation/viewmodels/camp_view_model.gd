class_name CampViewModel
extends RefCounted

## T11 / S5-AC-001（specs/meta-progression/design.md §4.4「無第二資料源」）：營地五設施
## （遠征門／指揮官廳／圖鑑館／解鎖工坊／挑戰碑）的唯讀投影，全部欄位自**同一份**
## ProfileState 導出。
##
## 只持 profile 的 deep_clone（同 collection_view_model.gd／expedition_gate_view_model.gd
## 的既定慣例），不跨操作保留可變 domain 物件引用；建構後改動呼叫端手上的 profile
## 不影響本 ViewModel 的讀出值。
##
## 明確不含「生效詞綴清單」子功能：那需要解析內容（registry＋manifest_digest），屬
## ExpeditionGateViewModel 自己的職責（design.md §3 模組圖把兩者並列為獨立 ViewModel）。
## 因此本型別**無 registry 依賴**。

var _profile: ProfileState

func _init(profile: ProfileState) -> void:
	_profile = profile.deep_clone() if profile != null else null


# --- 遠征門 ---------------------------------------------------------------

## 最近一次開遠征的選擇；此 profile 從未開過遠征時為 null。
func expedition_gate_last_selection() -> ProfileLastSelectionState:
	if _profile == null or _profile.last_selection == null:
		return null
	return _profile.last_selection.deep_clone()

## 該指揮官的最高通關挑戰階級；無紀錄＝未挑戰過＝0（與
## expedition_gate_view_model.gd:38-42 完全相同的語意）。
func expedition_gate_highest_cleared_level(commander_id: StringName) -> int:
	if _profile == null:
		return 0
	for record: CommanderChallengeRecordState in _profile.commander_challenge_records:
		if record.commander_id == commander_id:
			return record.highest_cleared_level
	return 0


# --- 指揮官廳 -------------------------------------------------------------

## 已解鎖的指揮官 id，保留 unlocked_content_ids 的原有（canonical）順序。
func commander_hall_unlocked_commander_ids() -> Array[StringName]:
	return collection_unlocked_ids_for_category(&"commander")


# --- 圖鑑館 ---------------------------------------------------------------

## 指定類別的已發現 id，台帳順序（該類別無發現時為空陣列）。
func collection_discovered_ids_for_category(category: StringName) -> Array[StringName]:
	return _filter_by_category(_discovered_ids(), category)

## 指定類別的已解鎖 id，台帳順序。
func collection_unlocked_ids_for_category(category: StringName) -> Array[StringName]:
	return _filter_by_category(_unlocked_ids(), category)


# --- 解鎖工坊 -------------------------------------------------------------

func unlock_workshop_currency() -> int:
	return _profile.meta_currency if _profile != null else 0

## 購買紀錄＝unlocked_content_ids 全量（design.md §4.3）——解鎖工坊涵蓋各類可購內容，
## 故此處刻意不濾 category。
func unlock_workshop_unlocked_content_ids() -> Array[StringName]:
	return _unlocked_ids()


# --- 挑戰碑 ---------------------------------------------------------------

func challenge_monument_records() -> Array[CommanderChallengeRecordState]:
	var records: Array[CommanderChallengeRecordState] = []
	if _profile == null:
		return records
	for record: CommanderChallengeRecordState in _profile.commander_challenge_records:
		records.append(record.deep_clone())
	return records

func challenge_monument_highest_challenge_level() -> int:
	return _profile.highest_challenge_level if _profile != null else 0


# --- 內部 -----------------------------------------------------------------

func _discovered_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _profile != null:
		ids.assign(_profile.discovered_content_ids)
	return ids

func _unlocked_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _profile != null:
		ids.assign(_profile.unlocked_content_ids)
	return ids

## 類別＝內容 id 第一個 "." 之前的區段（專案通用的 "<category>.<name>" 慣例，
## 沿用 collection_view_model.gd:49-52）。
func _filter_by_category(ids: Array[StringName], category: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for content_id: StringName in ids:
		if _category_of(content_id) == category:
			result.append(content_id)
	return result

func _category_of(content_id: StringName) -> StringName:
	var text := String(content_id)
	var separator := text.find(".")
	return StringName(text.substr(0, separator)) if separator >= 0 else content_id
