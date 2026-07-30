extends RefCounted

const ResolutionFixtureFactory = preload(
	"res://tests/fixtures/save/resolution_fixture_factory.gd"
)
const BOARD_TILE := Vector2i(17, 11)
const TILE_SIZE := Vector2i(16, 16)
const CAMP_HOTSPOT := Rect2(412.0, 196.0, 48.0, 32.0)
const UI_CONTROL := Rect2(930.0, 520.0, 210.0, 72.0)
const ACCESSIBILITY_PATH := ^"AccessibilityRuntime"
const REQUIRED_RUNTIME_PATHS: Array[NodePath] = [
	^"AccessibilityRuntime/StateSummary",
	^"AccessibilityRuntime/MotionProbe",
	^"AccessibilityRuntime/FlashProbe",
	^"AccessibilityRuntime/ParticleProbe",
	^"AccessibilityRuntime/RuleInformation",
	^"AccessibilityRuntime/DamageEvents",
	^"AccessibilityRuntime/CjkBody",
]


class FakeSettingsStorage:
	extends RefCounted

	var files: Dictionary = {}


	func read_bytes(path: StringName) -> Dictionary:
		if not files.has(path):
			return {
				"ok": true,
				"exists": false,
				"bytes": PackedByteArray(),
			}
		return {
			"ok": true,
			"exists": true,
			"bytes": (files[path] as PackedByteArray).duplicate(),
		}


	func write_bytes(path: StringName, bytes: PackedByteArray) -> Dictionary:
		files[path] = bytes.duplicate()
		return {"ok": true}


	func promote_bytes(source: StringName, destination: StringName) -> Dictionary:
		if not files.has(source):
			return _failure()
		if files.has(destination):
			files[SettingsRepository.BACKUP_PATH] = (
				files[destination] as PackedByteArray
			).duplicate()
		files[destination] = (files[source] as PackedByteArray).duplicate()
		files.erase(source)
		return {"ok": true}


	func copy_bytes(source: StringName, destination: StringName) -> Dictionary:
		if not files.has(source):
			return _failure()
		files[destination] = (files[source] as PackedByteArray).duplicate()
		return {"ok": true}


	func restore_bytes(source: StringName, destination: StringName) -> Dictionary:
		return copy_bytes(source, destination)


	func remove_bytes(path: StringName) -> Dictionary:
		files.erase(path)
		return {"ok": true}


	func _failure() -> Dictionary:
		return {
			"ok": false,
			"error_code": SettingsRepository.STORAGE_FAULT,
		}


class FakeAudioBusPort:
	extends AudioBusPort

	var assignments: Dictionary = {}
	var apply_count: int


	func apply_batch(batch: AudioBusBatch) -> AudioBusBatchResult:
		if batch == null or batch.assignments.size() != 4:
			return AudioBusBatchResult.failure(AUDIO_BUS_BATCH_INVALID)
		var next_assignments: Dictionary = {}
		for assignment: AudioBusAssignment in batch.assignments:
			next_assignments[assignment.bus] = assignment.deep_clone()
		assignments = next_assignments
		apply_count += 1
		return AudioBusBatchResult.success()


class BootHarness:
	extends RefCounted

	var registry: ContentRegistryService
	var repository: SaveRepository
	var router: SceneRouterService
	var settings_repository: SettingsRepository
	var settings_storage: FakeSettingsStorage
	var audio_port: FakeAudioBusPort
	var audio: AudioCoordinator
	var root: ApplicationRoot
	var host: Control
	var gameplay_storage: FakeSaveStorage
	var settings_bind_error: StringName
	var boot_error: StringName
	var owned_nodes: Array[Node] = []


	func dispose() -> void:
		for index: int in range(owned_nodes.size() - 1, -1, -1):
			var node := owned_nodes[index]
			if node != null and is_instance_valid(node):
				node.queue_free()
		owned_nodes.clear()


