extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)

var _harness: Support.BootHarness


func test_world_drop_uses_typed_preview_before_commit_and_rejects_without_dispatch() -> void:
	_harness = Support.boot_runtime(get_tree())
	await wait_process_frames(2)
	assert_not_null(_harness)
	assert_eq(_harness.boot_error, &"")
	assert_eq(_harness.settings_bind_error, &"")
	if (
		_harness == null
		or not _harness.boot_error.is_empty()
		or not _harness.settings_bind_error.is_empty()
	):
		await _dispose_harness()
		return
	var driven := Support.drive_to_run_prepare(_harness)
	assert_true(
		bool(driven.get("ok", false)),
		"production intent flow must reach RUN_PREPARE: %s"
		% String(driven.get("error", &""))
	)
	if not bool(driven.get("ok", false)):
		await _dispose_harness()
		return
	await wait_process_frames(4)

	var initial := _active_prepare_fixture()
	assert_true(
		bool(initial.get("ok", false)),
		"production prepare fixture missing: %s" % initial.get("error", "")
	)
	if not bool(initial.get("ok", false)):
		await _dispose_harness()
		return
	var supply := initial.get("supply") as LiveScreenSupplyPort
	var initial_composition := initial.get("composition") as RunPrepareScreen
	var initial_composition_id := initial_composition.get_instance_id()
	var committed := supply.try_committed_board_preview()
	assert_not_null(committed)
	assert_gt(
		committed.derived_capacity if committed != null else 0,
		0,
		"typed committed preview must expose the canonical capacity"
	)
	if committed == null or committed.derived_capacity <= 0:
		await _dispose_harness()
		return

	var required_unit_count := committed.derived_capacity + 1
	var stocked := await _ensure_deployable_unit_count(required_unit_count)
	assert_true(
		bool(stocked.get("ok", false)),
		"fixture could not stock capacity + 1 units: %s"
		% String(stocked.get("error", ""))
	)
	if not bool(stocked.get("ok", false)):
		await _dispose_harness()
		return
	await wait_process_frames(4)
	var replacement := _active_prepare_fixture()
	assert_true(
		bool(replacement.get("ok", false)),
		"route replacement must remount the typed world path: %s"
		% String(replacement.get("error", ""))
	)
	if not bool(replacement.get("ok", false)):
		await _dispose_harness()
		return
	var replacement_composition := replacement.get(
		"composition"
	) as RunPrepareScreen
	var replacement_target := replacement.get("target") as WorldBoardDragTarget
	var replacement_resolver: Callable = replacement_target.get(
		"_unit_drop_resolver"
	)
	assert_ne(
		replacement_composition.get_instance_id(),
		initial_composition_id,
		"synchronous command publication must install a new route composition"
	)
	assert_same(
		replacement_resolver.get_object(),
		replacement_composition,
		"persistent world target resolver must belong to the new composition"
	)

	# Fill the canonical player half through the same public payload and formal
	# projected drop target used by the live screen. Calling the engine DnD
	# callbacks is intentional; the test never calls RunPrepareScreen's private
	# drop/commit handlers directly.
	while _canonical_board_count() < committed.derived_capacity:
		var reload_error := Support.reload_current_route(_harness)
		assert_eq(reload_error, &"", "formal route reload must remount world overlay")
		if not reload_error.is_empty():
			await _dispose_harness()
			return
		await wait_process_frames(4)
		var legal_fixture := _active_prepare_fixture()
		assert_true(
			bool(legal_fixture.get("ok", false)),
			"route replacement lost production path: %s"
			% String(legal_fixture.get("error", ""))
		)
		if not bool(legal_fixture.get("ok", false)):
			await _dispose_harness()
			return
		var legal_cell := _first_empty_player_cell()
		var before_digest := _canonical_layout_digest()
		var exercised := _exercise_projected_drop(legal_fixture, legal_cell)
		assert_true(
			bool(exercised.get("accepted", false)),
			"capacity-filling preview must be legal: %s"
			% String(exercised.get("error", ""))
		)
		var panel := exercised.get("panel") as Label
		assert_not_null(panel)
		if panel != null:
			assert_true(panel.visible)
			assert_eq(panel.get_meta(&"typed_data_kind"), &"board_draft_preview")
			assert_true(bool(panel.get_meta(&"preview_valid", false)))
			assert_false(String(panel.get_meta(&"accessible_text", "")).is_empty())
		if not bool(exercised.get("accepted", false)):
			await _dispose_harness()
			return
		(exercised.get("target") as WorldBoardDragTarget).call(
			&"_drop_data",
			exercised.get("local_position", Vector2.ZERO),
			exercised.get("payload", {})
		)
		await wait_process_frames(5)
		assert_ne(
			_canonical_layout_digest(),
			before_digest,
			"legal world drop must converge on commit_board_draft()"
		)

	var illegal_fixture := _active_prepare_fixture()
	assert_true(
		bool(illegal_fixture.get("ok", false)),
		"post-commit prepare route must remain mounted"
	)
	if not bool(illegal_fixture.get("ok", false)):
		await _dispose_harness()
		return
	var illegal_screen := illegal_fixture.get("screen") as ProductionScreen
	var illegal_cell := _first_empty_player_cell()
	var canonical_before := _canonical_layout_digest()
	var persisted_before := _canonical_bytes()
	var result_before: Variant = illegal_screen.last_control_result()
	var rejected := _exercise_projected_drop(illegal_fixture, illegal_cell)
	assert_false(
		bool(rejected.get("accepted", true)),
		"capacity + 1 candidate must be rejected by the typed preview authority"
	)
	var rejected_panel := rejected.get("panel") as Label
	assert_not_null(rejected_panel)
	if rejected_panel != null:
		assert_true(rejected_panel.visible)
		assert_false(bool(rejected_panel.get_meta(&"preview_valid", true)))
		var issue_codes: Array[StringName] = []
		issue_codes.assign(rejected_panel.get_meta(&"issue_codes", []))
		assert_true(issue_codes.has(BoardValidationIssue.OVER_CAPACITY))
	var rejected_target := rejected.get("target") as WorldBoardDragTarget
	if rejected_target != null:
		# Exercise the consumer-side authoritative recheck as well. Native Godot
		# DnD would not call _drop_data after a false _can_drop_data result; this
		# deliberate call proves even a forged delivery cannot dispatch a command.
		rejected_target.call(
			&"_drop_data",
			rejected.get("local_position", Vector2.ZERO),
			rejected.get("payload", {})
		)
	await wait_process_frames(5)
	assert_eq(
		_canonical_layout_digest(),
		canonical_before,
		"illegal drop must preserve the canonical RunState digest"
	)
	assert_eq(
		_canonical_bytes(),
		persisted_before,
		"illegal drop must not publish a save or dispatch a layout command"
	)
	assert_same(
		illegal_screen.last_control_result(),
		result_before,
		"illegal drop must not report a command result because no dispatch occurred"
	)
	await _dispose_harness()


