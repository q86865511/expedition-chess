class_name CampFacilityScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"CAMP_FACILITY_COMPOSE_INVALID"
const CARD_WIDTH: float = 300.0
const CARD_ICON_SIZE: float = 144.0

var _bundle: CampFacilityBundle
var _navigation_port: LiveScreenNavigationPort
var _visuals := ProductionUnitVisualCatalog.new()
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
	var existing := get_node_or_null(^"FacilityData")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	var data := ItemList.new()
	data.name = "FacilityData"
	data.theme_type_variation = &"ExpeditionFacilityCardGrid"
	data.focus_mode = Control.FOCUS_ALL
	data.allow_reselect = true
	data.icon_mode = ItemList.ICON_MODE_TOP
	data.same_column_width = true
	data.fixed_column_width = roundi(CARD_WIDTH)
	data.fixed_icon_size = Vector2i.ONE * roundi(CARD_ICON_SIZE)
	data.set_meta(&"typed_data_kind", _parent_route_kind())
	data.set_meta(&"portrait_catalog_error", _visuals.load_error())
	var values: Array[StringName] = []
	match _parent_route_kind():
		&"FACILITY_COMMANDER_HALL", &"FACILITY_EXPEDITION_GATE":
			values.assign(commander_ids())
		&"COLLECTION":
			values.assign(discovered_ids())
		&"FACILITY_CHALLENGE_MONUMENT":
			values.append(StringName(str(highest_challenge_level())))
		&"FACILITY_UNLOCK_WORKSHOP":
			values.append(StringName(str(workshop_currency())))
	for value: StringName in values:
		var portrait := _visuals.try_portrait(value)
		data.add_item(_localized_content_text(value), portrait)
		data.set_item_metadata(data.item_count - 1, value)
		data.set_item_tooltip(
			data.item_count - 1,
			_localized_content_text(value)
		)
		if _parent_route_kind() == &"COLLECTION":
			data.set_meta(&"semantic_kind", &"rarity")
			data.set_meta(&"semantic_pattern", &"double-frame")
	var accessible_rows := PackedStringArray()
	for index: int in data.item_count:
		accessible_rows.append(data.get_item_text(index))
	data.set_meta(&"accessible_text", "\n".join(accessible_rows))
	add_child(data)
	_apply_card_metrics()
	refresh_layout_rects()


func apply_theme_scale_layout(scale_percent: int) -> void:
	_ui_scale_percent = clampi(scale_percent, 100, 150)
	_apply_card_metrics()
	refresh_layout_rects()


func refresh_layout_rects() -> void:
	var data := get_node_or_null(^"FacilityData") as ItemList
	var parent_screen := get_parent() as ProductionScreen
	if data == null or parent_screen == null:
		return
	var rect := parent_screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_CENTER
	)
	data.position = rect.position
	data.size = rect.size


func _apply_card_metrics() -> void:
	var data := get_node_or_null(^"FacilityData") as ItemList
	if data == null:
		return
	var factor := float(_ui_scale_percent) / 100.0
	data.fixed_column_width = roundi(CARD_WIDTH * factor)
	data.fixed_icon_size = Vector2i.ONE * roundi(CARD_ICON_SIZE * factor)


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
