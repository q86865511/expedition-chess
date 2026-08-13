extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)

## A successful board-layout command publishes a new save root, so the save
## timestamp is expected to change alongside the two layout fields. Every other
## persisted field is an explicit denylist: the helpers below diff the full
## SaveJsonCodec document and hash it again after removing only these roots.
const REQUIRED_LAYOUT_MUTATION_ROOTS: Array[String] = [
	"run.roster_state.board",
	"run.roster_state.bench_unit_instance_ids",
]
const ALLOWED_CANONICAL_MUTATION_ROOTS: Array[String] = [
	"run.roster_state.board",
	"run.roster_state.bench_unit_instance_ids",
	"saved_at_utc",
]

var _active_harness: Support.BootHarness


func test_projected_drag_matches_button_canonical_run_state_layout() -> void:
	var button := await _exercise_button_path()
	assert_true(
		bool(button.get("ok", false)),
		"button fixture failed: %s" % String(button.get("error", ""))
	)
	if not bool(button.get("ok", false)):
		await _dispose_active_harness()
		return
	await _dispose_active_harness()

	var drag := await _exercise_projected_drag_path(
		button.get("target_cell", Vector2i(-1, -1))
	)
	assert_true(
		bool(drag.get("ok", false)),
		"drag fixture failed: %s" % String(drag.get("error", ""))
	)
	if not bool(drag.get("ok", false)):
		await _dispose_active_harness()
		return

	assert_eq(
		drag.get("before_layout_digest", ""),
		button.get("before_layout_digest", ""),
		"both paths must start from the same fresh canonical RunState layout"
	)
	assert_ne(
		button.get("after_layout_digest", ""),
		button.get("before_layout_digest", ""),
		"the real action buttons must commit a canonical layout change"
	)
	assert_ne(
		drag.get("after_layout_digest", ""),
		drag.get("before_layout_digest", ""),
		"the projected DnD relay must commit a canonical layout change"
	)
	assert_eq(
		drag.get("after_layout_digest", ""),
		button.get("after_layout_digest", ""),
		(
			"projected screen/local DnD and the existing buttons must converge "
			+ "on the same saved RunState layout"
		)
	)
	_assert_only_authorized_canonical_mutations(
		button.get("before_canonical_document", {}),
		button.get("after_canonical_document", {}),
		"button"
	)
	_assert_only_authorized_canonical_mutations(
		drag.get("before_canonical_document", {}),
		drag.get("after_canonical_document", {}),
		"drag"
	)
	assert_eq(
		_canonical_denylist_digest(
			drag.get("after_canonical_document", {})
		),
		_canonical_denylist_digest(
			button.get("after_canonical_document", {})
		),
		(
			"button and projected drag must converge on every persisted canonical "
			+ "field outside the explicit layout/publication allowlist"
		)
	)
	assert_eq(
		drag.get("target_cell", Vector2i(-1, -1)),
		button.get("target_cell", Vector2i(-1, -1))
	)
	await _dispose_active_harness()


func _exercise_button_path() -> Dictionary:
	var fixture := await _fresh_prepare_fixture()
	if not bool(fixture.get("ok", false)):
		return fixture
	var screen := fixture.get("screen") as ProductionScreen
	var composition := fixture.get("composition") as RunPrepareScreen
	var unit_id := String(fixture.get("unit_id", ""))
	var bench := composition.find_child(
		"BenchSelector", true, false
	) as ItemList
	if bench == null:
		return _failure("button_bench_selector_missing")
	var bench_index := _item_index_for(bench, unit_id)
	if bench_index < 0:
		return _failure("button_bench_unit_missing")
	bench.select(bench_index)
	bench.item_selected.emit(bench_index)

	var group := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	if group == null or group.item_count <= 1:
		return _failure("button_party_group_missing")
	group.select(1)
	group.item_selected.emit(1)
	await wait_process_frames(2)
	var stage := _action_button(screen, &"prepare.move_board")
	var commit := _action_button(screen, &"prepare.unit")
	if stage == null or commit == null:
		return _failure("button_action_missing")
	if (
		stage.disabled
		or commit.disabled
		or not stage.is_visible_in_tree()
		or not commit.is_visible_in_tree()
	):
		return _failure("button_action_not_interactive")
	stage.pressed.emit()
	await wait_process_frames(1)
	commit.pressed.emit()
	await wait_process_frames(4)

	var loaded := _load_canonical_run()
	if not bool(loaded.get("ok", false)):
		return loaded
	var run := loaded.get("run") as RunState
	var target_cell := _cell_for(run.roster_state.board, unit_id)
	if target_cell == Vector2i(-1, -1):
		return _failure("button_unit_not_committed_to_board")
	return {
		"ok": true,
		"error": "",
		"before_layout_digest": fixture.get("before_layout_digest", ""),
		"after_layout_digest": _canonical_layout_digest(run),
		"before_canonical_document": fixture.get("before_canonical_document", {}),
		"after_canonical_document": _canonical_persisted_document(),
		"target_cell": target_cell,
	}


