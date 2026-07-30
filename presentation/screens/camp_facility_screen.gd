class_name CampFacilityScreen
extends ProductionScreen

const COMPOSE_INVALID: StringName = &"CAMP_FACILITY_COMPOSE_INVALID"

var _bundle: CampFacilityBundle
var _navigation_port: LiveScreenNavigationPort


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
	data.position = Vector2(72.0, 112.0)
	data.custom_minimum_size = Vector2(640.0, 320.0)
	data.focus_mode = Control.FOCUS_ALL
	data.set_meta(&"typed_data_kind", _parent_route_kind())
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
		data.add_item(_localized_content_text(value))
		data.set_item_metadata(data.item_count - 1, value)
		if _parent_route_kind() == &"COLLECTION":
			data.set_meta(&"semantic_kind", &"rarity")
			data.set_meta(&"semantic_pattern", &"double-frame")
	data.set_meta(&"accessible_text", &"camp.facility_data")
	add_child(data)


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
