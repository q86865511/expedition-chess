class_name CampFacilityScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"CAMP_FACILITY_COMPOSE_INVALID"

var _bundle: CampFacilityBundle
var _navigation_port: LiveScreenNavigationPort
var _visuals := ProductionUnitVisualCatalog.new()
var _commander_visuals := ProductionCommanderVisualCatalog.new()
var _ui_scale_percent: int = 100


func compose(
	profile: ProfileState,
	navigation_port: LiveScreenNavigationPort
) -> StringName:
	if profile == null or navigation_port == null:
		return COMPOSE_INVALID
	_bundle = CampFacilityBundle.new(profile)
	_navigation_port = navigation_port
	_build_facility_data()
	return &""


func projection_digest() -> String:
	return _bundle.projection_digest() if _bundle != null else ""


func expedition_last_commander() -> StringName:
	return (
		_bundle.expedition_last_commander()
		if _bundle != null
		else &""
	)


func expedition_last_selection() -> ProfileLastSelectionState:
	return (
		_bundle.expedition_last_selection()
		if _bundle != null
		else null
	)


func commander_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if _bundle != null:
		result.assign(_bundle.commander_ids())
	return result


func discovered_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if _bundle != null:
		result.assign(_bundle.discovered_ids())
	return result


func unlocked_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if _bundle != null:
		result.assign(_bundle.unlocked_ids())
	return result


func challenge_records() -> Array[CommanderChallengeRecordState]:
	var result: Array[CommanderChallengeRecordState] = []
	if _bundle != null:
		result.assign(_bundle.challenge_records())
	return result


func workshop_currency() -> int:
	return _bundle.workshop_currency() if _bundle != null else 0


func highest_challenge_level() -> int:
	return _bundle.highest_challenge_level() if _bundle != null else 0


func return_to_camp() -> AppActionResult:
	if _navigation_port == null:
		return AppActionResult.failure(
			DiagnosticError.new(
				COMPOSE_INVALID,
				&"error.presentation.camp_facility_compose_invalid"
			)
		)
	return _navigation_port.navigate(&"CAMP_WORLD")


func _build_facility_data() -> void:
	var existing := get_node_or_null(^"FacilityContent")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	var content := VBoxContainer.new()
	content.name = "FacilityContent"
	content.theme_type_variation = &"ExpeditionFacilityContent"
	content.set_meta(&"typed_data_kind", _parent_route_kind())
	add_child(content)
	var stat_card := PanelContainer.new()
	stat_card.name = "FacilityStatCard"
	stat_card.theme_type_variation = &"ExpeditionResultsMetricCard"
	ExpeditionLayoutMetrics.set_fixed_min(
		stat_card, 0.0, ExpeditionLayoutMetrics.FACILITY_STAT_CARD_HEIGHT
	)
	content.add_child(stat_card)
	var stat_value := Label.new()
	stat_value.name = "FacilityStatValue"
	stat_value.theme_type_variation = &"ExpeditionResultsMetric"
	stat_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stat_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_card.add_child(stat_value)
	var data := ItemList.new()
	data.name = "FacilityData"
	data.theme_type_variation = &"ExpeditionFacilityCardGrid"
	data.focus_mode = Control.FOCUS_ALL
	data.allow_reselect = true
	data.icon_mode = ItemList.ICON_MODE_TOP
	data.same_column_width = true
	data.fixed_column_width = roundi(
		ExpeditionLayoutMetrics.FACILITY_CARD_WIDTH
	)
	data.fixed_icon_size = Vector2i.ONE * roundi(
		ExpeditionLayoutMetrics.FACILITY_CARD_ICON_SIZE
	)
	data.size_flags_vertical = Control.SIZE_EXPAND_FILL
	data.set_meta(&"typed_data_kind", _parent_route_kind())
	data.set_meta(&"portrait_catalog_error", _visuals.load_error())
	var values: Array[StringName] = []
	var route := _parent_route_kind()
	match _parent_route_kind():
		&"FACILITY_COMMANDER_HALL":
			values.assign(commander_ids())
			stat_value.text = "%s  %d" % [
				_localized_ui_text(&"camp.commander_selector"), values.size()
			]
		&"FACILITY_EXPEDITION_GATE":
			values.assign(commander_ids())
			stat_value.text = _expedition_summary_text()
		&"COLLECTION":
			values.assign(discovered_ids())
		&"FACILITY_CHALLENGE_MONUMENT":
			stat_value.text = "%s  %d" % [
				_localized_ui_text(&"camp.resource.challenge"),
				highest_challenge_level(),
			]
			for record: CommanderChallengeRecordState in challenge_records():
				data.add_item("%s  ·  %s %d" % [
					_localized_content_text(record.commander_id),
					_localized_ui_text(&"camp.resource.challenge"),
					record.highest_cleared_level,
				])
				data.set_item_metadata(data.item_count - 1, record.commander_id)
		&"FACILITY_UNLOCK_WORKSHOP":
			values.assign(unlocked_ids())
			stat_value.text = "%s  %d" % [
				_localized_ui_text(&"camp.resource.currency"), workshop_currency()
			]
	for value: StringName in values:
		var portrait := _facility_portrait(value)
		var state_prefix := "✓ " if route == &"FACILITY_UNLOCK_WORKSHOP" else ""
		data.add_item(state_prefix + _localized_content_text(value), portrait)
		data.set_item_metadata(data.item_count - 1, value)
		data.set_item_tooltip(
			data.item_count - 1,
			_localized_content_text(value)
		)
		if route == &"COLLECTION":
			data.set_meta(&"semantic_kind", &"rarity")
			data.set_meta(&"semantic_pattern", &"double-frame")
		if route == &"FACILITY_UNLOCK_WORKSHOP":
			data.set_item_metadata(data.item_count - 1, {
				"content_id": value,
				"lock_state": &"unlocked",
			})
	if stat_value.text.is_empty():
		stat_value.text = "%s  %d" % [
			_localized_ui_text(&"camp.resource.discovered"), values.size()
		]
	var accessible_rows := PackedStringArray()
	for index: int in data.item_count:
		accessible_rows.append(data.get_item_text(index))
	data.set_meta(&"accessible_text", "\n".join(accessible_rows))
	content.add_child(data)
	var empty_state := Label.new()
	empty_state.name = "FacilityEmptyState"
	empty_state.theme_type_variation = &"ExpeditionDetail"
	empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_state.text = _facility_empty_text(route)
	empty_state.visible = data.item_count == 0
	empty_state.set_meta(&"lock_state", &"locked")
	empty_state.set_meta(&"accessible_text", empty_state.text)
	ExpeditionLayoutMetrics.set_fixed_min(empty_state, 0.0, 72.0)
	content.add_child(empty_state)
	data.visible = data.item_count > 0
	data.focus_mode = (
		Control.FOCUS_ALL if data.item_count > 0 else Control.FOCUS_NONE
	)
	_apply_card_metrics()
	refresh_layout_rects()


