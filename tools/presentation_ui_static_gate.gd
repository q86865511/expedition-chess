class_name PresentationUiStaticGate
extends RefCounted

## Deterministic production-only static checks for the G2 presentation-ui slice.
##
## `validate_candidate` is the pure contract used by the T14 tests.
## `validate_project` builds the same candidate from a checked-out Godot project.

const PRODUCTION_ROOTS: Array[String] = [
	"res://app/",
	"res://presentation/",
	"res://scenes/production/",
	"res://services/settings/",
]
const IGNORED_ROOTS: Array[String] = [
	"res://.godot/",
	"res://.pipeline/",
	"res://scripts/dev/",
	"res://scenes/dev/",
	"res://tests/",
]
const SOURCE_EXTENSIONS: Array[String] = [
	".gd",
	".tscn",
	".tres",
	".json",
	".cfg",
]
const APP_ROOT_PATH := "res://app/app_root.gd"
const COMBAT_LAB_SCENE_PATH := "res://scenes/dev/combat_lab/combat_lab.tscn"
const ASSET_REFERENCE_PREFIX := "res://assets/"
const LAYOUT_METRICS_SETTER_PATH := \
	"res://presentation/theme/expedition_layout_metrics.gd"
const CUSTOM_MINIMUM_SIZE_TOKEN := "custom_minimum_size"

const DEV_REFERENCE := &"PUI_DEV_REFERENCE"
const HARDCODED_PLAYER_TEXT := &"PUI_HARDCODED_PLAYER_TEXT"
const LOCALIZATION_KEY_PARITY := &"PUI_LOCALIZATION_KEY_PARITY"
const LOCALIZATION_REFERENCE_MISSING := &"PUI_LOCALIZATION_REFERENCE_MISSING"
const ASSET_REFERENCE_MISSING := &"PUI_ASSET_REFERENCE_MISSING"
const FOCUS_GRAPH_INVALID := &"PUI_FOCUS_GRAPH_INVALID"
const VIEWPORT_POLICY_INVALID := &"PUI_VIEWPORT_POLICY_INVALID"
const FILTER_POLICY_INVALID := &"PUI_FILTER_POLICY_INVALID"
const THEME_TOKEN_INVALID := &"PUI_THEME_TOKEN_INVALID"
const LAYOUT_METRIC_ASSIGNMENT := &"PUI_LAYOUT_METRIC_ASSIGNMENT"
const UI_TUNE_DUPLICATE := &"PUI_UI_TUNE_DUPLICATE"
const SCREEN_WRITER_DEPENDENCY := &"PUI_SCREEN_WRITER_DEPENDENCY"
const ACCESSIBILITY_BINDING_INVALID := &"PUI_ACCESSIBILITY_BINDING_INVALID"
const REQUIRED_ACCESSIBILITY_SCENES: Array[String] = [
	"res://scenes/production/run_combat.tscn",
]
const REQUIRED_ACCESSIBILITY_CAPABILITIES: Array[String] = [
	"motion",
	"flash",
	"particles",
	"density",
	"tooltip",
	"cjk",
]


