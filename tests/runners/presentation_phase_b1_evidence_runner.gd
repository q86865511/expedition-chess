extends SceneTree

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)
const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)

const CASES: Array[Dictionary] = [
	{"name": "720p-ui100", "size": Vector2i(1280, 720), "ui": 100},
	{"name": "720p-ui125", "size": Vector2i(1280, 720), "ui": 125},
	{"name": "720p-ui150", "size": Vector2i(1280, 720), "ui": 150},
	{"name": "1080p-ui100", "size": Vector2i(1920, 1080), "ui": 100},
	{"name": "1080p-ui125", "size": Vector2i(1920, 1080), "ui": 125},
	{"name": "1080p-ui150", "size": Vector2i(1920, 1080), "ui": 150},
	{"name": "1440p-ui100", "size": Vector2i(2560, 1440), "ui": 100},
	{"name": "1440p-ui125", "size": Vector2i(2560, 1440), "ui": 125},
	{"name": "1440p-ui150", "size": Vector2i(2560, 1440), "ui": 150},
]
const UI_REFERENCE_SIZE := Vector2i(1920, 1080)
const EVIDENCE_ROOT := "res://specs/in-run-hud/evidence"
const DEFAULT_OUTPUT_DIR := EVIDENCE_ROOT + "/phase-b1"
const BASELINE_REPORT_CASE_COUNT := 128
const SHOP_TIER_EVIDENCE_CASE_COUNT := 9
const BOARD_DRAFT_PREVIEW_EVIDENCE_CASE_COUNT := 9
const EXPECTED_REPORT_CASE_COUNT := (
	BASELINE_REPORT_CASE_COUNT
	+ SHOP_TIER_EVIDENCE_CASE_COUNT
	+ BOARD_DRAFT_PREVIEW_EVIDENCE_CASE_COUNT
)

