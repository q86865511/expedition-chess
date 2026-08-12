class_name RunCombatScreen
extends ProductionScreen

const PLAYBACK_PORT_ALREADY_BOUND: StringName = &"PLAYBACK_PORT_ALREADY_BOUND"
const INSPECTION_PORT_ALREADY_BOUND: StringName = \
	&"INSPECTION_PORT_ALREADY_BOUND"
## 檢視面板的 stat 呈現順序；每個 key 對應 loc 鍵 combat.stat.<key>。
const INSPECTION_STAT_ORDER: Array[String] = [
	"star",
	"health",
	"attack",
	"armor",
	"magic_resist",
	"attack_speed_milli",
	"attack_range_cells",
	"start_mana",
	"max_mana",
	"move_speed_milli",
]
const STAT_TEXT_KEY_PREFIX: String = "combat.stat."
const INSPECTION_NONE_KEY: StringName = &"combat.inspection.none"
const PLAYBACK_NOT_AVAILABLE: StringName = &"PLAYBACK_NOT_AVAILABLE"
## G2 F3：SETTLE 失敗後的重試間隔（presentation 節奏，不是 gameplay entropy）。
## 沒有間隔就會每一影格重送一次被拒絕的命令。
const SETTLE_RETRY_INTERVAL_MS: float = 500.0
## T22：短 transcript 也必須至少留下可辨識、可擷取的正式戰鬥畫面。
## 這是純 presentation 時鐘；只累積 SceneTree 傳入的 delta，不讀系統時間，
## 不改 canonical transcript、事件順序或 battle summary。
const MIN_VISIBLE_PLAYBACK_MS: float = 750.0
const SEMANTIC_PALETTES: Dictionary = {
	&"default": {
		&"ally": Color("7ee0a1"),
		&"enemy": Color("ff8a8a"),
		&"trait": Color("c7a7ff"),
		&"rarity": Color("ffd56a"),
		&"danger": Color("ffb05e"),
	},
	&"protanopia": {
		&"ally": Color("68c5ff"),
		&"enemy": Color("ffd166"),
		&"trait": Color("c0b7ff"),
		&"rarity": Color("f4a261"),
		&"danger": Color("ffffff"),
	},
	&"deuteranopia": {
		&"ally": Color("56b4e9"),
		&"enemy": Color("f0e442"),
		&"trait": Color("cc79a7"),
		&"rarity": Color("e69f00"),
		&"danger": Color("ffffff"),
	},
	&"tritanopia": {
		&"ally": Color("f28e8e"),
		&"enemy": Color("67d5b5"),
		&"trait": Color("f2c14e"),
		&"rarity": Color("c7a7ff"),
		&"danger": Color("ffffff"),
	},
}

var _model := RunCombatIntelModel.new()
var _presenter: RunScreenPresenter
var _playback_port: LiveScreenPlaybackPort
var _inspection_port: LiveScreenInspectionPort
var _snapshot: RunPresentationSnapshot
var _hud_shell: InRunHudShell
var _world_snapshot_factory := WorldBoardSnapshotFactory.new()
var _combat_world_projection := CombatWorldEventProjection.new()
var _unit_selector: ItemList
var _selected_unit_serial: int = -1
var _settle_requested: bool = false
var _settle_result: RunPresentationResult
var _settle_retry_countdown_ms: float = 0.0
var _first_frame_presented: bool = false
var _visible_playback_elapsed_ms: float = 0.0
var _settlement_pending_visibility_contract: bool = false
var _world_board_mount_error: StringName = &""
var _world_board_mount_scheduled: bool = false
var _world_board_ready: bool = false
## Snapshot of the exact status report emitted by this consumer. Recovery may
## clear it only while the parent still exposes that same report; a newer action
## result must never be erased by a renderer recovery.
var _world_board_render_status_signature: Dictionary = {}