static func boot_runtime(
	tree: SceneTree,
	gameplay_storage: FakeSaveStorage = null,
	settings_storage: FakeSettingsStorage = null
) -> BootHarness:
	var harness := BootHarness.new()
	harness.gameplay_storage = (
		gameplay_storage
		if gameplay_storage != null
		else FakeSaveStorage.new()
	)
	harness.settings_storage = (
		settings_storage
		if settings_storage != null
		else FakeSettingsStorage.new()
	)
	harness.registry = ContentRegistryService.new()
	harness.registry.name = "R14ContentRegistry"
	harness.repository = SaveRepository.new(harness.gameplay_storage)
	harness.repository.name = "R14SaveRepository"
	harness.router = SceneRouterService.new()
	harness.router.name = "R14SceneRouter"
	harness.settings_repository = SettingsRepository.new(
		harness.settings_storage
	)
	harness.settings_repository.name = "R14SettingsRepository"
	harness.audio_port = FakeAudioBusPort.new()
	harness.audio = AudioCoordinator.new(harness.audio_port)
	harness.audio.name = "R14AudioCoordinator"
	harness.root = ApplicationRoot.new()
	harness.root.name = "R14ApplicationRoot"
	harness.host = Control.new()
	harness.host.name = "PresentationHost"
	harness.host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	harness.root.add_child(harness.host)
	harness.root.boot_failed.connect(func(error_code: StringName) -> void:
		harness.boot_error = error_code
	)
	var service_error := harness.root.bind_services(
		harness.registry,
		harness.repository,
		harness.router
	)
	if not service_error.is_empty():
		harness.boot_error = service_error
		return harness

	# B05 intentionally requires the composition root to construct the concrete
	# PresentationSettingsRuntimeConsumer. The test and screenshot runner inject
	# only real persistence/audio services and never instantiate/activate a
	# consumer themselves.
	if not harness.root.has_method(&"bind_settings_services"):
		harness.settings_bind_error = &"R14_SETTINGS_SERVICE_BINDING_MISSING"
		return harness
	harness.settings_bind_error = StringName(harness.root.call(
		&"bind_settings_services",
		harness.settings_repository,
		harness.audio
	))
	if not harness.settings_bind_error.is_empty():
		return harness

	for node: Node in [
		harness.registry,
		harness.repository,
		harness.router,
		harness.settings_repository,
		harness.audio,
		harness.root,
	]:
		tree.root.add_child(node)
		harness.owned_nodes.append(node)
	return harness


static func boot(
	test: GutTest,
	gameplay_storage: FakeSaveStorage = null,
	settings_storage: FakeSettingsStorage = null
) -> BootHarness:
	var harness := boot_runtime(
		test.get_tree(),
		gameplay_storage,
		settings_storage
	)
	for node: Node in harness.owned_nodes:
		test.autofree(node)
	return harness


static func active_screen(harness: BootHarness) -> ProductionScreen:
	if (
		harness == null
		or harness.host == null
		or harness.host.get_child_count() != 1
	):
		return null
	return harness.host.get_child(0) as ProductionScreen


static func drive_to_run_prepare(harness: BootHarness) -> Dictionary:
	if harness == null or harness.root == null or not harness.root.is_booted():
		return _failure(&"R14_APP_ROOT_NOT_BOOTED")
	var opened: AppActionResult = harness.root.open_camp()
	if not opened.ok:
		return _failure(_app_error(opened))
	var view_model: CampViewModel = harness.root.try_camp_view_model()
	if view_model == null:
		return _failure(&"R14_CAMP_VIEW_MISSING")
	var commanders := view_model.commander_hall_unlocked_commander_ids()
	if commanders.is_empty():
		return _failure(&"R14_COMMANDER_MISSING")
	var started: AppActionResult = harness.root.start_expedition(
		StartExpeditionRequest.new(commanders[0], 0)
	)
	if not started.ok:
		return _failure(_app_error(started))
	var screen := active_screen(harness)
	if screen == null or screen.route_kind != &"RUN_MAP":
		return _failure(&"R14_RUN_MAP_ROUTE_MISSING")
	var generated := screen.request_intent(
		RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	)
	if not generated.ok:
		return _failure(_run_error(generated))
	var loaded: LoadResult = harness.repository.load()
	if not loaded.ok or loaded.run == null or loaded.run.map_state == null:
		return _failure(&"R14_GENERATED_MAP_NOT_COMMITTED")
	var target_node_id := _first_reachable_combat_node_id(loaded.run)
	if target_node_id.is_empty():
		return _failure(&"R14_REACHABLE_COMBAT_NODE_MISSING")
	screen = active_screen(harness)
	if screen == null:
		return _failure(&"R14_RUN_MAP_REPLACEMENT_MISSING")
	var enter := RunPresentationIntent.new(RunPresentationIntent.Kind.ENTER_NODE)
	enter.target_node_id = target_node_id
	var entered := screen.request_intent(enter)
	if not entered.ok:
		return _failure(_run_error(entered))
	screen = active_screen(harness)
	if screen == null or screen.route_kind != &"RUN_PREPARE":
		return _failure(&"R14_RUN_PREPARE_ROUTE_MISSING")
	return {
		"ok": true,
		"error": &"",
		"screen_instance_id": screen.get_instance_id(),
	}