func _active_prepare_fixture() -> Dictionary:
	var screen := Support.active_screen(_harness)
	var composition := (
		screen.get_node_or_null(^"Composition") as RunPrepareScreen
		if screen != null and screen.route_kind == &"RUN_PREPARE"
		else null
	)
	var live_context := (
		screen.get("_live_context") as ProductionLiveScreenContext
		if screen != null
		else null
	)
	var surface := _production_world_surface()
	var overlay := surface.ui_overlay() if surface != null else null
	var target := overlay.drag_target() if overlay != null else null
	var mapper := (
		_harness.viewport_coordinator.coordinate_mapper_clone()
		if _harness != null and _harness.viewport_coordinator != null
		else null
	)
	if screen == null:
		return {"ok": false, "error": "screen_missing"}
	if composition == null:
		return {"ok": false, "error": "composition_missing"}
	if live_context == null or live_context.supply_port == null:
		return {"ok": false, "error": "typed_supply_missing"}
	if surface == null or target == null or mapper == null:
		return {
			"ok": false,
			"error": "production_world_path_missing:surface=%s,target=%s,mapper=%s,mount=%s"
			% [
				surface != null,
				target != null,
				mapper != null,
				String(composition.world_board_mount_error()),
			],
		}
	var resolver: Callable = target.get("_unit_drop_resolver")
	if not resolver.is_valid() or resolver.get_object() != composition:
		return {"ok": false, "error": "production_preview_resolver_missing"}
	return {
		"ok": true,
		"screen": screen,
		"composition": composition,
		"supply": live_context.supply_port,
		"target": target,
		"mapper": mapper,
	}


func _exercise_projected_drop(
	fixture: Dictionary,
	target_cell: Vector2i
) -> Dictionary:
	var composition := fixture.get("composition") as RunPrepareScreen
	var target := fixture.get("target") as WorldBoardDragTarget
	var mapper: Object = fixture.get("mapper")
	var source := _first_bench_drag_source(composition)
	if source == null:
		return {"accepted": false, "error": "bench_source_missing"}
	var payload: Variant = source.unit_drag_payload()
	if not payload is Dictionary:
		return {"accepted": false, "error": "public_payload_missing"}
	var screen_position: Vector2 = mapper.call(
		&"world_to_screen",
		BoardProjection.new().project_cell(target_cell)
	)
	var local_position := (
		target.get_global_transform_with_canvas().affine_inverse()
		* screen_position
	)
	var accepted := bool(target.call(
		&"_can_drop_data", local_position, payload
	))
	return {
		"accepted": accepted,
		"error": "",
		"panel": composition.find_child(
			"BoardDraftPreview", true, false
		) as Label,
		"target": target,
		"local_position": local_position,
		"payload": payload,
	}


