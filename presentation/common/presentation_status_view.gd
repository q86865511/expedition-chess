class_name PresentationStatusView
extends RefCounted

## G2 H3：玩家可見的錯誤呈現面。
##
## 在此之前 `PresentationErrorMapper`／`DiagnosticError` 整條對映鏈只有測試在讀，
## 玩家操作失敗時畫面零變化。本類別是那條鏈唯一的畫面出口：ProductionScreen 與
## SettingsScreenComposition 各持一份，把 typed result 轉成常駐 Label 的文字。
##
## 兩個刻意的設計約束：
## 1. pre-commit（權威狀態沒動、可重試）與 post-commit（狀態已提交、只有畫面退到
##    fallback）必須是畫面上兩句不同的話——玩家要能分辨「再按一次就好」與
##    「事情已經發生了，只是畫面沒跟上」。前綴由 `PresentationErrorMapper`
##    的 `committed` 旗標決定。
## 2. 無障礙：可辨識性不靠顏色。Label 常駐 UI 樹（成功時清空文字），訊息一律帶
##    在地化文字前綴，不用只變色或只彈出提示。

const NODE_NAME: String = "StatusMessage"
const PRE_COMMIT_PREFIX_KEY: StringName = &"error.status.pre_commit"
const POST_COMMIT_PREFIX_KEY: StringName = &"error.status.post_commit"

## G2 F1：沒有明確版面時這個 Label 玩家實際看不到——autowrap Label 的
## `get_minimum_size()` 寬度是 1px，不在 Container 內又沒有 anchors/offsets 時
## size 就被夾成 1px；且預設 z_index=0 會被 scenes/production/*.tscn 那個
## z_index=1 的全 rect Composition 蓋掉。座標沿用同一批 .tscn 的 1280×720
## 設計空間絕對座標慣例（run_combat_screen.gd 的 EnemySemantics、
## run_map_screen.gd 的 NodeSelector 亦同）。
const BAR_ORIGIN: Vector2 = Vector2(72.0, 636.0)
const BAR_SIZE: Vector2 = Vector2(1136.0, 48.0)
## 同一畫面可以有多條狀態列（ProductionScreen 一條、SETTINGS 的 Composition 一條）；
## row 往上疊，兩條訊息不會互相蓋住。
const BAR_ROW_STRIDE: float = 56.0
## Composition 是 z_index=1、標題 Label 是 z_index=10；狀態列必須高於兩者。
const BAR_Z_INDEX: int = 20

var _label: Label
var _report: Dictionary = {}


## 掛上（或接回）常駐狀態列。回傳 null 代表沒有可掛載的父節點。
## `row` 讓同一畫面的第二條狀態列往上疊一格（見 BAR_ROW_STRIDE）。
func attach(parent: Control, row: int = 0) -> Label:
	if parent == null:
		return null
	var existing := parent.get_node_or_null(NODE_NAME) as Label
	if existing != null:
		_label = existing
		_apply_layout(_label, row)
		return _label
	var label := Label.new()
	label.name = NODE_NAME
	label.focus_mode = Control.FOCUS_NONE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = ""
	_apply_layout(label, row)
	parent.add_child(label)
	_label = label
	return label


## 版面是這條狀態列「玩家看得到」的唯一保證，因此不論新建或接回都重新套用。
func _apply_layout(label: Label, row: int) -> void:
	label.position = Vector2(
		BAR_ORIGIN.x,
		BAR_ORIGIN.y - BAR_ROW_STRIDE * float(maxi(row, 0))
	)
	label.custom_minimum_size = BAR_SIZE
	label.size = BAR_SIZE
	label.z_index = BAR_Z_INDEX
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## typed result（AppActionResult／RunPresentationResult／playback result…）的統一入口：
## 成功清空、失敗顯示。全部只讀 `ok`／`committed`／`error`，不綁定具體型別。
func show_result(result: Variant, resolver: Callable) -> void:
	if not _has_property(result, &"ok"):
		clear(resolver)
		return
	var target := result as Object
	if bool(target.get(&"ok")):
		clear(resolver)
		return
	var error := target.get(&"error") as DiagnosticError
	show_failure(
		error.source_code if error != null else &"",
		bool(target.get(&"committed")) if _has_property(target, &"committed") else false,
		error.message_key if error != null else &"",
		resolver
	)


func show_failure(
	source_code: StringName,
	committed: bool,
	_message_key: StringName,
	resolver: Callable
) -> void:
	var mapper := PresentationErrorMapper.new()
	_report = mapper.map_failure(source_code, committed, {})
	# 只有明確登錄的 source code 才使用專屬文案。未知碼固定落到 catalog
	# 中的泛用訊息，不能把 DiagnosticError 自帶但 catalog 未收錄的 key 裸露給玩家。
	_render(resolver)


func clear(resolver: Callable) -> void:
	_report = {}
	_render(resolver)


func relocalize(resolver: Callable) -> void:
	_render(resolver)


func report() -> Dictionary:
	return _report.duplicate(true)


func message_text() -> String:
	return _label.text if _label != null else ""


func is_showing_failure() -> bool:
	return not _report.is_empty()


func _render(resolver: Callable) -> void:
	if _label == null:
		return
	if _report.is_empty():
		_label.text = ""
		_label.tooltip_text = ""
		return
	var prefix_key := (
		POST_COMMIT_PREFIX_KEY
		if bool(_report.get("committed", false))
		else PRE_COMMIT_PREFIX_KEY
	)
	var message_key := StringName(
		_report.get("message_key", PresentationErrorMapper.DEFAULT_MESSAGE_KEY)
	)
	var composed := _resolve(resolver, prefix_key) + _resolve(resolver, message_key)
	_label.text = composed
	_label.tooltip_text = composed


func _resolve(resolver: Callable, key: StringName) -> String:
	if not resolver.is_valid():
		return String(key)
	var resolved: Variant = resolver.call(key)
	return String(resolved) if resolved != null else String(key)


func _has_property(target: Variant, property: StringName) -> bool:
	if target == null or not target is Object:
		return false
	for entry: Dictionary in (target as Object).get_property_list():
		if StringName(entry.get("name", &"")) == property:
			return true
	return false