static func seed_committed_combat_phase(harness: BootHarness) -> StringName:
	if harness == null or harness.repository == null:
		return &"R14_SAVE_REPOSITORY_MISSING"
	var loaded := harness.repository.load()
	if (
		not loaded.ok
		or loaded.profile == null
		or loaded.run == null
		or loaded.run.map_state == null
		or loaded.run.map_state.current_node_id == null
	):
		return &"R14_PREPARE_SAVE_MISSING"
	var run := loaded.run.deep_clone()
	run.run_phase = RunState.RunPhase.COMBAT
	run.resolution_state = CombatPendingResolutionState.new(
		ResolutionFixtureFactory.create_battle_setup()
	)
	var saved := harness.repository.save(
		RunSaveRootFactory.new().build(loaded.profile, run)
	)
	return &"" if saved.ok else saved.error.code


static func continue_to_run_combat(harness: BootHarness) -> Dictionary:
	if harness == null or harness.root == null or not harness.root.is_booted():
		return _failure(&"R14_APP_ROOT_NOT_BOOTED")
	var continued: AppActionResult = harness.root.continue_active_run()
	if not continued.ok:
		return _failure(_app_error(continued))
	var screen := active_screen(harness)
	if screen == null or screen.route_kind != &"RUN_COMBAT":
		return _failure(&"R14_RUN_COMBAT_RESTART_ROUTE_MISSING")
	return {
		"ok": true,
		"error": &"",
		"screen_instance_id": screen.get_instance_id(),
	}


static func reload_current_route(harness: BootHarness) -> StringName:
	if harness == null or harness.root == null:
		return &"R14_APP_ROOT_MISSING"
	if not harness.root.has_method(&"_route_for_state"):
		return &"R14_ROUTE_RELOAD_MISSING"
	return StringName(harness.root.call(&"_route_for_state"))


static func accessibility_host(
	harness: BootHarness
) -> ProductionAccessibilityHost:
	var screen := active_screen(harness)
	if screen == null or screen.route_kind != &"RUN_COMBAT":
		return null
	return screen.get_node_or_null(ACCESSIBILITY_PATH) as ProductionAccessibilityHost


static func candidate(
	ui_scale_percent: int = 150,
	color_mode: StringName = &"deuteranopia"
) -> SettingsSnapshot:
	var snapshot := SettingsSnapshot.new()
	snapshot.locale = &"zh_TW"
	snapshot.ui_scale_percent = ui_scale_percent
	snapshot.color_vision_mode = color_mode
	snapshot.reduced_motion = true
	snapshot.reduced_flash = true
	snapshot.reduced_particles = true
	snapshot.damage_number_density = &"reduced"
	return snapshot


static func snapshots_equal(
	left: SettingsSnapshot,
	right: SettingsSnapshot
) -> bool:
	if left == null or right == null:
		return false
	return (
		left.schema_version == right.schema_version
		and left.locale == right.locale
		and left.ui_scale_percent == right.ui_scale_percent
		and left.color_vision_mode == right.color_vision_mode
		and left.reduced_motion == right.reduced_motion
		and left.reduced_flash == right.reduced_flash
		and left.reduced_particles == right.reduced_particles
		and left.damage_number_density == right.damage_number_density
		and left.master_volume_bps == right.master_volume_bps
		and left.master_muted == right.master_muted
		and left.music_volume_bps == right.music_volume_bps
		and left.music_muted == right.music_muted
		and left.sfx_volume_bps == right.sfx_volume_bps
		and left.sfx_muted == right.sfx_muted
		and left.ui_volume_bps == right.ui_volume_bps
		and left.ui_muted == right.ui_muted
	)


