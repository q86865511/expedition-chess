class_name BuildLabSession
extends RefCounted

## T11 (specs/build-systems/design.md §8) -- Build Lab 灰盒場景的操作流入口。
## 這是第一個把 RunController 接上「真正雙 pack 內容經 ContentRegistry 安裝＋
## pinned BattleRuleCatalog」的 composition 場景(HANDOFF §2 消費契約：只持
## clone/snapshot、寫操作一律經 RunController.dispatch())。初始 roster 直接
## 構造在 REWARD/RELIC_RESOLUTION 階段 -- forge/equip/resolve_overflow 不檢查
## run_phase(只有 ResolveOverflowCommand 檢查 tray 成員、跟 run_state_validator
## 的 COMBAT/MAP/RESULTS 硬 gate 無關);content-production 起 dismantle 需
## Idle resolution,故 dismantle_demo 內先 advance 收掉 reward 流程,示範順序為
## 鍛造／換裝／遺物替換／overflow 處置／(advance＋)拆卸,不需要真的跑一輪
## 地圖/戰鬥去推進 phase。

const UNIT_A_ID: String = "u_0000000000000000"
const UNIT_B_ID: String = "u_0000000000000001"
const ITEM_EQUIPPED_ID: String = "it_0000000000000000"
const ITEM_COMPONENT_A_ID: String = "it_0000000000000001"
const ITEM_COMPONENT_B_ID: String = "it_0000000000000002"
const ITEM_LOOSE_EQUIPMENT_ID: String = "it_0000000000000003"
const ITEM_DISMANTLE_CONSUMABLE_ID: String = "it_0000000000000004"
const ITEM_OVERFLOW_ID: String = "it_0000000000000005"

const UNIT_A_DEF: StringName = &"unit.slice_player_00"
const UNIT_B_DEF: StringName = &"unit.slice_player_01"
const EQUIPPED_DEF: StringName = &"equipment.iron_iron"
const COMPONENT_DEF: StringName = &"item_component.iron_plate"
const LOOSE_EQUIPMENT_DEF: StringName = &"equipment.frost_frost"
const OVERFLOW_COMPONENT_DEF: StringName = &"item_component.ember_shard"
const COMMANDER_ID: StringName = &"commander.slice_c0"

const RELIC_SLOT_IDS: Array[StringName] = [
	&"relic.iron_will", &"relic.golden_ledger", &"relic.pathfinder_boots",
	&"relic.arbiter_seal", &"relic.frost_edge",
]
const RELIC_OFFER_ID: StringName = &"relic.shadow_veil"
const RELIC_REPLACE_SLOT_INDEX: int = 0

const _PROFILE_ID: String = "00000000000000000000000000000001"

var _bootstrap: BuildLabBootstrapResult
var _catalog_lease: CatalogLease
var _controller: RunController
var _save_repository: SaveRepository

var _trait_preview: TraitPreviewViewModel
var _forge: ForgeViewModel
var _inventory: InventoryViewModel
var _relic_slot: RelicSlotViewModel

## `host` 只用來掛載 SaveRepository(extends Node)避免變成 orphan node -- 呼叫端
## (build_lab.gd)傳入自己即可,不需要對它做任何其他事。
func initialize(registry: ContentRegistryService, host: Node) -> String:
	_bootstrap = BuildLabContentBootstrap.new().run(registry)
	if not _bootstrap.ok:
		return _bootstrap.error_message

	var handle_result := registry.catalog_handle(_bootstrap.manifest_digest)
	if not handle_result.ok:
		return "catalog_handle failed: %s" % handle_result.error.code
	var lease_result := registry.acquire_catalog_lease(handle_result.value)
	if not lease_result.ok:
		return "acquire_catalog_lease failed: %s" % lease_result.error.code
	_catalog_lease = lease_result.lease

	# T11 wave4:雙 pack 已補齊 meta_reward_table 內容(見
	# content/packs/vertical_slice/README.md「T11 wave4 內容缺口修復」),
	# BuildLabContentBootstrap 現在改用 registry.compile_pinned_generation() 換回
	# 真正的 PinnedCatalogBuildReceipt,ContentRegistryReceiptAdapter 的動態
	# receipt 重建不再撞上 PINNED_CATALOG_REFERENCE_MISSING,改回正常 production 路徑
	# (內容缺口修復後改回 ContentRegistryReceiptAdapter 正常路徑,W4-F9 已移除應急埠)。
	_save_repository = SaveRepository.new(
		BuildLabMemoryStorage.new(),
		ContentRegistryReceiptAdapter.new(registry),
		BuildLabActiveContentIdPort.new(),
		RunStateValidator.new()
	)
	host.add_child(_save_repository)

	var run := _build_initial_run()
	var profile := _build_profile()
	var session := RunSession.new(profile, run, _catalog_lease)
	var factory := RunSaveRootFactory.new()
	_controller = RunController.new(
		session, _save_repository, RunStateValidator.new(), factory,
		_bootstrap.battle_catalog
	)

	_trait_preview = TraitPreviewViewModel.new(_controller, _bootstrap.battle_catalog)
	_forge = ForgeViewModel.new(_controller, _bootstrap.forge_table)
	_inventory = InventoryViewModel.new(_controller)
	_relic_slot = RelicSlotViewModel.new(_controller)
	return ""

