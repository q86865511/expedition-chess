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
	var build_op_count := 0
	var manifest := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var catalog := EconomyTestFixture.settlement_catalog(manifest)
	# T12：把路線／經濟遺物織入遠征走訪——遺物表釘在與 catalog 同一 manifest 世代（世代守衛
	# 通過路徑），active_relic_ids 依 slot 序固定啟用；路線遺物把首個 branch anchor 逼為 ELITE、
	# 經濟遺物給商店折扣。兩者皆決定性、無新 entropy（見 map_service.gd 註解），replay 逐位元一致。
	var relic_table := _expedition_relic_table(manifest)
	var active_relic_ids: Array[StringName] = [&"relic.route_a", &"relic.eco_a"]
	for seed_index: int in range(seed_count):
		var seed_result := U64Bits.from_u32(0, seed_index)
		if not seed_result.ok:
			failures.append("seed conversion failed at %d" % seed_index)
			break
		var run_id := StringName("run_soak_%08d" % seed_index)
		var generated := MapService.new().generate_map(MapGenerationRequest.new(
			run_id, seed_result.value, catalog, relic_table, active_relic_ids
		))
		if not generated.ok or not _map_is_valid(generated.map_state):
			failures.append("map invariant failed at %d" % seed_index)
			break
		if seed_index < mini(seed_count, 64):
			var replay := MapService.new().generate_map(MapGenerationRequest.new(
				run_id, seed_result.value, catalog, relic_table, active_relic_ids
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
			no_owners, shop_rng.snapshot, U64Bits.zero(), U64Bits.one(), catalog,
			relic_table, active_relic_ids
		))
		if not generated_shop.ok or not _reservation_ledger_is_valid(generated_shop.transaction):
			failures.append("shop pool invariant failed at %d" % seed_index)
			break
		pool_checks += 1
		# T12：決定性構築操作走訪（鍛造→換裝→拆卸→overflow 處置），以 reward 具名 stream 決策。
		var build := _build_walk(run_id, seed_result.value)
		if not build.get("ok", false):
			failures.append("build walk failed at %d: %s" % [seed_index, build.get("reason", "?")])
			break
		build_op_count += int(build.get("ops", 0))
		if seed_index < mini(seed_count, 64):
			var build_replay := _build_walk(run_id, seed_result.value)
			if not build_replay.get("ok", false) \
				or build_replay.get("digest", "") != build.get("digest", ""):
				failures.append("build walk replay drift at %d" % seed_index)
				break
	_finish(
		seed_count, failures, replay_count, 0 if failures.is_empty() else 2,
		pool_checks, build_op_count
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
	pool_checks: int = 0,
	build_op_count: int = 0
) -> void:
	var completed: Array[String] = []
	if failures.is_empty():
		completed = [
			"three_act_full_topology_seed_soak",
			"shop_reservation_ledger_seed_soak",
			"deterministic_map_replay",
			"relic_route_and_economy_effect_seed_soak",
			"deterministic_build_operation_walk",
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
	report["build_operation_count"] = build_op_count
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var written := Support.write_json_artifact(ARTIFACT_PATH, report)
	quit(3 if written != OK else exit_code)

# --- T12 遺物與構築操作走訪 helpers ---------------------------------------

## 遠征走訪用的最小遺物表：一件路線遺物（佔 branch anchor）＋一件經濟遺物（商店折扣），
## 皆釘在傳入的 manifest 世代（與 catalog 同世代，通過各 service 的 F7 世代守衛）。
func _expedition_relic_table(manifest_digest: String) -> RunRelicTable:
	var route_op := RunRelicOperationRule.new()
	route_op.operation_index = 0
	route_op.kind = &"add_gold"
	route_op.amount = 0
	route_op.claim_scope = &"always"
	var route_rule := RunRelicRule.new()
	route_rule.relic_id = &"relic.route_a"
	route_rule.category = &"route"
	route_rule.effect_ids = [&"effect.fixture"]
	route_rule.run_operations = [route_op]
	var eco_op := RunRelicOperationRule.new()
	eco_op.operation_index = 0
	eco_op.kind = &"shop_discount"
	eco_op.amount = 1
	eco_op.claim_scope = &"always"
	var eco_rule := RunRelicRule.new()
	eco_rule.relic_id = &"relic.eco_a"
	eco_rule.category = &"economy"
	eco_rule.effect_ids = [&"effect.fixture"]
	eco_rule.run_operations = [eco_op]
	return RunRelicTable.new(manifest_digest, [route_rule, eco_rule])

## 決定性構築操作走訪：鍛造→換裝→拆卸→overflow 處置，全程走真實 domain command 的 apply_to
## （不落存檔）。唯一的 RNG 決策是 overflow 的處置種類（abandon/forge），由 reward 具名 stream
## 抽出——同 seed 同抽值 → 同最終 roster digest，replay 逐位元一致。回傳 {ok, ops, digest, reason}。
func _build_walk(run_id: StringName, run_seed: U64Bits) -> Dictionary:
	var derived := RngService.new().derive_stream(
		run_seed, &"reward", StringName("%s:build_v1" % String(run_id))
	)
	if not derived.ok:
		return {"ok": false, "ops": 0, "reason": "build stream derive"}
	var stream := derived.stream
	var run := _build_base_run()
	var digest := run.content_snapshot.manifest_digest_value()
	var forge_table := ResolveOverflowTestFixture.forge_table(digest)
	var battle_catalog := ResolveOverflowTestFixture.battle_catalog(digest)
	var consumable_rules := EquipDismantleTestFixture.consumable_rules(digest)
	var ops := 0
	# W4-F8:逐步追蹤 item_instances 總數,依各步驟操作語意斷言操作前後守恆
	# （讀 command apply_to 實作決定的精確預期,非猜測值）。base run 起始 5 件
	# （it_1..it_5）。
	var item_total := run.roster_state.item_instances.size()

	# 1) 鍛造：ovf_alpha(it_1) + ovf_beta(it_2) → equipment.ovf_forged 入 inventory
	# （ForgeEquipmentCommand 消耗 2 個 component、產出 1 個裝備，總數 -1）。
	var forged := ForgeEquipmentCommand.new(
		ResolveOverflowTestFixture.item_id(1), ResolveOverflowTestFixture.item_id(2), forge_table
	).apply_to(run)
	if not forged.ok:
		return {"ok": false, "ops": ops, "reason": "forge"}
	run = forged.draft
	ops += 1
	item_total -= 1
	if run.roster_state.item_instances.size() != item_total:
		return {"ok": false, "ops": ops, "reason": "forge item total"}
	var forged_id := _find_unbound_item_by_def(run, ResolveOverflowTestFixture.EQUIPMENT_FORGED)
	if forged_id.is_empty():
		return {"ok": false, "ops": ops, "reason": "forged missing"}

	# 2) 換裝：把鍛造出的裝備綁到 benched 棋 u_...1（EquipItemCommand 只改綁定狀態，
	# 不增減 item_instances，總數不變）。
	var equipped := EquipItemCommand.new(_unit_one(), forged_id, battle_catalog).apply_to(run)
	if not equipped.ok:
		return {"ok": false, "ops": ops, "reason": "equip"}
	run = equipped.draft
	ops += 1
	if run.roster_state.item_instances.size() != item_total:
		return {"ok": false, "ops": ops, "reason": "equip item total"}

	# 3) 拆卸：用 dismantle_kit(it_3) 卸下該裝備、退回 inventory（DismantleEquipmentCommand
	# 消耗掉該消耗品、裝備本身保留只是解綁，總數 -1）。
	var dismantled := DismantleEquipmentCommand.new(
		forged_id, ResolveOverflowTestFixture.item_id(3), consumable_rules
	).apply_to(run)
	if not dismantled.ok:
		return {"ok": false, "ops": ops, "reason": "dismantle"}
	run = dismantled.draft
	ops += 1
	item_total -= 1
	if run.roster_state.item_instances.size() != item_total:
		return {"ok": false, "ops": ops, "reason": "dismantle item total"}

	# 4) overflow 處置：tray 內預置 ovf_alpha(it_5)，依 stream 抽 abandon（消耗 1 個，-1）
	# 或 forge（配 it_4 的 ovf_beta，消耗 2 個、產出 1 個，同為 -1）——兩條路徑總數皆 -1。
	var pick := stream.next_bounded(2)
	if not pick.ok:
		return {"ok": false, "ops": ops, "reason": "overflow pick"}
	var disposition: CommandApplyResult
	if pick.value_u32.low_u32() == 0:
		disposition = ResolveOverflowCommand.abandon(ResolveOverflowTestFixture.item_id(5)).apply_to(run)
	else:
		disposition = ResolveOverflowCommand.forge(
			ResolveOverflowTestFixture.item_id(5), ResolveOverflowTestFixture.item_id(4), forge_table
		).apply_to(run)
	if not disposition.ok:
		return {"ok": false, "ops": ops, "reason": "overflow resolve"}
	run = disposition.draft
	ops += 1
	item_total -= 1
	if run.roster_state.item_instances.size() != item_total:
		return {"ok": false, "ops": ops, "reason": "overflow item total"}

	if not _items_conserved(run):
		return {"ok": false, "ops": ops, "reason": "item conservation"}
	return {"ok": true, "ops": ops, "digest": _roster_digest(run), "reason": ""}

## PREPARE 期 base run：1 隻 benched 棋、inventory 內兩對鍛造零件＋一個 dismantle_kit，
## overflow tray 預置一個零件（供處置步驟）。全部釘在 ResolveOverflowTestFixture 的世代。
func _build_base_run() -> RunState:
	var run := ResolveOverflowTestFixture.base_run(1)
	var items: Array[ItemInstanceState] = [
		ResolveOverflowTestFixture.item(ResolveOverflowTestFixture.item_id(1), ResolveOverflowTestFixture.COMPONENT_ALPHA),
		ResolveOverflowTestFixture.item(ResolveOverflowTestFixture.item_id(2), ResolveOverflowTestFixture.COMPONENT_BETA),
		ResolveOverflowTestFixture.item(ResolveOverflowTestFixture.item_id(3), &"consumable.dismantle_kit"),
		ResolveOverflowTestFixture.item(ResolveOverflowTestFixture.item_id(4), ResolveOverflowTestFixture.COMPONENT_BETA),
		ResolveOverflowTestFixture.item(ResolveOverflowTestFixture.item_id(5), ResolveOverflowTestFixture.COMPONENT_ALPHA),
	]
	run.roster_state.item_instances = items
	run.roster_state.inventory_item_instance_ids = [
		ResolveOverflowTestFixture.item_id(1), ResolveOverflowTestFixture.item_id(2),
		ResolveOverflowTestFixture.item_id(3), ResolveOverflowTestFixture.item_id(4),
	]
	run.roster_state.pending_item_overflow = [ResolveOverflowTestFixture.item_id(5)]
	return run

func _unit_one() -> String:
	return ResolveOverflowTestFixture.unit_id(1)

func _find_unbound_item_by_def(run: RunState, def_id: StringName) -> String:
	for item_instance: ItemInstanceState in run.roster_state.item_instances:
		if item_instance.def_id == def_id and item_instance.bound_unit_instance_id == null:
			return item_instance.instance_id
	return ""

## roster 的最小結構摘要，用於 replay 逐位元比對（inventory／overflow／每棋裝備綁定）。
func _roster_digest(run: RunState) -> String:
	var parts: Array[String] = ["BUILD-SOAK-1"]
	var inventory := run.roster_state.inventory_item_instance_ids.duplicate()
	inventory.sort()
	parts.append("inv:" + "/".join(inventory))
	var overflow := run.roster_state.pending_item_overflow.duplicate()
	overflow.sort()
	parts.append("ovf:" + "/".join(overflow))
	for item_instance: ItemInstanceState in run.roster_state.item_instances:
		var bound := item_instance.bound_unit_instance_id.value if item_instance.bound_unit_instance_id != null else ""
		parts.append("it:%s:%s:%s" % [item_instance.instance_id, String(item_instance.def_id), bound])
	parts.sort()
	return EconomyPayloadDigest.sha256(parts)

## 物品守恆不變式：每個 instance id 唯一，且每件綁定裝備都指向一隻真實 roster 棋。
func _items_conserved(run: RunState) -> bool:
	var seen: Dictionary = {}
	var unit_ids: Dictionary = {}
	for unit: UnitInstance in run.roster_state.unit_instances:
		unit_ids[unit.instance_id] = true
	for item_instance: ItemInstanceState in run.roster_state.item_instances:
		if seen.has(item_instance.instance_id):
			return false
		seen[item_instance.instance_id] = true
		if item_instance.bound_unit_instance_id != null \
			and not unit_ids.has(item_instance.bound_unit_instance_id.value):
			return false
	return true
