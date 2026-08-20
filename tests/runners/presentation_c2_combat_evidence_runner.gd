extends SceneTree

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
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
const SHOP_CASES: Array[Dictionary] = [
	{"name": "720p-ui100", "size": Vector2i(1280, 720), "ui": 100},
	{"name": "1080p-ui100", "size": Vector2i(1920, 1080), "ui": 100},
	{"name": "1440p-ui100", "size": Vector2i(2560, 1440), "ui": 100},
]
const UI_REFERENCE_SIZE := Vector2i(1920, 1080)
const EVIDENCE_ROOT := "res://specs/ui-art-refresh/evidence"
const DEFAULT_OUTPUT_DIR := EVIDENCE_ROOT + "/c-2"

var _harness: Support.BootHarness
var _combat: RunCombatScreen
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output_dir := _output_directory().trim_suffix("/")
	if output_dir.is_empty():
		quit(3)
		return
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_dir)
	) != OK:
		quit(3)
		return
	_harness = Support.boot_runtime(self)
	await process_frame
	await process_frame
	if not _harness.root.is_booted():
		_issues.append("app_root_boot_failed:%s" % _harness.boot_error)
		await _finish(output_dir)
		return
	var driven := Support.drive_to_run_prepare(_harness)
	if not bool(driven.get("ok", false)):
		_issues.append("run_prepare_route_failed:%s" % driven.get("error", &""))
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in SHOP_CASES:
		await _capture_prepare_shop_case(output_dir, case)
	await _stage_prepare_world_unit()
	if not await _start_and_pause_combat():
		await _finish(output_dir)
		return
	if not _prime_committed_effect_window():
		await _finish(output_dir)
		return
	for case: Dictionary in CASES:
		await _capture_matrix_case(output_dir, case)
	for case: Dictionary in SHOP_CASES:
		await _capture_combat_shop_case(output_dir, case)
	await _capture_playback_sequence(output_dir)
	await _finish(output_dir)


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


func _start_and_pause_combat() -> bool:
	var prepare := Support.active_screen(_harness)
	if prepare == null or prepare.route_kind != &"RUN_PREPARE":
		_issues.append("prepare_start_screen_missing")
		return false
	var started := prepare.request_intent(RunPresentationIntent.new(
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
	))
	if not started.ok:
		_issues.append("combat_start_failed")
		return false
	await process_frame
	var active := Support.active_screen(_harness)
	_combat = (
		active.get_node_or_null(^"Composition") as RunCombatScreen
		if active != null
		else null
	)
	if active == null or active.route_kind != &"RUN_COMBAT" or _combat == null:
		_issues.append("combat_route_missing")
		return false
	var paused := _combat.set_playback_paused(true)
	if paused == null or not paused.ok:
		_issues.append("combat_initial_pause_failed")
		return false
	await process_frame
	await process_frame
	await process_frame
	if not _combat.world_board_ready():
		_issues.append("combat_world_board_not_ready")
		return false
	return true


func _prime_committed_effect_window() -> bool:
	var playback := _combat.try_playback()
	if (
		playback == null
		or not playback.ok
		or playback.state == null
		or playback.state.transcript_identity == null
	):
		_issues.append("combat_prime_identity_missing")
		return false
	var identity := playback.state.transcript_identity.deep_clone()
	for _index: int in 24:
		var window := _combat.drain_playback_window(identity, 8)
		if window == null or not window.ok or window.window == null:
			_issues.append("combat_prime_window_failed")
			return false
		var report := _combat.combat_effects_report()
		if (
			int(report.get("active_vfx", 0)) > 0
			and int(report.get("active_damage_labels", 0)) > 0
		):
			return true
		if window.window.exhausted:
			break
	_issues.append("combat_effect_window_not_observed")
	return false


func _capture_matrix_case(output_dir: String, case: Dictionary) -> void:
	if not await _apply_case(case):
		return
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != &"RUN_COMBAT":
		_issues.append("matrix_route_mismatch:%s" % case["name"])
		return
	var validation := _validate_combat(screen, String(case["name"]))
	var report := _save_viewport(
		"%s/run-combat-%s.png" % [output_dir, case["name"]],
		"matrix",
		case
	)
	report["validation"] = validation
	_reports.append(report)


