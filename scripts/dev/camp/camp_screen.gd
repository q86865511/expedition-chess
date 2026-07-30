class_name CampScreen
extends Control

## S5 T11 灰盒（specs/meta-progression/design.md §4.4；requirements.md S5-AC-001）：
## 營地五設施的開發用畫面，比照 combat_lab／expedition_lab 慣例——只把 CampViewModel
## 的讀出值排版出來，不自帶任何第二資料源；正式 UI 歸 Codex（HANDOFF.md）。
##
## 五設施「進出」＝左側五顆按鈕切換右側明細；遠征門另有一顆「開始遠征」按鈕，把
## composition root 的 CampController→AppStateMachine 全鏈跑一次。

const FACILITY_EXPEDITION_GATE: int = 0
const FACILITY_COMMANDER_HALL: int = 1
const FACILITY_COLLECTION: int = 2
const FACILITY_UNLOCK_WORKSHOP: int = 3
const FACILITY_CHALLENGE_MONUMENT: int = 4

const COLLECTION_CATEGORIES: Array[StringName] = [&"unit", &"equipment", &"relic", &"commander"]

@onready var facility_label: Label = %FacilityLabel
@onready var detail_label: RichTextLabel = %DetailLabel
@onready var status_label: Label = %StatusLabel
@onready var start_button: Button = %StartButton
@onready var discard_button: Button = %DiscardButton

var _root: ApplicationRoot
var _view_model: CampViewModel
var _facility: int = FACILITY_EXPEDITION_GATE


func _ready() -> void:
	%ExpeditionGateButton.pressed.connect(func() -> void: _open(FACILITY_EXPEDITION_GATE))
	%CommanderHallButton.pressed.connect(func() -> void: _open(FACILITY_COMMANDER_HALL))
	%CollectionButton.pressed.connect(func() -> void: _open(FACILITY_COLLECTION))
	%UnlockWorkshopButton.pressed.connect(func() -> void: _open(FACILITY_UNLOCK_WORKSHOP))
	%ChallengeMonumentButton.pressed.connect(func() -> void: _open(FACILITY_CHALLENGE_MONUMENT))
	start_button.pressed.connect(_start_expedition)
	discard_button.pressed.connect(_discard_unresumable_run)
	_render()


## composition root 於換場後注入；view_model 為 null＝尚未載入 profile。
func bind(root: ApplicationRoot, view_model: CampViewModel) -> void:
	_root = root
	_view_model = view_model
	_render()


func _open(facility: int) -> void:
	_facility = facility
	_render()


func _start_expedition() -> void:
	if _root == null or _view_model == null:
		status_label.text = "尚未載入 profile，無法開始遠征"
		return
	var commander_id := _selected_commander_id()
	if commander_id == &"":
		status_label.text = "沒有任何已解鎖的指揮官"
		return
	var challenge_level := 0
	var last_selection := _view_model.expedition_gate_last_selection()
	if last_selection != null:
		challenge_level = last_selection.challenge_level
	var result := _root.start_expedition(
		StartExpeditionRequest.new(commander_id, challenge_level)
	)
	status_label.text = (
		"遠征已開始：%s（挑戰 %d）" % [String(commander_id), challenge_level]
		if result.ok
		else "開始遠征失敗：%s" % String(result.error.source_code)
	)


func _discard_unresumable_run() -> void:
	if _root == null:
		status_label.text = "無法棄置：composition root 尚未綁定"
		return
	var error := _root.discard_unresumable_active_run()
	status_label.text = (
		"已棄置無法續跑的遠征"
		if error.is_empty()
		else "棄置遠征失敗：%s" % String(error)
	)
	_render()


## 最近選擇優先；沒有紀錄就取指揮官廳清單的第一位。
func _selected_commander_id() -> StringName:
	var last_selection := _view_model.expedition_gate_last_selection()
	if last_selection != null:
		return last_selection.commander_id
	var unlocked := _view_model.commander_hall_unlocked_commander_ids()
	return unlocked[0] if not unlocked.is_empty() else &""


func _render() -> void:
	if facility_label == null:
		return
	facility_label.text = _facility_name()
	start_button.visible = _facility == FACILITY_EXPEDITION_GATE
	discard_button.visible = (
		_facility == FACILITY_EXPEDITION_GATE
		and _root != null
		and _root.has_unresumable_active_run()
	)
	detail_label.clear()
	if _view_model == null:
		detail_label.append_text("（尚未載入 profile）")
		return
	detail_label.append_text(_facility_detail())


func _facility_name() -> String:
	match _facility:
		FACILITY_COMMANDER_HALL:
			return "指揮官廳"
		FACILITY_COLLECTION:
			return "圖鑑館"
		FACILITY_UNLOCK_WORKSHOP:
			return "解鎖工坊"
		FACILITY_CHALLENGE_MONUMENT:
			return "挑戰碑"
	return "遠征門"


func _facility_detail() -> String:
	match _facility:
		FACILITY_COMMANDER_HALL:
			return "已解鎖指揮官：%s" % _join(
				_view_model.commander_hall_unlocked_commander_ids()
			)
		FACILITY_COLLECTION:
			return _collection_detail()
		FACILITY_UNLOCK_WORKSHOP:
			return "局外貨幣：%d\n購買紀錄：%s" % [
				_view_model.unlock_workshop_currency(),
				_join(_view_model.unlock_workshop_unlocked_content_ids()),
			]
		FACILITY_CHALLENGE_MONUMENT:
			return _challenge_detail()
	return _expedition_gate_detail()


func _expedition_gate_detail() -> String:
	var last_selection := _view_model.expedition_gate_last_selection()
	var selection_text := "（無）"
	if last_selection != null:
		selection_text = "%s｜挑戰 %d" % [
			String(last_selection.commander_id), last_selection.challenge_level
		]
	var lines: Array[String] = ["最近選擇：%s" % selection_text]
	for commander_id: StringName in _view_model.commander_hall_unlocked_commander_ids():
		lines.append("%s：最高通關 %d" % [
			String(commander_id),
			_view_model.expedition_gate_highest_cleared_level(commander_id),
		])
	return "\n".join(lines)


func _collection_detail() -> String:
	var lines: Array[String] = []
	for category: StringName in COLLECTION_CATEGORIES:
		lines.append("%s｜已發現 %s｜已解鎖 %s" % [
			String(category),
			_join(_view_model.collection_discovered_ids_for_category(category)),
			_join(_view_model.collection_unlocked_ids_for_category(category)),
		])
	return "\n".join(lines)


func _challenge_detail() -> String:
	var lines: Array[String] = [
		"整體最高挑戰階級：%d" % _view_model.challenge_monument_highest_challenge_level()
	]
	for record: CommanderChallengeRecordState in _view_model.challenge_monument_records():
		lines.append("%s：%d" % [String(record.commander_id), record.highest_cleared_level])
	return "\n".join(lines)


func _join(ids: Array[StringName]) -> String:
	if ids.is_empty():
		return "（無）"
	var values: Array[String] = []
	for content_id: StringName in ids:
		values.append(String(content_id))
	return ", ".join(values)