func trait_preview_view_model() -> TraitPreviewViewModel:
	return _trait_preview

func forge_view_model() -> ForgeViewModel:
	return _forge

func inventory_view_model() -> InventoryViewModel:
	return _inventory

func relic_slot_view_model() -> RelicSlotViewModel:
	return _relic_slot

## 鍛造示範:把兩個 item_component.iron_plate 自配零件合成 equipment.iron_iron。
func forge_demo() -> CommandResult:
	return _forge.forge(ITEM_COMPONENT_A_ID, ITEM_COMPONENT_B_ID)

## 換裝示範:把 inventory 中未裝備的 equipment.frost_frost 裝到 UNIT_A 身上。
func equip_demo() -> CommandResult:
	return _inventory.equip(ITEM_LOOSE_EQUIPMENT_ID, UNIT_A_ID, _bootstrap.battle_catalog)

## 拆卸示範:消耗 consumable.dismantle_kit,解綁 UNIT_B 身上的 equipment.iron_iron。
## content-production 起 DismantleEquipmentCommand 要求 Idle(或 dismantle node
## service)resolution,故先 advance 結束 reward 流程再拆卸——呼叫前需已完成
## relic 替換(READY_TO_ADVANCE)且 overflow tray 已清空。
func dismantle_demo() -> CommandResult:
	var advanced := _controller.dispatch(
		AdvanceRewardCommand.new(_bootstrap.economy_catalog)
	)
	if not advanced.ok:
		return advanced
	return _inventory.dismantle(
		ITEM_EQUIPPED_ID, ITEM_DISMANTLE_CONSUMABLE_ID, _bootstrap.consumable_rules
	)

## overflow 處置示範:把 tray 裡的 item_component.ember_shard 明確放棄。
func resolve_overflow_abandon_demo() -> CommandResult:
	return _inventory.resolve_overflow(ResolveOverflowCommand.abandon(ITEM_OVERFLOW_ID))

## 遺物替換示範:把待決 RELIC_RESOLUTION 選定的 relic.shadow_veil 放入槽 0
## (原本的 relic.iron_will 該局永久移除)。T11 wave4 起 economy_catalog 已能
## 由正式雙 pack 內容建置成功(見 build_lab_content_bootstrap.gd 註解),不再需要
## 具名內容缺口的軟性拒絕。
func resolve_relic_demo() -> CommandResult:
	return _relic_slot.choose_slot(RELIC_REPLACE_SLOT_INDEX, _bootstrap.economy_catalog)

## 供測試驗證 save/load 走 ContentRegistryReceiptAdapter 正常路徑用:每次
## dispatch() 已經過 RunController._commit_draft() 內部 save() 落盤(copy-
## validate-save-swap),這裡只是把同一份儲存讀回,exercise receipt_port.
## compile_or_lookup() 的 decode 路徑,回傳 LoadResult 供呼叫端斷言。不供
## Build Lab UI 本身使用。
func reload_from_storage_for_test() -> LoadResult:
	return _save_repository.load()

func _build_profile() -> ProfileState:
	var unlocked: Array[StringName] = [COMMANDER_ID]
	var discovered: Array[StringName] = []
	var settlements: Array[SettlementReceiptState] = []
	var records: Array[CommanderChallengeRecordState] = []
	return ProfileState.new(
		_PROFILE_ID, U64Bits.one(), 0, unlocked, discovered, 0, settlements,
		&"settings.default", null, records
	)