func _exercise_projected_drag_path(target_cell: Vector2i) -> Dictionary:
	var fixture := await _fresh_prepare_fixture()
	if not bool(fixture.get("ok", false)):
		return fixture
	var unit_id := String(fixture.get("unit_id", ""))
	var composition := fixture.get("composition") as RunPrepareScreen
	var board_grid := composition.find_child(
		"BoardGrid", true, false
	) as GridContainer
	if (
		board_grid == null
		or board_grid.get_child_count() <= 0
		or board_grid.get_child_count()
			!= BoardPreparationValidator.PLAYER_HALF_CAPACITY
	):
		return _failure("drag_board_grid_proxy_empty")

	var source := _bench_drag_source(composition, unit_id)
	var overlay := _active_harness.world_surface.ui_overlay()
	var target := overlay.drag_target() if overlay != null else null
	var mapper := _active_harness.viewport_coordinator.coordinate_mapper_clone()
	if source == null or target == null or mapper == null:
		return _failure("drag_production_surface_missing")
	if not source.is_visible_in_tree() or not target.is_visible_in_tree():
		return _failure("drag_production_surface_not_visible")
	# Calling Control._get_drag_data() outside a native Viewport drag lifecycle
	# makes set_drag_preview() emit an engine error. The source button's public
	# typed payload accessor is covered by its unit contract; this integration
	# starts at the formal projected target and does not claim pointer-gesture QA.
	var payload: Variant = source.unit_drag_payload()
	if not payload is Dictionary:
		return _failure("drag_source_payload_missing")
	var screen_position := mapper.world_to_screen(
		BoardProjection.new().project_cell(target_cell)
	)
	var local_position := (
		target.get_global_transform_with_canvas().affine_inverse()
		* screen_position
	)
	if not bool(target.call(&"_can_drop_data", local_position, payload)):
		return _failure("drag_projected_target_rejected")
	target.call(&"_drop_data", local_position, payload)
	await wait_process_frames(4)

	var loaded := _load_canonical_run()
	if not bool(loaded.get("ok", false)):
		return loaded
	var run := loaded.get("run") as RunState
	var committed_cell := _cell_for(run.roster_state.board, unit_id)
	if committed_cell != target_cell:
		return _failure(
			"drag_committed_wrong_cell:%s" % committed_cell
		)
	return {
		"ok": true,
		"error": "",
		"before_layout_digest": fixture.get("before_layout_digest", ""),
		"after_layout_digest": _canonical_layout_digest(run),
		"before_canonical_document": fixture.get("before_canonical_document", {}),
		"after_canonical_document": _canonical_persisted_document(),
		"target_cell": committed_cell,
	}


