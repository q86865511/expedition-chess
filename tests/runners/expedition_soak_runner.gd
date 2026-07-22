extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const ARTIFACT_PATH := "res://artifacts/test/expedition-soak.json"

var _started_at_utc := ""

func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")

func _run() -> void:
	var seed_count := _seed_count()
	if seed_count < 1:
		_finish(seed_count, ["invalid --seed-count"], 0, 3)
		return
	var failures: Array[String] = []
	var replay_count := 0
	var pool_checks := 0
	var manifest := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var catalog := EconomyTestFixture.settlement_catalog(manifest)
	for seed_index: int in range(seed_count):
		var seed_result := U64Bits.from_u32(0, seed_index)
		if not seed_result.ok:
			failures.append("seed conversion failed at %d" % seed_index)
			break
		var run_id := StringName("run_soak_%08d" % seed_index)
		var generated := MapService.new().generate_map(MapGenerationRequest.new(
			run_id, seed_result.value, catalog
		))
		if not generated.ok or not _map_is_valid(generated.map_state):
			failures.append("map invariant failed at %d" % seed_index)
			break
		if seed_index < mini(seed_count, 64):
			var replay := MapService.new().generate_map(MapGenerationRequest.new(
				run_id, seed_result.value, catalog
			))
			if not replay.ok or _map_digest(replay.map_state) != _map_digest(generated.map_state):
				failures.append("map replay drift at %d" % seed_index)
				break
			replay_count += 1
		var shop_rng := RngService.new().derive_stream(
			seed_result.value, &"shop", StringName("%s:shop_v1" % String(run_id))
		)
		if not shop_rng.ok:
			failures.append("shop RNG derive failed at %d" % seed_index)
			break
		var no_owners: Array[ReservationOwnerState] = []
		var generated_shop := ShopService.new().generate_offers(GenerateOffersRequest.new(
			run_id, StringName(generated.map_state.nodes[0].node_id),
			EconomyState.new(20, 3, 0, 0, 0, 0, []),
			catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
			no_owners, shop_rng.snapshot, U64Bits.zero(), U64Bits.one(), catalog
		))
		if not generated_shop.ok or not _reservation_ledger_is_valid(generated_shop.transaction):
			failures.append("shop pool invariant failed at %d" % seed_index)
			break
		pool_checks += 1
	_finish(
		seed_count, failures, replay_count, 0 if failures.is_empty() else 2,
		pool_checks
	)

func _map_is_valid(map: MapState) -> bool:
	if map == null:
		return false
	var seen_nodes: Dictionary = {}
	var ordered_layers: Array[Array] = []
	for act: int in range(1, 4):
		for layer_index: int in range(7):
			var layer: Array[MapNodeState] = []
			for node: MapNodeState in map.nodes:
				if node.act_index == act and node.layer_index == layer_index:
					if seen_nodes.has(node.node_id) or node.slot_index != layer.size():
						return false
					seen_nodes[node.node_id] = true
					layer.append(node)
			var expected_width := 1 if layer_index in [0, 5, 6] else -1
			if (expected_width == 1 and layer.size() != 1) \
				or (expected_width < 0 and layer.size() not in [2, 3]):
				return false
			for node: MapNodeState in layer:
				if layer_index == 0 and node.node_kind != MapNodeState.NodeKind.NORMAL:
					return false
				if layer_index in [1, 3] and node.node_kind not in [
					MapNodeState.NodeKind.NORMAL, MapNodeState.NodeKind.ELITE,
				]:
					return false
				if layer_index in [2, 4] and node.node_kind not in [
					MapNodeState.NodeKind.MERCHANT, MapNodeState.NodeKind.EVENT,
					MapNodeState.NodeKind.TREASURE,
				]:
					return false
				if layer_index == 5 and node.node_kind != MapNodeState.NodeKind.REST:
					return false
				if layer_index == 6 and node.node_kind != MapNodeState.NodeKind.BOSS:
					return false
			ordered_layers.append(layer)
	if seen_nodes.size() != map.nodes.size() or ordered_layers.size() != 21:
		return false
	var expected_edges: Dictionary = {}
	for layer_index: int in range(ordered_layers.size() - 1):
		for left: MapNodeState in ordered_layers[layer_index]:
			for right: MapNodeState in ordered_layers[layer_index + 1]:
				expected_edges[left.node_id + ">" + right.node_id] = true
	if map.edges.size() != expected_edges.size():
		return false
	for edge: MapEdgeState in map.edges:
		var edge_key := edge.from_node_id + ">" + edge.to_node_id
		if not expected_edges.has(edge_key):
			return false
		expected_edges.erase(edge_key)
	return expected_edges.is_empty()

func _reservation_ledger_is_valid(transaction: ShopTransaction) -> bool:
	if transaction == null:
		return false
	var live_references: Dictionary = {}
	var active_copies: Dictionary = {}
	for owner: ReservationOwnerState in transaction.reservation_owners:
		if owner.status == ReservationOwnerState.Status.ACTIVE:
			live_references[owner.key.digest] = 0
			active_copies[owner.unit_def_id] = int(
				active_copies.get(owner.unit_def_id, 0)
			) + owner.reserved_copies
	for offer: ShopOffer in transaction.economy_state.shop_offers:
		var owner: ReservationOwnerState = null
		for candidate: ReservationOwnerState in transaction.reservation_owners:
			if candidate.key.digest == offer.reservation_owner_key.digest:
				owner = candidate
				break
		if owner == null or owner.status != ReservationOwnerState.Status.ACTIVE \
			or owner.unit_def_id != offer.unit_def_id \
			or owner.reserved_copies != offer.reserved_copies:
			return false
		live_references[owner.key.digest] = int(live_references.get(owner.key.digest, 0)) + 1
	for owner: ReservationOwnerState in transaction.reservation_owners:
		var count := int(live_references.get(owner.key.digest, 0))
		if (owner.status == ReservationOwnerState.Status.ACTIVE and count != 1) \
			or (owner.status != ReservationOwnerState.Status.ACTIVE and count != 0):
			return false
	for entry: UnitPoolEntryState in transaction.unit_pool_state.entries:
		if entry.remaining_copies + entry.reserved_copies + entry.held_copies \
			!= entry.total_copies \
			or entry.reserved_copies != int(active_copies.get(entry.unit_def_id, 0)):
			return false
	return true

func _map_digest(map: MapState) -> String:
	var parts: Array[String] = ["MAP-SOAK-1"]
	for node: MapNodeState in map.nodes:
		parts.append(node.node_id)
	for edge: MapEdgeState in map.edges:
		parts.append(edge.from_node_id + ">" + edge.to_node_id)
	return EconomyPayloadDigest.sha256(parts)

func _seed_count() -> int:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--seed-count":
			return int(arguments[index + 1])
	return 10000

func _finish(
	seed_count: int,
	failures: Array[String],
	replay_count: int,
	exit_code: int,
	pool_checks: int = 0
) -> void:
	var completed: Array[String] = []
	if failures.is_empty():
		completed = [
			"three_act_full_topology_seed_soak",
			"shop_reservation_ledger_seed_soak",
			"deterministic_map_replay",
		]
	var deferred: Array[String] = []
	var report := Support.base_report(
		"economy-expedition-soak", _started_at_utc, completed, deferred
	)
	report["scope"] = "economy-expedition"
	report["seed_count"] = seed_count
	report["case_count"] = seed_count
	report["deterministic_replay_count"] = replay_count
	report["pool_conservation_checks"] = pool_checks
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var written := Support.write_json_artifact(ARTIFACT_PATH, report)
	quit(3 if written != OK else exit_code)