var _harness: Support.BootHarness
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []
var _prepare_fixture_snapshot: RunPresentationSnapshot
var _prepare_fixture_localized_text: Dictionary = {}


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output_dir := _output_directory().trim_suffix("/")
	if output_dir.is_empty():
		push_error(
			"Evidence output must remain under %s/." % EVIDENCE_ROOT
		)
		quit(3)
		return
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		quit(3)
		return
	_harness = Support.boot_runtime(self)
	await process_frame
	await process_frame
	if not _harness.root.is_booted():
		_issues.append("app_root_boot_failed:%s" % _harness.boot_error)
		await _finish(output_dir)
		return
	var opened := _harness.root.open_camp()
	if not opened.ok:
		_issues.append("camp_route_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in CASES:
		await _capture(output_dir, &"CAMP_WORLD", "camp", case)

	var returned := _harness.root.return_to_menu()
	if not returned.ok:
		_issues.append("return_to_menu_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in CASES:
		await _capture(output_dir, &"MENU_MAIN", "menu-main", case)
	var settings_opened := _harness.root.open_settings()
	if not settings_opened.ok:
		_issues.append("settings_route_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in CASES:
		await _capture_settings_after_apply(output_dir, case)
	var settings_closed := _harness.root.close_settings()
	if not settings_closed.ok:
		_issues.append("settings_close_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	var driven := Support.drive_to_run_prepare(_harness)
	if not bool(driven.get("ok", false)):
		_issues.append("run_prepare_route_failed:%s" % driven.get("error", &""))
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	await _stage_prepare_world_unit()
	_preserve_prepare_fixture_source()
	_capture_world_board_state(output_dir)
	for case: Dictionary in CASES:
		await _capture(output_dir, &"RUN_PREPARE", "prepare", case)
	await _capture_prepare_groups(output_dir)
	await _capture_scale_rebuild(output_dir)
	await _capture_node_choice(output_dir)
	await _capture_status_band(output_dir)
	await _capture_focus(output_dir)
	await _capture_remaining_run_routes(output_dir)
	await _capture_prepare_shop_tiers(output_dir)
	await _capture_board_draft_preview(output_dir)
	await _finish(output_dir)


func _capture_world_board_state(output_dir: String) -> void:
	var surfaces := get_nodes_in_group(ProductionWorldSurface.MOUNT_GROUP)
	var surface := (
		surfaces[0] as ProductionWorldSurface
		if not surfaces.is_empty()
		else null
	)
	var renderer := surface.board_renderer() if surface != null else null
	var snapshot := surface.snapshot_clone() if surface != null else null
	var report := {
		"ok": (
			surfaces.size() == 1
			and surface != null
			and renderer != null
			and renderer.visible
			and snapshot != null
			and snapshot.is_valid()
		),
		"surface_count": surfaces.size(),
		"renderer_visible": renderer.visible if renderer != null else false,
		"unit_count": snapshot.units.size() if snapshot != null else -1,
		"snapshot_valid": snapshot.is_valid() if snapshot != null else false,
	}
	if not bool(report["ok"]):
		_issues.append("world_board_not_mounted")
	_write_json("%s/world-board-state.json" % output_dir, report)


func _stage_prepare_world_unit() -> void:
	var screen := Support.active_screen(_harness)
	var composition := (
		screen.get_node_or_null(^"Composition") as RunPrepareScreen
		if screen != null
		else null
	)
	var bench_cell := (
		screen.find_child("BenchCell*", true, false) as Button
		if screen != null
		else null
	)
	var unit_id := (
		String(bench_cell.get_meta(&"unit_instance_id", ""))
		if bench_cell != null
		else ""
	)
	if composition == null or unit_id.is_empty():
		_issues.append("prepare_world_unit_missing")
		return
	var result := composition.quick_toggle_unit(unit_id)
	if result == null or not result.ok:
		_issues.append("prepare_world_unit_commit_failed")
		return
	await process_frame
	await process_frame
	await process_frame


func _preserve_prepare_fixture_source() -> void:
	var screen := Support.active_screen(_harness)
	var context := (
		screen.get("_context") as StagedScreenContext
		if screen != null
		else null
	)
	var snapshot := (
		context.snapshot_clone() as RunPresentationSnapshot
		if context != null
		else null
	)
	if (
		snapshot == null
		or snapshot.economy == null
		or snapshot.roster == null
		or snapshot.manifest_digest.is_empty()
	):
		_issues.append("prepare_shop_tier_source_missing")
		return
	_prepare_fixture_snapshot = snapshot.deep_clone()
	_prepare_fixture_localized_text = context.localized_text.duplicate(true)


func _capture_remaining_run_routes(output_dir: String) -> void:
	# The node-choice/status evidence intentionally composes presentation-only
	# variants. Refresh once through the real command path so combat starts from
	# the canonical snapshot while retaining the committed board placement.
	var prepare := Support.active_screen(_harness)
	if prepare == null:
		_issues.append("prepare_restore_screen_missing")
		return
	var refreshed := prepare.request_intent(
		RunPresentationIntent.new(RunPresentationIntent.Kind.REFRESH_SHOP)
	)
	if not refreshed.ok:
		_issues.append("prepare_restore_command_failed")
		return
	await process_frame
	await process_frame
	prepare = Support.active_screen(_harness)
	if prepare == null or prepare.route_kind != &"RUN_PREPARE":
		_issues.append("prepare_start_screen_missing")
		return
	var started := prepare.request_intent(
		RunPresentationIntent.new(
			RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
		)
	)
	if not started.ok:
		_issues.append("prepare_start_command_failed")
		return
	await process_frame
	await process_frame
	var combat := Support.active_screen(_harness)
	if combat == null or combat.route_kind != &"RUN_COMBAT":
		_issues.append("combat_route_failed")
		return
	for case: Dictionary in CASES:
		await _capture(output_dir, &"RUN_COMBAT", "combat", case)

	var destination := await _drive_combat_playback_to_route()
	if destination == &"RUN_REWARD":
		for case: Dictionary in CASES:
			await _capture(output_dir, &"RUN_REWARD", "reward", case)
		var reward := Support.active_screen(_harness)
		var confirm := _action_button(reward, &"reward.confirm")
		if confirm == null:
			_issues.append("reward_confirm_action_missing")
			return
		confirm.pressed.emit()
		await process_frame
		await process_frame
		if Support.active_screen(_harness).route_kind == &"RUN_REWARD":
			var acknowledge := _action_button(
				Support.active_screen(_harness),
				&"choice.ack"
			)
			if acknowledge != null and not acknowledge.disabled:
				acknowledge.pressed.emit()
				await process_frame
				await process_frame
		destination = await _wait_for_route([&"RUN_MAP"], 180)
	elif destination == &"RUN_MAP":
		# A legal non-boss loss routes directly to MAP. Capture that canonical
		# route first; a formal typed reward fixture is mounted afterwards because
		# one deterministic run cannot be both a win and a loss.
		pass
	else:
		_issues.append("combat_settlement_route_not_reached")
	if destination != &"RUN_MAP":
		_issues.append("map_route_not_reached_after_combat")
		return
	for case: Dictionary in CASES:
		await _capture(output_dir, &"RUN_MAP", "map", case)
	if not _reports.any(func(report: Dictionary) -> bool:
		return String(report.get("route", "")) == "reward"
	):
		await _capture_formal_reward_fixture(output_dir)


func _drive_combat_playback_to_route() -> StringName:
	for _step: int in range(240):
		var screen := Support.active_screen(_harness)
		if screen == null:
			return &""
		if screen.route_kind in [&"RUN_REWARD", &"RUN_MAP"]:
			return screen.route_kind
		if screen.route_kind != &"RUN_COMBAT":
			return &""
		var composition := screen.get_node_or_null(
			^"Composition"
		) as RunCombatScreen
		if composition == null:
			return &""
		composition.advance_presentation_frame(500.0)
		await process_frame
	return await _wait_for_route([&"RUN_REWARD", &"RUN_MAP"], 30)


func _capture_formal_reward_fixture(output_dir: String) -> void:
	_write_json("%s/reward-evidence-source.json" % output_dir, {
		"route": "RUN_REWARD",
		"source": "formal-screen-typed-snapshot-fixture",
		"reason": "fresh-profile first combat deterministically routed to RUN_MAP",
		"snapshot_phase": "PendingRewardState.CHOOSING",
	})
	for case_index: int in CASES.size():
		var case: Dictionary = CASES[case_index]
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append("reward_fixture_settings_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		var screen := _mount_formal_reward_screen(900 + case_index)
		if screen == null:
			_issues.append("reward_fixture_mount_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		_validate_action_buttons(screen, "reward:%s" % case["name"])
		_validate_run_route_actions_region(
			screen,
			"reward:%s" % case["name"]
		)
		_reports.append(_save_viewport(
			"%s/reward-%s.png" % [output_dir, case["name"]],
			"reward",
			case
		))


func _mount_formal_reward_screen(generation: int) -> ProductionScreen:
	var current := Support.active_screen(_harness)
	var current_context := (
		current.get("_context") as StagedScreenContext
		if current != null
		else null
	)
	if current_context == null:
		return null
	var localized := current_context.localized_text.duplicate()
	for child: Node in _harness.host.get_children():
		_harness.host.remove_child(child)
		child.free()
	var canonical := current_context.snapshot_clone() as RunPresentationSnapshot
	if canonical == null:
		return null
	var snapshot := CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	snapshot.roster = canonical.roster.deep_clone() if canonical.roster != null else null
	snapshot.economy = (
		canonical.economy.deep_clone() if canonical.economy != null else null
	)
	snapshot.map = canonical.map.deep_clone() if canonical.map != null else null
	var content_ids: Array[StringName] = []
	if canonical.economy != null:
		for shop_offer: ShopOffer in canonical.economy.shop_offers:
			if shop_offer != null and not shop_offer.unit_def_id.is_empty():
				content_ids.append(shop_offer.unit_def_id)
	if content_ids.is_empty() and canonical.roster != null:
		for unit: UnitInstance in canonical.roster.unit_instances:
			if unit != null and not unit.def_id.is_empty():
				content_ids.append(unit.def_id)
	if content_ids.is_empty():
		return null
	var localized_offers: Array[RewardOfferState] = []
	for offer_index: int in snapshot.pending_reward.offers.size():
		var offer := snapshot.pending_reward.offers[offer_index]
		localized_offers.append(RewardOfferState.new(
			offer.choice_id,
			offer.reward_kind,
			OptionalStringNameValue.of(
				content_ids[offer_index % content_ids.size()]
			),
			offer.amount,
			offer.reservation_owner_key,
			offer.payload_digest
		))
	snapshot.pending_reward.offers.assign(localized_offers)
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_REWARD")
	if screen == null:
		return null
	var staged := StagedScreenContext.new(
		&"RUN_REWARD",
		snapshot,
		null,
		&"zh_TW",
		localized
	)
	if not screen.bind(staged).is_empty():
		screen.free()
		return null
	var session := CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = snapshot.deep_clone()
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, generation)
	var live := ProductionLiveScreenContext.new(
		&"RUN_REWARD",
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		LiveScreenIntentPort.new(lease, registry, session)
	)
	if not screen.prepare_live_binding(live).is_empty():
		screen.free()
		return null
	_harness.host.add_child(screen)
	screen.activate_live()
	return screen


func _capture_prepare_shop_tiers(output_dir: String) -> void:
	var built := _build_prepare_shop_tier_fixture()
	if not bool(built.get("ok", false)):
		_issues.append(
			"prepare_shop_tier_fixture_failed:%s"
			% String(built.get("error", "unknown"))
		)
		return
	var snapshot := built.get("snapshot") as RunPresentationSnapshot
	var expected: Array[Dictionary] = []
	var expected_value: Variant = built.get("expected", [])
	if expected_value is Array:
		for entry_value: Variant in expected_value:
			if entry_value is Dictionary:
				expected.append((entry_value as Dictionary).duplicate(true))
	if snapshot == null or expected.size() != 5:
		_issues.append("prepare_shop_tier_fixture_incomplete")
		return

	var source_offers: Array[Dictionary] = []
	for entry: Dictionary in expected:
		source_offers.append({
			"slot_index": int(entry["slot_index"]),
			"tier": int(entry["tier"]),
			"unit_def_id": String(entry["unit_def_id"]),
			"authoritative_cost": int(entry["cost"]),
		})
	_write_json("%s/prepare-shop-tiers-source.json" % output_dir, {
		"route": "RUN_PREPARE",
		"source": "pinned-project-content-bootstrap-and-shop-offer-preview-vm",
		"manifest_digest": snapshot.manifest_digest,
		"case_count": CASES.size(),
		"offers": source_offers,
	})

	for case_index: int in CASES.size():
		var case: Dictionary = CASES[case_index]
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append("prepare_shop_tier_settings_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		var screen := _mount_formal_prepare_shop_tier_screen(
			snapshot, 1000 + case_index
		)
		if screen == null:
			_issues.append("prepare_shop_tier_mount_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		await process_frame
		_validate_prepare_top_bar(screen, "shop-tiers:%s" % case["name"])
		_validate_prepare_content_regions(screen, "shop-tiers:%s" % case["name"])
		_validate_prepare_shop_tier_cards(screen, String(case["name"]), expected)
		_reports.append(_save_viewport(
			"%s/prepare-shop-tiers-%s.png" % [output_dir, case["name"]],
			"prepare-shop-tiers",
			case
		))


func _capture_board_draft_preview(output_dir: String) -> void:
	var built := _build_prepare_shop_tier_fixture()
	var snapshot := built.get("snapshot") as RunPresentationSnapshot
	var session_result := _harness.root.current_run_presentation()
	if not bool(built.get("ok", false)) or snapshot == null:
		_issues.append(
			"board_draft_preview_fixture_failed:%s"
			% String(built.get("error", "unknown"))
		)
		return
	if not session_result.ok or session_result.session == null:
		_issues.append("board_draft_preview_typed_session_missing")
		return
	# The tier fixture's canonical unit starts on the board. Stage that same
	# known roster instance on the bench so the formal PrepareUnitDragButton
	# can originate a real DnD payload; the candidate preview itself still
	# comes exclusively from the live typed supply/session below.
	snapshot = snapshot.deep_clone()
	if (
		snapshot.roster != null
		and snapshot.roster.bench_unit_instance_ids.is_empty()
		and not snapshot.roster.board.placements.is_empty()
	):
		var staged := (
			snapshot.roster.board.placements.pop_front()
			as BoardPlacementState
		)
		if staged != null:
			snapshot.roster.bench_unit_instance_ids.append(
				staged.unit_instance_id
			)
	_write_json("%s/board-draft-preview-source.json" % output_dir, {
		"route": "RUN_PREPARE",
		"source": "typed-live-screen-supply-port-board-draft-preview",
		"manifest_digest": snapshot.manifest_digest,
		"case_count": CASES.size(),
	})
	for case_index: int in CASES.size():
		var case: Dictionary = CASES[case_index]
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append(
				"board_draft_preview_settings_failed:%s" % case["name"]
			)
			continue
		await process_frame
		await process_frame
		var mounted := _mount_formal_prepare_shop_tier_screen(
			snapshot, 1100 + case_index, session_result.session
		)
		if mounted == null:
			_issues.append(
				"board_draft_preview_mount_failed:%s" % case["name"]
			)
			continue
		await process_frame
		await process_frame
		await process_frame
		var composition := mounted.get_node_or_null(
			^"Composition"
		) as RunPrepareScreen
		var source := _first_board_draft_preview_source(composition)
		var target := _first_board_draft_preview_target(composition, source)
		var payload: Variant = source.unit_drag_payload() if source != null else null
		var accepted := (
			bool(target.call(&"_can_drop_data", Vector2.ZERO, payload))
			if target != null and payload is Dictionary
			else false
		)
		await process_frame
		var panel := (
			composition.find_child("BoardDraftPreview", true, false) as Label
			if composition != null
			else null
		)
		_validate_board_draft_preview(
			mounted, panel, accepted, String(case["name"])
		)
		_reports.append(_save_viewport(
			"%s/prepare-board-draft-preview-%s.png" % [
				output_dir, case["name"],
			],
			"prepare-board-draft-preview",
			case
		))


func _first_board_draft_preview_source(
	composition: RunPrepareScreen
) -> PrepareUnitDragButton:
	if composition == null:
		return null
	for node: Node in composition.find_children(
		"BuildUnitDrag*", "Button", true, false
	):
		var source := node as PrepareUnitDragButton
		if (
			source != null
			and not String(source.get_meta(&"unit_instance_id", "")).is_empty()
		):
			return source
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


func _first_board_draft_preview_target(
	composition: RunPrepareScreen,
	source: PrepareUnitDragButton
) -> PrepareUnitDragButton:
	if composition == null or source == null:
		return null
	var source_slot := int(source.get_meta(&"bench_slot", -1))
	for node: Node in composition.find_children(
		"BenchCell*", "Button", true, false
	):
		var target := node as PrepareUnitDragButton
		if (
			target != null
			and int(target.get_meta(&"bench_slot", -1)) != source_slot
		):
			return target
	return null


func _validate_board_draft_preview(
	screen: ProductionScreen,
	panel: Label,
	accepted: bool,
	case_name: String
) -> void:
	if screen == null or panel == null:
		_issues.append("board_draft_preview_missing:%s" % case_name)
		return
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	var bench := screen.find_child("BenchRow", true, false) as Control
	var bottom := screen.find_child("BottomRegion", true, false) as Control
	var status := screen.find_child("StatusRegion", true, false) as Control
	var canvas := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	var margin := Vector2.ONE * ProductionLayoutShell.SAFE_MARGIN
	var safe_region := Rect2(
		margin,
		ProductionLayoutShell.REFERENCE_SIZE - margin * 2.0
	)
	var panel_rect := panel.get_global_rect()
	if (
		not accepted
		or not panel.visible
		or not panel.is_visible_in_tree()
		or not panel_rect.has_area()
		or not canvas.encloses(panel_rect)
		or not safe_region.encloses(panel_rect)
	):
		_issues.append("board_draft_preview_visibility:%s:%s" % [
			case_name, panel_rect,
		])
	if shell == null:
		_issues.append("board_draft_preview_shell_missing:%s" % case_name)
	else:
		var center_rect := shell.current_region_rect(
			ProductionLayoutShell.REGION_CENTER
		)
		if not center_rect.encloses(panel_rect):
			_issues.append("board_draft_preview_outside_center:%s:%s" % [
				case_name, panel_rect,
			])
	for entry: Dictionary in [
		{"name": "bench", "control": bench},
		{"name": "status", "control": status},
		{"name": "bottom", "control": bottom},
	]:
		var control := entry["control"] as Control
		if (
			control != null
			and control.is_visible_in_tree()
			and panel_rect.intersects(control.get_global_rect())
		):
			_issues.append("board_draft_preview_over_%s:%s" % [
				String(entry["name"]), case_name,
			])
	var accessible := String(panel.get_meta(&"accessible_text", ""))
	var audited := "\n".join([panel.text, panel.tooltip_text, accessible])
	if (
		StringName(panel.get_meta(&"typed_data_kind", &""))
			!= &"board_draft_preview"
		or panel.text.is_empty()
		or panel.tooltip_text != panel.text
		or accessible != panel.text
		or not panel.text.contains(
			String(_prepare_fixture_localized_text.get(
				&"prepare.resource.capacity", ""
			))
		)
	):
		_issues.append("board_draft_preview_localized_copy:%s" % case_name)
	var raw_ids := PackedStringArray()
	var source_snapshot := (
		_prepare_fixture_snapshot
		if _prepare_fixture_snapshot != null
		else null
	)
	if source_snapshot != null and source_snapshot.roster != null:
		for unit: UnitInstance in source_snapshot.roster.unit_instances:
			if unit != null:
				raw_ids.append(unit.instance_id)
				raw_ids.append(String(unit.def_id))
	for raw_id: String in raw_ids:
		if not raw_id.is_empty() and audited.contains(raw_id):
			_issues.append("board_draft_preview_raw_identity:%s:%s" % [
				case_name, raw_id,
			])


func _build_prepare_shop_tier_fixture() -> Dictionary:
	if (
		_prepare_fixture_snapshot == null
		or _prepare_fixture_snapshot.economy == null
		or _prepare_fixture_snapshot.roster == null
	):
		return {"ok": false, "error": "prepare_source_missing"}
	var snapshot := _prepare_fixture_snapshot.deep_clone()
	var content := ProjectContentBootstrap.new().run(ContentRegistryService.new())
	if content == null or not content.ok:
		return {
			"ok": false,
			"error": "pinned_bootstrap:%s" % (
				String(content.error_code) if content != null else "null"
			),
		}
	if content.manifest_digest != snapshot.manifest_digest:
		return {"ok": false, "error": "pinned_manifest_mismatch"}
	var economy_catalog := (
		content.economy_catalog.deep_clone()
		if content.economy_catalog != null
		else null
	)
	var battle_catalog := content.battle_catalog_snapshot()
	if economy_catalog == null or battle_catalog == null:
		return {"ok": false, "error": "pinned_catalog_missing"}

	var shop_rules := economy_catalog.shop_units()
	shop_rules.sort_custom(
		func(left: ShopUnitRule, right: ShopUnitRule) -> bool:
			if left.cost_tier != right.cost_tier:
				return left.cost_tier < right.cost_tier
			return String(left.unit_id) < String(right.unit_id)
	)
	var selected_rules: Array[ShopUnitRule] = []
	for tier: int in range(1, 6):
		var selected: ShopUnitRule
		for rule: ShopUnitRule in shop_rules:
			if rule != null and rule.cost_tier == tier:
				selected = rule.deep_clone()
				break
		if selected == null:
			return {"ok": false, "error": "tier_%d_missing" % tier}
		var battle_rule := battle_catalog.try_unit_rule(selected.unit_id)
		if battle_rule == null or battle_rule.cost_tier != tier:
			return {"ok": false, "error": "tier_%d_battle_mismatch" % tier}
		if not _fixture_content_is_localized(selected.unit_id):
			return {"ok": false, "error": "tier_%d_unit_loc_missing" % tier}
		for trait_id: StringName in battle_rule.trait_ids:
			if not _fixture_content_is_localized(trait_id):
				return {"ok": false, "error": "tier_%d_trait_loc_missing" % tier}
		selected_rules.append(selected)

	var source_by_slot: Dictionary = {}
	for source_offer: ShopOffer in snapshot.economy.shop_offers:
		if (
			source_offer != null
			and source_offer.slot_index >= 0
			and source_offer.slot_index < 5
			and source_offer.reservation_owner_key != null
			and not source_by_slot.has(source_offer.slot_index)
		):
			source_by_slot[source_offer.slot_index] = source_offer.deep_clone()
	if source_by_slot.size() != 5:
		return {"ok": false, "error": "canonical_offer_slots_incomplete"}

	var offers: Array[ShopOffer] = []
	for slot_index: int in range(5):
		var source := source_by_slot.get(slot_index) as ShopOffer
		var selected := selected_rules[slot_index]
		offers.append(ShopOffer.new(
			slot_index,
			source.offer_id,
			selected.unit_id,
			selected.cost,
			source.reserved_copies,
			source.reservation_owner_key
		))
	snapshot.economy = EconomyState.new(
		snapshot.economy.gold,
		snapshot.economy.level,
		snapshot.economy.xp,
		snapshot.economy.win_streak,
		snapshot.economy.loss_streak,
		snapshot.economy.shop_refresh_index,
		offers
	)
	var previews := ShopOfferPreviewViewModel.new(
		snapshot.roster, battle_catalog
	).previews(snapshot.economy)
	if previews.size() != 5:
		return {"ok": false, "error": "rich_preview_count"}
	snapshot.shop_offer_previews.assign(previews)
	snapshot.app_phase = &"PREPARE"

	var expected: Array[Dictionary] = []
	for slot_index: int in range(5):
		var preview := previews[slot_index]
		var offer := offers[slot_index]
		if (
			preview == null
			or preview.slot_index != slot_index
			or preview.offer_id != StringName(offer.offer_id)
			or preview.unit_def_id != offer.unit_def_id
			or preview.cost != offer.cost
			or preview.cost_tier != slot_index + 1
		):
			return {"ok": false, "error": "strict_match_slot_%d" % slot_index}
		expected.append({
			"slot_index": slot_index,
			"offer_id": offer.offer_id,
			"unit_def_id": preview.unit_def_id,
			"tier": preview.cost_tier,
			"cost": preview.cost,
			"trait_ids": preview.trait_ids.duplicate(),
			"owned_unit_count": preview.owned_unit_count,
			"star_up_after_purchase": preview.star_up_after_purchase,
		})
	return {"ok": true, "snapshot": snapshot, "expected": expected}


func _mount_formal_prepare_shop_tier_screen(
	snapshot: RunPresentationSnapshot,
	generation: int,
	typed_session: RunPresentationSession = null
) -> ProductionScreen:
	if snapshot == null or _prepare_fixture_localized_text.is_empty():
		return null
	for child: Node in _harness.host.get_children():
		_harness.host.remove_child(child)
		child.free()
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	if screen == null:
		return null
	var staged := StagedScreenContext.new(
		&"RUN_PREPARE",
		snapshot,
		null,
		&"zh_TW",
		_prepare_fixture_localized_text
	)
	if not screen.bind(staged).is_empty():
		screen.free()
		return null
	var session: RunPresentationSession = typed_session
	if session == null:
		var spy := CompositionSupport.SpyRunPresentationSession.new()
		spy.current_snapshot = snapshot.deep_clone()
		session = spy
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, generation)
	var live := ProductionLiveScreenContext.new(
		&"RUN_PREPARE",
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		LiveScreenIntentPort.new(lease, registry, session)
	)
	if not screen.prepare_live_binding(live).is_empty():
		screen.free()
		return null
	_harness.host.add_child(screen)
	screen.activate_live()
	return screen


func _validate_prepare_shop_tier_cards(
	screen: ProductionScreen,
	case_name: String,
	expected: Array[Dictionary]
) -> void:
	var cards := screen.find_child("PrepareShopCards", true, false) as HBoxContainer
	if cards == null or cards.get_child_count() != 5 or expected.size() != 5:
		_issues.append("prepare_shop_tier_card_count:%s" % case_name)
		return
	var variations: Dictionary = {}
	var style_signatures: Dictionary = {}
	var canvas := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	for slot_index: int in range(5):
		var card := cards.get_child(slot_index) as Button
		var entry := expected[slot_index]
		if card == null:
			_issues.append("prepare_shop_tier_card_missing:%s:%d" % [
				case_name, slot_index,
			])
			continue
		var tier := int(entry["tier"])
		var expected_variation := StringName("ExpeditionShopCardTier%d" % tier)
		if card.theme_type_variation != expected_variation:
			_issues.append("prepare_shop_tier_variation:%s:%d" % [
				case_name, slot_index,
			])
		variations[card.theme_type_variation] = true
		var style_signature := _shop_card_style_signature(card)
		if style_signature.is_empty():
			_issues.append("prepare_shop_tier_style_missing:%s:%d" % [
				case_name, slot_index,
			])
		else:
			style_signatures[style_signature] = true
		if (
			card.disabled
			or StringName(card.get_meta(&"typed_data_kind", &"")) != &"shop_offer"
			or not bool(card.get_meta(&"direct_action_owned", false))
			or card.has_meta(&"action_id")
			or String(card.get_meta(&"shop_offer_id", "")) != String(entry["offer_id"])
			or int(card.get_meta(&"shop_cost", -1)) != int(entry["cost"])
			or int(card.get_meta(&"shop_cost_tier", -1)) != tier
		):
			_issues.append("prepare_shop_tier_strict_match:%s:%d" % [
				case_name, slot_index,
			])

		var name_label := card.get_node_or_null(
			"CardContent/IdentityRow/IdentityText/UnitName"
		) as Label
		var price_label := card.get_node_or_null(
			"CardContent/IdentityRow/IdentityText/PriceTier"
		) as Label
		var trait_label := card.get_node_or_null("CardContent/Traits") as Label
		var ownership_label := card.get_node_or_null(
			"CardContent/OwnedAndStarUp"
		) as Label
		var tier_cues := card.get_node_or_null(
			"CardContent/IdentityRow/IdentityText/PriceTier/TierCueShapes"
		) as HBoxContainer
		var portrait := card.get_node_or_null(
			"CardContent/IdentityRow/Portrait"
		) as TextureRect
		if (
			name_label == null
			or price_label == null
			or trait_label == null
			or ownership_label == null
			or tier_cues == null
			or portrait == null
			or portrait.texture == null
		):
			_issues.append("prepare_shop_tier_labels_missing:%s:%d" % [
				case_name, slot_index,
			])
			continue
		if (
			int(tier_cues.get_meta(&"authoritative_cost_tier", -1)) != tier
			or tier_cues.get_meta(&"non_color_cue", &"") != &"tier-pips"
		):
			_issues.append("prepare_shop_tier_cue_contract:%s:%d" % [
				case_name, slot_index,
			])
		if tier_cues.get_child_count() != tier:
			_issues.append("prepare_shop_tier_shape_count:%s:%d:%d:%d" % [
				case_name, slot_index, tier_cues.get_child_count(), tier,
			])
		elif not _shop_tier_cue_has_visible_geometry(tier_cues):
			_issues.append("prepare_shop_tier_shape_geometry:%s:%d" % [
				case_name, slot_index,
			])
		var card_rect := card.get_global_rect()
		var effective_visible := card_rect.intersection(
			_scroll_effective_rect(_scroll_ancestor_chain(card), canvas)
		)
		if (
			not card.is_visible_in_tree()
			or not card_rect.has_area()
			or not effective_visible.has_area()
		):
			_issues.append("prepare_shop_tier_not_visible:%s:%d" % [
				case_name, slot_index,
			])

		var unit_def_id := StringName(entry["unit_def_id"])
		var unit_name := _fixture_localized_content(unit_def_id)
		var localized_traits: Array[String] = []
		var raw_trait_ids := entry.get("trait_ids", []) as Array
		for raw_trait_id: Variant in raw_trait_ids:
			localized_traits.append(
				_fixture_localized_content(StringName(raw_trait_id))
			)
		var cost_text := String(
			_prepare_fixture_localized_text.get(&"tooltip.cost", "")
		)
		var star_text := String(
			_prepare_fixture_localized_text.get(&"tooltip.star", "")
		)
		var owned_text := String(
			_prepare_fixture_localized_text.get(&"prepare.panel.units", "")
		)
		var star_up_after_purchase := bool(entry["star_up_after_purchase"])
		var expected_star := 1 if star_up_after_purchase else 0
		var expected_price := "%s %d" % [cost_text, int(entry["cost"])]
		var expected_ownership := "%s %d" % [
			owned_text,
			int(entry["owned_unit_count"]),
		]
		if star_up_after_purchase:
			expected_ownership += " · %s" % star_text
		if (
			unit_name.is_empty()
			or name_label.text != unit_name
			or price_label.text != expected_price
			or trait_label.text != " / ".join(localized_traits)
			or ownership_label.text != expected_ownership
			or int(price_label.get_meta(&"authoritative_cost", -1)) != int(entry["cost"])
			or int(price_label.get_meta(&"authoritative_cost_tier", -1)) != tier
			or int(ownership_label.get_meta(
				&"star_up_after_purchase_value", -1
			)) != expected_star
		):
			_issues.append("prepare_shop_tier_non_color_cue:%s:%d" % [
				case_name, slot_index,
			])
		var card_accessible := String(card.get_meta(&"accessible_text", ""))
		var name_accessible := String(
			name_label.get_meta(&"accessible_text", "")
		)
		var price_accessible := String(
			price_label.get_meta(&"accessible_text", "")
		)
		var trait_accessible := String(
			trait_label.get_meta(&"accessible_text", "")
		)
		var ownership_accessible := String(
			ownership_label.get_meta(&"accessible_text", "")
		)
		if (
			card.tooltip_text.is_empty()
			or card_accessible.is_empty()
			or card_accessible != card.tooltip_text
			or name_label.text.is_empty()
			or name_accessible.is_empty()
			or name_accessible != name_label.text
			or price_label.text.is_empty()
			or price_accessible.is_empty()
			or price_accessible != price_label.text
			or trait_label.text.is_empty()
			or trait_accessible.is_empty()
			or trait_accessible != trait_label.text
			or ownership_label.text.is_empty()
			or ownership_accessible.is_empty()
			or ownership_accessible != ownership_label.text
		):
			_issues.append("prepare_shop_tier_accessibility_copy:%s:%d" % [
				case_name, slot_index,
			])
		var audited_text := "\n".join([
			card.text,
			card.tooltip_text,
			card_accessible,
			name_label.text,
			name_accessible,
			price_label.text,
			price_accessible,
			trait_label.text,
			trait_accessible,
			ownership_label.text,
			ownership_accessible,
		])
		if (
			audited_text.contains(String(unit_def_id))
			or audited_text.contains(String(_fixture_content_key(unit_def_id)))
		):
			_issues.append("prepare_shop_tier_raw_unit_identity:%s:%d" % [
				case_name, slot_index,
			])
		for raw_trait_id: Variant in raw_trait_ids:
			var trait_id := StringName(raw_trait_id)
			if (
				audited_text.contains(String(trait_id))
				or audited_text.contains(String(_fixture_content_key(trait_id)))
			):
				_issues.append("prepare_shop_tier_raw_trait_identity:%s:%d" % [
					case_name, slot_index,
				])
	if variations.size() != 5:
		_issues.append("prepare_shop_tier_variations_not_distinct:%s" % case_name)
	if style_signatures.size() != 5:
		_issues.append("prepare_shop_tier_styles_not_distinct:%s" % case_name)


func _shop_tier_cue_has_visible_geometry(tier_cues: HBoxContainer) -> bool:
	if (
		tier_cues == null
		or not tier_cues.is_visible_in_tree()
		or not tier_cues.get_global_rect().has_area()
	):
		return false
	for shape_index: int in range(tier_cues.get_child_count()):
		var shape := tier_cues.get_child(shape_index) as ColorRect
		if (
			shape == null
			or not shape.is_visible_in_tree()
			or shape.custom_minimum_size.x <= 0.0
			or shape.custom_minimum_size.y <= 0.0
			or not shape.get_global_rect().has_area()
		):
			return false
	return true


func _shop_card_style_signature(card: Button) -> String:
	var style := card.get_theme_stylebox(&"normal")
	if not style is StyleBoxFlat:
		return ""
	var flat := style as StyleBoxFlat
	return "%s|%s|%d|%d|%d|%d" % [
		flat.bg_color.to_html(true),
		flat.border_color.to_html(true),
		flat.border_width_left,
		flat.border_width_top,
		flat.border_width_right,
		flat.border_width_bottom,
	]


func _fixture_content_key(content_id: StringName) -> StringName:
	return StringName("loc.%s" % String(content_id).replace(".", "_"))


func _fixture_localized_content(content_id: StringName) -> String:
	var key := _fixture_content_key(content_id)
	return String(_prepare_fixture_localized_text.get(key, String(key)))


func _fixture_content_is_localized(content_id: StringName) -> bool:
	if content_id.is_empty():
		return false
	var key := _fixture_content_key(content_id)
	var value := String(_prepare_fixture_localized_text.get(key, ""))
	return (
		not value.is_empty()
		and value != String(key)
		and value != String(content_id)
	)


func _wait_for_route(
	route_kinds: Array[StringName],
	frame_limit: int
) -> StringName:
	for _frame: int in range(frame_limit):
		var screen := Support.active_screen(_harness)
		if screen != null and screen.route_kind in route_kinds:
			return screen.route_kind
		await process_frame
	return &""


func _capture_settings_after_apply(
	output_dir: String,
	case: Dictionary
) -> void:
	_configure_window(case["size"])
	var screen := Support.active_screen(_harness)
	var composition := (
		screen.get_node_or_null(^"Composition") as SettingsScreenComposition
		if screen != null and screen.route_kind == &"SETTINGS"
		else null
	)
	if composition == null:
		_issues.append("settings_composition_missing:%s" % case["name"])
		return
	var candidate := composition.settings_draft()
	candidate.locale = &"zh_TW"
	candidate.ui_scale_percent = int(case["ui"])
	var edit_error := composition.replace_settings_draft(candidate)
	var apply_button := _action_button(screen, &"settings.apply")
	if not edit_error.is_empty() or apply_button == null:
		_issues.append("settings_prepare_apply_failed:%s" % case["name"])
		return
	apply_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	if screen.last_control_result() == null or not bool(screen.last_control_result().ok):
		_issues.append("settings_live_apply_failed:%s" % case["name"])
		return
	_validate_action_buttons(screen, String(case["name"]))
	_reports.append(_save_viewport(
		"%s/settings-after-apply-%s.png" % [output_dir, case["name"]],
		"settings-after-apply",
		case
	))


func _capture_prepare_groups(output_dir: String) -> void:
	var screen := Support.active_screen(_harness)
	var selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton if screen != null else null
	if selector == null:
		_issues.append("prepare_group_selector_missing")
		return
	for case: Dictionary in CASES:
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append("prepare_group_scale_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		for group_index: int in selector.item_count:
			selector.select(group_index)
			selector.item_selected.emit(group_index)
			await process_frame
			await process_frame
			await _focus_last_enabled_scroll_action(
				screen,
				"%s-group-%d" % [case["name"], group_index]
			)
			await _validate_bottom_focus_scroll(
				screen,
				"%s-group-%d" % [case["name"], group_index]
			)
			_validate_action_buttons(
				screen,
				"%s-group-%d" % [case["name"], group_index]
			)
			var group_id := String(
				ProductionScreen.PREPARE_ACTION_GROUPS[group_index]["id"]
			).replace("_", "-")
			_reports.append(_save_viewport(
				"%s/prepare-group-%s-%s.png" % [
					output_dir, group_id, case["name"],
				],
				"prepare-group-%s" % group_id,
				case
			))


func _capture(
	output_dir: String,
	expected_route: StringName,
	prefix: String,
	case: Dictionary
) -> void:
	_configure_window(case["size"])
	var settings := Support.candidate(int(case["ui"]), &"default")
	settings.locale = &"zh_TW"
	var applied := _harness.root.settings_application_port().apply(settings)
	if not applied.ok:
		_issues.append("settings_apply_failed:%s:%s" % [prefix, case["name"]])
		return
	await process_frame
	await process_frame
	await process_frame
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != expected_route:
		_issues.append("route_mismatch:%s:%s" % [prefix, case["name"]])
		return
	_validate_action_buttons(screen, "%s:%s" % [prefix, case["name"]])
	if expected_route in [&"RUN_PREPARE", &"RUN_COMBAT"]:
		_validate_world_board_bottom_regions(
			screen,
			"%s:%s" % [prefix, case["name"]]
		)
		await _validate_bottom_focus_scroll(
			screen,
			"%s:%s" % [prefix, case["name"]]
		)
	if expected_route in [&"RUN_MAP", &"RUN_REWARD"]:
		_validate_run_route_actions_region(
			screen,
			"%s:%s" % [prefix, case["name"]]
		)
	if expected_route == &"SETTINGS":
		_validate_settings_layout(screen, String(case["name"]))
	if prefix == "prepare":
		_validate_prepare_top_bar(screen, String(case["name"]))
		_validate_prepare_content_regions(screen, String(case["name"]))
	var path := "%s/%s-%s.png" % [output_dir, prefix, case["name"]]
	_reports.append(_save_viewport(path, prefix, case))


func _validate_prepare_top_bar(screen: Control, case_name: String) -> void:
	var title := screen.get_node_or_null(^"Label") as Label
	var metrics := screen.get_node_or_null(^"Composition/PrepareContent/PrepareMetrics") as Control
	if title == null or metrics == null:
		_issues.append("prepare_top_bar_missing:%s" % case_name)
		return
	var title_rect := title.get_global_rect()
	var metrics_rect := metrics.get_global_rect()
	if title_rect.intersects(metrics_rect):
		_issues.append("prepare_top_bar_overlap:%s" % case_name)
	var viewport_rect := get_root().get_visible_rect()
	for node: Node in metrics.get_children():
		var label := node as Label
		if label == null:
			continue
		if not viewport_rect.encloses(label.get_global_rect()):
			_issues.append("prepare_metric_overflow:%s:%s" % [case_name, label.name])


func _validate_prepare_content_regions(screen: Control, case_name: String) -> void:
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	if shell == null:
		_issues.append("prepare_layout_shell_missing:%s" % case_name)
		return
	var center_scroll := screen.find_child(
		"PrepareCenterScroll", true, false
	) as ScrollContainer
	var center_region := shell.current_region_rect(
		ProductionLayoutShell.REGION_CENTER
	).grow(1.0)
	var status_rect := shell.current_region_rect(ProductionLayoutShell.REGION_STATUS)
	var bottom_rect := shell.current_region_rect(ProductionLayoutShell.REGION_BOTTOM)
	var canvas := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	# B1R3 T13：捲動內容可以超出 viewport，但 viewport 本身必須有有效
	# geometry 並落在中央區域／canvas；focus target 還必須已被捲入可見範圍。
	if center_scroll == null:
		_issues.append("prepare_center_scroll_missing:%s" % case_name)
	else:
		_validate_scroll_viewport(center_scroll, canvas, case_name, false)
		if not center_region.encloses(center_scroll.get_global_rect()):
			_issues.append("prepare_center_scroll_overflow:%s:%s" % [
				case_name, center_scroll.get_global_rect(),
			])

	# WorldBoard 是正式棋盤；legacy BoardGrid 僅保留 metadata，必須完全
	# 退出繪製、輸入與 Container minimum-size 契約。
	var board_grid := screen.find_child("BoardGrid", true, false) as GridContainer
	if board_grid == null:
		_issues.append("prepare_region_control_missing:%s:BoardGrid" % case_name)
	else:
		if board_grid.visible or board_grid.is_visible_in_tree():
			_issues.append("prepare_legacy_board_grid_visible:%s" % case_name)
		if board_grid.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_issues.append("prepare_legacy_board_grid_captures_pointer:%s" % case_name)
		if not board_grid.custom_minimum_size.is_zero_approx():
			_issues.append("prepare_legacy_board_grid_reserves_layout:%s:%s" % [
				case_name, board_grid.custom_minimum_size,
			])

	var bench := screen.find_child("BenchRow", true, false) as HBoxContainer
	if bench == null:
		_issues.append("prepare_region_control_missing:%s:BenchRow" % case_name)
	else:
		var bench_rect := bench.get_global_rect()
		if center_scroll != null and center_scroll.is_ancestor_of(bench):
			_issues.append("prepare_bench_in_scaled_center_flow:%s" % case_name)
		if not center_region.encloses(bench_rect):
			_issues.append("prepare_center_overflow:%s:BenchRow:%s" % [
				case_name, bench_rect,
			])
		if bench.get_child_count() != 9:
			_issues.append("prepare_bench_slot_count:%s:%d" % [
				case_name, bench.get_child_count(),
			])
		var previous_x := -INF
		var bench_y := NAN
		for child: Node in bench.get_children():
			var slot := child as Control
			if slot == null:
				continue
			var slot_rect := slot.get_global_rect()
			if slot_rect.position.x <= previous_x:
				_issues.append("prepare_bench_not_horizontal:%s:%s" % [
					case_name, slot.name,
				])
			if not is_nan(bench_y) and absf(slot_rect.position.y - bench_y) > 1.0:
				_issues.append("prepare_bench_not_single_row:%s:%s" % [
					case_name, slot.name,
				])
			bench_y = slot_rect.position.y if is_nan(bench_y) else bench_y
			previous_x = slot_rect.position.x
		if bench_rect.intersects(bottom_rect):
			_issues.append("prepare_center_cross_region:%s:BenchRow" % case_name)
		if shell.is_status_visible() and bench_rect.intersects(status_rect):
			_issues.append("prepare_center_under_status:%s:BenchRow" % case_name)
		var drag_target := _production_world_drag_target()
		if drag_target == null or not drag_target.is_visible_in_tree():
			_issues.append("prepare_world_drag_target_missing:%s" % case_name)
		elif bench_rect.intersects(drag_target.get_global_rect()):
			_issues.append("prepare_bench_over_world_board:%s:%s:%s" % [
				case_name, bench_rect, drag_target.get_global_rect(),
			])

	var inventory := screen.find_child(
		"InventorySelector", true, false
	) as ItemList
	var hud := screen.find_child("InRunHudShell", true, false) as InRunHudShell
	var left_host := (
		hud.host(ProductionLayoutShell.REGION_LEFT) if hud != null else null
	)
	var left_scroll := screen.find_child(
		"InRunLeftScroll", true, false
	) as ScrollContainer
	if inventory == null:
		_issues.append("prepare_region_control_missing:%s:InventorySelector" % case_name)
	else:
		if left_host == null or not left_host.is_ancestor_of(inventory):
			_issues.append("prepare_inventory_outside_hud_left:%s" % case_name)
		if left_scroll == null or not left_scroll.is_ancestor_of(inventory):
			_issues.append("prepare_inventory_outside_left_scroll:%s" % case_name)
		if center_scroll != null and center_scroll.is_ancestor_of(inventory):
			_issues.append("prepare_inventory_in_world_center:%s" % case_name)
		if left_scroll != null:
			_validate_scroll_viewport(
				left_scroll, canvas, "%s:InventorySelector" % case_name
			)
	var bottom_panel := screen.find_child("BottomRegion", true, false) as Control
	var safe_margin := Vector2.ONE * ProductionLayoutShell.SAFE_MARGIN
	var safe_rect := Rect2(
		safe_margin,
		ProductionLayoutShell.REFERENCE_SIZE - safe_margin * 2.0
	)
	if bottom_panel == null or not safe_rect.encloses(bottom_panel.get_global_rect()):
		_issues.append("prepare_bottom_outside_safe_area:%s:%s" % [
			case_name,
			bottom_panel.get_global_rect() if bottom_panel != null else Rect2(),
		])


func _validate_world_board_bottom_regions(
	screen: Control,
	case_name: String
) -> void:
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	var bottom_panel := screen.find_child(
		"BottomRegion", true, false
	) as Control
	var bottom_scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	var drag_target := _production_world_drag_target()
	if shell == null:
		_issues.append("world_board_layout_shell_missing:%s" % case_name)
		return
	if bottom_panel == null or bottom_scroll == null:
		_issues.append("world_board_bottom_scroll_missing:%s" % case_name)
		return
	var content := shell.content(ProductionLayoutShell.REGION_BOTTOM)
	if bottom_scroll.get_parent() != bottom_panel:
		_issues.append("world_board_bottom_scroll_not_direct:%s" % case_name)
	if content == null or not bottom_scroll.is_ancestor_of(content):
		_issues.append("world_board_bottom_content_outside_scroll:%s" % case_name)
	if (
		bottom_scroll.horizontal_scroll_mode
		!= ScrollContainer.SCROLL_MODE_DISABLED
		or bottom_scroll.vertical_scroll_mode
		!= ScrollContainer.SCROLL_MODE_AUTO
		or not bottom_scroll.follow_focus
	):
		_issues.append("world_board_bottom_scroll_contract:%s" % case_name)
	var bottom_rect := shell.current_region_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	if bottom_panel.get_global_rect() != bottom_rect:
		_issues.append("world_board_bottom_actual_rect_drift:%s:%s:%s" % [
			case_name, bottom_panel.get_global_rect(), bottom_rect,
		])
	var status_panel := screen.find_child(
		"StatusRegion", true, false
	) as Control
	var status_rect := shell.current_region_rect(
		ProductionLayoutShell.REGION_STATUS
	)
	if status_panel == null or status_panel.get_global_rect() != status_rect:
		_issues.append("world_board_status_actual_rect_drift:%s:%s:%s" % [
			case_name,
			status_panel.get_global_rect() if status_panel != null else Rect2(),
			status_rect,
		])
	var expected_variation := (
		ProductionLayoutShell.ACTION_BAR_COMPACT_VARIATION
		if shell.is_status_visible()
		else ProductionLayoutShell.ACTION_BAR_VARIATION
	)
	if bottom_panel.theme_type_variation != expected_variation:
		_issues.append("world_board_bottom_variation_drift:%s:%s:%s" % [
			case_name, bottom_panel.theme_type_variation, expected_variation,
		])
	if bottom_rect.position.y < 804.0 - 0.001:
		_issues.append("world_board_bottom_cap_invalid:%s:%s" % [
			case_name, bottom_rect,
		])
	if drag_target == null:
		_issues.append("world_board_drag_target_missing:%s" % case_name)
		return
	var board_screen_rect := _control_canvas_rect(drag_target)
	var bottom_screen_rect := _control_canvas_rect(bottom_panel)
	if board_screen_rect.end.y > bottom_screen_rect.position.y + 1.0:
		_issues.append("world_board_under_bottom_band:%s:%s:%s" % [
			case_name, board_screen_rect, bottom_screen_rect,
		])
	if shell.is_status_visible():
		if status_panel == null:
			_issues.append("world_board_status_region_missing:%s" % case_name)
		else:
			var status_screen_rect := _control_canvas_rect(status_panel)
			if board_screen_rect.end.y > status_screen_rect.position.y + 1.0:
				_issues.append("world_board_under_status_band:%s:%s:%s" % [
					case_name, board_screen_rect, status_screen_rect,
				])


func _validate_bottom_focus_scroll(
	screen: Control,
	case_name: String
) -> void:
	var scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	if scroll == null:
		_issues.append("bottom_focus_scroll_missing:%s" % case_name)
		return
	var enabled_actions: Array[Button] = []
	for node: Node in scroll.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.is_visible_in_tree()
			and not button.disabled
			and button.focus_mode != Control.FOCUS_NONE
		):
			enabled_actions.append(button)
	if enabled_actions.is_empty():
		_issues.append("bottom_focus_target_missing:%s" % case_name)
		return
	for button: Button in enabled_actions:
		if _ancestor_scroll_container_named(
			button, &"PrepareActionGroupScroll"
		) != null:
			# Prepare actions live in nested scroll containers. Their stricter
			# inner+outer focus contract is validated per action group below.
			continue
		var focus_owner := root.gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()
		await process_frame
		scroll.scroll_vertical = 0
		await process_frame
		button.grab_focus()
		await process_frame
		await process_frame
		if not button.has_focus():
			_issues.append("bottom_action_focus_failed:%s:%s" % [
				case_name, button.name,
			])
			continue
		var scroll_rect := _control_canvas_rect(scroll)
		var button_rect := _control_canvas_rect(button)
		var can_fully_fit := (
			button_rect.size.x <= scroll_rect.size.x
			and button_rect.size.y <= scroll_rect.size.y
		)
		var intersection := scroll_rect.intersection(button_rect)
		var required_visible_height := minf(
			scroll_rect.size.y, button_rect.size.y
		) - 1.0
		var vertical_center_visible := (
			button_rect.get_center().y >= scroll_rect.position.y - 1.0
			and button_rect.get_center().y <= scroll_rect.end.y + 1.0
		)
		var focus_visible := (
			scroll_rect.grow(1.0).encloses(button_rect)
			if can_fully_fit
			else (
				intersection.size.y >= required_visible_height
				and vertical_center_visible
			)
		)
		if not focus_visible:
			_issues.append("bottom_action_focus_clipped:%s:%s:%s" % [
				case_name, button.name, button_rect,
			])


func _control_canvas_rect(control: Control) -> Rect2:
	if control == null:
		return Rect2()
	var transform := control.get_global_transform_with_canvas()
	var minimum := transform * Vector2.ZERO
	var maximum := minimum
	for corner: Vector2 in [
		Vector2(control.size.x, 0.0),
		control.size,
		Vector2(0.0, control.size.y),
	]:
		var mapped := transform * corner
		minimum = minimum.min(mapped)
		maximum = maximum.max(mapped)
	return Rect2(minimum, maximum - minimum)


func _validate_action_buttons(screen: Control, case_name: String) -> void:
	var canvas := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button == null
			or not button.is_visible_in_tree()
			or not button.has_meta(&"action_id")
		):
			continue
		var text_width := _button_text_width(button)
		var rect := button.get_global_rect()
		if rect.size.x + 0.5 < text_width:
			_issues.append("action_text_clipped:%s:%s:%s<%s" % [
				case_name,
				button.get_meta(&"action_id"),
				rect.size.x,
				text_width,
			])
		# Nested scroll contents may extend beyond the outer viewport. Validate
		# every clipping ancestor, require only the outermost viewport itself to
		# be inside the canvas, and judge focus against their effective
		# intersection.
		var scrolls := _scroll_ancestor_chain(button)
		if not scrolls.is_empty():
			for index: int in range(scrolls.size()):
				_validate_scroll_viewport(
					scrolls[index],
					canvas,
					case_name,
					true,
					index == scrolls.size() - 1
				)
			var effective_rect := _scroll_effective_rect(scrolls, canvas)
			if button.has_focus() and not effective_rect.grow(1.0).encloses(rect):
				_issues.append("focused_action_clipped:%s:%s:%s" % [
					case_name, button.get_meta(&"action_id"), rect,
				])
			if _all_scrolls_follow_focus(scrolls):
				continue
		if not canvas.encloses(rect):
			_issues.append("action_outside_canvas:%s:%s:%s" % [
				case_name, button.get_meta(&"action_id"), rect,
			])


func _validate_scroll_viewport(
	scroll: ScrollContainer,
	canvas: Rect2,
	case_name: String,
	require_follow_focus: bool = true,
	require_canvas_enclosure: bool = true
) -> void:
	if scroll == null:
		_issues.append("scroll_viewport_missing:%s" % case_name)
		return
	var viewport_rect := scroll.get_global_rect()
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		_issues.append("scroll_viewport_zero:%s:%s:%s" % [
			case_name, scroll.name, viewport_rect,
		])
	if require_canvas_enclosure and not canvas.grow(1.0).encloses(viewport_rect):
		_issues.append("scroll_viewport_outside_canvas:%s:%s:%s" % [
			case_name, scroll.name, viewport_rect,
		])
	if require_follow_focus and not scroll.follow_focus:
		_issues.append("scroll_viewport_without_follow_focus:%s:%s" % [
			case_name, scroll.name,
		])


func _production_world_drag_target() -> WorldBoardDragTarget:
	for candidate: Node in get_nodes_in_group(ProductionWorldSurface.MOUNT_GROUP):
		var surface := candidate as ProductionWorldSurface
		if surface == null:
			continue
		var overlay := surface.ui_overlay()
		if overlay != null:
			return overlay.drag_target()
	return null


func _validate_run_route_actions_region(
	screen: Control,
	case_name: String
) -> void:
	var production_screen := screen as ProductionScreen
	var actions := screen.find_child("Actions", true, false) as Control
	var bottom_content := (
		production_screen.layout_content(ProductionLayoutShell.REGION_BOTTOM)
		if production_screen != null
		else null
	)
	if actions == null or bottom_content == null:
		_issues.append("run_actions_bottom_content_missing:%s" % case_name)
		return
	var actions_rect := actions.get_global_rect()
	var bottom_rect := bottom_content.get_global_rect()
	if actions_rect.size.x <= 0.0 or actions_rect.size.y <= 0.0:
		_issues.append("run_actions_zero:%s:%s" % [case_name, actions_rect])
	if not bottom_rect.grow(1.0).encloses(actions_rect):
		_issues.append("run_actions_outside_bottom_content:%s:%s:%s" % [
			case_name, actions_rect, bottom_rect,
		])


func _validate_settings_layout(screen: Control, case_name: String) -> void:
	var title := screen.get_node_or_null(^"Label") as Label
	var locale_row := screen.find_child("LocaleRow", true, false) as Control
	var locale_editor := screen.find_child("Locale", true, false) as Control
	var actions := screen.get_node_or_null(^"Actions") as Control
	var composition := screen.get_node_or_null(^"Composition") as Control
	if (
		title == null
		or locale_row == null
		or locale_editor == null
		or actions == null
		or composition == null
	):
		_issues.append("settings_layout_nodes_missing:%s" % case_name)
		return
	if title.get_global_rect().intersects(locale_row.get_global_rect()):
		_issues.append("settings_title_locale_overlap:%s" % case_name)
	if not locale_editor.tooltip_text.is_empty():
		_issues.append("settings_duplicate_hover_text:%s" % case_name)
	# B1R3 T13：改為對安全區與獨立期望值斷言（先前 gap.end==actions.y 恆真）。
	var safe_bottom := (
		ProductionLayoutShell.REFERENCE_SIZE.y
		- ProductionLayoutShell.SAFE_MARGIN
	)
	var actions_rect := actions.get_global_rect()
	if actions_rect.end.y > safe_bottom + 0.5:
		_issues.append("settings_actions_below_safe_area:%s:%s" % [
			case_name, actions_rect,
		])
	var composition_rect := composition.get_global_rect()
	if composition_rect.intersects(actions_rect):
		_issues.append("settings_composition_actions_overlap:%s" % case_name)
	var status := screen.get_node_or_null(^"StatusMessage") as Control
	if status != null and status.get_global_rect().intersects(actions_rect):
		_issues.append("settings_status_actions_overlap:%s" % case_name)


func _button_text_width(button: Button) -> float:
	if button == null or button.text.is_empty():
		return 0.0
	var widest := 0.0
	var font := button.get_theme_font(&"font")
	var size := button.get_theme_font_size(&"font_size")
	for line: String in button.text.split("\n"):
		widest = maxf(widest, font.get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, size
		).x)
	return widest


func _ancestor_scroll_container_named(
	control: Control,
	target_name: StringName
) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and ancestor.name == target_name:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _scroll_ancestor_chain(control: Control) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			result.append(ancestor as ScrollContainer)
		ancestor = ancestor.get_parent()
	return result


func _scroll_effective_rect(
	scrolls: Array[ScrollContainer],
	canvas: Rect2
) -> Rect2:
	var result := canvas
	for scroll: ScrollContainer in scrolls:
		result = result.intersection(scroll.get_global_rect())
	return result


func _all_scrolls_follow_focus(scrolls: Array[ScrollContainer]) -> bool:
	for scroll: ScrollContainer in scrolls:
		if not scroll.follow_focus:
			return false
	return true


func _focus_last_enabled_scroll_action(
	screen: Control,
	case_name: String
) -> void:
	var scroll := screen.find_child(
		"PrepareActionGroupScroll", true, false
	) as ScrollContainer
	if scroll == null:
		_issues.append("prepare_action_scroll_missing:%s" % case_name)
		return
	var canvas := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	var scrolls := _scroll_ancestor_chain(scroll)
	scrolls.push_front(scroll)
	for index: int in range(scrolls.size()):
		_validate_scroll_viewport(
			scrolls[index],
			canvas,
			case_name,
			true,
			index == scrolls.size() - 1
		)
	var last_enabled: Button = null
	var visible_actions := 0
	for node: Node in scroll.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		visible_actions += 1
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			last_enabled = button
	if visible_actions == 0:
		_issues.append("prepare_action_group_empty:%s" % case_name)
		return
	# An all-disabled contextual group has no legal focus target. Its viewport is
	# still validated above; groups with an enabled action must prove focus-scroll.
	if last_enabled == null:
		return
	var focus_owner := root.gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	await process_frame
	for ancestor_scroll: ScrollContainer in scrolls:
		ancestor_scroll.scroll_vertical = 0
	await process_frame
	last_enabled.grab_focus()
	for _settle_index: int in range(5):
		await process_frame
	if not last_enabled.has_focus():
		_issues.append("prepare_action_focus_failed:%s:%s" % [
			case_name, last_enabled.name,
		])
	var action_rect := last_enabled.get_global_rect()
	var effective_rect := _scroll_effective_rect(scrolls, canvas)
	for ancestor_scroll: ScrollContainer in scrolls:
		var viewport_rect := ancestor_scroll.get_global_rect()
		if (
			action_rect.size.x > viewport_rect.size.x + 1.0
			or action_rect.size.y > viewport_rect.size.y + 1.0
		):
			_issues.append("prepare_action_does_not_fit_viewport:%s:%s:%s:%s" % [
				case_name, last_enabled.name, ancestor_scroll.name, action_rect,
			])
		if not viewport_rect.grow(1.0).encloses(action_rect):
			_issues.append("prepare_action_focus_clipped_in_viewport:%s:%s:%s:%s" % [
				case_name, last_enabled.name, ancestor_scroll.name, action_rect,
			])
	if not effective_rect.grow(1.0).encloses(action_rect):
		_issues.append("prepare_action_focus_clipped:%s:%s:%s" % [
			case_name, last_enabled.name, action_rect,
		])


func _capture_focus(output_dir: String) -> void:
	_configure_window(UI_REFERENCE_SIZE)
	var settings := Support.candidate(100, &"default")
	settings.locale = &"zh_TW"
	_harness.root.settings_application_port().apply(settings)
	var screen := Support.active_screen(_harness)
	var start_button: Button
	if screen != null:
		for node: Node in screen.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and StringName(button.get_meta(&"action_id", &"")) == &"prepare.start":
				start_button = button
				break
	if start_button == null:
		_issues.append("focus_target_missing")
		return
	start_button.grab_focus()
	await process_frame
	await process_frame
	var case := {
		"name": "focus-prepare-start",
		"size": UI_REFERENCE_SIZE,
		"ui": 100,
	}
	_reports.append(_save_viewport(
		"%s/focus-prepare-start.png" % output_dir,
		"focus",
		case
	))


func _capture_scale_rebuild(output_dir: String) -> void:
	_configure_window(UI_REFERENCE_SIZE)
	var baseline_settings := Support.candidate(100, &"default")
	baseline_settings.locale = &"zh_TW"
	var baseline_applied := _harness.root.settings_application_port().apply(
		baseline_settings
	)
	await process_frame
	await process_frame
	var baseline_screen := Support.active_screen(_harness)
	var baseline_start := _action_button(baseline_screen, &"prepare.start")
	var recorded_100_minimum := (
		baseline_start.custom_minimum_size
		if baseline_start != null
		else Vector2.ZERO
	)
	var scaled := Support.candidate(150, &"default")
	scaled.locale = &"zh_TW"
	var applied := _harness.root.settings_application_port().apply(scaled)
	if not applied.ok:
		_issues.append("scale_rebuild_150_apply_failed")
		return
	await process_frame
	await process_frame
	var reload_error := Support.reload_current_route(_harness)
	if not reload_error.is_empty():
		_issues.append("scale_rebuild_route_failed:%s" % reload_error)
		return
	await process_frame
	await process_frame
	var restored := _harness.root.settings_application_port().apply(
		baseline_settings
	)
	await process_frame
	await process_frame
	var screen := Support.active_screen(_harness)
	var start := _action_button(screen, &"prepare.start")
	var report := {
		"ok": (
			baseline_applied.ok
			and restored.ok
			and start != null
			and recorded_100_minimum.x > 8.0
			and start.custom_minimum_size == recorded_100_minimum
			and start.get_global_rect().size.x >= _button_text_width(start)
		),
		"sequence": [150, "rebuild", 100],
		"recorded_100_minimum": recorded_100_minimum,
		"start_button_minimum": start.custom_minimum_size if start != null else Vector2.ZERO,
		"effective_scale": (
			_harness.root.presentation_host.get_meta(
				&"effective_theme_scale_percent", 0
			)
			if _harness.root.presentation_host != null
			else 0
		),
	}
	if not bool(report["ok"]):
		_issues.append("scale_rebuild_baseline_not_restored")
	_write_json("%s/scale-rebuild-report.json" % output_dir, report)
	_reports.append(_save_viewport(
		"%s/prepare-scale-rebuild-150-rebuild-100.png" % output_dir,
		"prepare-scale-rebuild",
		{"name": "150-rebuild-100", "size": UI_REFERENCE_SIZE, "ui": 100}
	))


func _capture_node_choice(output_dir: String) -> void:
	var screen := Support.active_screen(_harness)
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen if screen != null else null
	var context := screen.get("_context") as StagedScreenContext if screen != null else null
	var live_context := screen.get("_live_context") as ProductionLiveScreenContext if screen != null else null
	var snapshot := context.snapshot_clone() as RunPresentationSnapshot if context != null else null
	if composition == null or live_context == null or snapshot == null:
		_issues.append("node_choice_prepare_context_missing")
		return
	var overlay := NodeChoiceOverlaySnapshot.new()
	overlay.choice_set_id = &"evidence.choice_set"
	overlay.display_name_key = &"prepare.panel.expedition"
	overlay.options = [
		NodeChoiceOptionSnapshot.new(
			&"choice_a", &"prepare.panel.party", &"prepare.panel.party",
			&"prepare.empty.synergies", true
		),
		NodeChoiceOptionSnapshot.new(
			&"choice_b", &"prepare.panel.inventory", &"prepare.panel.inventory",
			&"prepare.empty.overflow", true
		),
		NodeChoiceOptionSnapshot.new(
			&"choice_c", &"prepare.panel.shop", &"prepare.panel.shop",
			&"prepare.empty.issues", true
		),
	]
	snapshot.node_choice_overlay = overlay
	var report := screen.call(&"_snapshot_board_validation_report", snapshot) as BoardValidationReport
	var compose_error := composition.compose(snapshot, report, live_context.intent_port)
	screen.refresh_interaction_state()
	await process_frame
	await process_frame
	var scroll := screen.find_child("PrepareRightScroll", true, false) as ScrollContainer
	var start := _action_button(screen, &"prepare.start")
	var choice := screen.find_child("ChoiceSelector", true, false) as ItemList
	var canvas := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	var start_rect := start.get_global_rect() if start != null else Rect2()
	var right_rect := scroll.get_global_rect() if scroll != null else Rect2()
	var scenario := {
		"ok": (
			compose_error.is_empty()
			and scroll != null
			and choice != null
			and start != null
			and canvas.encloses(start_rect)
			and not right_rect.intersects(start_rect)
		),
		"right_scroll_present": scroll != null,
		"choice_count": choice.item_count if choice != null else 0,
		"start_button_rect": start_rect,
		"right_panel_rect": right_rect,
		"shop_card_count": 0,
		"disabled_shop_card_count": 0,
	}
	for node: Node in screen.find_children("ShopCard*", "Button", true, false):
		var card := node as Button
		if card == null or not card.has_meta(&"shop_offer_id"):
			continue
		scenario["shop_card_count"] = int(scenario["shop_card_count"]) + 1
		if card.disabled:
			scenario["disabled_shop_card_count"] = int(
				scenario["disabled_shop_card_count"]
			) + 1
	scenario["ok"] = bool(scenario["ok"]) and (
		int(scenario["shop_card_count"]) == 5
		and int(scenario["disabled_shop_card_count"]) == 5
	)
	if not bool(scenario["ok"]):
		_issues.append("node_choice_layout_failed:%s" % compose_error)
	_write_json("%s/node-choice-layout-report.json" % output_dir, scenario)
	for case: Dictionary in CASES:
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(settings)
		await process_frame
		await process_frame
		_validate_prepare_content_regions(screen, "node-choice-%s" % case["name"])
		_reports.append(_save_viewport(
			"%s/prepare-node-choice-%s.png" % [output_dir, case["name"]],
			"prepare-node-choice",
			case
		))
	var begin := _action_button(screen, &"choice.begin")
	if begin == null:
		_issues.append("node_choice_modal_trigger_missing")
		return
	begin.pressed.emit()
	await process_frame
	await process_frame
	var modal := screen.get_node_or_null(^"NodeChoiceConfirmation") as PanelContainer
	if modal == null or not screen.is_confirmation_modal_open():
		_issues.append("node_choice_modal_missing")
		return
	var modal_style := modal.get_theme_stylebox(&"panel") as StyleBoxFlat
	if modal_style == null or modal_style.bg_color.a < 0.99:
		_issues.append("node_choice_modal_not_opaque")
	for case: Dictionary in CASES:
		_configure_window(case["size"])
		var modal_settings := Support.candidate(int(case["ui"]), &"default")
		modal_settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(modal_settings)
		await process_frame
		await process_frame
		_reports.append(_save_viewport(
			"%s/prepare-node-choice-modal-%s.png" % [output_dir, case["name"]],
			"prepare-node-choice-modal",
			case
		))
	screen.call(&"_close_confirmation_modal")
	await process_frame
	if not screen.open_system_menu():
		_issues.append("system_menu_open_failed")
		return
	await process_frame
	await process_frame
	var run_menu := _action_button(screen, &"run.menu")
	if run_menu == null:
		_issues.append("return_modal_trigger_missing")
		screen.close_system_menu()
		return
	run_menu.pressed.emit()
	await process_frame
	await process_frame
	var return_modal := screen.find_child(
		"RunMenuConfirmation", true, false
	) as PanelContainer
	var system_overlay := screen.system_menu_overlay()
	if (
		return_modal == null
		or system_overlay == null
		or not system_overlay.is_confirmation_open()
	):
		_issues.append("return_modal_missing")
		screen.close_system_menu()
		return
	var return_style := return_modal.get_theme_stylebox(&"panel") as StyleBoxFlat
	if return_style == null or return_style.bg_color.a < 0.99:
		_issues.append("return_modal_not_opaque")
	for case: Dictionary in CASES:
		_configure_window(case["size"])
		var return_settings := Support.candidate(int(case["ui"]), &"default")
		return_settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(return_settings)
		await process_frame
		await process_frame
		_reports.append(_save_viewport(
			"%s/prepare-return-modal-%s.png" % [output_dir, case["name"]],
			"prepare-return-modal",
			case
		))
	screen.close_system_menu()
	await process_frame


func _capture_status_band(output_dir: String) -> void:
	var screen := Support.active_screen(_harness)
	if screen == null:
		_issues.append("status_screen_missing")
		return
	var injected := AppActionResult.failure(
		DiagnosticError.new(
			&"PREPARE_SELECTION_REQUIRED",
			&"error.presentation.prepare_selection_required"
		)
	)
	screen.report_composition_result(injected)
	await process_frame
	await process_frame
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	var status_rect := shell.current_region_rect(ProductionLayoutShell.REGION_STATUS)
	var center_rect := shell.current_region_rect(ProductionLayoutShell.REGION_CENTER)
	var report := {
		"ok": (
			not screen.status_message_text().is_empty()
			and shell.is_status_visible()
			and not status_rect.intersects(center_rect)
		),
		"message": screen.status_message_text(),
		"status_rect": status_rect,
		"content_rect": center_rect,
	}
	if not bool(report["ok"]):
		_issues.append("status_band_not_reserved")
	_write_json("%s/status-band-report.json" % output_dir, report)
	for case: Dictionary in CASES:
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(settings)
		await process_frame
		await process_frame
		_validate_prepare_content_regions(screen, "status-%s" % case["name"])
		_validate_world_board_bottom_regions(
			screen, "status-%s" % case["name"]
		)
		await _validate_bottom_focus_scroll(
			screen, "status-%s" % case["name"]
		)
		_reports.append(_save_viewport(
			"%s/prepare-status-message-%s.png" % [output_dir, case["name"]],
			"prepare-status",
			case
		))


func _action_button(screen: ProductionScreen, action_id: StringName) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and StringName(button.get_meta(&"action_id", &"")) == action_id:
			return button
	return null


func _configure_window(size: Vector2i) -> void:
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_root().content_scale_size = UI_REFERENCE_SIZE
	get_root().size = size


func _save_viewport(path: String, prefix: String, case: Dictionary) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := get_root().get_texture().get_image()
	var error := image.save_png(absolute_path)
	var readback := Image.load_from_file(absolute_path)
	var report := {
		"ok": error == OK and readback != null and _image_non_black(readback),
		"route": prefix,
		"case": String(case["name"]),
		"ui_scale": int(case["ui"]),
		"requested_width": (case["size"] as Vector2i).x,
		"requested_height": (case["size"] as Vector2i).y,
		"width": readback.get_width() if readback != null else 0,
		"height": readback.get_height() if readback != null else 0,
		"sha256": FileAccess.get_sha256(absolute_path),
		"path": path,
	}
	if not bool(report["ok"]):
		_issues.append("screenshot_failed:%s:%s" % [prefix, case["name"]])
	return report


func _image_non_black(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	for y: int in range(0, image.get_height(), maxi(1, image.get_height() / 32)):
		for x: int in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
			var color := image.get_pixel(x, y)
			if color.a > 0.1 and (color.r > 0.02 or color.g > 0.02 or color.b > 0.02):
				return true
	return false


func _output_directory() -> String:
	var requested := DEFAULT_OUTPUT_DIR
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			requested = argument.trim_prefix("--output-dir=")
			break
	var absolute := ProjectSettings.globalize_path(
		requested.replace("\\", "/")
	).simplify_path()
	var allowed_absolute := ProjectSettings.globalize_path(
		EVIDENCE_ROOT
	).simplify_path().trim_suffix("/")
	var allowed_prefix := allowed_absolute + "/"
	if not absolute.to_lower().begins_with(allowed_prefix.to_lower()):
		return ""
	return ProjectSettings.localize_path(absolute).replace("\\", "/")


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if file == null:
		_issues.append("report_write_failed:%s" % path)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _finish(output_dir: String) -> void:
	if _reports.size() != EXPECTED_REPORT_CASE_COUNT:
		_issues.append("evidence_report_case_count:%d:%d" % [
			_reports.size(), EXPECTED_REPORT_CASE_COUNT,
		])
	_write_json("%s/evidence-report.json" % output_dir, {
		"ok": _issues.is_empty(),
		"exit_code": 0 if _issues.is_empty() else 2,
		"locale": "zh_TW",
		"baseline_case_count": BASELINE_REPORT_CASE_COUNT,
		"shop_tier_evidence_case_count": SHOP_TIER_EVIDENCE_CASE_COUNT,
		"expected_case_count": EXPECTED_REPORT_CASE_COUNT,
		"cases": _reports,
		"issues": _issues,
	})
	if _harness != null:
		_harness.dispose()
		await process_frame
		await process_frame
	quit(0 if _issues.is_empty() else 2)
