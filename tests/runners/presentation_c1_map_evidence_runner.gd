extends SceneTree

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)
const ProductionCaseDriver = preload(
	"res://application/balance/balance_production_case_driver.gd"
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
const EVIDENCE_ROOT := "res://specs/ui-art-refresh/evidence"
const DEFAULT_OUTPUT_DIR := EVIDENCE_ROOT + "/c-1"

var _harness: Support.BootHarness
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []
var _source_summary: Dictionary = {}


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
	var storage := await _build_two_layer_production_save()
	if storage == null:
		await _finish(output_dir)
		return
	_harness = Support.boot_runtime(self, storage)
	await process_frame
	await process_frame
	if not _harness.root.is_booted():
		_issues.append("app_root_boot_failed:%s" % _harness.boot_error)
		await _finish(output_dir)
		return
	var continued := _harness.root.continue_active_run()
	if not continued.ok:
		_issues.append("continue_active_run_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	await process_frame
	for case: Dictionary in CASES:
		await _capture_matrix_case(output_dir, case)
	await _capture_interaction_sequence(output_dir)
	await _finish(output_dir)


func _build_two_layer_production_save() -> FakeSaveStorage:
	var registry := ContentRegistryService.new()
	root.add_child(registry)
	var content := ProjectContentBootstrap.new().run(registry)
	if not content.ok:
		_issues.append("content_bootstrap_failed:%s" % content.error_code)
		return null
	var storage := FakeSaveStorage.new()
	var driver: BalanceProductionCaseDriver = ProductionCaseDriver.new(
		content,
		func() -> SaveStoragePort: return storage
	)
	driver.diagnostic_node_limit = 2
	var walked := driver.run_case(BalanceBotStrategy.TEMPO, 0)
	var repository := SaveRepository.new(
		storage,
		ContentRegistryReceiptAdapter.new(content.registry),
		ContentRegistryMigrationAdapter.new(content.registry),
		RunStateValidator.new()
	)
	var loaded := repository.load()
	if (
		walked == null
		or not loaded.ok
		or loaded.run == null
		or loaded.run.map_state == null
		or loaded.run.map_state.completed_node_ids.size() != 2
	):
		_issues.append("two_layer_production_save_failed")
		return null
	_source_summary = {
		"source": "BalanceProductionCaseDriver + production content",
		"strategy": "TEMPO",
		"seed": 0,
		"diagnostic_node_limit": 2,
		"completed_node_ids": loaded.run.map_state.completed_node_ids,
		"run_phase": loaded.run.run_phase,
	}
	root.remove_child(registry)
	registry.free()
	return storage


func _capture_matrix_case(output_dir: String, case: Dictionary) -> void:
	if not await _apply_case(case):
		return
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != &"RUN_MAP":
		_issues.append("route_mismatch:%s" % case["name"])
		return
	var validation := _validate_map(screen, String(case["name"]))
	var path := "%s/run-map-%s.png" % [output_dir, case["name"]]
	var report := _save_viewport(path, "matrix", case)
	report["validation"] = validation
	_reports.append(report)


func _capture_interaction_sequence(output_dir: String) -> void:
	var case := {
		"name": "1080p-ui100",
		"size": Vector2i(1920, 1080),
		"ui": 100,
	}
	if not await _apply_case(case):
		return
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != &"RUN_MAP":
		_issues.append("interaction_initial_route_missing")
		return
	_reports.append(_save_viewport(
		"%s/interaction-01-initial.png" % output_dir,
		"interaction-initial",
		case
	))
	var graph := screen.find_child(
		"RunMapNodeGraph", true, false
	) as RunMapNodeGraph
	if graph == null:
		_issues.append("interaction_graph_missing")
		return
	var original_id := graph.selected_node_id()
	var alternate_id := ""
	for node_id: String in graph.node_ids_in_layout_order():
		var button := graph.node_button(node_id)
		if button != null and not button.disabled and node_id != original_id:
			alternate_id = node_id
			break
	if alternate_id.is_empty():
		_issues.append("interaction_alternate_frontier_missing")
		return
	graph.node_button(alternate_id).pressed.emit()
	await process_frame
	await process_frame
	if graph.selected_node_id() != alternate_id:
		_issues.append("interaction_graph_selection_not_applied")
		return
	_reports.append(_save_viewport(
		"%s/interaction-02-selected.png" % output_dir,
		"interaction-selected",
		case
	))
	var confirm := _action_button(screen, &"map.confirm")
	if confirm == null or confirm.disabled:
		_issues.append("interaction_confirm_unavailable")
		return
	confirm.pressed.emit()
	var next_route := await _wait_for_next_route(120)
	if next_route.is_empty():
		_issues.append("interaction_next_route_not_reached")
		return
	var final_report := _save_viewport(
		"%s/interaction-03-confirmed-next-route.png" % output_dir,
		"interaction-confirmed",
		case
	)
	final_report["selected_node_id"] = alternate_id
	final_report["next_route"] = String(next_route)
	_reports.append(final_report)


func _apply_case(case: Dictionary) -> bool:
	_configure_window(case["size"])
	var settings := Support.candidate(int(case["ui"]), &"default")
	settings.locale = &"zh_TW"
	var applied := _harness.root.settings_application_port().apply(settings)
	if not applied.ok:
		_issues.append("settings_apply_failed:%s" % case["name"])
		return false
	await process_frame
	await process_frame
	await process_frame
	return true


func _validate_map(screen: ProductionScreen, case_name: String) -> Dictionary:
	var graph := screen.find_child(
		"RunMapNodeGraph", true, false
	) as RunMapNodeGraph
	var selector := screen.find_child("NodeSelector", true, false) as ItemList
	var background := screen.find_child(
		"RunMapEnvironmentTexture", true, false
	) as TextureRect
	if graph == null:
		_issues.append("graph_missing:%s" % case_name)
		return {}
	if selector == null:
		_issues.append("selector_missing:%s" % case_name)
	if background == null or background.texture == null:
		_issues.append("background_missing:%s" % case_name)
	var state_counts := {
		"completed": 0,
		"reachable": 0,
		"unreachable": 0,
	}
	var edge_weight_counts := {
		"background": 0,
		"traversed": 0,
		"frontier": 0,
	}
	for segment: Dictionary in graph.edge_segments():
		var weight := String(segment.get("weight", ""))
		edge_weight_counts[weight] = int(edge_weight_counts.get(weight, 0)) + 1
	for weight: String in ["background", "traversed", "frontier"]:
		if int(edge_weight_counts[weight]) <= 0:
			_issues.append("edge_weight_missing:%s:%s" % [case_name, weight])
	var node_ids := graph.node_ids_in_layout_order()
	for node_id: String in node_ids:
		var state := String(graph.state_for(node_id))
		state_counts[state] = int(state_counts.get(state, 0)) + 1
		var button := graph.node_button(node_id)
		if button == null or not graph.get_global_rect().encloses(
			button.get_global_rect()
		):
			_issues.append("node_out_of_bounds:%s:%s:%s-%s-%s:%s:%s" % [
				case_name,
				node_id,
				button.get_meta(&"act_index", -1) if button != null else -1,
				button.get_meta(&"layer_index", -1) if button != null else -1,
				button.get_meta(&"slot_index", -1) if button != null else -1,
				button.get_global_rect() if button != null else Rect2(),
				graph.get_global_rect(),
			])
	for state_name: String in ["completed", "reachable", "unreachable"]:
		if int(state_counts[state_name]) <= 0:
			_issues.append("state_missing:%s:%s" % [case_name, state_name])
	var current_markers := graph.find_children("Current_*", "Label", true, false)
	if current_markers.size() != 1:
		_issues.append("current_marker_count:%s:%d" % [
			case_name, current_markers.size(),
		])
	var act_labels := graph.find_children("ActLabel*", "Label", true, false)
	if act_labels.size() != 3:
		_issues.append("act_label_count:%s:%d" % [case_name, act_labels.size()])
	else:
		var expected_titles: Array[String] = ["第一幕", "第二幕", "第三幕"]
		for index: int in expected_titles.size():
			if (act_labels[index] as Label).text != expected_titles[index]:
				_issues.append("act_label_text:%s:%d:%s" % [
					case_name, index, (act_labels[index] as Label).text,
				])
	if selector != null and selector.item_count != node_ids.size():
		_issues.append("accessibility_row_count:%s" % case_name)
	var graph_rect := graph.get_global_rect()
	var center_rect := screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_CENTER
	)
	if not center_rect.encloses(graph_rect):
		_issues.append("graph_out_of_center:%s:%s:%s" % [
			case_name, graph_rect, center_rect,
		])
	return {
		"node_count": node_ids.size(),
		"edge_count": graph.edge_segments().size(),
		"edge_weight_counts": edge_weight_counts,
		"state_counts": state_counts,
		"current_marker_count": current_markers.size(),
		"act_label_count": act_labels.size(),
		"accessibility_row_count": selector.item_count if selector != null else 0,
		"background_visual_id": (
			String(background.get_meta(&"visual_id", &""))
			if background != null else ""
		),
	}


func _action_button(
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


func _wait_for_next_route(max_frames: int) -> StringName:
	for _index: int in max_frames:
		await process_frame
		var screen := Support.active_screen(_harness)
		if screen != null and screen.route_kind != &"RUN_MAP":
			return screen.route_kind
	return &""


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
	var interaction_count := _reports.filter(func(report: Dictionary) -> bool:
		return String(report.get("kind", "")).begins_with("interaction-")
	).size()
	var report := {
		"schema_version": "c-1-evidence-1",
		"ok": (
			_issues.is_empty()
			and matrix_count == CASES.size()
			and interaction_count == 3
		),
		"exit_code": 0 if _issues.is_empty() else 2,
		"expected_matrix_count": CASES.size(),
		"matrix_count": matrix_count,
		"expected_interaction_count": 3,
		"interaction_count": interaction_count,
		"production_source": _source_summary,
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
