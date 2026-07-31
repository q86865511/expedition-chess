extends RefCounted

const CAMP_WORLD_SCREEN_PATH := \
	"res://presentation/screens/camp_world_screen.gd"
const CAMP_FACILITY_SCREEN_PATH := \
	"res://presentation/screens/camp_facility_screen.gd"
const COLLECTION_SCREEN_PATH := \
	"res://presentation/screens/collection_screen.gd"
const RUN_PREPARE_SCREEN_PATH := \
	"res://presentation/screens/run_prepare_screen.gd"
const RUN_COMBAT_SCREEN_PATH := \
	"res://presentation/screens/run_combat_screen.gd"
const RUN_REWARD_SCREEN_PATH := \
	"res://presentation/screens/run_reward_screen.gd"
const PRODUCTION_SCREEN_PATH := \
	"res://presentation/screens/production_screen.gd"

const CAMP_SCENES: Dictionary = {
	&"CAMP_WORLD": "res://scenes/production/camp_world.tscn",
	&"FACILITY_EXPEDITION_GATE":
		"res://scenes/production/facility_expedition_gate.tscn",
	&"FACILITY_COMMANDER_HALL":
		"res://scenes/production/facility_commander_hall.tscn",
	&"COLLECTION": "res://scenes/production/collection.tscn",
	&"FACILITY_UNLOCK_WORKSHOP":
		"res://scenes/production/facility_unlock_workshop.tscn",
	&"FACILITY_CHALLENGE_MONUMENT":
		"res://scenes/production/facility_challenge_monument.tscn",
}

const EXPECTED_FACILITY_ROUTES: Array[StringName] = [
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
]

const ALL_BOARD_ISSUE_CODES: Array[StringName] = [
	&"BENCH_EMPTY_SLOT",
	&"BENCH_TOO_LARGE",
	&"BOARD_CELL_OVERLAP",
	&"BOARD_OUT_OF_BOUNDS",
	&"BOARD_OVER_CAPACITY",
	&"BOARD_PHYSICAL_LIMIT",
	&"BOARD_REQUEST_INVALID",
	&"BOARD_UNIT_DUPLICATE",
	&"BOARD_UNIT_REFERENCE_MISSING",
	&"BOARD_UNIT_UNASSIGNED",
	&"BOARD_WRONG_HALF",
	&"POPULATION_INVALID",
]


class SpyRunPresentationSession:
	extends RunPresentationSession

	var dispatch_count: int = 0
	var dispatched_kinds: Array[int] = []
	## 送出的 intent 原件：驗「ack 帶的是畫面上顯示的那一筆 receipt_digest」需要欄位，
	## 只看 kind 看不出 T25 review N1 的錯 receipt 缺陷。
	var dispatched_intents: Array[RunPresentationIntent] = []
	var current_snapshot: RunPresentationSnapshot
	var next_snapshot: RunPresentationSnapshot
	var reject_code: StringName = &""

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		dispatched_kinds.append(intent.kind)
		dispatched_intents.append(intent)
		if not reject_code.is_empty():
			return RunPresentationResult.failure(
				DiagnosticError.new(
					reject_code,
					StringName(
						"error.presentation.%s" % String(reject_code).to_lower()
					)
				)
			)
		if next_snapshot != null:
			current_snapshot = next_snapshot.deep_clone()
			next_snapshot = null
		return RunPresentationResult.success(current_snapshot)
		return RunPresentationResult.success(snapshot())

	func snapshot() -> RunPresentationSnapshot:
		return (
			current_snapshot.deep_clone()
			if current_snapshot != null
			else RunPresentationSnapshot.new()
		)


static func require_script(
	test: GutTest,
	path: String,
	purpose: String
) -> Script:
	var exists: bool = FileAccess.file_exists(path)
	test.assert_true(exists, "%s missing production script: %s" % [purpose, path])
	if not exists:
		return null
	var resource: Resource = load(path)
	test.assert_not_null(resource, "%s must load: %s" % [purpose, path])
	return resource as Script