func compose(
	snapshot: RunPresentationSnapshot,
	intent_port: LiveScreenIntentPort
) -> StringName:
	var error_code := _model.compose(snapshot)
	if not error_code.is_empty():
		_snapshot = null
		return error_code
	_snapshot = snapshot.deep_clone()
	_presenter = RunScreenPresenter.new(&"RUN_COMBAT", intent_port)
	_selected_unit_serial = -1
	_settle_requested = false
	_settle_result = null
	_settle_retry_countdown_ms = 0.0
	_first_frame_presented = false
	_visible_playback_elapsed_ms = 0.0
	_settlement_pending_visibility_contract = false
	_world_board_mount_error = &""
	_world_board_mount_scheduled = false
	_world_board_ready = false
	_world_board_render_status_signature.clear()
	_combat_world_projection = CombatWorldEventProjection.new()
	var projection_error := _combat_world_projection.compose(
		_world_snapshot_factory.build_combat(_snapshot.deep_clone())
	)
	if not projection_error.is_empty():
		_world_board_mount_error = projection_error
		_snapshot = null
		return projection_error
	_build_hud_shell()
	_build_typed_combat_controls()
	_suppress_legacy_accessibility_probe_surface()
	_schedule_world_board_mount()
	queue_redraw()
	return &""


## Composition may run while this subtree is still detached. Its deferred mount
## can therefore be consumed before the ProductionScreen is attached. Enter-tree
## is the lifecycle boundary that guarantees one fresh retry without polling.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_schedule_world_board_mount()


## NOTIFICATION_DRAW 由 Godot 的實際 CanvasItem draw pass 送出。用它釘住首幀，
## 避免在第一個 _process（仍可能早於第一張畫面）就因 exhausted 離開 route。
func _draw() -> void:
	if _world_board_ready and is_visible_in_tree():
		_first_frame_presented = true


## 正式路徑的戰鬥驅動。canonical simulation 已在 START_OR_RESUME_COMBAT 跑到 result
## 提交（commit-before-present），這裡只依 presentation 節奏重播已提交 transcript；
## 播放推進用 SceneTree delta，屬 presentation 節奏，不是 gameplay entropy。
func _process(delta: float) -> void:
	advance_presentation_frame(delta * 1000.0)


## 每影格的 presentation 驅動入口：播放尚未結束就推播放，已請求 SETTLE 就走重試
## 倒數。獨立成公開函式是為了讓測試以固定 delta 驅動，不必依賴真實影格時間。
func advance_presentation_frame(delta_ms: float) -> void:
	if _playback_port == null:
		return
	if _settle_requested:
		_advance_settle_retry(delta_ms)
		return
	advance_playback_frame(delta_ms)


func advance_playback_frame(delta_ms: float) -> BattleEventWindowResult:
	if _playback_port == null or _settle_requested:
		return BattleEventWindowResult.failure(_screen_not_active_error())
	if (
		_world_board_ready
		and _first_frame_presented
		and not _playback_is_paused()
	):
		_visible_playback_elapsed_ms += maxf(0.0, delta_ms)
	var result := _playback_port.advance_playback(delta_ms)
	if not result.ok or result.window == null:
		if _committed_result_awaiting_settlement(result):
			_settlement_pending_visibility_contract = true
		_try_settle_after_visibility_contract()
		return result
	if not result.window.events.is_empty():
		_render_damage_events(result.window.events)
		_present_world_event_window(result.window.events)
	if result.window.exhausted:
		_settlement_pending_visibility_contract = true
	_try_settle_after_visibility_contract()
	return result


func _playback_is_paused() -> bool:
	var playback := try_playback()
	return (
		playback != null
		and playback.ok
		and playback.state != null
		and playback.state.paused
	)


func _try_settle_after_visibility_contract() -> void:
	if (
		not _settlement_pending_visibility_contract
		or not _world_board_ready
		or not _first_frame_presented
		or _visible_playback_elapsed_ms < MIN_VISIBLE_PLAYBACK_MS
		or _settlement_is_blocked()
	):
		return
	_settlement_pending_visibility_contract = false
	_settle_requested = true
	_apply_settle_result(_request_settle())