func _build_initial_run() -> RunState:
	var zero := U64Bits.zero()
	var one := U64Bits.one()
	var key_registry := RuntimeKeySchemaRegistry.new()
	var run_key_result := key_registry.build_run(_PROFILE_ID, zero)
	var run_key: RunKeyState = run_key_result.key_state as RunKeyState
	var run_id := String(run_key.digest)

	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, UNIT_A_ID),
		BoardPlacementState.new(0, 1, UNIT_B_ID),
	]
	var units: Array[UnitInstance] = [
		UnitInstance.new(UNIT_A_ID, UNIT_A_DEF, 1, [], zero),
		UnitInstance.new(UNIT_B_ID, UNIT_B_DEF, 1, [ITEM_EQUIPPED_ID], zero),
	]
	var items: Array[ItemInstanceState] = [
		ItemInstanceState.new(ITEM_EQUIPPED_ID, EQUIPPED_DEF, OptionalStringValue.new(UNIT_B_ID), zero),
		ItemInstanceState.new(ITEM_COMPONENT_A_ID, COMPONENT_DEF, null, zero),
		ItemInstanceState.new(ITEM_COMPONENT_B_ID, COMPONENT_DEF, null, zero),
		ItemInstanceState.new(ITEM_LOOSE_EQUIPMENT_ID, LOOSE_EQUIPMENT_DEF, null, zero),
		ItemInstanceState.new(ITEM_DISMANTLE_CONSUMABLE_ID, _bootstrap.dismantle_consumable_id, null, zero),
		ItemInstanceState.new(ITEM_OVERFLOW_ID, OVERFLOW_COMPONENT_DEF, null, zero),
	]
	var inventory_ids: Array[String] = [
		ITEM_COMPONENT_A_ID, ITEM_COMPONENT_B_ID, ITEM_LOOSE_EQUIPMENT_ID,
		ITEM_DISMANTLE_CONSUMABLE_ID,
	]
	var overflow_ids: Array[String] = [ITEM_OVERFLOW_ID]
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, OptionalStringNameValue.of(RELIC_SLOT_IDS[index])))
	var no_ids: Array[String] = []
	var roster := RosterState.new(
		BoardState.new(placements), no_ids, units, items, inventory_ids, overflow_ids, relics
	)

	var pool: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(UNIT_A_DEF, 9, 8, 0, 1),
		UnitPoolEntryState.new(UNIT_B_DEF, 9, 8, 0, 1),
	]

	# dismantle_demo 內的 advance 需要 current node 真的存在於 map,node_id 必須是
	# RuntimeKeyCodecV1 的 node key digest(run_state_validator 驗 node_id==key.digest)
	var node_key_result := key_registry.build_node(StringName(run_id), 0, &"merchant", 0, 0)
	var node_key: NodeKeyState = node_key_result.key_state as NodeKeyState
	var node_id := String(node_key.digest)
	var demo_node := MapNodeState.new(
		node_id, node_key, &"mapnode.build_lab", 0, 0, 0,
		MapNodeState.NodeKind.MERCHANT, "a".repeat(64), null, false
	)
	var map_nodes: Array[MapNodeState] = [demo_node]
	var empty_edges: Array[MapEdgeState] = []
	var empty_strings: Array[String] = []
	var map := MapState.new(map_nodes, empty_edges, OptionalStringValue.new(node_id), empty_strings)

	var empty_offers: Array[ShopOffer] = []
	var economy := EconomyState.new(20, 1, 0, 0, 0, 0, empty_offers)

	var rng_states: Array[NamedRngState] = []
	for stream_index: int in range(4):
		var snapshot_result := RngSnapshot.create(1, zero, one, zero)
		rng_states.append(NamedRngState.new(stream_index, snapshot_result.snapshot))

	var empty_ints: Array[int] = []
	var owners: Array[ReservationOwnerState] = []
	var transactions: Array[TransactionReceiptState] = []
	var claims: Array[ClaimReceiptState] = []

	var transaction_result := key_registry.build_transaction(
		StringName(run_id), &"node_build_lab_demo", &"reward", zero
	)
	var offers: Array[RewardOfferState] = [
		RewardOfferState.new(
			"choice_relic_shadow_veil", RewardOfferState.RewardKind.RELIC,
			OptionalStringNameValue.of(RELIC_OFFER_ID), 1, null, "a".repeat(64)
		),
		RewardOfferState.new(
			"choice_gold_1", RewardOfferState.RewardKind.GOLD, null, 5, null, "b".repeat(64)
		),
		RewardOfferState.new(
			"choice_gold_2", RewardOfferState.RewardKind.GOLD, null, 2, null, "c".repeat(64)
		),
	]
	var reserved: Array[ReservedCopyState] = []
	var pending := PendingRewardState.new(
		node_id, PendingRewardState.StageId.RELIC, PendingRewardState.Phase.RELIC_RESOLUTION,
		offers, reserved, OptionalStringValue.new("choice_relic_shadow_veil"), null,
		transaction_result.key_state as TransactionKeyState
	)
	var resolution := RewardPendingResolutionState.new(pending)

	var empty_names: Array[StringName] = []
	var run := RunState.new(
		run_id, run_key, zero, _bootstrap.content_snapshot, zero, _serial(2),
		_serial(6), COMMANDER_ID, 0, 0, map, OptionalStringValue.new(node_id),
		RunState.RunPhase.REWARD, 100, economy, UnitPoolState.new(pool), roster, 0, 0, 0,
		rng_states, empty_strings, empty_ints, owners, transactions, claims, resolution,
		empty_names
	)
	return run

## next_unit_serial／next_item_serial 都是小整數(初始 seed 只需 2/6),U64Bits
## 沒有 from_int() -- 用 one() 疊加到目標值,避免手刻 32/32 位切分。
func _serial(count: int) -> U64Bits:
	var value := U64Bits.zero()
	for _index: int in range(count):
		value = value.add(U64Bits.one())
	return value