static func machine_report(
	harness: BootHarness,
	window_size: Vector2i,
	settings: SettingsSnapshot
) -> Dictionary:
	var screen := active_screen(harness)
	var runtime := accessibility_host(harness)
	if screen == null or runtime == null:
		return {
			"ok": false,
			"issues": ["production_run_combat_runtime_missing"],
		}
	var issues: Array[String] = []
	var action_buttons: Array[Button] = []
	for node: Node in screen.find_children("*", "Button", true, false):
		action_buttons.append(node as Button)
	if action_buttons.is_empty():
		issues.append("focus_actions_missing")
	var focused := false
	var focus_style_visible := true
	var non_color_cues := true
	for button: Button in action_buttons:
		focused = focused or button.has_focus()
		focus_style_visible = (
			focus_style_visible
			and button.get_theme_stylebox(&"focus") != null
		)
		non_color_cues = (
			non_color_cues
			and button.focus_mode == Control.FOCUS_ALL
			and button.has_meta(&"action_id")
			and not button.text.strip_edges().is_empty()
		)
	if not focused or not focus_style_visible:
		issues.append("focus_not_visible")
	if not non_color_cues:
		issues.append("non_color_action_cues_missing")

	var clipped: Array[String] = []
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(window_size))
	for path: NodePath in REQUIRED_RUNTIME_PATHS:
		var runtime_node := screen.get_node_or_null(path)
		if runtime_node == null:
			clipped.append(String(path))
			continue
		if runtime_node is Control:
			var control := runtime_node as Control
			if control.visible \
				and not viewport_rect.encloses(control.get_global_rect()):
				clipped.append(String(path))
		elif runtime_node is Node2D:
			var canvas_node := runtime_node as Node2D
			if canvas_node.visible \
				and not viewport_rect.has_point(canvas_node.global_position):
				clipped.append(String(path))
	for button: Button in action_buttons:
		if button.visible and not viewport_rect.encloses(button.get_global_rect()):
			clipped.append(String(button.get_path()))
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.visible:
			continue
		var is_text_leaf := (
			control is Label
			and not (control as Label).text.strip_edges().is_empty()
		)
		var is_choice_leaf := (
			control is ItemList or control is OptionButton
		)
		if not is_text_leaf and not is_choice_leaf:
			continue
		var leaf_rect := control.get_global_rect()
		if (
			leaf_rect.size.x <= 0.0
			or leaf_rect.size.y <= 0.0
			or not viewport_rect.encloses(leaf_rect)
		):
			var leaf_path := String(control.get_path())
			if not clipped.has(leaf_path):
				clipped.append(leaf_path)
	var cjk_body := screen.get_node_or_null(
		^"AccessibilityRuntime/CjkBody"
	) as Label
	if cjk_body != null and cjk_body.visible:
		for button: Button in action_buttons:
			if (
				button.visible
				and cjk_body.get_global_rect().intersects(
					button.get_global_rect()
				)
			):
				var body_path := String(cjk_body.get_path())
				if not clipped.has(body_path):
					clipped.append(body_path)
				break
	if not clipped.is_empty():
		issues.append("required_controls_clipped")

	var runtime_report := runtime.runtime_accessibility_report()
	if runtime_report == null or not runtime_report.ok:
		issues.append("accessibility_runtime_report_failed")
	else:
		if (
			runtime_report.motion_effects_enabled
			or runtime_report.flash_effects_enabled
			or runtime_report.particle_effects_enabled
		):
			issues.append("reduced_effect_flags_not_applied")
		if (
			runtime_report.damage_number_density != settings.damage_number_density
			or not runtime_report.rule_information_visible
		):
			issues.append("density_or_rule_information_mismatch")
		if (
			not runtime_report.cjk_ok
			or not runtime_report.cjk_readable
			or not runtime_report.cjk_missing_glyphs.is_empty()
		):
			issues.append("cjk_runtime_unreadable")

	var host_meta := {
		"ui_scale_percent": int(
			harness.host.get_meta(&"ui_scale_percent", -1)
		),
		"color_vision_mode": StringName(
			harness.host.get_meta(&"color_vision_mode", &"")
		),
	}
	if int(host_meta["ui_scale_percent"]) != settings.ui_scale_percent:
		issues.append("ui_scale_runtime_mismatch")
	if StringName(host_meta["color_vision_mode"]) != settings.color_vision_mode:
		issues.append("color_mode_runtime_mismatch")

	var mapping := mapping_report(window_size, settings.ui_scale_percent)
	if not bool(mapping.get("ok", false)):
		issues.append("pointer_mapping_failed")
	var route_title := screen.get_node_or_null(^"Label") as Label
	var route_title_rect := (
		route_title.get_global_rect()
		if route_title != null
		else Rect2()
	)
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"route": screen.route_kind,
		"screen_instance_id": screen.get_instance_id(),
		"production_host": (
			runtime_report.production_host
			if runtime_report != null and runtime_report.ok
			else ""
		),
		"window_size": [window_size.x, window_size.y],
		"aspect_ratio": float(window_size.x) / float(window_size.y),
		"ui_scale_percent": settings.ui_scale_percent,
		"color_vision_mode": settings.color_vision_mode,
		"focus": {
			"action_count": action_buttons.size(),
			"focused": focused,
			"visible_style": focus_style_visible,
			"reachable": not action_buttons.is_empty() and non_color_cues,
		},
		"non_color_cues": non_color_cues,
		"clipped_required_controls": clipped,
		"route_title": {
			"text": route_title.text if route_title != null else "",
			"visible": route_title != null and route_title.visible,
			"position": [
				route_title_rect.position.x,
				route_title_rect.position.y,
			],
			"size": [
				route_title_rect.size.x,
				route_title_rect.size.y,
			],
		},
		"host_runtime_meta": host_meta,
		"pointer_mapping": mapping,
		"accessibility": (
			_accessibility_report(runtime_report)
			if runtime_report != null
			else {}
		),
	}


