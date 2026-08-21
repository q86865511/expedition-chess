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
const CAMP_VISUAL_ID: StringName = &"environment.camp"
const METRIC_WIDTH: float = 216.0
## CAMP top metrics keep a route-local gap for the mouse entry to the ESC menu.
## The button itself is owned by ProductionScreen; this reservation prevents the
## third metric from rendering underneath it at every supported UI scale.
const SYSTEM_MENU_RESERVE_WIDTH: float = 294.0
const FACILITY_MARKERS: Array[Dictionary] = [
	{
		"name": "FacilityExpeditionGate",
		"key": &"camp.expedition_gate",
		"anchor": Vector2(0.22, 0.22),
	},
	{
		"name": "FacilityCommanderHall",
		"key": &"camp.commander_hall",
		"anchor": Vector2(0.20, 0.73),
	},
	{
		"name": "FacilityCollection",
		"key": &"camp.collection",
		"anchor": Vector2(0.79, 0.72),
	},
	{
		"name": "FacilityWorkshop",
		"key": &"camp.forge",
		"anchor": Vector2(0.79, 0.22),
	},
	{
		"name": "FacilityChallengeMonument",
		"key": &"camp.challenge_monument",
		"anchor": Vector2(0.50, 0.50),
	},
]

var _bundle: CampFacilityBundle
var _navigation_port: LiveScreenNavigationPort
var _selected_commander_id: StringName = &""
var _selected_challenge_level: int = -1
var _commander_selector: OptionButton
var _challenge_selector: SpinBox
var _layout_root: Control
var _environment_visuals := ProductionEnvironmentVisualCatalog.new()


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
	metrics.theme_type_variation = &"ExpeditionCampMetrics"
	metrics.alignment = BoxContainer.ALIGNMENT_END
	var metrics_rect := _camp_metrics_rect()
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
	var center_rect := _region_content_rect(ProductionLayoutShell.REGION_CENTER)
	_build_environment_visual(center_rect)
	var expedition_panel := VBoxContainer.new()
	expedition_panel.name = "ExpeditionPanelContent"
	expedition_panel.theme_type_variation = &"ExpeditionCampExpeditionPanel"
	var expedition_rect := _region_content_rect(
		ProductionLayoutShell.REGION_RIGHT
	)
	expedition_panel.position = expedition_rect.position
	expedition_panel.size = expedition_rect.size
	expedition_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_root.add_child(expedition_panel)
	var heading := Label.new()
	heading.text = _localized_ui_text(&"camp.panel.expedition")
	heading.theme_type_variation = &"ExpeditionCampCardHeading"
	expedition_panel.add_child(heading)
	var commander_label := Label.new()
	commander_label.text = _localized_ui_text(&"camp.commander_selector")
	commander_label.theme_type_variation = &"ExpeditionCampCardLabel"
	expedition_panel.add_child(commander_label)
	_commander_selector = OptionButton.new()
	_commander_selector.name = "CommanderSelector"
	_commander_selector.theme_type_variation = &"ExpeditionCampCompactChoice"
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
	challenge_label.theme_type_variation = &"ExpeditionCampCardLabel"
	expedition_panel.add_child(challenge_label)
	_challenge_selector = SpinBox.new()
	_challenge_selector.name = "ChallengeSelector"
	_challenge_selector.theme_type_variation = &"ExpeditionCampCompactSpinBox"
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
	var challenge_input := _challenge_selector.get_line_edit()
	if challenge_input != null:
		challenge_input.theme_type_variation = &"ExpeditionCampCompactInput"
	var start := _take_staged_action(&"camp.start")
	if start != null:
		start.name = "CampStartAction"
		start.visible = true
		start.theme_type_variation = &"ExpeditionCampStartAction"
		ExpeditionLayoutMetrics.set_min(start, 0.0, 72.0)
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		expedition_panel.add_child(start)
	_discard_empty_action_staging()


