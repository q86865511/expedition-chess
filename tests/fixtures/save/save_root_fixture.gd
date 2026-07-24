class_name SaveRootFixture
extends RefCounted

const PROFILE_ID: String = "00000000000000000000000000000001"
const CONTENT_VERSION: String = "fixture.1"
const MANIFEST_DIGEST: String = "2222222222222222222222222222222222222222222222222222222222222222"
const SELECTION_DIGEST: String = "1111111111111111111111111111111111111111111111111111111111111111"

static func create_valid_root() -> SaveRoot:
	var zero := U64Bits.zero()
	var one := U64Bits.one()
	var run_key_result := RuntimeKeySchemaRegistry.new().build_run(PROFILE_ID, zero)
	var run_key: RunKeyState = run_key_result.key_state as RunKeyState
	var content_result := ContentSnapshotState.from_pinned_receipt(create_receipt())
	assert(content_result.ok)
	var content := content_result.snapshot
	var empty_nodes: Array[MapNodeState] = []
	var empty_edges: Array[MapEdgeState] = []
	var empty_strings: Array[String] = []
	var map := MapState.new(empty_nodes, empty_edges, null, empty_strings)
	var empty_offers: Array[ShopOffer] = []
	var economy := EconomyState.new(0, 1, 0, 0, 0, 0, empty_offers)
	var empty_pool: Array[UnitPoolEntryState] = []
	var empty_placements: Array[BoardPlacementState] = []
	var empty_units: Array[UnitInstance] = []
	var empty_items: Array[ItemInstanceState] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	var roster := RosterState.new(
		BoardState.new(empty_placements), empty_strings, empty_units, empty_items,
		empty_strings, empty_strings, relics
	)
	var rng_states: Array[NamedRngState] = []
	for stream_index: int in range(4):
		var snapshot_result := RngSnapshot.create(1, zero, one, zero)
		rng_states.append(NamedRngState.new(stream_index, snapshot_result.snapshot))
	var empty_ints: Array[int] = []
	var owners: Array[ReservationOwnerState] = []
	var transactions: Array[TransactionReceiptState] = []
	var claims: Array[ClaimReceiptState] = []
	var empty_names: Array[StringName] = []
	var run := RunState.new(
		String(run_key.digest), run_key, zero, content, zero, zero, zero,
		&"commander.fixture", 0, 0, map, null, RunState.RunPhase.MAP, 100,
		economy, UnitPoolState.new(empty_pool), roster, 0, 0, 0,
		rng_states, empty_strings, empty_ints, owners, transactions, claims,
		IdleResolutionState.new(), empty_names
	)
	var unlocked: Array[StringName] = [&"commander.fixture"]
	var discovered: Array[StringName] = []
	var settlements: Array[SettlementReceiptState] = []
	var records: Array[CommanderChallengeRecordState] = []
	var profile := ProfileState.new(
		PROFILE_ID, one, 0, unlocked, discovered, 0, settlements, &"settings.default",
		null, records
	)
	return SaveRoot.new(
		SaveJsonCodec.SCHEMA_VERSION,
		CONTENT_VERSION,
		"0.2.0",
		1,
		1,
		"2026-07-13T00:00:00Z",
		profile,
		run
	)

static func create_receipt() -> PinnedCatalogBuildReceipt:
	var enabled: Array[StringName] = [
		&"commander.fixture", &"config.combat_default", &"economy.fixture", &"effect.fixture",
		&"mapnode.fixture", &"meta.fixture", &"relic.fixture", &"unit.fixture"
	]
	var empty_names: Array[StringName] = []
	var map_node_defs: Array[StringName] = [&"mapnode.fixture"]
	return PinnedCatalogBuildReceipt.new(
		1, 2, CONTENT_VERSION, SELECTION_DIGEST, enabled,
		&"economy.fixture", &"config.combat_default", empty_names, map_node_defs, empty_names,
		&"meta.fixture", MANIFEST_DIGEST
	)

static func create_codec() -> SaveJsonCodec:
	return SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(create_receipt()),
		FakeContentIdMigrationPort.new()
	)

static func create_repository(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(create_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)