func _capture_prepare_shop_case(output_dir: String, case: Dictionary) -> void:
	if not await _apply_case(case):
		return
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != &"RUN_PREPARE":
		_issues.append("prepare_shop_route_mismatch:%s" % case["name"])
		return
	var validation := _validate_shop_cards(screen, true, String(case["name"]))
	var report := _save_viewport(
		"%s/shop-prepare-%s.png" % [output_dir, case["name"]],
		"prepare-shop-revision",
		case
	)
	report["validation"] = validation
	_reports.append(report)


func _capture_combat_shop_case(output_dir: String, case: Dictionary) -> void:
	if not await _apply_case(case):
		return
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != &"RUN_COMBAT":
		_issues.append("combat_shop_route_mismatch:%s" % case["name"])
		return
	var validation := _validate_shop_cards(screen, false, String(case["name"]))
	var report := _save_viewport(
		"%s/shop-combat-%s.png" % [output_dir, case["name"]],
		"combat-shop-revision",
		case
	)
	report["validation"] = validation
	_reports.append(report)


func _capture_playback_sequence(output_dir: String) -> void:
	var case := {
		"name": "1080p-ui100",
		"size": Vector2i(1920, 1080),
		"ui": 100,
	}
	if not await _apply_case(case):
		return
	var states: Array[Dictionary] = [
		{"name": "pause", "paused": true, "speed": 1},
		{"name": "1x", "paused": false, "speed": 1},
		{"name": "2x", "paused": false, "speed": 2},
		{"name": "4x", "paused": false, "speed": 4},
	]
	var index := 0
	for state: Dictionary in states:
		index += 1
		var speed_result := _combat.set_playback_speed(int(state["speed"]))
		var pause_result := _combat.set_playback_paused(bool(state["paused"]))
		if (
			speed_result == null
			or not speed_result.ok
			or pause_result == null
			or not pause_result.ok
		):
			_issues.append("playback_state_apply_failed:%s" % state["name"])
			continue
		await process_frame
		var playback := _combat.try_playback()
		var path := "%s/playback-%s.png" % [output_dir, state["name"]]
		var report := _save_viewport(path, "playback-state", case)
		report["requested_state"] = state.duplicate(true)
		report["actual_paused"] = (
			playback.state.paused
			if playback != null and playback.ok and playback.state != null
			else null
		)
		report["actual_speed"] = (
			String(playback.state.speed)
			if playback != null and playback.ok and playback.state != null
			else ""
		)
		report["effects"] = _combat.combat_effects_report()
		_reports.append(report)
		var sequence_report := _save_viewport(
			"%s/battle-sequence-%02d-%s.png" % [
				output_dir,
				index,
				state["name"],
			],
			"battle-sequence",
			case
		)
		sequence_report["requested_state"] = state.duplicate(true)
		sequence_report["actual_paused"] = report["actual_paused"]
		sequence_report["actual_speed"] = report["actual_speed"]
		sequence_report["effects"] = report["effects"]
		sequence_report["sequence_index"] = index
		_reports.append(sequence_report)
		_combat.set_playback_paused(true)


func _apply_case(case: Dictionary) -> bool:
	_configure_window(case["size"])
	var settings := Support.candidate(int(case["ui"]), &"default")
	settings.locale = &"zh_TW"
	settings.damage_number_density = &"full"
	var applied := _harness.root.settings_application_port().apply(settings)
	if not applied.ok:
		_issues.append("settings_apply_failed:%s" % case["name"])
		return false
	# Applying UI scale rebuilds the route-local shell and remounts the world
	# surface over several deferred layout passes.  Capture only after that
	# mount has settled; route-local HUD replacement can remain visible beyond
	# the board remount at high UI scales, so evidence waits for the whole shell.
	for _settle_frame: int in 30:
		await process_frame
	var active := Support.active_screen(_harness)
	var current_combat := (
		active.get_node_or_null(^"Composition") as RunCombatScreen
		if active != null
		else null
	)
	if current_combat != null:
		_combat = current_combat
	return true


