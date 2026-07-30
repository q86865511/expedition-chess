extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_run_screens/run_screens_test_support.gd"
)


func test_combat_unit_inspection_is_typed_and_read_only() -> void:
	var presenter_script := Support.load_script(
		self, Support.COMBAT_INSPECTION_PRESENTER_PATH
	)
	if presenter_script == null:
		return
	var session := Support.SpyRunPresentationSession.new()
	session.inspections[1] = Support.inspection(1, &"unit.source", 2)
	session.inspections[2] = Support.inspection(2, &"unit.target", 1)
	var inspection_call_count: Array[int] = [0]
	var clone_accessor := func(unit_serial: int) -> CombatUnitInspectionResult:
		inspection_call_count[0] += 1
		return session.inspect_combat_unit(unit_serial)
	var presenter: Variant = presenter_script.new(&"RUN_COMBAT", clone_accessor)
	for method_name: StringName in [
		&"select_mouse",
		&"select_keyboard",
		&"current_snapshot",
	]:
		if not Support.require_method(self, presenter, method_name):
			return

	var mouse: Variant = presenter.call(&"select_mouse", 1)
	assert_true(bool(mouse.get("ok")))
	var mouse_snapshot: Variant = mouse.get("snapshot")
	assert_true(mouse_snapshot is CombatUnitInspectionSnapshot)
	assert_eq(mouse_snapshot.get("source_id"), &"unit.source")
	assert_eq(mouse_snapshot.get("target_serial"), 2)
	assert_eq(mouse_snapshot.get("stats"), {"attack": 17, "health": 41})
	assert_eq(mouse_snapshot.get("equipment_ids"), [&"equipment.test"])
	assert_eq(mouse_snapshot.get("trait_ids"), [&"trait.test"])
	assert_eq(mouse_snapshot.get("status_ids"), [&"status.test"])

	var keyboard: Variant = presenter.call(&"select_keyboard", 2)
	assert_true(bool(keyboard.get("ok")))
	assert_eq(keyboard.get("snapshot").get("unit_serial"), 2)
	assert_eq(inspection_call_count[0], 2)
	assert_eq(session.dispatch_count, 0, "inspection must never dispatch")

	var leaked: Variant = presenter.call(&"current_snapshot")
	leaked.get("stats")["attack"] = 999
	assert_eq(
		presenter.call(&"current_snapshot").get("stats")["attack"],
		17,
		"current inspection must be clone-only"
	)

	session.inspections.erase(2)
	var disappeared: Variant = presenter.call(&"select_keyboard", 2)
	assert_false(bool(disappeared.get("ok")))
	assert_null(presenter.call(&"current_snapshot"))

	session.inspections[1] = Support.inspection(1, &"unit.source", 2)
	session.inspection_error_code = &"INSPECTION_IDENTITY_STALE"
	var stale: Variant = presenter.call(&"select_mouse", 1)
	assert_false(bool(stale.get("ok")))
	assert_null(presenter.call(&"current_snapshot"))

	session.inspection_error_code = &""
	session.current_phase = &"PREPARE"
	var non_combat: Variant = presenter.call(&"select_mouse", 1)
	assert_false(bool(non_combat.get("ok")))
	assert_eq(Support.error_code(non_combat), &"PLAYBACK_NOT_AVAILABLE")
	assert_null(presenter.call(&"current_snapshot"))
	assert_eq(session.dispatch_count, 0)

	# R12-A01/A02 terminal/results ownership is intentionally not exercised.