func _facility_portrait(content_id: StringName) -> Texture2D:
	if String(content_id).begins_with("commander."):
		return _commander_visuals.try_portrait(content_id)
	return _visuals.try_portrait(content_id)


func apply_theme_scale_layout(scale_percent: int) -> void:
	_ui_scale_percent = clampi(scale_percent, 100, 150)
	_apply_card_metrics()
	refresh_layout_rects()


func refresh_layout_rects() -> void:
	var content := get_node_or_null(^"FacilityContent") as VBoxContainer
	var parent_screen := get_parent() as ProductionScreen
	if content == null or parent_screen == null:
		return
	var rect := parent_screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_CENTER
	)
	content.position = rect.position
	content.size = rect.size


func _apply_card_metrics() -> void:
	var data := get_node_or_null(
		^"FacilityContent/FacilityData"
	) as ItemList
	if data == null:
		return
	var factor := float(_ui_scale_percent) / 100.0
	data.fixed_column_width = roundi(
		ExpeditionLayoutMetrics.FACILITY_CARD_WIDTH * factor
	)
	data.fixed_icon_size = Vector2i.ONE * roundi(
		ExpeditionLayoutMetrics.FACILITY_CARD_ICON_SIZE * factor
	)


func _expedition_summary_text() -> String:
	var selection := expedition_last_selection()
	if selection == null:
		return "%s  ·  %s" % [
			_localized_ui_text(&"prepare.panel.expedition"),
			_localized_ui_text(&"combat.inspection.none"),
		]
	return "%s  %s\n%s  %d" % [
		_localized_ui_text(&"camp.commander_selector"),
		_localized_content_text(selection.commander_id),
		_localized_ui_text(&"camp.challenge_selector"),
		selection.challenge_level,
	]


func _facility_empty_text(route: StringName) -> String:
	var label_key := &"collection.category.content"
	match route:
		&"FACILITY_COMMANDER_HALL", &"FACILITY_EXPEDITION_GATE":
			label_key = &"camp.commander_selector"
		&"FACILITY_CHALLENGE_MONUMENT":
			label_key = &"camp.resource.challenge"
	return "◇ %s：%s" % [
		_localized_ui_text(label_key),
		_localized_ui_text(&"combat.inspection.none"),
	]


func _parent_route_kind() -> StringName:
	var parent_screen := get_parent() as ProductionScreen
	return parent_screen.route_kind if parent_screen != null else &""


func _localized_content_text(content_id: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_content_text(content_id)
		if parent_screen != null
		else String(content_id)
	)


func _localized_ui_text(key: StringName) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.localized_ui_text(key)
		if parent_screen != null
		else String(key)
	)