static func instantiate_scene(
	test: GutTest,
	path: String,
	expected_script_path: String
) -> Object:
	var resource := load(path) as PackedScene
	test.assert_not_null(resource, "production scene must load: %s" % path)
	if resource == null:
		return null
	var root: Node = resource.instantiate()
	test.assert_not_null(root, "production scene must instantiate: %s" % path)
	if root == null:
		return null
	test.autofree(root)
	var root_script: Script = root.get_script() as Script
	var root_path: String = root_script.resource_path if root_script != null else ""
	test.assert_eq(
		root_path,
		PRODUCTION_SCREEN_PATH,
		"%s root must preserve the canonical ProductionScreen contract" % path
	)
	var composition := root.get_node_or_null("Composition")
	test.assert_not_null(composition, "%s must expose a composition child" % path)
	if composition == null:
		return null
	var script: Script = composition.get_script() as Script
	var actual_path: String = script.resource_path if script != null else ""
	test.assert_eq(
		actual_path,
		expected_script_path,
		"%s must attach its concrete production composition screen" % path
	)
	if actual_path != expected_script_path:
		return null
	return composition


static func require_methods(
	test: GutTest,
	target: Object,
	methods: Array[StringName],
	contract_name: String
) -> bool:
	for method_name: StringName in methods:
		var exists: bool = target != null and target.has_method(method_name)
		test.assert_true(
			exists,
			"%s requires method %s" % [contract_name, String(method_name)]
		)
		if not exists:
			return false
	return true


static func profile_fixture() -> ProfileState:
	var unlocked: Array[StringName] = [
		&"commander.alpha",
		&"relic.unlocked",
	]
	var discovered: Array[StringName] = [
		&"unit.discovered",
		&"relic.unlocked",
	]
	var receipts: Array[SettlementReceiptState] = []
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 4),
	]
	return ProfileState.new(
		"profile.scene.composition",
		U64Bits.one(),
		37,
		unlocked,
		discovered,
		6,
		receipts,
		&"settings.default",
		ProfileLastSelectionState.new(&"commander.alpha", 3),
		records
	)


static func invalid_board_report() -> BoardValidationReport:
	var issues: Array[BoardValidationIssue] = []
	for index: int in ALL_BOARD_ISSUE_CODES.size():
		issues.append(
			BoardValidationIssue.new(
				ALL_BOARD_ISSUE_CODES[index],
				index % 8,
				(index * 3) % 8,
				"unit.%02d" % index
			)
		)
	return BoardValidationReport.new(11, issues)


static func valid_board_report() -> BoardValidationReport:
	var issues: Array[BoardValidationIssue] = []
	return BoardValidationReport.new(12, issues)


static func prepare_snapshot() -> RunPresentationSnapshot:
	var snapshot: RunPresentationSnapshot = RunPresentationSnapshot.new()
	snapshot.run_id = &"run.nonterminal.prepare"
	snapshot.app_phase = &"PREPARE"
	snapshot.manifest_digest = "manifest.prepare"
	var item: ItemInstanceState = ItemInstanceState.new(
		"overflow.item",
		&"equipment.test",
		null,
		U64Bits.one()
	)
	var items: Array[ItemInstanceState] = [item]
	var overflow: Array[String] = ["overflow.item"]
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	var units: Array[UnitInstance] = []
	var inventory: Array[String] = []
	var relics: Array[RelicSlotState] = []
	snapshot.roster = RosterState.new(
		BoardState.new(placements),
		bench,
		units,
		items,
		inventory,
		overflow,
		relics
	)
	snapshot.board_validation_report = valid_board_report()
	return snapshot


