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
	_remove_control(^"CommanderSelector")
	_remove_control(^"ChallengeSelector")
	_commander_selector = OptionButton.new()
	_commander_selector.name = "CommanderSelector"
	_commander_selector.position = Vector2(72.0, 112.0)
	_commander_selector.custom_minimum_size = Vector2(320.0, 48.0)
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
	add_child(_commander_selector)

	_challenge_selector = SpinBox.new()
	_challenge_selector.name = "ChallengeSelector"
	_challenge_selector.position = Vector2(72.0, 176.0)
	_challenge_selector.custom_minimum_size = Vector2(240.0, 48.0)
	_challenge_selector.focus_mode = Control.FOCUS_ALL
	_challenge_selector.min_value = 0.0
	_challenge_selector.max_value = float(
		maxi(_bundle.highest_challenge_level(), 0)
	)
	_challenge_selector.step = 1.0
	_challenge_selector.value = 0.0
	_challenge_selector.set_meta(&"typed_choice_kind", &"challenge")
	_challenge_selector.set_meta(
		&"accessible_text",
		&"camp.challenge_selector"
	)
	_challenge_selector.value_changed.connect(_on_challenge_selected)
	add_child(_challenge_selector)


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


func _remove_control(path: NodePath) -> void:
	var existing := get_node_or_null(path)
	if existing != null:
		remove_child(existing)
		existing.queue_free()
