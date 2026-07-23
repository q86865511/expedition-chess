class_name BuildLabScreen
extends Control

## T11 (specs/build-systems/design.md §8) -- Build Lab 灰盒:比照
## expedition_lab／combat_lab 慣例,開發用、非正式 UI。經 BuildLabSession 的
## 四個 ViewModel(TraitPreview/Forge/Inventory/RelicSlot)完成鍛造／換裝／
## 拆卸／overflow 處置／遺物替換操作流,操作結果與具名 error(見 HANDOFF §2
## 「具名原因的讀法」)一律顯示於 LogLabel,不吞錯不繞過。

@onready var trait_label: RichTextLabel = %TraitLabel
@onready var inventory_label: RichTextLabel = %InventoryLabel
@onready var forge_label: RichTextLabel = %ForgeLabel
@onready var relic_label: RichTextLabel = %RelicLabel
@onready var log_label: RichTextLabel = %LogLabel
@onready var forge_button: Button = %ForgeButton
@onready var equip_button: Button = %EquipButton
@onready var dismantle_button: Button = %DismantleButton
@onready var overflow_button: Button = %OverflowButton
@onready var relic_button: Button = %RelicButton

var _registry: ContentRegistryService
var _session := BuildLabSession.new()
var _ready_ok: bool = false

func _ready() -> void:
	_registry = ContentRegistryService.new()
	add_child(_registry)

	forge_button.pressed.connect(_on_forge_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	dismantle_button.pressed.connect(_on_dismantle_pressed)
	overflow_button.pressed.connect(_on_overflow_pressed)
	relic_button.pressed.connect(_on_relic_pressed)

	var init_error := _session.initialize(_registry, self)
	if not init_error.is_empty():
		_append_log("初始化失敗：%s" % init_error)
		_set_buttons_enabled(false)
		return
	_ready_ok = true
	_append_log("Build Lab 就緒：雙 pack 內容已安裝、pinned BattleRuleCatalog 已接線。")
	_render_all()

## 供測試存取 session,以驗證 save/load 走 ContentRegistryReceiptAdapter 正常路徑
## (見 BuildLabSession.reload_from_storage_for_test())。
func session_for_test() -> BuildLabSession:
	return _session

func _on_forge_pressed() -> void:
	_run_and_render(_session.forge_demo(), "鍛造 iron_plate ×2 → equipment.iron_iron")

func _on_equip_pressed() -> void:
	_run_and_render(_session.equip_demo(), "把 equipment.frost_frost 裝到 UNIT_A")

func _on_dismantle_pressed() -> void:
	_run_and_render(_session.dismantle_demo(), "消耗 dismantle_kit 拆下 UNIT_B 的裝備")

func _on_overflow_pressed() -> void:
	_run_and_render(_session.resolve_overflow_abandon_demo(), "overflow tray 明確放棄一件零件")

func _on_relic_pressed() -> void:
	_run_and_render(_session.resolve_relic_demo(), "遺物替換：槽 0 換成 relic.shadow_veil")

func _run_and_render(result: CommandResult, action_label: String) -> void:
	if not _ready_ok:
		return
	if result.ok:
		_append_log("%s：成功" % action_label)
	else:
		_append_log("%s：拒絕（%s）" % [action_label, _source_code(result)])
	_render_all()

func _source_code(result: CommandResult) -> String:
	if result.error == null:
		return "?"
	for diagnostic: DiagnosticValue in result.error.diagnostic_values:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return diagnostic.string_value.value
	return String(result.error.code)

func _render_all() -> void:
	_render_trait_preview()
	_render_inventory()
	_render_forge()
	_render_relic_slots()

func _render_trait_preview() -> void:
	var text := "[b]羈絆預覽（與實戰同源 BattleSetupSourceCompiler）[/b]\n"
	for snapshot: TraitBattleSnapshot in _session.trait_preview_view_model().trait_snapshots():
		text += "%s｜tier %d\n" % [String(snapshot.trait_id), snapshot.tier]
	trait_label.text = text

func _render_inventory() -> void:
	var view_model := _session.inventory_view_model()
	var text := "[b]物品庫[/b]\n"
	for item: ItemInstanceState in view_model.inventory_items():
		text += "%s｜%s\n" % [item.instance_id, String(item.def_id)]
	text += "[b]UNIT_B 裝備[/b]\n"
	for item: ItemInstanceState in view_model.equipped_items(BuildLabSession.UNIT_B_ID):
		text += "%s｜%s\n" % [item.instance_id, String(item.def_id)]
	text += "[b]overflow tray[/b]\n"
	for item: ItemInstanceState in view_model.overflow_items():
		text += "%s｜%s\n" % [item.instance_id, String(item.def_id)]
	inventory_label.text = text

func _render_forge() -> void:
	var text := "[b]鍛造零件庫（僅零件）[/b]\n"
	for item: ItemInstanceState in _session.forge_view_model().inventory_components():
		text += "%s｜%s\n" % [item.instance_id, String(item.def_id)]
	forge_label.text = text

func _render_relic_slots() -> void:
	var view_model := _session.relic_slot_view_model()
	var text := "[b]遺物槽（5）[/b]\n"
	for slot: RelicSlotState in view_model.active_slots():
		var relic_text := String(slot.relic_id.value) if slot.relic_id != null else "（空）"
		text += "槽 %d：%s\n" % [slot.slot_index, relic_text]
	var candidate := view_model.pending_replacement_candidate()
	text += "待選替換候選：%s\n" % (String(candidate.value) if candidate != null else "（無）")
	relic_label.text = text

func _append_log(message: String) -> void:
	log_label.append_text("%s\n" % message)

func _set_buttons_enabled(enabled: bool) -> void:
	forge_button.disabled = not enabled
	equip_button.disabled = not enabled
	dismantle_button.disabled = not enabled
	overflow_button.disabled = not enabled
	relic_button.disabled = not enabled