static func combat_snapshot() -> RunPresentationSnapshot:
	var snapshot: RunPresentationSnapshot = RunPresentationSnapshot.new()
	snapshot.run_id = &"run.nonterminal.combat"
	snapshot.app_phase = &"COMBAT"
	snapshot.manifest_digest = "manifest.combat"
	var preview: EncounterPreviewSnapshot = EncounterPreviewSnapshot.new()
	preview.encounter_id = &"encounter.elite"
	preview.manifest_digest = &"manifest.combat"

	var effect: BattleEffectSnapshot = BattleEffectSnapshot.new()
	effect.effect_id = &"effect.mark_target"
	effect.target_ids.assign([&"player.front"])
	var enemy: UnitBattleSnapshot = UnitBattleSnapshot.new()
	enemy.instance_id = &"enemy.alpha"
	enemy.unit_id = &"unit.enemy.alpha"
	enemy.side = &"enemy"
	enemy.logical_x = 5
	enemy.logical_y = 6
	enemy.ability_id = OptionalStringNameValue.of(&"ability.enemy.alpha")
	enemy.effect_ids.assign([&"effect.mark_target"])
	enemy.effect_assignments.append(effect)
	preview.enemy_units.append(enemy)

	var trait_snapshot: TraitBattleSnapshot = TraitBattleSnapshot.new()
	trait_snapshot.trait_id = &"trait.enemy.arcane"
	trait_snapshot.tier = 2
	trait_snapshot.member_instance_ids.assign([&"enemy.alpha"])
	preview.active_traits.append(trait_snapshot)

	var phase: BossPhaseSnapshot = BossPhaseSnapshot.new()
	phase.phase_index = 1
	phase.hp_threshold_bps = 5000
	phase.source_instance_id = &"enemy.alpha"
	phase.effect_ids.assign([&"effect.boss.enrage"])
	preview.boss_phases.append(phase)

	var key: NodeKeyState = NodeKeyState.create(
		&"run.nonterminal.combat",
		1,
		&"elite",
		2,
		0,
		&"node-key-digest"
	)
	var node: MapNodeState = MapNodeState.new(
		"elite.node",
		key,
		&"map_node.elite",
		1,
		2,
		0,
		MapNodeState.NodeKind.ELITE,
		"payload.digest",
		preview,
		false
	)
	var nodes: Array[MapNodeState] = [node]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	snapshot.map = MapState.new(
		nodes,
		edges,
		OptionalStringValue.new("elite.node"),
		completed
	)
	return snapshot


static func reward_snapshot(
	phase: PendingRewardState.Phase,
	include_offers: bool = true
) -> RunPresentationSnapshot:
	var snapshot: RunPresentationSnapshot = prepare_snapshot()
	snapshot.run_id = &"run.nonterminal.reward"
	snapshot.app_phase = &"REWARD"
	snapshot.manifest_digest = "manifest.reward"
	var offers: Array[RewardOfferState] = []
	if include_offers:
		for index: int in 3:
			var owner: ReservationOwnerKeyState = ReservationOwnerKeyState.create(
				&"run.nonterminal.reward",
				&"elite.node",
				&"reward",
				&"standard",
				index,
				StringName("owner.%d" % index)
			)
			offers.append(RewardOfferState.new(
				"choice.%d" % index,
				RewardOfferState.RewardKind.UNIT,
				OptionalStringNameValue.of(
					StringName("unit.reward.%d" % index)
				),
				1,
				owner,
				"payload.%d" % index
			))
	var reserved: Array[ReservedCopyState] = []
	var selected_owner: ReservationOwnerKeyState = ReservationOwnerKeyState.create(
		&"run.nonterminal.reward",
		&"elite.node",
		&"reward",
		&"selected",
		0,
		&"owner.selected"
	)
	var transaction: TransactionKeyState = TransactionKeyState.create(
		&"run.nonterminal.reward",
		&"elite.node",
		&"reward",
		U64Bits.one(),
		&"transaction.reward"
	)
	snapshot.pending_reward = PendingRewardState.new(
		"elite.node",
		(
			PendingRewardState.StageId.RELIC
			if phase == PendingRewardState.Phase.RELIC_RESOLUTION
			else PendingRewardState.StageId.STANDARD
		),
		phase,
		offers,
		reserved,
		OptionalStringValue.new("choice.0"),
		selected_owner,
		transaction
	)
	var shop_owner: ReservationOwnerKeyState = ReservationOwnerKeyState.create(
		&"run.nonterminal.reward",
		&"elite.node",
		&"shop",
		&"refresh.1",
		0,
		&"owner.shop"
	)
	var shop_offers: Array[ShopOffer] = [
		ShopOffer.new(
			0,
			"shop.retained",
			&"unit.shop.retained",
			3,
			1,
			shop_owner
		),
	]
	snapshot.economy = EconomyState.new(10, 9, 0, 0, 0, 1, shop_offers)
	return snapshot


static func post_claim_snapshot() -> RunPresentationSnapshot:
	return reward_snapshot(PendingRewardState.Phase.UNIT_RESOLUTION, false)


static func live_intent_port(
	session: RunPresentationSession,
	generation: int = 1
) -> Array:
	var registry: LiveScreenLeaseRegistry = LiveScreenLeaseRegistry.new()
	var lease: LiveScreenLease = registry.activate(
		AppStateMachine.State.RUN,
		generation
	)
	return [LiveScreenIntentPort.new(lease, registry, session), registry]


static func error_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	return (
		StringName(error.get("source_code"))
		if error != null
		else &""
	)
