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

var _label: Label
var _report: Dictionary = {}


## 掛上（或接回）常駐狀態列。回傳 null 代表沒有可掛載的父節點。
func attach(parent: Control) -> Label:
	if parent == null:
		return null
	var existing := parent.get_node_or_null(NODE_NAME) as Label
	if existing != null:
		_label = existing
		return _label
	var label := Label.new()
	label.name = NODE_NAME
	label.focus_mode = Control.FOCUS_NONE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = ""
	parent.add_child(label)
	_label = label
	return label


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
	message_key: StringName,
	resolver: Callable
) -> void:
	var mapper := PresentationErrorMapper.new()
	_report = mapper.map_failure(source_code, committed, {})
	# 具名碼優先（mapper 認得就用它的專屬訊息），其次才是 DiagnosticError 自帶的鍵，
	# 最後才落到泛用訊息——否則 AppRoot 一律帶 error.presentation.app_action，
	# 每種失敗在畫面上都會長得一模一樣。
	var mapped := mapper.message_key_for(source_code)
	if mapped.is_empty() and not message_key.is_empty():
		_report["message_key"] = message_key
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
