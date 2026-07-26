class_name ResultsScreen
extends Control

## S5 T11 灰盒（specs/meta-progression/design.md §4.4、§5.1）：遠征結算後的結果畫面。
## meta 結算已在進入本畫面「之前」以單一原子存檔完成（貨幣/receipt/挑戰紀錄/清 run 同
## 一筆），故本畫面純唯讀——只顯示結算後 profile 的投影，按「回營地」發
## ACKNOWLEDGE_RESULTS（無存檔提交）回 CAMP。正式 UI 歸 Codex（HANDOFF.md）。

@onready var summary_label: RichTextLabel = %SummaryLabel
@onready var status_label: Label = %StatusLabel

var _root: ApplicationRoot
var _view_model: CampViewModel


func _ready() -> void:
	%AcknowledgeButton.pressed.connect(_acknowledge)
	_render()


func bind(root: ApplicationRoot, view_model: CampViewModel) -> void:
	_root = root
	_view_model = view_model
	_render()


func _acknowledge() -> void:
	if _root == null:
		return
	var error := _root.acknowledge_results()
	if not error.is_empty():
		status_label.text = "回營地失敗：%s" % String(error)


func _render() -> void:
	if summary_label == null:
		return
	summary_label.clear()
	if _view_model == null:
		summary_label.append_text("（尚未載入 profile）")
		return
	var lines: Array[String] = [
		"局外貨幣：%d" % _view_model.unlock_workshop_currency(),
		"整體最高挑戰階級：%d" % _view_model.challenge_monument_highest_challenge_level(),
	]
	for record: CommanderChallengeRecordState in _view_model.challenge_monument_records():
		lines.append("%s：最高通關 %d" % [
			String(record.commander_id), record.highest_cleared_level
		])
	summary_label.append_text("\n".join(lines))
