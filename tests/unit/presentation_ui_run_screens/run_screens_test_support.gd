extends RefCounted

const RUN_SCREEN_PRESENTER_PATH := \
	"res://presentation/screens/run_screen_presenter.gd"
const COMBAT_INSPECTION_PRESENTER_PATH := \
	"res://presentation/screens/combat_unit_inspection_presenter.gd"


class SpyRunPresentationSession:
	extends RunPresentationSession

	var dispatch_count: int = 0
	var dispatched_kinds: Array[int] = []
	var current_phase: StringName = &"COMBAT"
	var inspection_error_code: StringName = &""
	var inspections: Dictionary[int, CombatUnitInspectionSnapshot] = {}

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		dispatched_kinds.append(intent.kind)
		return RunPresentationResult.success(snapshot())

	func snapshot() -> RunPresentationSnapshot:
		var value := RunPresentationSnapshot.new()
		value.run_id = &"run.t09"
		value.app_phase = current_phase
		return value

	func inspect_combat_unit(unit_serial: int) -> CombatUnitInspectionResult:
		if not inspection_error_code.is_empty():
			return CombatUnitInspectionResult.failure(
				DiagnosticError.new(
					inspection_error_code,
					&"error.presentation.combat_inspection_unavailable"
				)
			)
		if current_phase != &"COMBAT":
			return CombatUnitInspectionResult.failure(
				DiagnosticError.new(
					&"PLAYBACK_NOT_AVAILABLE",
					&"error.presentation.combat_inspection_not_available"
				)
			)
		var value: CombatUnitInspectionSnapshot = inspections.get(unit_serial)
		if value == null:
			return CombatUnitInspectionResult.failure(
				DiagnosticError.new(
					&"COMBAT_UNIT_NOT_FOUND",
					&"error.presentation.combat_unit_not_found"
				)
			)
		return CombatUnitInspectionResult.new(true, value, null)


static func load_script(test: GutTest, path: String) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "T09 production contract missing: %s" % path)
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "T09 script must load: %s" % path)
	return resource as Script


static func require_method(
	test: GutTest,
	target: Variant,
	method_name: StringName
) -> bool:
	var present: bool = target != null and target.has_method(method_name)
	test.assert_true(present, "T09 contract requires method %s" % String(method_name))
	return present


static func error_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	if error == null:
		return &""
	return StringName(error.get("source_code"))


static func inspection(
	unit_serial: int,
	source_id: StringName,
	target_serial: int
) -> CombatUnitInspectionSnapshot:
	var value := CombatUnitInspectionSnapshot.new()
	value.unit_serial = unit_serial
	value.source_id = source_id
	value.target_serial = target_serial
	value.stats = {"attack": 17, "health": 41}
	value.equipment_ids.assign([&"equipment.test"])
	value.trait_ids.assign([&"trait.test"])
	value.status_ids.assign([&"status.test"])
	return value
