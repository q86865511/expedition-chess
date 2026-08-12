class_name CampWorldScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"CAMP_WORLD_COMPOSE_INVALID"
const FACILITY_ROUTE_INVALID: StringName = &"CAMP_FACILITY_ROUTE_INVALID"
const FACILITY_ROUTES: Array[StringName] = [
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
]
const EXPEDITION_SELECTION_REQUIRED: StringName = \
	&"CAMP_EXPEDITION_SELECTION_REQUIRED"

var _bundle: CampFacilityBundle
var _navigation_port: LiveScreenNavigationPort
var _selected_commander_id: StringName = &""
var _selected_challenge_level: int = -1
var _commander_selector: OptionButton
var _challenge_selector: SpinBox
var _layout_root: Control
var _commander_summary: Label
var _challenge_summary: Label


func compose(
	profile: ProfileState,
	navigation_port: LiveScreenNavigationPort
) -> StringName:
	if profile == null or navigation_port == null:
		return COMPOSE_INVALID
	_bundle = CampFacilityBundle.new(profile)
	_navigation_port = navigation_port
	_selected_commander_id = &""
	_selected_challenge_level = 0
	_build_expedition_controls()
	if _commander_selector.item_count > 0:
		_commander_selector.select(0)
		_selected_commander_id = StringName(
			_commander_selector.get_item_metadata(0)
		)
	_refresh_center_summary()
	return &""


func projection_digest() -> String:
	return _bundle.projection_digest() if _bundle != null else ""


func facility_routes() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(FACILITY_ROUTES)
	return result


func open_facility(route: StringName) -> AppActionResult:
	if _navigation_port == null or not FACILITY_ROUTES.has(route):
		return AppActionResult.failure(
			DiagnosticError.new(
				FACILITY_ROUTE_INVALID,
				&"error.presentation.camp_facility_route_invalid"
			)
		)
	return _navigation_port.navigate(route)


func select_expedition(
	commander_id: StringName,
	challenge_level: int
) -> StringName:
	if commander_id.is_empty() or challenge_level < 0:
		return EXPEDITION_SELECTION_REQUIRED
	_selected_commander_id = commander_id
	_selected_challenge_level = challenge_level
	return &""


func selected_expedition_request() -> StartExpeditionRequest:
	if _selected_commander_id.is_empty() or _selected_challenge_level < 0:
		return null
	return StartExpeditionRequest.new(
		_selected_commander_id,
		_selected_challenge_level
	)


func _build_expedition_controls() -> void:
	_remove_control(&"CampContent")
	_layout_root = Control.new()
	_layout_root.name = "CampContent"
	_layout_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout_root)
	var metrics := HBoxContainer.new()
	metrics.name = "CampMetrics"
	var metrics_rect := _region_content_rect(ProductionLayoutShell.REGION_TOP)
	metrics_rect.position.x += ProductionLayoutShell.TITLE_COLUMN_WIDTH
	metrics_rect.size.x -= ProductionLayoutShell.TITLE_COLUMN_WIDTH
	metrics.position = metrics_rect.position
	metrics.size = metrics_rect.size
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_root.add_child(metrics)
	metrics.add_child(_metric_label(
		&"camp.resource.currency",
		str(_bundle.workshop_currency())
	))
	metrics.add_child(_metric_label(
		&"camp.resource.challenge",
		str(_bundle.highest_challenge_level())
	))
	metrics.add_child(_metric_label(
		&"camp.resource.discovered",
		str(_bundle.discovered_ids().size())
	))
	var center := VBoxContainer.new()
	center.name = "CampCenterSummary"
	var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
	center.position = center_rect.position
	center.size = center_rect.size
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_root.add_child(center)
	var center_heading := Label.new()
	center_heading.text = _localized_ui_text(&"camp.commander_selector")
	center_heading.theme_type_variation = &"ExpeditionHeading"
	center.add_child(center_heading)
	_commander_summary = Label.new()
	_commander_summary.name = "CommanderSummary"
	_commander_summary.theme_type_variation = &"ExpeditionTitle"
	_commander_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commander_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_commander_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_child(_commander_summary)
	_challenge_summary = Label.new()
	_challenge_summary.name = "ChallengeSummary"
	_challenge_summary.theme_type_variation = &"ExpeditionMetric"
	center.add_child(_challenge_summary)
	center.add_child(_metric_label(
		&"camp.resource.discovered",
		str(_bundle.discovered_ids().size())
	))
	var expedition_panel := VBoxContainer.new()
	expedition_panel.name = "ExpeditionPanelContent"
	var expedition_rect := _region_content_rect(
		ProductionLayoutShell.REGION_RIGHT
	)
	expedition_panel.position = expedition_rect.position
	expedition_panel.size = expedition_rect.size
	expedition_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_root.add_child(expedition_panel)
	var heading := Label.new()
	heading.text = _localized_ui_text(&"camp.panel.expedition")
	heading.theme_type_variation = &"ExpeditionHeading"
	expedition_panel.add_child(heading)
	var commander_label := Label.new()
	commander_label.text = _localized_ui_text(&"camp.commander_selector")
	commander_label.theme_type_variation = &"ExpeditionAuxiliary"
	expedition_panel.add_child(commander_label)
	_commander_selector = OptionButton.new()
	_commander_selector.name = "CommanderSelector"
	ExpeditionLayoutMetrics.set_min(_commander_selector, 0.0, 72.0)
	_commander_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commander_selector.focus_mode = Control.FOCUS_ALL
	_commander_selector.allow_reselect = true
	_commander_selector.set_meta(&"typed_choice_kind", &"commander")
	_commander_selector.set_meta(
		&"accessible_text",
		&"camp.commander_selector"
	)
	for commander_id: StringName in _bundle.commander_ids():
		_commander_selector.add_item(
			_localized_content_text(commander_id)
		)
		var index := _commander_selector.item_count - 1
		_commander_selector.set_item_metadata(index, commander_id)
	_commander_selector.item_selected.connect(_on_commander_selected)
	expedition_panel.add_child(_commander_selector)

	var challenge_label := Label.new()
	challenge_label.text = _localized_ui_text(&"camp.challenge_selector")
	challenge_label.theme_type_variation = &"ExpeditionAuxiliary"
	expedition_panel.add_child(challenge_label)
	_challenge_selector = SpinBox.new()
	_challenge_selector.name = "ChallengeSelector"
	ExpeditionLayoutMetrics.set_min(_challenge_selector, 0.0, 72.0)
	_challenge_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_selector.focus_mode = Control.FOCUS_ALL
	_challenge_selector.min_value = 0.0
	_challenge_selector.max_value = float(
		maxi(_bundle.highest_challenge_level() + 1, 0)
	)
	_challenge_selector.step = 1.0
	_challenge_selector.value = 0.0
	_challenge_selector.set_meta(&"typed_choice_kind", &"challenge")
	_challenge_selector.set_meta(
		&"accessible_text",
		&"camp.challenge_selector"
	)
	_challenge_selector.value_changed.connect(_on_challenge_selected)
	expedition_panel.add_child(_challenge_selector)


