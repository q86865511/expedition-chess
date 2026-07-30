extends RefCounted

const LifecycleSupport = preload(
	"res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd"
)


class FaultScreen:
	extends ProductionScreen

	func bind(_context: StagedScreenContext) -> StringName:
		return &"R14_INJECTED_BIND_FAULT"


class RouteFaultCatalog:
	extends ProductionSceneCatalog

	var fault_route: StringName

	func _init(p_fault_route: StringName) -> void:
		fault_route = p_fault_route

	func instantiate(route_kind: StringName) -> ProductionScreen:
		if route_kind == fault_route:
			var screen := FaultScreen.new()
			screen.route_kind = route_kind
			return screen
		return super.instantiate(route_kind)


static func boot(test: GutTest, storage: FakeSaveStorage = null) -> Variant:
	return LifecycleSupport.boot(
		test,
		storage if storage != null else FakeSaveStorage.new()
	)


static func active_screen(harness: Variant) -> ProductionScreen:
	if harness == null or harness.host == null or harness.host.get_child_count() != 1:
		return null
	return harness.host.get_child(0) as ProductionScreen


static func composition(harness: Variant) -> Node:
	var screen := active_screen(harness)
	return screen.get_node_or_null("Composition") if screen != null else null


static func action_buttons(screen: ProductionScreen) -> Array[Button]:
	var result: Array[Button] = []
	if screen == null:
		return result
	for node: Node in screen.find_children("*", "Button", true, false):
		result.append(node as Button)
	return result


static func action_ids(screen: ProductionScreen) -> Array[StringName]:
	var result: Array[StringName] = []
	for button: Button in action_buttons(screen):
		if button.has_meta(&"action_id"):
			result.append(StringName(button.get_meta(&"action_id")))
	result.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return result


static func first_commander(root: ApplicationRoot) -> StringName:
	var view_model: CampViewModel = root.try_camp_view_model()
	if view_model == null:
		return &""
	var commanders: Array[StringName] = (
		view_model.commander_hall_unlocked_commander_ids()
	)
	return commanders[0] if not commanders.is_empty() else &""


static func start_run(harness: Variant) -> AppActionResult:
	var opened: AppActionResult = harness.root.open_camp()
	if not opened.ok:
		return opened
	var commander_id: StringName = first_commander(harness.root)
	if commander_id.is_empty():
		return AppActionResult.failure(
			DiagnosticError.new(
				&"R14_COMMANDER_MISSING",
				&"error.presentation.r14_commander_missing"
			)
		)
	return harness.root.start_expedition(
		StartExpeditionRequest.new(commander_id, 0)
	)


static func error_code(result: Variant) -> StringName:
	if result is AppActionResult and result.error != null:
		return result.error.source_code
	if result is RunPresentationResult and result.error != null:
		return result.error.source_code
	return &""