func has_presented_first_frame() -> bool:
	return _first_frame_presented


func visible_playback_elapsed_ms() -> float:
	return _visible_playback_elapsed_ms


func world_board_ready() -> bool:
	return _world_board_ready


## G2 F3：SETTLE 失敗以前完全無出口——`_settle_requested` 已為 true、`_process`
## 之後永遠 early-return、結果沒有任何 production 讀者，玩家停在一場播完的戰鬥前
## 零訊息，唯一出路是放棄整場 run。現在失敗會顯示在狀態列並定時重試。
## exactly-once：本重試只在「上一次 SETTLE 明確失敗且未提交」時發生；成功或
## post-commit（committed=true）的結果都會讓倒數停止，不會產生第二次結算。
func _advance_settle_retry(delta_ms: float) -> void:
	if _settle_result == null or _settle_result.ok or _settle_result.committed:
		return
	if _settlement_is_blocked():
		return
	_settle_retry_countdown_ms -= maxf(0.0, delta_ms)
	if _settle_retry_countdown_ms > 0.0:
		return
	_apply_settle_result(_request_settle())


## Initial settlement and every retry share the same presentation guard.  A
## system-menu substate or confirmation modal must never allow the committed
## transcript to route away underneath the blocking surface; the pending latch
## remains set and the next unblocked presentation frame resumes settlement.
func _settlement_is_blocked() -> bool:
	if _playback_is_paused():
		return true
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen != null
		and parent_screen.is_background_input_blocked()
	)


func _apply_settle_result(result: RunPresentationResult) -> void:
	_settle_result = result
	_settle_retry_countdown_ms = SETTLE_RETRY_INTERVAL_MS
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.report_composition_result(result)


## 仍在等待重試的 SETTLE（成功結算後恆為 false）。
func settle_retry_pending() -> bool:
	return (
		_settle_requested
		and _settle_result != null
		and not _settle_result.ok
		and not _settle_result.committed
	)


## 已提交 result 重載時沒有 transcript authority（design.md §10：只顯示 committed
## summary，不虛構重播）。少了這條，續跑進 COMBAT 的戰鬥同樣沒有任何東西能結算它。
func _committed_result_awaiting_settlement(
	result: BattleEventWindowResult
) -> bool:
	return (
		result != null
		and result.error != null
		and result.error.source_code == PLAYBACK_NOT_AVAILABLE
		and _snapshot != null
		and _snapshot.view != null
		and _snapshot.view.resolution_kind == ResolutionState.Kind.BATTLE_RESULT_PENDING
	)


## 播完即結算：SETTLE_BATTLE 之後由既有 run route 決定進 REWARD／MAP／結算。
func _request_settle() -> RunPresentationResult:
	if _presenter == null:
		return RunPresentationResult.failure(_screen_not_active_error())
	return _presenter.request(RunPresentationIntent.new(
		RunPresentationIntent.Kind.SETTLE_BATTLE
	))


func settle_result() -> RunPresentationResult:
	return _settle_result


func bind_playback_port(port: LiveScreenPlaybackPort) -> StringName:
	if _playback_port != null:
		return PLAYBACK_PORT_ALREADY_BOUND
	if port == null:
		return SCREEN_NOT_ACTIVE
	_playback_port = port
	return &""


func bind_inspection_port(
	port: LiveScreenInspectionPort
) -> StringName:
	if _inspection_port != null:
		return INSPECTION_PORT_ALREADY_BOUND
	if port == null:
		return SCREEN_NOT_ACTIVE
	_inspection_port = port
	return &""


func try_playback() -> BattlePlaybackStateResult:
	if _playback_port == null:
		return BattlePlaybackStateResult.failure(_screen_not_active_error())
	return _playback_port.try_playback()