func _metric_label(key: StringName, value: String) -> Label:
	var label := Label.new()
	label.text = "%s  %s" % [_localized_ui_text(key), value]
	label.theme_type_variation = &"ExpeditionMetric"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _region_content_rect(region: StringName) -> Rect2:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.layout_region_content_rect(region)
		if parent_screen != null
		else Rect2()
	)


func _on_commander_selected(index: int) -> void:
	if (
		_commander_selector == null
		or index < 0
		or index >= _commander_selector.item_count
	):
		_selected_commander_id = &""
	else:
		_selected_commander_id = StringName(
			_commander_selector.get_item_metadata(index)
		)
	_refresh_center_summary()
	_update_parent_action_state()


func _on_challenge_selected(value: float) -> void:
	_selected_challenge_level = roundi(value)
	_refresh_center_summary()
	_update_parent_action_state()


func _refresh_center_summary() -> void:
	if _commander_summary != null:
		_commander_summary.text = (
			_localized_content_text(_selected_commander_id)
			if not _selected_commander_id.is_empty()
			else _localized_ui_text(&"camp.commander_selector")
		)
	if _challenge_summary != null:
		_challenge_summary.text = "%s  %d" % [
			_localized_ui_text(&"camp.challenge_selector"),
			maxi(_selected_challenge_level, 0),
		]


func refresh_layout_rects() -> void:
	var metrics := find_child("CampMetrics", true, false) as Control
	if metrics != null:
		var metrics_rect := _region_content_rect(ProductionLayoutShell.REGION_TOP)
		metrics_rect.position.x += ProductionLayoutShell.TITLE_COLUMN_WIDTH
		metrics_rect.size.x -= ProductionLayoutShell.TITLE_COLUMN_WIDTH
		metrics.position = metrics_rect.position
		metrics.size = metrics_rect.size
	var center := find_child("CampCenterSummary", true, false) as Control
	if center != null:
		var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
		center.position = center_rect.position
		center.size = center_rect.size
	var expedition := find_child("ExpeditionPanelContent", true, false) as Control
	if expedition != null:
		var expedition_rect := _region_content_rect(ProductionLayoutShell.REGION_RIGHT)
		expedition.position = expedition_rect.position
		expedition.size = expedition_rect.size


func _update_parent_action_state() -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen != null:
		parent_screen.refresh_interaction_state()


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


func _remove_control(node_name: StringName) -> void:
	var existing := find_child(String(node_name), true, false)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.queue_free()