func _validate_combat(screen: ProductionScreen, case_name: String) -> Dictionary:
	var surfaces := get_nodes_in_group(ProductionWorldSurface.MOUNT_GROUP)
	var surface := (
		surfaces[0] as ProductionWorldSurface
		if surfaces.size() == 1 and surfaces[0] is ProductionWorldSurface
		else null
	)
	var board := surface.board_renderer() if surface != null else null
	var effects := _combat.combat_effects_report()
	var cue := screen.find_child("PlaybackStateCue", true, false) as Label
	var background_ok := (
		board != null
		and board.background_texture() != null
		and board.background_texture().resource_path
		== "res://assets/production/environment/run_combat.png"
	)
	var ok := (
		surface != null
		and board != null
		and board.visible
		and background_ok
		and int(effects.get("active_vfx", 0)) > 0
		and int(effects.get("active_damage_labels", 0)) > 0
		and cue != null
		and not cue.text.is_empty()
	)
	if not ok:
		_issues.append("combat_visual_validation_failed:%s" % case_name)
	return {
		"ok": ok,
		"surface_count": surfaces.size(),
		"board_visible": board.visible if board != null else false,
		"background_ok": background_ok,
		"playback_cue": cue.text if cue != null else "",
		"effects": effects,
	}


func _validate_shop_cards(
	screen: ProductionScreen,
	interactive: bool,
	case_name: String
) -> Dictionary:
	var pattern := "ShopCard*" if interactive else "CombatShopCardSlot*"
	var cards := screen.find_children(pattern, "Button", true, false)
	var populated := 0
	var clipped_labels: Array[String] = []
	var leaked_english: Array[String] = []
	var invalid_cards: Array[String] = []
	var first_card_geometry: Dictionary = {}
	for node: Node in cards:
		var card := node as Button
		if card == null or String(card.get_meta(&"shop_offer_id", "")).is_empty():
			continue
		populated += 1
		var portrait := card.get_node_or_null("CardContent/Portrait") as TextureRect
		var badges := card.get_node_or_null(
			"CardContent/ForegroundMargin/ForegroundLayout/TopInfo/TraitBadges"
		) as VBoxContainer
		var bottom := card.get_node_or_null(
			"CardContent/ForegroundMargin/ForegroundLayout/BottomInfo"
		) as HBoxContainer
		if first_card_geometry.is_empty():
			first_card_geometry = {
				"card": _control_rect_report(card),
				"foreground": _control_rect_report(card.get_node_or_null(
					"CardContent/ForegroundMargin/ForegroundLayout"
				) as Control),
				"badges": _control_rect_report(badges),
				"bottom": _control_rect_report(bottom),
			}
		if (
			portrait == null
			or portrait.texture == null
			or portrait.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED
			or badges == null
			or badges.get_child_count() < 1
			or badges.get_child_count() > ExpeditionLayoutMetrics.SHOP_CARD_TRAIT_BADGE_MAX
			or bottom == null
			or card.size.x + 0.5 < ExpeditionLayoutMetrics.SHOP_CARD_SIZE.x
			or card.size.y + 0.5 < ExpeditionLayoutMetrics.SHOP_CARD_SIZE.y
		):
			invalid_cards.append(card.name)
		for label_node: Node in card.find_children("*", "Label", true, false):
			var label := label_node as Label
			if label == null or label.text.is_empty():
				continue
			if label.name in [&"UnitName", &"TraitName"] and _label_is_clipped(label):
				clipped_labels.append("%s/%s" % [card.name, label.name])
			if (
				label.name == &"TraitName"
				and (label.text.contains("Frost") or label.text.contains("Marksman"))
			):
				leaked_english.append(label.text)
	var ok := (
		cards.size() == 5
		and populated == 5
		and invalid_cards.is_empty()
		and clipped_labels.is_empty()
		and leaked_english.is_empty()
	)
	if not ok:
		_issues.append("shop_card_validation_failed:%s:%s" % [
			"prepare" if interactive else "combat",
			case_name,
		])
	return {
		"ok": ok,
		"card_count": cards.size(),
		"populated_count": populated,
		"invalid_cards": invalid_cards,
		"clipped_labels": clipped_labels,
		"leaked_english": leaked_english,
		"first_card_geometry": first_card_geometry,
	}