func set_playback_speed(multiplier: int) -> BattlePlaybackCommandResult:
	if _playback_port == null:
		return BattlePlaybackCommandResult.failure(_screen_not_active_error())
	return _playback_port.set_speed(multiplier)


func set_playback_paused(paused: bool) -> BattlePlaybackCommandResult:
	if _playback_port == null:
		return BattlePlaybackCommandResult.failure(_screen_not_active_error())
	return _playback_port.set_paused(paused)


func drain_playback_window(
	expected_identity: BattleTranscriptIdentity,
	max_count: int
) -> BattleEventWindowResult:
	if _playback_port == null:
		return BattleEventWindowResult.failure(_screen_not_active_error())
	var result := _playback_port.drain_window(expected_identity, max_count)
	if result.ok and result.window != null:
		_render_damage_events(result.window.events)
		if not result.window.events.is_empty():
			_present_world_event_window(result.window.events)
	return result


## Event-window boundary for the world renderer. The reducer swaps its clone
## only after the full window succeeds, then the surface remounts once so the
## sprite and UI overlay observe the same health/mana/cell snapshot.
func _present_world_event_window(events: Array) -> StringName:
	var projection_error := _combat_world_projection.apply_window(events)
	if not projection_error.is_empty():
		_mark_world_board_not_ready()
		_world_board_mount_error = projection_error
		_report_world_board_mount_error(projection_error)
		return projection_error
	if not is_inside_tree():
		_schedule_world_board_mount()
		return &""
	_mount_world_board()
	return _world_board_mount_error


func _render_damage_events(events: Array) -> void:
	var parent_screen := get_parent() as ProductionScreen
	var accessibility := (
		parent_screen.get_node_or_null(^"AccessibilityRuntime")
		as ProductionAccessibilityHost
		if parent_screen != null
		else null
	)
	if accessibility != null:
		accessibility.render_damage_events(events)


func enemy_rows() -> Array[RunCombatIntelModel.EnemyIntelRow]:
	return _model.enemy_rows()


func active_trait_ids() -> Array[StringName]:
	return _model.active_trait_ids()


func boss_phase_rows() -> Array[RunCombatIntelModel.BossPhaseIntelRow]:
	return _model.boss_phase_rows()


func selected_unit_serial() -> int:
	return _selected_unit_serial


func apply_color_vision_mode(color_mode: StringName) -> void:
	var palette_value: Variant = SEMANTIC_PALETTES.get(
		color_mode,
		SEMANTIC_PALETTES[&"default"]
	)
	var palette := palette_value as Dictionary
	set_meta(&"effective_color_vision_mode", color_mode)
	for node: Node in find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or not label.has_meta(&"semantic_kind"):
			continue
		var semantic_kind := StringName(label.get_meta(&"semantic_kind"))
		if palette.has(semantic_kind):
			label.add_theme_color_override(
				&"font_color",
				palette[semantic_kind] as Color
			)


func _screen_not_active_error() -> DiagnosticError:
	return DiagnosticError.new(
		SCREEN_NOT_ACTIVE,
		&"error.presentation.screen_not_active"
	)


func toggle_pause() -> BattlePlaybackCommandResult:
	var current := try_playback()
	if not current.ok:
		return BattlePlaybackCommandResult.failure(current.error)
	return set_playback_paused(not current.state.paused)


func cycle_speed() -> BattlePlaybackCommandResult:
	var current := try_playback()
	if not current.ok:
		return BattlePlaybackCommandResult.failure(current.error)
	var multiplier := 1
	match current.state.speed:
		&"x1":
			multiplier = 2
		&"x2":
			multiplier = 4
		_:
			multiplier = 1
	return set_playback_speed(multiplier)