func _ensure_deployable_unit_count(required: int) -> Dictionary:
	for _attempt: int in range(24):
		var run := _canonical_run()
		if run == null:
			return {"ok": false, "error": "canonical_run_missing"}
		var count := (
			run.roster_state.board.placements.size()
			+ run.roster_state.bench_unit_instance_ids.size()
		)
		if count >= required:
			return {"ok": true}
		var screen := Support.active_screen(_harness)
		if screen == null:
			return {"ok": false, "error": "prepare_screen_missing"}
		var refreshed := screen.request_intent(
			RunPresentationIntent.new(RunPresentationIntent.Kind.REFRESH_SHOP)
		)
		if not refreshed.ok or refreshed.snapshot == null:
			return {"ok": false, "error": "shop_refresh_failed"}
		await wait_process_frames(4)
		var offers: Array[ShopOffer] = []
		offers.assign(refreshed.snapshot.economy.shop_offers)
		var purchased := false
		for offer: ShopOffer in offers:
			screen = Support.active_screen(_harness)
			if screen == null or offer == null:
				continue
			var buy := RunPresentationIntent.new(
				RunPresentationIntent.Kind.BUY_UNIT
			)
			buy.offer_id = offer.offer_id
			var result := screen.request_intent(buy)
			if result.ok:
				purchased = true
				await wait_process_frames(4)
				break
		if not purchased:
			return {"ok": false, "error": "affordable_offer_missing"}
	return {"ok": false, "error": "stock_attempts_exhausted"}


func _first_bench_drag_source(
	composition: RunPrepareScreen
) -> PrepareUnitDragButton:
	if composition == null:
		return null
	for node: Node in composition.find_children(
		"BenchCell*", "Button", true, false
	):
		var source := node as PrepareUnitDragButton
		if (
			source != null
			and not String(source.get_meta(&"unit_instance_id", "")).is_empty()
		):
			return source
	return null


func _first_empty_player_cell() -> Vector2i:
	var run := _canonical_run()
	if run == null:
		return Vector2i(-1, -1)
	for y: int in range(BoardPreparationValidator.PLAYER_MAX_Y + 1):
		for x: int in range(BoardPreparationValidator.BOARD_WIDTH):
			var cell := Vector2i(x, y)
			var occupied := false
			for placement: BoardPlacementState in run.roster_state.board.placements:
				if (
					placement != null
					and placement.logical_x == x
					and placement.logical_y == y
				):
					occupied = true
					break
			if not occupied:
				return cell
	return Vector2i(-1, -1)


func _production_world_surface() -> ProductionWorldSurface:
	for node: Node in get_tree().get_nodes_in_group(
		ProductionWorldSurface.MOUNT_GROUP
	):
		var surface := node as ProductionWorldSurface
		if surface != null:
			return surface
	return null


func _canonical_run() -> RunState:
	if _harness == null or _harness.repository == null:
		return null
	var loaded: LoadResult = _harness.repository.load()
	return loaded.run if loaded.ok else null


func _canonical_board_count() -> int:
	var run := _canonical_run()
	return (
		run.roster_state.board.placements.size()
		if run != null and run.roster_state != null
		else -1
	)


func _canonical_layout_digest() -> String:
	var run := _canonical_run()
	if run == null or run.roster_state == null:
		return ""
	var placements := PackedStringArray()
	for placement: BoardPlacementState in run.roster_state.board.placements:
		placements.append("%d:%d:%s" % [
			placement.logical_y,
			placement.logical_x,
			placement.unit_instance_id,
		])
	placements.sort()
	var bench := PackedStringArray(run.roster_state.bench_unit_instance_ids)
	return ("%s#%s" % [
		",".join(placements),
		",".join(bench),
	]).sha256_text()


func _canonical_bytes() -> PackedByteArray:
	if _harness == null or _harness.repository == null:
		return PackedByteArray()
	var storage := _harness.repository.get("_storage") as FakeSaveStorage
	if storage == null:
		return PackedByteArray()
	var stored := storage.file_bytes(StorageFaultKey.MAIN)
	return stored.value.duplicate() if stored != null else PackedByteArray()


func _dispose_harness() -> void:
	if _harness != null:
		_harness.dispose()
		_harness = null
	await wait_process_frames(4)