func _control_rect_report(control: Control) -> Dictionary:
	if control == null:
		return {}
	var rect := control.get_global_rect()
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
		"visible": control.is_visible_in_tree(),
	}


func _label_is_clipped(label: Label) -> bool:
	var font := label.get_theme_font(&"font")
	if font == null:
		return false
	var required := font.get_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		label.get_theme_font_size(&"font_size")
	).x
	return required > label.size.x + 0.5


func _configure_window(size: Vector2i) -> void:
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_root().content_scale_size = UI_REFERENCE_SIZE
	get_root().size = size


func _save_viewport(
	path: String,
	kind: String,
	case: Dictionary
) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := get_root().get_texture().get_image()
	var error := image.save_png(absolute_path)
	var readback := Image.load_from_file(absolute_path)
	var report := {
		"ok": error == OK and readback != null and not readback.is_empty(),
		"kind": kind,
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
		_issues.append("screenshot_failed:%s:%s" % [kind, case["name"]])
	return report


func _output_directory() -> String:
	var requested := DEFAULT_OUTPUT_DIR
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			requested = argument.trim_prefix("--output-dir=")
			break
	var absolute := ProjectSettings.globalize_path(
		requested.replace("\\", "/")
	).simplify_path()
	var allowed := ProjectSettings.globalize_path(
		EVIDENCE_ROOT
	).simplify_path().trim_suffix("/") + "/"
	if not absolute.to_lower().begins_with(allowed.to_lower()):
		return ""
	return ProjectSettings.localize_path(absolute).replace("\\", "/")


func _finish(output_dir: String) -> void:
	var matrix_count := _reports.filter(func(report: Dictionary) -> bool:
		return String(report.get("kind", "")) == "matrix"
	).size()
	var playback_count := _reports.filter(func(report: Dictionary) -> bool:
		return String(report.get("kind", "")) == "playback-state"
	).size()
	var sequence_count := _reports.filter(func(report: Dictionary) -> bool:
		return String(report.get("kind", "")) == "battle-sequence"
	).size()
	var prepare_shop_count := _reports.filter(func(report: Dictionary) -> bool:
		return String(report.get("kind", "")) == "prepare-shop-revision"
	).size()
	var combat_shop_count := _reports.filter(func(report: Dictionary) -> bool:
		return String(report.get("kind", "")) == "combat-shop-revision"
	).size()
	var report := {
		"schema_version": "c-2-evidence-1",
		"ok": (
			_issues.is_empty()
			and matrix_count == CASES.size()
			and playback_count == 4
			and sequence_count == 4
			and prepare_shop_count == SHOP_CASES.size()
			and combat_shop_count == SHOP_CASES.size()
		),
		"exit_code": 0 if _issues.is_empty() else 2,
		"expected_matrix_count": CASES.size(),
		"matrix_count": matrix_count,
		"expected_playback_state_count": 4,
		"playback_state_count": playback_count,
		"battle_sequence_count": sequence_count,
		"expected_prepare_shop_count": SHOP_CASES.size(),
		"prepare_shop_count": prepare_shop_count,
		"expected_combat_shop_count": SHOP_CASES.size(),
		"combat_shop_count": combat_shop_count,
		"screenshots": _reports,
		"issues": _issues,
	}
	var file := FileAccess.open(
		"%s/evidence-report.json" % output_dir,
		FileAccess.WRITE
	)
	if file == null:
		quit(3)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print(JSON.stringify(report))
	if _harness != null:
		_harness.dispose()
	quit(0 if bool(report["ok"]) else 2)