func _fresh_prepare_fixture() -> Dictionary:
	_active_harness = Support.boot_runtime(get_tree())
	await wait_process_frames(2)
	if (
		_active_harness == null
		or not _active_harness.boot_error.is_empty()
		or not _active_harness.settings_bind_error.is_empty()
		or not _active_harness.root.is_booted()
	):
		return _failure("production_boot_failed")
	var driven: Dictionary = Support.drive_to_run_prepare(_active_harness)
	if not bool(driven.get("ok", false)):
		return _failure(
			"drive_prepare_failed:%s" % String(driven.get("error", &""))
		)
	await wait_process_frames(4)

	var screen := Support.active_screen(_active_harness)
	if screen == null or screen.route_kind != &"RUN_PREPARE":
		return _failure("prepare_screen_missing")
	var refreshed := screen.request_intent(
		RunPresentationIntent.new(RunPresentationIntent.Kind.REFRESH_SHOP)
	)
	if (
		not refreshed.ok
		or refreshed.snapshot == null
		or refreshed.snapshot.economy == null
	):
		return _failure("prepare_refresh_failed")
	var purchased: RunPresentationResult
	for offer: ShopOffer in refreshed.snapshot.economy.shop_offers:
		screen = Support.active_screen(_active_harness)
		if screen == null:
			return _failure("prepare_refresh_replacement_missing")
		var buy := RunPresentationIntent.new(
			RunPresentationIntent.Kind.BUY_UNIT
		)
		buy.offer_id = offer.offer_id
		var candidate := screen.request_intent(buy)
		if candidate.ok:
			purchased = candidate
			break
	if purchased == null or purchased.snapshot == null:
		return _failure("prepare_affordable_unit_missing")
	if purchased.snapshot.roster.bench_unit_instance_ids.is_empty():
		return _failure("prepare_bench_unit_missing")
	var unit_id := purchased.snapshot.roster.bench_unit_instance_ids[0]
	await wait_process_frames(4)
	screen = Support.active_screen(_active_harness)
	var composition := (
		screen.get_node_or_null(^"Composition") as RunPrepareScreen
		if screen != null
		else null
	)
	if composition == null:
		return _failure("prepare_composition_missing")
	if composition.world_board_mount_error() != &"":
		return _failure(
			"prepare_world_mount_failed:%s"
			% composition.world_board_mount_error()
		)
	var board_grid := composition.find_child(
		"BoardGrid", true, false
	) as GridContainer
	if board_grid == null or board_grid.get_child_count() <= 0:
		return _failure("prepare_board_grid_proxy_empty")
	var loaded := _load_canonical_run()
	if not bool(loaded.get("ok", false)):
		return loaded
	return {
		"ok": true,
		"error": "",
		"screen": screen,
		"composition": composition,
		"unit_id": unit_id,
		"before_layout_digest": _canonical_layout_digest(
			loaded.get("run") as RunState
		),
		"before_canonical_document": _canonical_persisted_document(),
	}


func _load_canonical_run() -> Dictionary:
	var loaded: LoadResult = _active_harness.repository.load()
	if not loaded.ok or loaded.run == null:
		return _failure("canonical_run_load_failed")
	if loaded.run.run_phase != RunState.RunPhase.PREPARE:
		return _failure("canonical_run_not_prepare")
	return {"ok": true, "error": "", "run": loaded.run}


func _dispose_active_harness() -> void:
	if _active_harness != null:
		_active_harness.dispose()
		_active_harness = null
	await wait_process_frames(4)


func _bench_drag_source(
	composition: RunPrepareScreen,
	unit_id: String
) -> PrepareUnitDragButton:
	for node: Node in composition.find_children(
		"BenchCell*", "Button", true, false
	):
		var cell := node as PrepareUnitDragButton
		if (
			cell != null
			and String(cell.get_meta(&"unit_instance_id", "")) == unit_id
		):
			return cell
	return null


func _action_button(
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and StringName(button.get_meta(&"action_id", &"")) == action_id
		):
			return button
	return null


func _item_index_for(selector: ItemList, identity: String) -> int:
	for index: int in selector.item_count:
		if String(selector.get_item_metadata(index)) == identity:
			return index
	return -1


func _cell_for(board: BoardState, unit_id: String) -> Vector2i:
	if board != null:
		for placement: BoardPlacementState in board.placements:
			if placement != null and placement.unit_instance_id == unit_id:
				return Vector2i(placement.logical_x, placement.logical_y)
	return Vector2i(-1, -1)


func _canonical_layout_digest(run: RunState) -> String:
	var placements := PackedStringArray()
	for placement: BoardPlacementState in run.roster_state.board.placements:
		placements.append("%d:%d:%s" % [
			placement.logical_y,
			placement.logical_x,
			placement.unit_instance_id,
		])
	placements.sort()
	var bench := PackedStringArray(run.roster_state.bench_unit_instance_ids)
	return ("%s#%s" % [",".join(placements), ",".join(bench)]).sha256_text()