func _build_environment_visual(rect: Rect2) -> void:
	var frame := PanelContainer.new()
	frame.name = "CampEnvironmentView"
	frame.position = rect.position
	frame.size = rect.size
	frame.theme_type_variation = &"ExpeditionCampMapFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	_layout_root.add_child(frame)
	var canvas := Control.new()
	canvas.name = "CampEnvironmentCanvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.clip_contents = true
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(canvas)
	var environment := TextureRect.new()
	environment.name = "CampEnvironmentTexture"
	environment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	environment.texture = _environment_visuals.try_texture(CAMP_VISUAL_ID)
	environment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	environment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	environment.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	environment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	environment.set_meta(&"visual_id", CAMP_VISUAL_ID)
	canvas.add_child(environment)
	for marker_spec: Dictionary in FACILITY_MARKERS:
		_add_facility_marker(canvas, marker_spec)


func _add_facility_marker(canvas: Control, marker_spec: Dictionary) -> void:
	var localization_key := StringName(marker_spec["key"])
	var marker := _take_staged_action(localization_key)
	if marker == null:
		return
	marker.name = String(marker_spec["name"])
	marker.visible = true
	marker.theme_type_variation = &"ExpeditionCampFacilityMarker"
	marker.focus_mode = Control.FOCUS_ALL
	marker.mouse_filter = Control.MOUSE_FILTER_STOP
	marker.z_index = 2
	ExpeditionLayoutMetrics.set_min(
		marker,
		ExpeditionLayoutMetrics.CAMP_FACILITY_MARKER_SIZE.x,
		ExpeditionLayoutMetrics.CAMP_FACILITY_MARKER_SIZE.y
	)
	marker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	canvas.add_child(marker)
	var anchor := marker_spec["anchor"] as Vector2
	marker.anchor_left = anchor.x
	marker.anchor_right = anchor.x
	marker.anchor_top = anchor.y
	marker.anchor_bottom = anchor.y
	marker.offset_left = -ExpeditionLayoutMetrics.CAMP_FACILITY_MARKER_SIZE.x * 0.5
	marker.offset_right = ExpeditionLayoutMetrics.CAMP_FACILITY_MARKER_SIZE.x * 0.5
	marker.offset_top = -ExpeditionLayoutMetrics.CAMP_FACILITY_MARKER_SIZE.y * 0.5
	marker.offset_bottom = ExpeditionLayoutMetrics.CAMP_FACILITY_MARKER_SIZE.y * 0.5
	marker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	marker.grow_vertical = Control.GROW_DIRECTION_BOTH
	marker.set_meta(&"facility_localization_key", localization_key)
	marker.focus_entered.connect(_show_facility_context.bind(marker))
	marker.mouse_entered.connect(_show_facility_context.bind(marker))


func _show_facility_context(marker: Button) -> void:
	if marker == null:
		return
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen == null:
		return
	var context := parent_screen.find_child(
		"CampFacilityContext", true, false
	) as Label
	if context == null:
		return
	context.text = marker.text
	context.set_meta(
		&"facility_localization_key",
		marker.get_meta(&"facility_localization_key", &"")
	)


func _metric_label(key: StringName, value: String) -> Label:
	var label := Label.new()
	label.text = "%s  %s" % [_localized_ui_text(key), value]
	label.theme_type_variation = &"ExpeditionCampMetric"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	ExpeditionLayoutMetrics.set_fixed_min(label, METRIC_WIDTH, 0.0)
	return label


func _camp_metrics_rect() -> Rect2:
	var rect := _region_content_rect(ProductionLayoutShell.REGION_TOP)
	var total_width := METRIC_WIDTH * 3.0 + 24.0
	rect.position.x = rect.end.x - SYSTEM_MENU_RESERVE_WIDTH - total_width
	rect.size.x = total_width
	return rect


func _take_staged_action(action_id: StringName) -> Button:
	var staging := find_child("CampActionStaging", true, false) as Control
	if staging == null:
		return null
	for node: Node in staging.get_children():
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			staging.remove_child(button)
			return button
	return null


func _discard_empty_action_staging() -> void:
	var staging := find_child("CampActionStaging", true, false) as Control
	if staging != null and staging.get_child_count() == 0:
		staging.queue_free()


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
	_update_parent_action_state()


func _on_challenge_selected(value: float) -> void:
	_selected_challenge_level = roundi(value)
	_update_parent_action_state()


func refresh_layout_rects() -> void:
	var metrics := find_child("CampMetrics", true, false) as Control
	if metrics != null:
		var metrics_rect := _camp_metrics_rect()
		metrics.position = metrics_rect.position
		metrics.size = metrics_rect.size
	var center := find_child("CampEnvironmentView", true, false) as Control
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