func inspect() -> CombatUnitInspectionResult:
	if _inspection_port == null or _selected_unit_serial <= 0:
		_clear_inspection_panel()
		return CombatUnitInspectionResult.failure(
			DiagnosticError.new(
				&"ACTION_NOT_AVAILABLE",
				&"error.presentation.action_not_available"
			)
		)
	var result := _inspection_port.inspect_combat_unit(
		_selected_unit_serial
	)
	if result == null or not result.ok or result.snapshot == null:
		_clear_inspection_panel()
		return (
			result
			if result != null
			else CombatUnitInspectionResult.failure(
				DiagnosticError.new(
					&"INSPECTION_DEPENDENCY_MISSING",
					&"error.presentation.combat_inspection_dependency_missing"
				)
			)
		)
	_render_inspection(result.snapshot)
	return CombatUnitInspectionResult.new(true, result.snapshot, null)


func _build_typed_combat_controls() -> void:
	for path: NodePath in [
		^"UnitSelector",
		^"InspectionPanel",
		^"EnemySemantics",
		^"AllySemantics",
		^"TraitSemantics",
		^"RaritySemantics",
		^"DangerSemantics",
	]:
		_remove_control(path)
	_unit_selector = ItemList.new()
	_unit_selector.name = "UnitSelector"
	ExpeditionLayoutMetrics.set_min(_unit_selector, 0.0, 270.0)
	_unit_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_unit_selector.z_index = 2
	_unit_selector.focus_mode = Control.FOCUS_ALL
	_unit_selector.select_mode = ItemList.SELECT_SINGLE
	_unit_selector.set_meta(&"typed_choice_kind", &"combat_unit")
	_unit_selector.set_meta(&"accessible_text", &"combat.unit_selector")
	var inspections := _model.inspection_rows()
	if not inspections.is_empty():
		for row: RunCombatIntelModel.InspectionIntelRow in inspections:
			_unit_selector.add_item(_localized_content_text(row.source_id))
			var item_index := _unit_selector.item_count - 1
			_unit_selector.set_item_metadata(
				item_index,
				row.unit_serial
			)
			_unit_selector.set_item_tooltip(
				item_index,
				_tooltip_text(&"tooltip.star", row.star)
			)
	else:
		var rows := _model.enemy_rows()
		for index: int in rows.size():
			var row := rows[index] as RunCombatIntelModel.EnemyIntelRow
			_unit_selector.add_item(_localized_content_text(row.unit_id))
			_unit_selector.set_item_metadata(index, index + 1)
	_unit_selector.item_selected.connect(_on_unit_selected)
	var left_stack := (
		_hud_shell.find_child("InRunLeftStack", true, false) as VBoxContainer
		if _hud_shell != null
		else null
	)
	var selector_host: Control = left_stack if left_stack != null else self
	selector_host.add_child(_unit_selector)

	var panel := VBoxContainer.new()
	panel.name = "InspectionPanel"
	ExpeditionLayoutMetrics.set_min(panel, 0.0, 0.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta(&"accessible_text", &"combat.inspection_panel")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 2
	for value_name: StringName in [
		&"SourceValue",
		&"TargetValue",
		&"StatsValue",
		&"EquipmentValue",
		&"TraitsValue",
		&"StatusesValue",
	]:
		var label := Label.new()
		label.name = value_name
		label.text = _localized_ui_text(INSPECTION_NONE_KEY)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(label)
	var right_host := _hud_shell.host(
		ProductionLayoutShell.REGION_RIGHT
	) if _hud_shell != null else self
	var common_inspector := right_host.get_node_or_null(^"UnitInspector")
	if common_inspector != null:
		right_host.remove_child(common_inspector)
		common_inspector.free()
	right_host.add_child(panel)
	_build_semantic_controls()
	if _unit_selector.item_count > 0:
		_unit_selector.select(0)
		_on_unit_selected(0)
		_render_selected_snapshot()


func _build_semantic_controls() -> void:
	var left_stack := (
		_hud_shell.find_child("InRunLeftStack", true, false) as VBoxContainer
		if _hud_shell != null
		else null
	)
	var semantics_host: Control = left_stack if left_stack != null else self
	var ally_host := VBoxContainer.new()
	ally_host.name = "AllySemantics"
	ally_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_min(ally_host, 0.0, 42.0)
	var rarity_host := VBoxContainer.new()
	rarity_host.name = "RaritySemantics"
	rarity_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_min(rarity_host, 0.0, 42.0)
	for inspection: RunCombatIntelModel.InspectionIntelRow in _model.inspection_rows():
		var is_ally := inspection.side_id in [&"player", &"ally"]
		var kind := &"ally" if is_ally else &"enemy"
		var pattern := &"solid-border" if is_ally else &"cross-hatch"
		if is_ally:
			ally_host.add_child(_semantic_label(kind, inspection.source_id, pattern))
		if inspection.star > 0:
			rarity_host.add_child(_semantic_label(
				&"rarity",
				StringName("star.%d" % inspection.star),
				&"double-frame"
			))
	semantics_host.add_child(ally_host)
	semantics_host.add_child(rarity_host)

	# 每個 cue 是 InRunLeftStack 的獨立 Container row；父 VBox 持有排序與
	# 幾何，UI scale/status reflow 時不需任何座標重算或 frame polling。
	var enemy_host := VBoxContainer.new()
	enemy_host.name = "EnemySemantics"
	enemy_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_min(enemy_host, 0.0, 42.0)
	for row: RunCombatIntelModel.EnemyIntelRow in _model.enemy_rows():
		enemy_host.add_child(_semantic_label(
			&"enemy",
			row.unit_id,
			&"cross-hatch"
		))
	semantics_host.add_child(enemy_host)

	var trait_host := VBoxContainer.new()
	trait_host.name = "TraitSemantics"
	trait_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_min(trait_host, 0.0, 42.0)
	for trait_id: StringName in _model.active_trait_ids():
		trait_host.add_child(_semantic_label(
			&"trait",
			trait_id,
			&"linked-diamond"
		))
	semantics_host.add_child(trait_host)

	var danger_host := VBoxContainer.new()
	danger_host.name = "DangerSemantics"
	danger_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ExpeditionLayoutMetrics.set_min(danger_host, 0.0, 42.0)
	var danger_key := _current_node_danger_key()
	if not danger_key.is_empty():
		danger_host.add_child(_semantic_label(
			&"danger",
			danger_key,
			&"warning-stripes"
		))
	semantics_host.add_child(danger_host)


func _semantic_label(
	semantic_kind: StringName,
	typed_data_id: StringName,
	pattern: StringName
) -> Label:
	var label := Label.new()
	label.name = "%s%s" % [
		String(semantic_kind).to_pascal_case(),
		String(typed_data_id).replace(".", "_").to_pascal_case(),
	]
	label.text = _semantic_visible_text(semantic_kind, typed_data_id)
	label.set_meta(&"semantic_kind", semantic_kind)
	label.set_meta(&"typed_data_id", typed_data_id)
	label.set_meta(&"semantic_pattern", pattern)
	label.set_meta(&"accessible_text", label.text)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _semantic_visible_text(
	semantic_kind: StringName,
	typed_data_id: StringName
) -> String:
	if semantic_kind == &"danger":
		return _localized_ui_text(typed_data_id)
	if semantic_kind == &"rarity":
		return "%s %s" % [
			_localized_ui_text(&"combat.stat.star"),
			String(typed_data_id).get_slice(".", 1),
		]
	return _localized_content_text(typed_data_id)


func _on_unit_selected(index: int) -> void:
	if (
		_unit_selector == null
		or index < 0
		or index >= _unit_selector.item_count
	):
		_selected_unit_serial = -1
	else:
		_selected_unit_serial = int(
			_unit_selector.get_item_metadata(index)
		)
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.refresh_interaction_state()


func _render_selected_snapshot() -> void:
	if _snapshot == null or _selected_unit_serial <= 0:
		_clear_inspection_panel()
		return
	for inspection: CombatUnitInspectionSnapshot in _snapshot.combat_inspections:
		if inspection != null and inspection.unit_serial == _selected_unit_serial:
			_render_inspection(inspection)
			return
	_clear_inspection_panel()


func _render_inspection(
	snapshot: CombatUnitInspectionSnapshot
) -> void:
	_set_inspection_text(
		^"InspectionPanel/SourceValue",
		_localized_content_text(snapshot.source_id)
	)
	_set_inspection_text(
		^"InspectionPanel/TargetValue",
		_target_text(snapshot.target_serial)
	)
	_set_inspection_text(
		^"InspectionPanel/StatsValue",
		_stats_text(snapshot.stats)
	)
	_set_inspection_text(
		^"InspectionPanel/EquipmentValue",
		_join_names(snapshot.equipment_ids)
	)
	_set_inspection_text(
		^"InspectionPanel/TraitsValue",
		_join_names(snapshot.trait_ids)
	)
	_set_inspection_text(
		^"InspectionPanel/StatusesValue",
		_join_names(snapshot.status_ids)
	)


func _clear_inspection_panel() -> void:
	for path: NodePath in [
		^"InspectionPanel/SourceValue",
		^"InspectionPanel/TargetValue",
		^"InspectionPanel/StatsValue",
		^"InspectionPanel/EquipmentValue",
		^"InspectionPanel/TraitsValue",
		^"InspectionPanel/StatusesValue",
	]:
		_set_inspection_text(path, _localized_ui_text(INSPECTION_NONE_KEY))


func _set_inspection_text(path: NodePath, value: String) -> void:
	var label := find_child(
		String(path.get_name(path.get_name_count() - 1)), true, false
	) as Label
	if label != null:
		label.text = (
			value
			if not value.is_empty()
			else _localized_ui_text(INSPECTION_NONE_KEY)
		)


## 目標欄呈現目標單位的在地化名稱，不倒出內部 serial。
func _target_text(target_serial: int) -> String:
	if target_serial > 0:
		for row: RunCombatIntelModel.InspectionIntelRow in _model.inspection_rows():
			if row.unit_serial == target_serial:
				return _localized_content_text(row.source_id)
	return _localized_ui_text(INSPECTION_NONE_KEY)


## 數值欄以在地化欄位名＋數值呈現，不倒出 Dictionary 字面值。
func _stats_text(stats: Dictionary) -> String:
	var entries: Array[String] = []
	for stat_key: String in INSPECTION_STAT_ORDER:
		if not stats.has(stat_key):
			continue
		entries.append("%s %d" % [
			_localized_ui_text(StringName(STAT_TEXT_KEY_PREFIX + stat_key)),
			int(stats[stat_key]),
		])
	return (
		", ".join(entries)
		if not entries.is_empty()
		else _localized_ui_text(INSPECTION_NONE_KEY)
	)


func _localized_ui_text(text_key: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_ui_text(text_key)
		if parent_screen != null
		else String(text_key)
	)


func _join_names(values: Array[StringName]) -> String:
	var text_values: Array[String] = []
	for value: StringName in values:
		text_values.append(_localized_content_text(value))
	return ", ".join(text_values)


func _current_node_danger_key() -> StringName:
	if (
		_snapshot == null
		or _snapshot.map == null
		or _snapshot.map.current_node_id == null
	):
		return &""
	var current_node_id := _snapshot.map.current_node_id.value
	for node: MapNodeState in _snapshot.map.nodes:
		if node != null and node.node_id == current_node_id:
			return StringName(
				"map.node_kind.%s" % String(
					MapNodeState.node_kind_to_token(node.node_kind)
				)
			)
	return &""


func _remove_control(path: NodePath) -> void:
	var existing := find_child(
		String(path.get_name(path.get_name_count() - 1)), true, false
	)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()


func _build_hud_shell() -> void:
	var existing := find_child("InRunHudShell", true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()
	_hud_shell = InRunHudShell.new()
	_hud_shell.name = "InRunHudShell"
	add_child(_hud_shell)
	_hud_shell.bind(
		_snapshot,
		&"RUN_COMBAT",
		Callable(self, "_hud_region_rect"),
		Callable(self, "_localized_ui_text"),
		Callable(self, "_localized_content_text")
	)


func _suppress_legacy_accessibility_probe_surface() -> void:
	var parent_screen := get_parent() as ProductionScreen
	var runtime := (
		parent_screen.get_node_or_null(^"AccessibilityRuntime") as Control
		if parent_screen != null
		else null
	)
	if runtime != null:
		# Keep the established accessibility nodes alive as settings/runtime
		# semantics, but remove the old R13 diagnostic dashboard from the formal
		# CanvasItem tree. Child text, local visibility, typed metadata, and the
		# host report remain readable to assistive consumers and regression tests.
		runtime.visible = false
		runtime.mouse_filter = Control.MOUSE_FILTER_IGNORE
		runtime.set_meta(&"production_probe_surface_hidden", true)


func _hud_region_rect(region: StringName) -> Rect2:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.layout_region_content_rect(region)
		if parent_screen != null
		else Rect2()
	)


func _schedule_world_board_mount() -> void:
	if _snapshot == null or _world_board_mount_scheduled:
		return
	_world_board_mount_scheduled = true
	call_deferred(&"_mount_world_board")


func _mount_world_board() -> void:
	# Release the latch even when a detached deferred call is consumed. A later
	# NOTIFICATION_ENTER_TREE can then schedule the one required lifecycle retry.
	_world_board_mount_scheduled = false
	if not is_inside_tree() or _snapshot == null:
		return
	var overlay_mount: Control = (
		_hud_shell.host(ProductionLayoutShell.REGION_OVERLAY)
		if _hud_shell != null
		else null
	)
	var mount_error := ProductionWorldSurface.INVALID_OVERLAY_MOUNT
	if overlay_mount != null:
		mount_error = WorldBoardMountAdapter.mount(
			get_tree(),
			_combat_world_projection.snapshot_clone(),
			Callable(),
			overlay_mount
		)
	_world_board_mount_error = mount_error
	if not mount_error.is_empty():
		_mark_world_board_not_ready()
		_report_world_board_mount_error(mount_error)
		return
	_world_board_ready = true
	_clear_owned_world_board_mount_error()
	# Mount success is not itself a presented frame. Force a CanvasItem draw so
	# the first-frame latch can open only after the recovered board is drawable.
	queue_redraw()


func world_board_mount_error() -> StringName:
	return _world_board_mount_error


func _mark_world_board_not_ready() -> void:
	_world_board_ready = false
	_first_frame_presented = false


func _report_world_board_mount_error(_error_code: StringName) -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen == null:
		return
	parent_screen.report_composition_result(AppActionResult.failure(
		DiagnosticError.new(
			&"RENDER_FAILED",
			&"error.presentation.render_failed"
		)
	))
	_world_board_render_status_signature = parent_screen.status_report().duplicate(
		true
	)


func _clear_owned_world_board_mount_error() -> void:
	if _world_board_render_status_signature.is_empty():
		return
	var parent_screen := get_parent() as ProductionScreen
	if (
		parent_screen != null
		and parent_screen.status_report() == _world_board_render_status_signature
	):
		parent_screen.report_composition_result(AppActionResult.success())
	_world_board_render_status_signature.clear()


func _localized_content_text(content_id: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_content_text(content_id)
		if parent_screen != null
		else String(content_id)
	)


func _tooltip_text(
	label_key: StringName,
	numeric_value: int,
	depth: int = 1
) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.content_tooltip_text(
			label_key, numeric_value, depth
		)
		if parent_screen != null
		else ""
	)
