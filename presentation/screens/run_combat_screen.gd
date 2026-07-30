class_name RunCombatScreen
extends ProductionScreen

const PLAYBACK_PORT_ALREADY_BOUND: StringName = &"PLAYBACK_PORT_ALREADY_BOUND"
const INSPECTION_PORT_ALREADY_BOUND: StringName = \
	&"INSPECTION_PORT_ALREADY_BOUND"
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
var _playback_port: LiveScreenPlaybackPort
var _inspection_port: LiveScreenInspectionPort
var _snapshot: RunPresentationSnapshot
var _unit_selector: ItemList
var _selected_unit_serial: int = -1


func compose(
	snapshot: RunPresentationSnapshot,
	_intent_port: LiveScreenIntentPort
) -> StringName:
	var error_code := _model.compose(snapshot)
	if not error_code.is_empty():
		_snapshot = null
		return error_code
	_snapshot = snapshot.deep_clone()
	_selected_unit_serial = -1
	_build_typed_combat_controls()
	return &""


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
		var parent_screen := get_parent() as ProductionScreen
		var accessibility := (
			parent_screen.get_node_or_null(^"AccessibilityRuntime")
			as ProductionAccessibilityHost
			if parent_screen != null
			else null
		)
		if accessibility != null:
			accessibility.render_damage_events(result.window.events)
	return result


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
	_unit_selector.position = Vector2(72.0, 112.0)
	_unit_selector.custom_minimum_size = Vector2(360.0, 180.0)
	_unit_selector.size = Vector2(360.0, 180.0)
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
			_unit_selector.set_item_metadata(
				_unit_selector.item_count - 1,
				row.unit_serial
			)
	else:
		var rows := _model.enemy_rows()
		for index: int in rows.size():
			var row := rows[index] as RunCombatIntelModel.EnemyIntelRow
			_unit_selector.add_item(_localized_content_text(row.unit_id))
			_unit_selector.set_item_metadata(index, index + 1)
	_unit_selector.item_selected.connect(_on_unit_selected)
	add_child(_unit_selector)

	var panel := VBoxContainer.new()
	panel.name = "InspectionPanel"
	panel.position = Vector2(456.0, 112.0)
	panel.custom_minimum_size = Vector2(520.0, 240.0)
	panel.size = Vector2(520.0, 240.0)
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
		label.text = String(value_name)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(label)
	add_child(panel)
	_build_semantic_controls()


func _build_semantic_controls() -> void:
	var ally_host := VBoxContainer.new()
	ally_host.name = "AllySemantics"
	ally_host.position = Vector2(72.0, 320.0)
	var rarity_host := VBoxContainer.new()
	rarity_host.name = "RaritySemantics"
	rarity_host.position = Vector2(264.0, 320.0)
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
	add_child(ally_host)
	add_child(rarity_host)

	var enemy_host := VBoxContainer.new()
	enemy_host.name = "EnemySemantics"
	enemy_host.position = Vector2(72.0, 320.0)
	for row: RunCombatIntelModel.EnemyIntelRow in _model.enemy_rows():
		enemy_host.add_child(_semantic_label(
			&"enemy",
			row.unit_id,
			&"cross-hatch"
		))
	add_child(enemy_host)

	var trait_host := VBoxContainer.new()
	trait_host.name = "TraitSemantics"
	trait_host.position = Vector2(72.0, 440.0)
	for trait_id: StringName in _model.active_trait_ids():
		trait_host.add_child(_semantic_label(
			&"trait",
			trait_id,
			&"linked-diamond"
		))
	add_child(trait_host)

	var danger_host := VBoxContainer.new()
	danger_host.name = "DangerSemantics"
	danger_host.position = Vector2(456.0, 384.0)
	danger_host.custom_minimum_size = Vector2(520.0, 0.0)
	danger_host.size = Vector2(520.0, 0.0)
	var current_node_id := _current_node_id()
	if not current_node_id.is_empty():
		danger_host.add_child(_semantic_label(
			&"danger",
			StringName(current_node_id),
			&"warning-stripes"
		))
	add_child(danger_host)


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
	var prefix: String = {
		&"ally": "[A|solid]",
		&"enemy": "[E|cross]",
		&"trait": "[T|linked]",
		&"rarity": "[R|double]",
		&"danger": "[!|stripes]",
	}.get(semantic_kind, "[?]")
	label.text = "%s %s" % [prefix, _localized_content_text(typed_data_id)]
	label.set_meta(&"semantic_kind", semantic_kind)
	label.set_meta(&"typed_data_id", typed_data_id)
	label.set_meta(&"semantic_pattern", pattern)
	label.set_meta(&"accessible_text", label.text)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


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


func _render_inspection(
	snapshot: CombatUnitInspectionSnapshot
) -> void:
	_set_inspection_text(^"InspectionPanel/SourceValue", String(snapshot.source_id))
	_set_inspection_text(
		^"InspectionPanel/TargetValue",
		str(snapshot.target_serial)
	)
	_set_inspection_text(^"InspectionPanel/StatsValue", str(snapshot.stats))
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
		_set_inspection_text(path, "-")


func _set_inspection_text(path: NodePath, value: String) -> void:
	var label := get_node_or_null(path) as Label
	if label != null:
		label.text = value if not value.is_empty() else "-"


func _join_names(values: Array[StringName]) -> String:
	var text_values: Array[String] = []
	for value: StringName in values:
		text_values.append(_localized_content_text(value))
	return ", ".join(text_values)


func _current_node_id() -> String:
	if (
		_snapshot == null
		or _snapshot.map == null
		or _snapshot.map.current_node_id == null
	):
		return ""
	return _snapshot.map.current_node_id.value


func _remove_control(path: NodePath) -> void:
	var existing := get_node_or_null(path)
	if existing != null:
		remove_child(existing)
		existing.queue_free()


func _localized_content_text(content_id: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_content_text(content_id)
		if parent_screen != null
		else String(content_id)
	)