func validate_candidate(candidate: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	var sources := _production_sources(candidate)
	_validate_source_dependencies(sources, issues)
	_validate_layout_metric_assignments(sources, issues)
	var localization_reference_count := _validate_localization(
		candidate,
		sources,
		issues
	)
	_validate_asset_references(candidate, sources, issues)
	_validate_focus_graphs(candidate, issues)
	_validate_system_menu_contract(candidate, issues)
	_validate_render_policy(candidate, issues)
	_validate_theme_policy(candidate, issues)
	var accessibility_binding_count := _validate_accessibility_bindings(
		candidate,
		sources,
		issues
	)
	_validate_ui_tune(candidate, sources, issues)
	_validate_screen_writer_boundaries(sources, issues)
	issues.sort_custom(_issue_less)
	return {
		"ok": issues.is_empty(),
		"exit_code": 0 if issues.is_empty() else 1,
		"issues": issues,
		"accessibility_binding_count": accessibility_binding_count,
		"localization_reference_count": localization_reference_count,
	}


func validate_project(root_path: String = "res://") -> Dictionary:
	var candidate := {
		"production_roots": PRODUCTION_ROOTS.duplicate(),
		"ignored_roots": IGNORED_ROOTS.duplicate(),
		"sources": _collect_project_sources(root_path),
		"asset_paths": _collect_asset_paths(root_path),
		"localization": _collect_localization(root_path),
		"focus_graphs": _collect_focus_graphs(root_path),
		"system_menu_contract": _collect_system_menu_contract(root_path),
		"render_policy": _collect_render_policy(root_path),
		"theme_policy": _collect_theme_policy(root_path),
		"accessibility_bindings": _collect_accessibility_bindings(
			root_path
		),
		"ui_tune": {
			"forbidden_literal": "12",
			"forbidden_declaration_markers": PackedStringArray([
				"MAX_PARTY",
				"PARTY_LIMIT",
				"MAX_DEPLOY",
			]),
			"authoritative_member": "snapshot.party_limit",
		},
	}
	return validate_candidate(candidate)


func validate_localization_project(root_path: String = "res://") -> Dictionary:
	var issues: Array[Dictionary] = []
	var candidate := {"localization": _collect_localization(root_path)}
	var reference_count := _validate_localization(
		candidate,
		_production_sources({
			"production_roots": PRODUCTION_ROOTS.duplicate(),
			"ignored_roots": IGNORED_ROOTS.duplicate(),
			"sources": _collect_project_sources(root_path),
		}),
		issues
	)
	issues.sort_custom(_issue_less)
	return {
		"ok": issues.is_empty(),
		"exit_code": 0 if issues.is_empty() else 1,
		"issues": issues,
		"localization_reference_count": reference_count,
	}


func _production_sources(candidate: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var roots := _string_values(candidate.get("production_roots", PackedStringArray()))
	var ignored := _string_values(candidate.get("ignored_roots", PackedStringArray()))
	var source_value: Variant = candidate.get("sources", {})
	if not source_value is Dictionary:
		return result
	var paths: Array[String] = []
	for path_value: Variant in (source_value as Dictionary).keys():
		paths.append(String(path_value).replace("\\", "/"))
	paths.sort()
	for path: String in paths:
		if not _starts_with_any(path, roots) or _starts_with_any(path, ignored):
			continue
		result[path] = String((source_value as Dictionary).get(path, ""))
	return result


func _validate_source_dependencies(
	sources: Dictionary,
	issues: Array[Dictionary]
) -> void:
	for path: String in _sorted_keys(sources):
		var source := String(sources[path])
		var dependency_source := source
		if path == APP_ROOT_PATH and source.contains("--combat-lab"):
			dependency_source = dependency_source.replace(COMBAT_LAB_SCENE_PATH, "")
		if (
			dependency_source.contains("res://scripts/dev/")
			or dependency_source.contains("res://scenes/dev/")
		):
			_append_issue(
				issues,
				DEV_REFERENCE,
				path,
				"production source references a non-allowlisted dev path"
			)
		if _path_holds_localization_values(path):
			continue
		if (
			_contains_cjk_string_literal(source)
			or (
				path.ends_with(".gd")
				and _contains_visible_gd_text(source)
			)
			or (
				path.ends_with(".tscn")
				and _contains_visible_scene_text(source)
			)
		):
			_append_issue(
				issues,
				HARDCODED_PLAYER_TEXT,
				path,
				"production source contains hardcoded player-visible text"
			)


func _validate_layout_metric_assignments(
	sources: Dictionary,
	issues: Array[Dictionary]
) -> void:
	for path: String in _sorted_keys(sources):
		if (
			not path.begins_with("res://presentation/")
			or not path.ends_with(".gd")
			or path == LAYOUT_METRICS_SETTER_PATH
		):
			continue
		if _has_direct_custom_minimum_size_assignment(String(sources[path])):
			_append_issue(
				issues,
				LAYOUT_METRIC_ASSIGNMENT,
				path,
				"custom_minimum_size must be assigned through ExpeditionLayoutMetrics"
			)


func _validate_localization(
	candidate: Dictionary,
	sources: Dictionary,
	issues: Array[Dictionary]
) -> int:
	var value: Variant = candidate.get("localization", {})
	if not value is Dictionary:
		_append_issue(
			issues,
			LOCALIZATION_KEY_PARITY,
			"localization",
			"localization catalog is missing"
		)
		return 0
	var localization := value as Dictionary
	var zh_value: Variant = localization.get("zh_TW")
	var en_value: Variant = localization.get("en")
	if not zh_value is Dictionary or not en_value is Dictionary:
		_append_issue(
			issues,
			LOCALIZATION_KEY_PARITY,
			"localization",
			"zh_TW and en catalogs are required"
		)
		return 0
	var zh := zh_value as Dictionary
	var en := en_value as Dictionary
	var zh_keys := _variant_keys(zh)
	var en_keys := _variant_keys(en)
	if (
		zh_keys.is_empty()
		or zh_keys != en_keys
		or _has_empty_value(zh)
		or _has_empty_value(en)
	):
		_append_issue(
			issues,
			LOCALIZATION_KEY_PARITY,
			"localization/zh_TW|en",
			"locale key sets differ or contain an empty player-visible value"
		)
		return 0
	return _validate_localization_references(zh, en, sources, issues)


func _validate_localization_references(
	zh: Dictionary,
	en: Dictionary,
	sources: Dictionary,
	issues: Array[Dictionary]
) -> int:
	var references: Dictionary = {}
	for path: String in _sorted_keys(sources):
		if _path_holds_localization_values(path):
			continue
		var source := String(sources[path])
		for key: String in _localization_reference_literals(path, source, zh):
			var reference_id := "%s|%s" % [path, key]
			if references.has(reference_id):
				continue
			references[reference_id] = true
			if zh.has(key) and en.has(key):
				continue
			_append_issue(
				issues,
				LOCALIZATION_REFERENCE_MISSING,
				path,
				"referenced localization key is missing: %s" % key
			)
	return references.size()


func _localization_reference_literals(
	path: String,
	source: String,
	catalog: Dictionary
) -> Array[String]:
	var references: Dictionary = {}
	var recent_lines: Array[String] = []
	for line_value: Variant in source.split("\n"):
		var line := String(line_value)
		recent_lines.append(line)
		if recent_lines.size() > 3:
			recent_lines.pop_front()
		var context := "\n".join(recent_lines)
		for literal: String in _gdscript_string_literals(line):
			if not _looks_like_localization_key(literal):
				continue
			if catalog.has(literal) or _is_explicit_localization_context(
				path,
				context,
				literal
			):
				references[literal] = true
	return _sorted_keys(references)


func _gdscript_string_literals(line: String) -> Array[String]:
	var literals: Array[String] = []
	var index := 0
	while index < line.length():
		if line[index] == "#":
			break
		if line[index] != "\"":
			index += 1
			continue
		index += 1
		var literal := ""
		var escaped := false
		while index < line.length():
			var character := line[index]
			if escaped:
				literal += character
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				literals.append(literal)
				index += 1
				break
			else:
				literal += character
			index += 1
	return literals


func _looks_like_localization_key(value: String) -> bool:
	if (
		value.is_empty()
		or value.contains("%")
		or not value.contains(".")
		or value.begins_with(".")
		or value.ends_with(".")
	):
		return false
	for segment: String in value.split("."):
		if segment.is_empty():
			return false
	for character: String in value:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character in ["_", ".", "-"]
		):
			return false
	return true


func _is_explicit_localization_context(
	path: String,
	context: String,
	key: String
) -> bool:
	if (
		path == "res://presentation/common/presentation_error_mapper.gd"
		and key.begins_with("error.")
	):
		return true
	var current_line := context.get_slice(
		"\n",
		context.get_slice_count("\n") - 1
	)
	if current_line.contains("\"text_key\": &\""):
		return true
	for marker: String in [
		"_text(&\"",
		"_content(&\"",
		"resolve_text(&\"",
		"_localized_ui_text(&\"",
		"_localized_content_text(&\"",
		"localized_ui_text(&\"",
		"localized_content_text(&\"",
	]:
		if context.contains(marker):
			return true
	return false


func _validate_asset_references(
	candidate: Dictionary,
	sources: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var available: Dictionary = {}
	for path: String in _string_values(
		candidate.get("asset_paths", PackedStringArray())
	):
		available[path.replace("\\", "/")] = true
	for path: String in _sorted_keys(sources):
		for reference: String in _asset_references(String(sources[path])):
			if not available.has(reference):
				_append_issue(
					issues,
					ASSET_REFERENCE_MISSING,
					path,
					"referenced asset is missing: %s" % reference
				)


func _validate_focus_graphs(
	candidate: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var graphs_value: Variant = candidate.get("focus_graphs", [])
	if not graphs_value is Array or (graphs_value as Array).is_empty():
		_append_issue(
			issues,
			FOCUS_GRAPH_INVALID,
			"presentation/accessibility/focus_graphs",
			"no production focus graph was supplied"
		)
		return
	for graph_value: Variant in graphs_value:
		if not graph_value is Dictionary:
			_append_issue(
				issues,
				FOCUS_GRAPH_INVALID,
				"presentation/accessibility/focus_graphs",
				"focus graph entry is not a Dictionary"
			)
			continue
		var graph := graph_value as Dictionary
		var graph_id := String(graph.get("graph_id", "unnamed"))
		var graph_path := "presentation/accessibility/focus/%s" % graph_id
		var nodes := _string_values(graph.get("nodes", PackedStringArray()))
		var required := _string_values(
			graph.get("required_actions", PackedStringArray())
		)
		var edges_value: Variant = graph.get("edges", {})
		if (
			nodes.is_empty()
			or required.is_empty()
			or not edges_value is Dictionary
		):
			_append_issue(
				issues,
				FOCUS_GRAPH_INVALID,
				graph_path,
				"focus graph requires nodes, edges, and required actions"
			)
			continue
		var node_set: Dictionary = {}
		for node: String in nodes:
			node_set[node] = true
		var edges := edges_value as Dictionary
		var invalid_edge := false
		for from_value: Variant in edges.keys():
			var from := String(from_value)
			if not node_set.has(from):
				invalid_edge = true
				break
			for target: String in _string_values(edges[from_value]):
				if not node_set.has(target):
					invalid_edge = true
					break
		var reachable := _reachable_nodes(nodes[0], edges)
		var missing_required := false
		for action: String in required:
			if not node_set.has(action) or not reachable.has(action):
				missing_required = true
				break
		if invalid_edge or missing_required:
			_append_issue(
				issues,
				FOCUS_GRAPH_INVALID,
				graph_path,
				"required action is missing/unreachable or an edge targets an unknown node"
			)


func _validate_system_menu_contract(
	candidate: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var value: Variant = candidate.get("system_menu_contract", {})
	var contract: Dictionary = value if value is Dictionary else {}
	for required: String in [
		"custom_input_action",
		"stable_button",
		"ordered_focus",
		"five_states",
		"focus_trap",
		"no_resident_run_menu",
	]:
		if bool(contract.get(required, false)):
			continue
		_append_issue(
			issues,
			FOCUS_GRAPH_INVALID,
			"presentation/screens/system_menu_overlay.gd",
			"system menu is missing required input/focus contract: %s" % required
		)


func _validate_render_policy(
	candidate: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var value: Variant = candidate.get("render_policy", {})
	var path := "presentation/viewport/world_viewport_policy.gd"
	if not value is Dictionary:
		_append_issue(
			issues,
			VIEWPORT_POLICY_INVALID,
			path,
			"render policy is missing"
		)
		return
	var policy := value as Dictionary
	if (
		policy.get("world_size") != Vector2i(640, 360)
		or policy.get("ui_reference_size") != Vector2i(1920, 1080)
		or not bool(policy.get("integer_scale", false))
		or not bool(policy.get("letterbox", false))
	):
		_append_issue(
			issues,
			VIEWPORT_POLICY_INVALID,
			path,
			"world/UI sizes, integer scaling, or letterbox contract is invalid"
		)
	if (
		String(policy.get("world_texture_filter", "")).to_lower() != "nearest"
		or not bool(policy.get("pixel_snap", false))
	):
		_append_issue(
			issues,
			FILTER_POLICY_INVALID,
			path,
			"world rendering must use nearest filtering with pixel snap"
		)


func _validate_theme_policy(
	candidate: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var value: Variant = candidate.get("theme_policy", {})
	var path := "presentation/accessibility/theme_policy"
	if not value is Dictionary:
		_append_issue(issues, THEME_TOKEN_INVALID, path, "theme policy is missing")
		return
	var policy := value as Dictionary
	var scale_values: Array[float] = []
	var scales: Variant = policy.get("ui_scale_tokens", PackedFloat32Array())
	if scales is Array or scales is PackedFloat32Array:
		for scale_value: Variant in scales:
			scale_values.append(float(scale_value))
	var scales_valid := scale_values.size() == 3
	if scales_valid:
		scales_valid = (
			is_equal_approx(scale_values[0], 1.0)
			and is_equal_approx(scale_values[1], 1.25)
			and is_equal_approx(scale_values[2], 1.5)
		)
	var modes := _string_values(
		policy.get("color_modes", PackedStringArray())
	)
	var mode_set: Dictionary = {}
	for mode: String in modes:
		mode_set[mode] = true
	var modes_valid := (
		mode_set.size() == 4
		and (
			mode_set.has("standard")
			or mode_set.has("default")
		)
		and mode_set.has("protanopia")
		and mode_set.has("deuteranopia")
		and mode_set.has("tritanopia")
	)
	if (
		not scales_valid
		or not modes_valid
		or not bool(policy.get("non_color_cues", false))
		or String(policy.get("focus_token", "")).is_empty()
		or int(policy.get("tooltip_max_depth", -1)) != 2
		or String(policy.get("cjk_font_token", "")).is_empty()
	):
		_append_issue(
			issues,
			THEME_TOKEN_INVALID,
			path,
			"required UI scales, color modes, focus, tooltip, CJK, or non-color tokens are invalid"
		)


func _validate_ui_tune(
	candidate: Dictionary,
	sources: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var value: Variant = candidate.get("ui_tune", {})
	if not value is Dictionary:
		return
	var tune := value as Dictionary
	var forbidden_literal := String(tune.get("forbidden_literal", ""))
	var authoritative_member := String(tune.get("authoritative_member", ""))
	var markers := _string_values(
		tune.get("forbidden_declaration_markers", PackedStringArray())
	)
	if forbidden_literal.is_empty() or markers.is_empty():
		return
	for path: String in _sorted_keys(sources):
		var source := String(sources[path])
		for line_value: Variant in source.split("\n"):
			var line := String(line_value)
			if (
				not authoritative_member.is_empty()
				and line.contains(authoritative_member)
			):
				continue
			var declaration := line.strip_edges()
			if (
				not declaration.begins_with("const ")
				and not declaration.begins_with("var ")
				and not declaration.begins_with("@export")
			):
				continue
			if not _contains_integer_token(line, forbidden_literal):
				continue
			for marker: String in markers:
				if line.to_upper().contains(marker.to_upper()):
					_append_issue(
						issues,
						UI_TUNE_DUPLICATE,
						path,
						"UI declares forbidden gameplay tune %s=%s" % [
							marker,
							forbidden_literal,
						]
					)
					break


func _validate_accessibility_bindings(
	candidate: Dictionary,
	sources: Dictionary,
	issues: Array[Dictionary]
) -> int:
	# Candidate fixtures created before R13 remain backwards compatible.
	# validate_project always supplies this field, so the production gate cannot
	# bypass the contract.
	if not candidate.has("accessibility_bindings"):
		return 0
	var value: Variant = candidate.get("accessibility_bindings")
	if not value is Array:
		_append_issue(
			issues,
			ACCESSIBILITY_BINDING_INVALID,
			"presentation/accessibility/production_bindings",
			"production accessibility binding list is missing"
		)
		return 0
	var bindings := value as Array
	var valid_count := 0
	for required_scene: String in REQUIRED_ACCESSIBILITY_SCENES:
		var matching: Array[Dictionary] = []
		for entry: Variant in bindings:
			if entry is Dictionary \
				and String(entry.get("scene_path", "")) == required_scene:
				matching.append(entry as Dictionary)
		if matching.size() != 1:
			_append_issue(
				issues,
				ACCESSIBILITY_BINDING_INVALID,
				required_scene,
				"required production scene must declare exactly one binding"
			)
			continue
		var binding := matching[0]
		var capabilities := _string_values(
			binding.get("capabilities", PackedStringArray())
		)
		var capability_set: Dictionary = {}
		for capability: String in capabilities:
			capability_set[capability] = true
		var complete := (
			String(binding.get("host_path", "")).is_empty() == false
			and String(binding.get("consumer", ""))
				== "PresentationSettingsRuntimeConsumer"
			and capability_set.size()
				== REQUIRED_ACCESSIBILITY_CAPABILITIES.size()
		)
		for capability: String in REQUIRED_ACCESSIBILITY_CAPABILITIES:
			complete = complete and capability_set.has(capability)
		var scene_source := String(sources.get(required_scene, ""))
		complete = complete \
			and scene_source.contains(
				String(binding.get("host_path", ""))
			) \
			and scene_source.contains(
				"production_accessibility_host.gd"
			)
		if not complete:
			_append_issue(
				issues,
				ACCESSIBILITY_BINDING_INVALID,
				required_scene,
				"binding host, consumer, scene script, or capabilities are incomplete"
			)
			continue
		valid_count += 1
	return valid_count


func _validate_screen_writer_boundaries(
	sources: Dictionary,
	issues: Array[Dictionary]
) -> void:
	# 掃描範圍限定 screens 與 production scenes 是刻意豁免：
	# presentation/run 與 presentation/viewmodels 是 HANDOFF.md §2 授權的
	# writer 通道（session/viewmodel 持 RunController 轉發 command 屬合法設計），
	# 納入掃描會誤殺正確架構。另本規則為字串比對，僅防低級誤用，
	# 不防刻意繞過（改名/動態載入）；深層防線是 reviewer 與整合測試。
	for path: String in _sorted_keys(sources):
		if (
			not path.begins_with("res://presentation/screens/")
			and not path.begins_with("res://scenes/production/")
		):
			continue
		if _is_screen_writer_boundary_infrastructure(path):
			continue
		var source := String(sources[path])
		var has_writer_type := (
			source.contains("SaveRepository")
			or source.contains("SettingsRepository")
			or source.contains("RunController")
			or source.contains("RunPresentationSession")
			or source.contains("RunCommandFactory")
			or source.contains("ApplicationRoot")
			or source.contains("CampController")
		)
		var has_autoload_writer := (
			source.contains("get_node(\"/root/")
			or source.contains("get_node('/root/")
		) and (
			source.contains(".save(")
			or source.contains(".dispatch(")
			or source.contains(".clear(")
			or source.contains(".archive(")
		)
		if has_writer_type or has_autoload_writer:
			_append_issue(
				issues,
				SCREEN_WRITER_DEPENDENCY,
				path,
				"production screen directly depends on a canonical writer"
			)


func _is_screen_writer_boundary_infrastructure(path: String) -> bool:
	return path in [
		"res://presentation/screens/live_screen_intent_port.gd",
		"res://presentation/screens/live_screen_playback_port.gd",
		"res://presentation/screens/presentation_route_coordinator.gd",
	]


func _collect_project_sources(root_path: String) -> Dictionary:
	var result: Dictionary = {}
	for root: String in PRODUCTION_ROOTS:
		var relative := root.trim_prefix("res://")
		_collect_source_tree(
			_project_path(root_path, relative),
			"res://" + relative,
			result
		)
	return result


func _collect_source_tree(
	disk_path: String,
	resource_path: String,
	result: Dictionary
) -> void:
	var directory := DirAccess.open(disk_path)
	if directory == null:
		return
	var directories: Array[String] = []
	var files: Array[String] = []
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if not entry.begins_with("."):
				directories.append(entry)
		elif _has_source_extension(entry):
			files.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	directories.sort()
	files.sort()
	for file_name: String in files:
		var source_path := _join_path(disk_path, file_name)
		var canonical_path := _join_path(resource_path, file_name)
		result[canonical_path] = FileAccess.get_file_as_string(source_path)
	for directory_name: String in directories:
		_collect_source_tree(
			_join_path(disk_path, directory_name),
			_join_path(resource_path, directory_name),
			result
		)


func _collect_asset_paths(root_path: String) -> PackedStringArray:
	var collected: Dictionary = {}
	_collect_all_files(
		_project_path(root_path, "assets/"),
		"res://assets/",
		collected
	)
	var paths := PackedStringArray()
	for path: String in _sorted_keys(collected):
		if not path.ends_with(".import"):
			paths.append(path)
	return paths


func _collect_all_files(
	disk_path: String,
	resource_path: String,
	result: Dictionary
) -> void:
	var directory := DirAccess.open(disk_path)
	if directory == null:
		return
	var directories: Array[String] = []
	var files: Array[String] = []
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if not entry.begins_with("."):
				directories.append(entry)
		else:
			files.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	directories.sort()
	files.sort()
	for file_name: String in files:
		result[_join_path(resource_path, file_name)] = true
	for directory_name: String in directories:
		_collect_all_files(
			_join_path(disk_path, directory_name),
			_join_path(resource_path, directory_name),
			result
		)


func _collect_localization(root_path: String) -> Dictionary:
	var source_path := _project_path(
		root_path,
		"localization/catalog.v2.csv.raw"
	)
	if not FileAccess.file_exists(source_path):
		return {}
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {}
	var header := file.get_csv_line()
	if header != PackedStringArray(["key", "zh_TW", "en"]):
		file.close()
		return {}
	var zh: Dictionary = {}
	var en: Dictionary = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		if row.size() != 3 or row[0].is_empty():
			file.close()
			return {}
		zh[row[0]] = row[1]
		en[row[0]] = row[2]
	file.close()
	return {"zh_TW": zh, "en": en}


func _collect_focus_graphs(root_path: String) -> Array[Dictionary]:
	var source_path := _project_path(
		root_path,
		"presentation/accessibility/keyboard_focus_graph.gd"
	)
	if not FileAccess.file_exists(source_path):
		return []
	var source := FileAccess.get_file_as_string(source_path)
	var expected: Dictionary = {
		"MENU_MAIN": [
			"menu.continue",
			"menu.start",
			"menu.recovery",
			"menu.recovery.confirm",
			"menu.recovery.cancel",
			"menu.settings",
			"menu.exit",
		],
		"SETTINGS": ["settings.apply", "settings.back"],
		"CAMP_WORLD": [
			"camp.expedition_gate",
			"camp.commander_hall",
			"camp.collection",
			"camp.forge",
			"camp.challenge_monument",
			"camp.settings",
			"camp.start",
			"camp.menu",
		],
		"FACILITY_EXPEDITION_GATE": ["camp.back"],
		"FACILITY_COMMANDER_HALL": ["camp.back"],
		"COLLECTION": ["camp.back"],
		"FACILITY_UNLOCK_WORKSHOP": ["camp.back"],
		"FACILITY_CHALLENGE_MONUMENT": ["camp.back"],
		"RUN_MAP": ["map.select", "map.confirm"],
		"RUN_PREPARE": ["prepare.unit", "prepare.start"],
		"RUN_COMBAT": [
			"combat.pause",
			"combat.inspect",
			"combat.speed",
		],
		"RUN_REWARD": ["reward.select", "reward.confirm"],
		"RUN_ROUTE_FALLBACK": ["run.retry_route", "run.menu"],
		"RESULTS": ["results.camp", "results.menu"],
		"RESULTS_FALLBACK": [
			"results.retry",
			"results.camp",
			"results.menu",
		],
	}
	var graphs: Array[Dictionary] = []
	for graph_id: String in _sorted_keys(expected):
		var required := PackedStringArray()
		for action_value: Variant in expected[graph_id]:
			var action := String(action_value)
			if source.contains("&\"%s\"" % action):
				required.append(action)
		var edges: Dictionary = {}
		for index: int in required.size():
			edges[required[index]] = PackedStringArray([
				required[(index + 1) % required.size()],
			])
		graphs.append({
			"graph_id": graph_id.to_lower(),
			"nodes": required.duplicate(),
			"edges": edges,
			"required_actions": PackedStringArray(expected[graph_id]),
		})
	return graphs


func _collect_system_menu_contract(root_path: String) -> Dictionary:
	var screen_path := _project_path(
		root_path,
		"presentation/screens/production_screen.gd"
	)
	var overlay_path := _project_path(
		root_path,
		"presentation/screens/system_menu_overlay.gd"
	)
	var focus_path := _project_path(
		root_path,
		"presentation/accessibility/keyboard_focus_graph.gd"
	)
	if (
		not FileAccess.file_exists(screen_path)
		or not FileAccess.file_exists(overlay_path)
		or not FileAccess.file_exists(focus_path)
	):
		return {}
	var screen := FileAccess.get_file_as_string(screen_path)
	var overlay := FileAccess.get_file_as_string(overlay_path)
	var focus := FileAccess.get_file_as_string(focus_path)
	var route_contracts_are_clean := true
	for route_pair: PackedStringArray in [
		PackedStringArray(["RUN_MAP", "RUN_PREPARE"]),
		PackedStringArray(["RUN_PREPARE", "RUN_COMBAT"]),
		PackedStringArray(["RUN_COMBAT", "RUN_REWARD"]),
		PackedStringArray(["RUN_REWARD", "RUN_ROUTE_FALLBACK"]),
	]:
		route_contracts_are_clean = (
			route_contracts_are_clean
			and _route_contract_excludes_token(
				screen,
				"func _required_action_ids()",
				route_pair[0],
				route_pair[1],
				"&\"run.menu\""
			)
			and _route_contract_excludes_token(
				focus,
				"const _PRIMARY_ACTIONS",
				route_pair[0],
				route_pair[1],
				"&\"run.menu\""
			)
		)
	return {
		"custom_input_action": screen.contains(
			"const SYSTEM_MENU_INPUT: StringName = &\"system_menu\""
		),
		"stable_button": (
			screen.contains("SYSTEM_MENU_BUTTON_NODE")
			and screen.contains("&\"SystemMenuButton\"")
		),
		"ordered_focus": screen.contains(
			"result.append(_system_menu_button)"
		),
		"five_states": (
			overlay.contains("CLOSED")
			and overlay.contains("ROOT")
			and overlay.contains("SETTINGS_EMBEDDED")
			and overlay.contains("CONFIRM_MENU")
			and overlay.contains("CONFIRM_EXIT")
		),
		"focus_trap": (
			overlay.contains("_capture_background_focus")
			and overlay.contains("_restore_background_focus")
			and overlay.contains("focus_next")
		),
		"no_resident_run_menu": route_contracts_are_clean,
	}


func _route_contract_excludes_token(
	source: String,
	section_marker: String,
	route: String,
	next_route: String,
	forbidden_token: String
) -> bool:
	var section_start := source.find(section_marker)
	if section_start < 0:
		return false
	var route_start := source.find('&"%s":' % route, section_start)
	if route_start < 0:
		return false
	var route_end := source.find('&"%s":' % next_route, route_start + 1)
	if route_end < 0:
		return false
	return not source.substr(route_start, route_end - route_start).contains(
		forbidden_token
	)


func _collect_render_policy(root_path: String) -> Dictionary:
	var path := _project_path(
		root_path,
		"presentation/viewport/world_viewport_policy.gd"
	)
	if not FileAccess.file_exists(path):
		return {}
	var source := FileAccess.get_file_as_string(path)
	return {
		"world_size": Vector2i(640, 360) \
			if source.contains("Vector2i(640, 360)") else Vector2i.ZERO,
		"ui_reference_size": Vector2i(1920, 1080) \
			if source.contains("Vector2i(1920, 1080)") else Vector2i.ZERO,
		"integer_scale": source.contains("integer_scale"),
		"letterbox": (
			source.contains("letterboxed")
			or source.contains("letterbox")
		),
		"world_texture_filter": (
			"nearest" if source.contains("&\"nearest\"") else ""
		),
		"pixel_snap": source.contains("\"pixel_snap\": true"),
	}


func _collect_theme_policy(root_path: String) -> Dictionary:
	var semantic_path := _project_path(
		root_path,
		"presentation/accessibility/accessibility_semantic_tokens.gd"
	)
	var focus_path := _project_path(
		root_path,
		"presentation/accessibility/keyboard_focus_graph.gd"
	)
	var typography_path := _project_path(
		root_path,
		"presentation/accessibility/localized_typography_policy.gd"
	)
	var semantic := FileAccess.get_file_as_string(semantic_path)
	var focus := FileAccess.get_file_as_string(focus_path)
	var typography := FileAccess.get_file_as_string(typography_path)
	var modes := PackedStringArray()
	for mode: String in [
		"default",
		"protanopia",
		"deuteranopia",
		"tritanopia",
	]:
		if semantic.contains("&\"%s\"" % mode):
			modes.append(mode)
	return {
		"ui_scale_tokens": PackedFloat32Array([
			1.0 if focus.contains("100") else 0.0,
			1.25 if focus.contains("125") else 0.0,
			1.5 if focus.contains("150") else 0.0,
		]),
		"color_modes": modes,
		"non_color_cues": (
			semantic.contains("icon_token")
			and semantic.contains("pattern_token")
			and semantic.contains("text_key")
		),
		"focus_token": "focus.visible" if not focus.is_empty() else "",
		"tooltip_max_depth": 2 \
			if semantic.contains("depth <= 2") else -1,
		"cjk_font_token": "font.cjk" \
			if typography.contains("font.cjk") else "",
	}


func _collect_accessibility_bindings(
	root_path: String
) -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	for scene_path: String in REQUIRED_ACCESSIBILITY_SCENES:
		var relative_scene := scene_path.trim_prefix("res://")
		var scene_source := FileAccess.get_file_as_string(
			_project_path(root_path, relative_scene)
		)
		var host_source := FileAccess.get_file_as_string(
			_project_path(
				root_path,
				"presentation/accessibility/"
				+ "production_accessibility_host.gd"
			)
		)
		var consumer_source := FileAccess.get_file_as_string(
			_project_path(
				root_path,
				"services/settings/adapters/"
				+ "presentation_settings_runtime_consumer.gd"
			)
		)
		var capabilities := PackedStringArray()
		var node_markers: Dictionary = {
			"motion": "MotionProbe",
			"flash": "FlashProbe",
			"particles": "ParticleProbe",
			"density": "DamageEvents",
			"tooltip": "TooltipStack",
			"cjk": "CjkBody",
		}
		for capability: String in REQUIRED_ACCESSIBILITY_CAPABILITIES:
			if scene_source.contains(String(node_markers[capability])) \
				and host_source.contains("&\"%s\"" % capability):
				capabilities.append(capability)
		bindings.append({
			"scene_path": scene_path,
			"host_path": (
				"AccessibilityRuntime"
				if scene_source.contains("AccessibilityRuntime")
				else ""
			),
			"consumer": (
				"PresentationSettingsRuntimeConsumer"
				if (
					consumer_source.contains(
						"runtime_accessibility_report"
					)
					and consumer_source.contains(
						"open_accessibility_tooltip"
					)
				)
				else ""
			),
			"capabilities": capabilities,
		})
	return bindings


func _contains_cjk_string_literal(source: String) -> bool:
	for line_value: Variant in source.split("\n"):
		var line := String(line_value)
		var in_string := false
		var escaped := false
		var literal := ""
		for index: int in line.length():
			var character := line[index]
			if not in_string:
				if character == "#":
					break
				if character == "\"":
					in_string = true
					literal = ""
				continue
			if escaped:
				escaped = false
				literal += character
				continue
			if character == "\\":
				escaped = true
				continue
			if character == "\"":
				if _contains_cjk(literal):
					return true
				in_string = false
				continue
			literal += character
	return false


func _contains_cjk(value: String) -> bool:
	for index: int in value.length():
		var codepoint := value.unicode_at(index)
		if (
			(codepoint >= 0x3400 and codepoint <= 0x4DBF)
			or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
			or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
		):
			return true
	return false


func _contains_visible_scene_text(source: String) -> bool:
	for line_value: Variant in source.split("\n"):
		var line := String(line_value).strip_edges()
		if not line.begins_with("text = "):
			continue
		var separator := line.find("\"")
		var finish := line.rfind("\"")
		if separator < 0 or finish <= separator:
			continue
		var value := line.substr(separator + 1, finish - separator - 1)
		if not value.strip_edges().is_empty():
			return true
	return false


func _contains_visible_gd_text(source: String) -> bool:
	var visible_properties: Array[String] = [
		"text",
		"tooltip_text",
		"placeholder_text",
		"dialog_text",
		"title",
		"window_title",
	]
	for line_value: Variant in source.split("\n"):
		var line := String(line_value).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var assignment := line.find("=")
		if assignment >= 0:
			var left := line.substr(0, assignment).strip_edges()
			var property := left.get_slice(
				".",
				left.get_slice_count(".") - 1
			).strip_edges()
			if property in visible_properties and _starts_with_direct_literal(
				line,
				assignment + 1
			):
				return true
		for call_name: String in [
			"add_item",
			"set_text",
			"set_tooltip_text",
			"set_placeholder_text",
		]:
			var call := line.find("%s(" % call_name)
			if call >= 0 and _starts_with_direct_literal(
				line,
				call + call_name.length() + 1
			):
				return true
		var set_item := line.find("set_item_text(")
		if set_item >= 0:
			var comma := line.find(",", set_item)
			if comma >= 0 and _starts_with_direct_literal(line, comma + 1):
				return true
	return false


func _starts_with_direct_literal(source: String, offset: int) -> bool:
	var index := offset
	while index < source.length() and source[index] in [" ", "\t"]:
		index += 1
	if index >= source.length() or source[index] != "\"":
		return false
	index += 1
	var value := ""
	var escaped := false
	while index < source.length():
		var character := source[index]
		if escaped:
			value += character
			escaped = false
		elif character == "\\":
			escaped = true
		elif character == "\"":
			var language_probe := value \
				.replace("%%", "") \
				.replace("%s", "") \
				.replace("%d", "") \
				.replace("%f", "")
			return (
				_contains_ascii_letter(language_probe)
				or _contains_cjk(value)
			)
		else:
			value += character
		index += 1
	return false


func _contains_ascii_letter(value: String) -> bool:
	for index: int in value.length():
		var character := value[index]
		if (
			(character >= "a" and character <= "z")
			or (character >= "A" and character <= "Z")
		):
			return true
	return false


func _asset_references(source: String) -> Array[String]:
	var references: Dictionary = {}
	var offset := 0
	while true:
		var start := source.find(ASSET_REFERENCE_PREFIX, offset)
		if start < 0:
			break
		var finish := start
		while finish < source.length():
			var character := source[finish]
			if character in ["\"", "'", ")", "]", "}", " ", "\t", "\r", "\n"]:
				break
			finish += 1
		var reference := source.substr(start, finish - start)
		if not reference.is_empty():
			references[reference] = true
		offset = maxi(finish, start + 1)
	return _sorted_keys(references)


func _reachable_nodes(start: String, edges: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var pending: Array[String] = [start]
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		for target: String in _string_values(edges.get(current, PackedStringArray())):
			if not visited.has(target):
				pending.append(target)
	return visited


func _has_direct_custom_minimum_size_assignment(source: String) -> bool:
	var offset := 0
	while offset < source.length():
		var character := source[offset]
		if character == "#":
			offset = _skip_gdscript_line_comment(source, offset)
			continue
		if character == "\"" or character == "'":
			offset = _skip_gdscript_string(source, offset)
			continue
		if source.substr(offset, CUSTOM_MINIMUM_SIZE_TOKEN.length()) \
				== CUSTOM_MINIMUM_SIZE_TOKEN:
			var before_ok := (
				offset == 0
				or not _is_identifier_character(source[offset - 1])
			)
			var token_end := offset + CUSTOM_MINIMUM_SIZE_TOKEN.length()
			var after_ok := (
				token_end >= source.length()
				or not _is_identifier_character(source[token_end])
			)
			if before_ok and after_ok:
				var assignment := _skip_gdscript_trivia(source, token_end)
				if assignment < source.length():
					var operator := source[assignment]
					if operator == "=":
						if assignment + 1 >= source.length() \
								or source[assignment + 1] != "=":
							return true
					elif operator in ["+", "-", "*", "/", "%", "&", "|", "^"]:
						if assignment + 1 < source.length() \
								and source[assignment + 1] == "=":
							return true
			offset = token_end
			continue
		offset += 1
	return false


func _skip_gdscript_trivia(source: String, offset: int) -> int:
	var cursor := offset
	while cursor < source.length():
		if source[cursor] in [" ", "\t", "\r", "\n"]:
			cursor += 1
			continue
		if source[cursor] == "#":
			cursor = _skip_gdscript_line_comment(source, cursor)
			continue
		break
	return cursor


func _skip_gdscript_line_comment(source: String, offset: int) -> int:
	var line_end := source.find("\n", offset + 1)
	return source.length() if line_end < 0 else line_end + 1


func _skip_gdscript_string(source: String, offset: int) -> int:
	var quote := source[offset]
	var delimiter := quote
	if source.substr(offset, 3) == quote + quote + quote:
		delimiter = quote + quote + quote
	var cursor := offset + delimiter.length()
	while cursor < source.length():
		if source.substr(cursor, delimiter.length()) == delimiter:
			return cursor + delimiter.length()
		if delimiter.length() == 1 and source[cursor] == "\\":
			cursor += 2
		else:
			cursor += 1
	return source.length()


func _is_identifier_character(character: String) -> bool:
	return (
		(character >= "a" and character <= "z")
		or (character >= "A" and character <= "Z")
		or _is_ascii_digit(character)
		or character == "_"
	)


func _contains_integer_token(line: String, token: String) -> bool:
	var offset := 0
	while true:
		var found := line.find(token, offset)
		if found < 0:
			return false
		var before_ok := found == 0 or not _is_ascii_digit(line[found - 1])
		var after_index := found + token.length()
		var after_ok := (
			after_index >= line.length()
			or not _is_ascii_digit(line[after_index])
		)
		if before_ok and after_ok:
			return true
		offset = found + 1
	return false


func _is_ascii_digit(character: String) -> bool:
	return character >= "0" and character <= "9"


func _path_holds_localization_values(path: String) -> bool:
	var lower := path.to_lower()
	return (
		lower.contains("/localization/")
		or lower.ends_with("/localization_catalog.gd")
		or lower.ends_with(".translation")
		or lower.ends_with(".po")
	)


func _starts_with_any(path: String, prefixes: Array[String]) -> bool:
	for prefix: String in prefixes:
		if path.begins_with(prefix):
			return true
	return false


func _has_source_extension(path: String) -> bool:
	for extension: String in SOURCE_EXTENSIONS:
		if path.ends_with(extension):
			return true
	return false


func _project_path(root_path: String, relative: String) -> String:
	var normalized_root := root_path.replace("\\", "/").trim_suffix("/")
	return "%s/%s" % [normalized_root, relative.trim_prefix("/")]


func _join_path(left: String, right: String) -> String:
	return "%s/%s" % [
		left.replace("\\", "/").trim_suffix("/"),
		right.replace("\\", "/").trim_prefix("/"),
	]


func _string_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for item: Variant in value:
			result.append(String(item))
	return result


func _variant_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in values.keys():
		result.append(String(key))
	result.sort()
	return result


func _has_empty_value(values: Dictionary) -> bool:
	for value: Variant in values.values():
		if String(value).strip_edges().is_empty():
			return true
	return false


func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in values.keys():
		result.append(String(key))
	result.sort()
	return result


func _append_issue(
	issues: Array[Dictionary],
	code: StringName,
	path: String,
	detail: String
) -> void:
	issues.append({
		"code": code,
		"path": path,
		"detail": detail,
	})


func _issue_less(left: Dictionary, right: Dictionary) -> bool:
	var left_key := "%s|%s|%s" % [
		String(left.get("path", "")),
		String(left.get("code", "")),
		String(left.get("detail", "")),
	]
	var right_key := "%s|%s|%s" % [
		String(right.get("path", "")),
		String(right.get("code", "")),
		String(right.get("detail", "")),
	]
	return left_key < right_key
