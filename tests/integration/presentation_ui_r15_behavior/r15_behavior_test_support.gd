extends RefCounted

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)
const FunctionalSupport = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)
const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)
const InspectionSupport = preload(
	"res://tests/unit/presentation_ui_run_screens/"
	+ "run_screens_test_support.gd"
)


class SpyTypedSession:
	extends RunPresentationSession

	var current_snapshot: RunPresentationSnapshot
	var last_intent: RunPresentationIntent
	var inspections: Dictionary[int, CombatUnitInspectionSnapshot] = {}
	var dispatch_count: int = 0
	var inspection_count: int = 0

	func snapshot() -> RunPresentationSnapshot:
		return (
			current_snapshot.deep_clone()
			if current_snapshot != null
			else RunPresentationSnapshot.new()
		)

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		last_intent = intent
		return RunPresentationResult.success(snapshot())

	func inspect_combat_unit(unit_serial: int) -> CombatUnitInspectionResult:
		inspection_count += 1
		var value: CombatUnitInspectionSnapshot = inspections.get(unit_serial)
		if value == null:
			return CombatUnitInspectionResult.failure(
				DiagnosticError.new(
					&"COMBAT_UNIT_NOT_FOUND",
					&"error.presentation.combat_unit_not_found"
				)
			)
		return CombatUnitInspectionResult.new(true, value, null)


static func active_screen(harness: Variant) -> ProductionScreen:
	return RouteSupport.active_screen(harness)


static func action_button(
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


static func has_property(
	target: Object,
	property_name: StringName
) -> bool:
	if target == null:
		return false
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func semantic_control(
	root: Node,
	semantic_kind: StringName,
	typed_data_id: StringName
) -> Control:
	if root == null:
		return null
	for node: Node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if (
			control != null
			and StringName(control.get_meta(&"semantic_kind", &""))
				== semantic_kind
			and StringName(control.get_meta(&"typed_data_id", &""))
				== typed_data_id
		):
			return control
	return null


static func visible_text(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	return String(control.get_meta(&"accessible_text", ""))
