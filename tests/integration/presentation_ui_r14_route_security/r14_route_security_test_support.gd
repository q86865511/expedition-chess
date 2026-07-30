extends RefCounted

const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)
const ROUTER_SOURCE := "res://services/scene/scene_router_service.gd"
const APP_ROOT_SOURCE := "res://app/app_root.gd"
const SCREEN_SOURCE := "res://presentation/screens/production_screen.gd"


class RecordingSession:
	extends RunPresentationSession

	var current_snapshot: RunPresentationSnapshot
	var dispatched: Array[RunPresentationIntent] = []

	func _init() -> void:
		current_snapshot = CompositionSupport.combat_snapshot()

	func snapshot() -> RunPresentationSnapshot:
		return current_snapshot.deep_clone()

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatched.append(intent.deep_clone())
		return RunPresentationResult.success(current_snapshot)


static func router_fixture(test: GutTest) -> Dictionary:
	var router := SceneRouterService.new()
	var host := Control.new()
	test.add_child_autofree(router)
	test.add_child_autofree(host)
	router.bind_presentation_host(host)
	test.assert_eq(router.bind_production_catalog(ProductionSceneCatalog.new()), &"")
	return {"router": router, "host": host}


static func prepare_menu(
	test: GutTest,
	router: SceneRouterService
) -> PreparedProductionRoute:
	var context := StagedScreenContext.new(&"MENU_MAIN")
	var result := router.prepare_production(&"MENU_MAIN", context)
	test.assert_true(result.ok)
	test.assert_not_null(result.prepared)
	return result.prepared


static func source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func typed_commit_contract_ready() -> bool:
	var text := source(ROUTER_SOURCE)
	return (
		not text.contains("assert(_valid_prepared(prepared))")
		and text.contains("func commit_prepared(")
		and text.contains(") -> StringName:")
	)


static func commit_code(
	test: GutTest,
	router: SceneRouterService,
	prepared: PreparedProductionRoute
) -> StringName:
	if not typed_commit_contract_ready():
		test.assert_true(
			false,
			"commit_prepared must return a typed rejection instead of asserting"
		)
		return &"UNSAFE_ASSERT_CONTRACT"
	var value: Variant = router.call(&"commit_prepared", prepared)
	return StringName(value) if value != null else &""


static func app_commit_contract_ready() -> bool:
	var text := source(APP_ROOT_SOURCE)
	return (
		not text.contains("assert(lease != null)")
		and text.contains("func _commit_route(prepared: Dictionary) -> StringName:")
	)


static func malformed_composition_contract_ready() -> bool:
	var text := source(SCREEN_SOURCE)
	return (
		text.contains("SCREEN_COMPOSITION_TYPE_INVALID")
		and text.contains("composition is RunMapScreen")
	)


static func intent_fixture() -> Dictionary:
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 91)
	var session := RecordingSession.new()
	var port := LiveScreenIntentPort.new(lease, registry, session)
	return {
		"registry": registry,
		"lease": lease,
		"session": session,
		"port": port,
	}


static func enter_node_intent(target: String = "elite.node") -> RunPresentationIntent:
	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.ENTER_NODE)
	intent.target_node_id = target
	return intent


static func run_error_code(result: RunPresentationResult) -> StringName:
	return (
		result.error.source_code
		if result != null and result.error != null
		else &""
	)