static func mapping_report(
	window_size: Vector2i,
	ui_scale_percent: int
) -> Dictionary:
	var policy := WorldViewportPolicy.new()
	var mapper := WindowCoordinateMapper.new()
	var layout := policy.layout_for_window(window_size)
	var configure_error := mapper.configure(layout, ui_scale_percent)
	if not configure_error.is_empty():
		return {
			"ok": false,
			"error": configure_error,
		}
	var world_point := Vector2(
		(BOARD_TILE.x + 0.5) * TILE_SIZE.x,
		(BOARD_TILE.y + 0.5) * TILE_SIZE.y
	)
	var world_screen := mapper.world_to_screen(world_point)
	var world_round_trip := mapper.screen_to_world(world_screen)
	var camp_point := CAMP_HOTSPOT.get_center()
	var camp_screen := mapper.world_to_screen(camp_point)
	var camp_round_trip := mapper.screen_to_world(camp_screen)
	var ui_point := UI_CONTROL.get_center()
	var ui_screen := mapper.ui_to_screen(ui_point)
	var ui_round_trip := mapper.screen_to_ui(ui_screen)
	var world_ok := world_round_trip.distance_to(world_point) <= 0.01
	var camp_ok := CAMP_HOTSPOT.has_point(camp_round_trip)
	var ui_ok := UI_CONTROL.has_point(ui_round_trip)
	return {
		"ok": world_ok and camp_ok and ui_ok,
		"error": &"",
		"world": {
			"source": [world_point.x, world_point.y],
			"screen": [world_screen.x, world_screen.y],
			"round_trip": [world_round_trip.x, world_round_trip.y],
			"same_tile": world_ok,
		},
		"camp": {
			"source": [camp_point.x, camp_point.y],
			"screen": [camp_screen.x, camp_screen.y],
			"round_trip": [camp_round_trip.x, camp_round_trip.y],
			"same_hotspot": camp_ok,
		},
		"ui": {
			"source": [ui_point.x, ui_point.y],
			"screen": [ui_screen.x, ui_screen.y],
			"round_trip": [ui_round_trip.x, ui_round_trip.y],
			"same_control": ui_ok,
		},
	}


static func _first_reachable_combat_node_id(run: RunState) -> String:
	if run == null or run.map_state == null:
		return ""
	for node: MapNodeState in run.map_state.nodes:
		if (
			node.act_index == 1
			and node.layer_index == 0
			and node.node_kind in [
				MapNodeState.NodeKind.NORMAL,
				MapNodeState.NodeKind.ELITE,
				MapNodeState.NodeKind.BOSS,
			]
		):
			return node.node_id
	return ""


static func _accessibility_report(
	report: AccessibilityRuntimeReport
) -> Dictionary:
	if report == null:
		return {}
	return {
		"ok": report.ok,
		"error": report.error,
		"motion_effects_enabled": report.motion_effects_enabled,
		"flash_effects_enabled": report.flash_effects_enabled,
		"particle_effects_enabled": report.particle_effects_enabled,
		"damage_number_density": report.damage_number_density,
		"damage_event_budget": report.damage_event_budget,
		"visible_damage_samples": report.visible_damage_samples,
		"rule_information_visible": report.rule_information_visible,
		"cjk_ok": report.cjk_ok,
		"cjk_locale": report.cjk_locale,
		"cjk_font_source": report.cjk_font_source,
		"cjk_readable": report.cjk_readable,
		"cjk_missing_glyphs": report.cjk_missing_glyphs.duplicate(),
		"production_host": report.production_host,
	}


static func _app_error(result: AppActionResult) -> StringName:
	return (
		result.error.source_code
		if result != null and result.error != null
		else &"R14_APP_ACTION_FAILED"
	)


static func _run_error(result: RunPresentationResult) -> StringName:
	return (
		result.error.source_code
		if result != null and result.error != null
		else &"R14_RUN_INTENT_FAILED"
	)


static func _failure(error: StringName) -> Dictionary:
	return {
		"ok": false,
		"error": error,
	}
