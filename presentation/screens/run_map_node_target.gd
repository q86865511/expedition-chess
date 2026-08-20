class_name RunMapNodeTarget
extends Control

## RUN_MAP 圖形節點的滑鼠 hit target。刻意不繼承 BaseButton：全域 UI scale
## 契約會把所有 BaseButton 撐到一般動作按鈕的 72px 高度，而地圖三列需要
## 固定的緊密圖形格。鍵盤與朗讀通道仍由 NodeSelector 擁有。

signal pressed

var disabled: bool = false
var text: String = "":
	set(value):
		text = value
		_ensure_label()
		_label.text = value

var _label: Label


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_ensure_label()


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	):
		pressed.emit()
		accept_event()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pressed.emit()
		accept_event()


func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label.new()
	_label.name = "Signal"
	_label.theme_type_variation = &"ExpeditionMapNode"
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