func _canonical_persisted_document() -> Dictionary:
	if _active_harness == null or _active_harness.repository == null:
		return {}
	var storage := _active_harness.repository.get("_storage") as FakeSaveStorage
	if storage == null:
		return {}
	var stored := storage.file_bytes(StorageFaultKey.MAIN)
	if stored == null:
		return {}
	var document: Variant = JSON.parse_string(stored.value.get_string_from_utf8())
	if not document is Dictionary:
		return {}
	return (document as Dictionary).duplicate(true)


func _assert_only_authorized_canonical_mutations(
	before: Dictionary,
	after: Dictionary,
	path_label: String
) -> void:
	assert_false(before.is_empty(), "%s canonical before document missing" % path_label)
	assert_false(after.is_empty(), "%s canonical after document missing" % path_label)
	if before.is_empty() or after.is_empty():
		return
	var changed_paths := _canonical_changed_paths(before, after)
	var unauthorized := PackedStringArray()
	for changed_path: String in changed_paths:
		if not _path_is_under_any_root(
			changed_path, ALLOWED_CANONICAL_MUTATION_ROOTS
		):
			unauthorized.append(changed_path)
	for required_root: String in REQUIRED_LAYOUT_MUTATION_ROOTS:
		assert_true(
			_changed_paths_touch_root(changed_paths, required_root),
			"%s must mutate canonical %s" % [path_label, required_root]
		)
	assert_true(
		unauthorized.is_empty(),
		(
			"%s changed denylisted canonical paths: %s; full changes: %s"
			% [path_label, ", ".join(unauthorized), ", ".join(changed_paths)]
		)
	)
	assert_eq(
		_canonical_denylist_digest(before),
		_canonical_denylist_digest(after),
		(
			"%s layout publication must preserve every field outside the explicit "
			+ "canonical allowlist"
		) % path_label
	)


func _canonical_denylist_digest(document: Dictionary) -> String:
	if document.is_empty():
		return ""
	var root := document.duplicate(true)
	root.erase("saved_at_utc")
	var run_value: Variant = root.get("run")
	if not run_value is Dictionary:
		return ""
	var roster_value: Variant = (run_value as Dictionary).get("roster_state")
	if not roster_value is Dictionary:
		return ""
	# Everything not erased here is the denylist. This includes economy,
	# resolution, RNG streams, receipts, discovery/profile state, unit/item
	# records, and all version/content-generation fields.
	(roster_value as Dictionary).erase("board")
	(roster_value as Dictionary).erase("bench_unit_instance_ids")
	return JSON.stringify(root).sha256_text()


func _canonical_changed_paths(
	before: Variant,
	after: Variant,
	path: String = ""
) -> PackedStringArray:
	var result := PackedStringArray()
	if typeof(before) != typeof(after):
		result.append(path)
		return result
	if before is Dictionary:
		var keys := PackedStringArray()
		for key: Variant in (before as Dictionary).keys():
			keys.append(String(key))
		for key: Variant in (after as Dictionary).keys():
			var text_key := String(key)
			if not keys.has(text_key):
				keys.append(text_key)
		keys.sort()
		for key: String in keys:
			var child_path := key if path.is_empty() else "%s.%s" % [path, key]
			if (
				not (before as Dictionary).has(key)
				or not (after as Dictionary).has(key)
			):
				result.append(child_path)
				continue
			result.append_array(_canonical_changed_paths(
				(before as Dictionary).get(key),
				(after as Dictionary).get(key),
				child_path
			))
		return result
	if before is Array:
		if before != after:
			result.append(path)
		return result
	if before != after:
		result.append(path)
	return result


func _path_is_under_any_root(path: String, roots: Array[String]) -> bool:
	for root: String in roots:
		if path == root or path.begins_with(root + "."):
			return true
	return false


func _changed_paths_touch_root(
	changed_paths: PackedStringArray,
	root: String
) -> bool:
	for path: String in changed_paths:
		if (
			path == root
			or path.begins_with(root + ".")
			or root.begins_with(path + ".")
		):
			return true
	return false


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
