extends GutTest

const REQUIRED_TYPED_PATHS: Array[String] = [
	"res://domain/run/economy/node_choice_operation_rule.gd",
	"res://domain/run/economy/node_choice_rule.gd",
	"res://domain/run/economy/node_choice_set_rule.gd",
	"res://presentation/run/node_choice_overlay_snapshot.gd",
	"res://presentation/run/node_choice_option_snapshot.gd",
]


class SpyRunPresentationSession:
	extends RunPresentationSession

	var dispatch_count: int = 0
	var current := RunPresentationSnapshot.new()

	func _init() -> void:
		current.run_id = &"run.choice"
		current.app_phase = &"PREPARE"

	func snapshot() -> RunPresentationSnapshot:
		return current.deep_clone()

	func dispatch(_intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		return RunPresentationResult.success(current)


func test_choice_runtime_uses_typed_catalog_and_existing_confirmation_port() -> void:
	for path: String in REQUIRED_TYPED_PATHS:
		assert_true(FileAccess.file_exists(path), "missing typed choice contract: %s" % path)
	if REQUIRED_TYPED_PATHS.any(
		func(path: String) -> bool: return not FileAccess.file_exists(path)
	):
		return
	assert_true(RunPresentationIntent.Kind.keys().has("COMMIT_NODE_CHOICE"))
	if not RunPresentationIntent.Kind.keys().has("COMMIT_NODE_CHOICE"):
		return
	var factory := RunCommandFactory.new(null, null)
	assert_true(factory.has_method("commit_node_choice_command"))
	var catalog_script := load(
		"res://domain/run/economy/economy_expedition_catalog.gd"
	) as GDScript
	var catalog_methods: Array[StringName] = []
	for method: Dictionary in catalog_script.get_script_method_list():
		catalog_methods.append(StringName(method.get("name", "")))
	assert_true(catalog_methods.has(&"try_node_choice_set"))

	var registry := LiveScreenLeaseRegistry.new()
	var session := SpyRunPresentationSession.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 51)
	var port := LiveScreenIntentPort.new(lease, registry, session)
	var choice_kind := int(RunPresentationIntent.Kind.get("COMMIT_NODE_CHOICE"))
	var intent := RunPresentationIntent.new(choice_kind)
	intent.set("choice_set_id", &"choice_set.event_00")
	intent.choice_id = "choice.event_00.safe"
	var begun := port.begin_confirmation(intent)
	assert_true(begun.ok)
	assert_eq(session.dispatch_count, 0)
	assert_eq(begun.draft.snapshot_identity, &"run.choice")
	assert_eq(begun.draft.route_generation, 51)
	assert_eq(begun.draft.lifecycle, &"PREPARE")
	assert_eq(begun.draft.payload_digest.length(), 64)
	var cancelled := port.cancel(begun.draft)
	assert_true(cancelled.ok)
	assert_eq(session.dispatch_count, 0, "cancel is zero dispatch")

	var confirmed_begin := port.begin_confirmation(intent)
	var confirmed := port.confirm(confirmed_begin.draft)
	assert_true(confirmed.ok)
	assert_eq(session.dispatch_count, 1, "confirm dispatches exactly once")
	var repeated := port.confirm(confirmed_begin.draft)
	assert_false(repeated.ok)
	assert_eq(repeated.error.code, &"CONFIRMATION_ALREADY_RESOLVED")
	assert_eq(session.dispatch_count, 1)


func test_prepare_screen_exposes_choice_overlay_without_second_app_state() -> void:
	var screen := RunPrepareScreen.new()
	for method_name: StringName in [
		&"select_first_node_choice",
		&"begin_selected_node_choice",
		&"confirm_node_choice",
		&"cancel_node_choice",
		&"has_pending_node_choice_confirmation",
	]:
		assert_true(screen.has_method(method_name), "missing choice overlay method: %s" % method_name)
	screen.free()
	assert_false(
		AppStateMachine.State.keys().has("NODE_CHOICE"),
		"node choice must remain inside the existing RUN lifecycle"
	)
