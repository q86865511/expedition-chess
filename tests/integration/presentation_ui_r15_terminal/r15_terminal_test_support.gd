extends RefCounted

const R13Support = preload(
	"res://tests/integration/presentation_ui_r13_terminal/"
	+ "r13_terminal_test_support.gd"
)


class RecordingRunSession:
	extends RunPresentationSession

	var current := RunPresentationSnapshot.new()
	var dispatch_count: int = 0

	func _init() -> void:
		current.run_id = &"run.r15.terminal.old"
		current.app_phase = &"MAP"
		current.manifest_digest = "manifest.r15.terminal.old"

	func snapshot() -> RunPresentationSnapshot:
		return current.deep_clone()

	func dispatch(_intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		return RunPresentationResult.success(current)


class DoubleFaultSceneRouter:
	extends SceneRouterService

	const RESULTS_FAULT: StringName = &"INJECTED_RESULTS_INSTALL_FAULT"
	const FALLBACK_FAULT: StringName = \
		&"INJECTED_RESULTS_FALLBACK_INSTALL_FAULT"

	var routes: Array[StringName] = []

	func install_production(
		route_kind: StringName,
		_context: StagedScreenContext
	) -> StringName:
		routes.append(route_kind)
		match route_kind:
			&"RESULTS":
				return RESULTS_FAULT
			&"RESULTS_FALLBACK":
				return FALLBACK_FAULT
		return &"INJECTED_UNEXPECTED_ROUTE"


class FreshHostRecoveryRouter:
	extends SceneRouterService

	var routes: Array[StringName] = []

	func install_production(
		route_kind: StringName,
		context: StagedScreenContext
	) -> StringName:
		routes.append(route_kind)
		if route_kind == &"RESULTS":
			return &"INJECTED_FRESH_RESULTS_INSTALL_FAULT"
		return super.install_production(route_kind, context)


class FallbackAuthorityFaultRepository:
	extends SaveRepository

	var fault_kind: StringName

	func _init(
		p_fault_kind: StringName,
		storage: SaveStoragePort,
		receipt_port: PinnedCatalogReceiptPort,
		migration_port: ContentIdMigrationPort,
		validator: RunStateValidator
	) -> void:
		fault_kind = p_fault_kind
		super(storage, receipt_port, migration_port, validator)

	func _issue_terminal_postcommit_fallback_capability(
		run_id: StringName,
		receipt_id: StringName
	) -> TerminalPostcommitFallbackCapability:
		if fault_kind == &"issue":
			return null
		return super._issue_terminal_postcommit_fallback_capability(
			run_id,
			receipt_id
		)

	func _consume_terminal_postcommit_fallback_capability(
		capability: TerminalPostcommitFallbackCapability,
		snapshot: ResultsPresentationSnapshot
	) -> bool:
		if fault_kind == &"consume":
			return false
		return super._consume_terminal_postcommit_fallback_capability(
			capability,
			snapshot
		)


static func repository_with_terminal_root() -> SaveRepository:
	return R13Support.repository_with_terminal_root()


static func repository_with_fallback_authority_fault(
	fault_kind: StringName
) -> SaveRepository:
	var repository := FallbackAuthorityFaultRepository.new(
		fault_kind,
		FakeSaveStorage.new(),
		FakePinnedCatalogReceiptPort.new(
			SaveRootFixture.create_receipt()
		),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)
	assert(repository.save(R13Support.terminal_root()).ok)
	return repository


static func reward_table() -> MetaRewardTableDef:
	return R13Support.reward_table()


static func enter_node_intent() -> RunPresentationIntent:
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.ENTER_NODE
	)
	intent.target_node_id = "node.r15.stale"
	return intent


static func source_code(result: Variant) -> StringName:
	if result == null or not result is Object:
		return &""
	var error: Variant = (result as Object).get("error")
	if error == null or not error is Object:
		return &""
	return StringName((error as Object).get("source_code"))


static func results_context(
	route_kind: StringName,
	snapshot: ResultsPresentationSnapshot
) -> StagedScreenContext:
	var localized: Dictionary = {}
	var catalog := LocalizationCatalog.new()
	for key: StringName in catalog.keys_for_locale(&"zh_TW"):
		var resolved := catalog.resolve(&"zh_TW", key)
		if resolved.ok:
			localized[key] = resolved.value
	return StagedScreenContext.new(
		route_kind,
		snapshot,
		null,
		&"zh_TW",
		localized
	)
