extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const INDEX_PATH: String = "res://docs/game-architecture-spec.md"
const ARTIFACT_PATH: String = "res://artifacts/test/spec-contract.json"
const CANONICAL_PREFIX: String = "spec-chapter-set-v1"
const FOUNDATION_SPEC_PATHS: Array[String] = [
	"res://specs/foundation-core/requirements.md",
	"res://specs/foundation-core/design.md",
	"res://specs/foundation-core/tasks.md",
]
const FOUNDATION_REQUIREMENTS: Array[String] = [
	"REQ-TECH-001", "REQ-TECH-002", "REQ-TECH-003", "REQ-TECH-004",
	"REQ-TECH-005", "REQ-TECH-006", "REQ-DATA-001", "REQ-DATA-002",
	"REQ-DATA-003", "REQ-DATA-004", "REQ-DATA-005", "REQ-DATA-006",
	"REQ-DATA-007", "REQ-DATA-008", "REQ-RNG-001", "REQ-RNG-002",
	"REQ-SAVE-001", "REQ-SAVE-002", "REQ-SAVE-003", "REQ-SAVE-004",
	"REQ-SAVE-005", "REQ-SAVE-006", "REQ-CONTENT-001",
]
const FOUNDATION_F: Array[String] = [
	"AC-025", "AC-026", "AC-036", "AC-039", "AC-040", "AC-051",
	"AC-052", "AC-054", "AC-055", "AC-063", "AC-064", "AC-068",
	"AC-069", "AC-070", "AC-078",
]
const FOUNDATION_X: Array[String] = [
	"AC-016", "AC-027", "AC-034", "AC-047", "AC-065", "AC-073", "AC-075",
]
const FOUNDATION_D: Array[String] = [
	"AC-007", "AC-020", "AC-023", "AC-024", "AC-035", "AC-041",
	"AC-046", "AC-058", "AC-066", "AC-072", "AC-076",
]

var _started_at_utc: String = ""
var _failures: Array[String] = []
var _infrastructure_error: bool = false
var _case_count: int = 0


func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = _load_manifest()
	if not manifest.is_empty():
		_validate_document_set(manifest)
		_validate_source_contracts(manifest)
	_validate_foundation_spec()
	_finish()


func _load_manifest() -> Dictionary:
	_case_count += 1
	if not FileAccess.file_exists(INDEX_PATH):
		_infrastructure_error = true
		_failures.append("Spec index is missing")
		return {}
	var text: String = FileAccess.get_file_as_string(INDEX_PATH)
	var marker_start: int = text.find("<!-- spec-manifest:start -->")
	var marker_end: int = text.find("<!-- spec-manifest:end -->")
	if marker_start < 0 or marker_end <= marker_start:
		_infrastructure_error = true
		_failures.append("Spec manifest markers are missing or reversed")
		return {}
	var fence_start: int = text.find("```json", marker_start)
	var json_start: int = text.find("\n", fence_start) + 1
	var fence_end: int = text.find("```", json_start)
	if fence_start < 0 or json_start <= 0 or fence_end <= json_start or fence_end > marker_end:
		_infrastructure_error = true
		_failures.append("Spec manifest JSON fence is invalid")
		return {}
	var parsed: Variant = JSON.parse_string(text.substr(json_start, fence_end - json_start))
	if not parsed is Dictionary:
		_infrastructure_error = true
		_failures.append("Spec manifest JSON is invalid")
		return {}
	var manifest: Dictionary = parsed
	if int(manifest.get("manifest_schema_version", 0)) != 2:
		_failures.append("manifest_schema_version must be 2")
	if str(manifest.get("spec_version", "")) != "0.2" or str(manifest.get("status", "")) != "Approved":
		_failures.append("Spec manifest version/status must be 0.2/Approved")
	return manifest


func _validate_document_set(manifest: Dictionary) -> void:
	var files_value: Variant = manifest.get("files", null)
	var expected_value: Variant = manifest.get("expected", null)
	if not files_value is Array or not expected_value is Dictionary:
		_infrastructure_error = true
		_failures.append("Manifest files/expected schema is invalid")
		return
	var files: Array = files_value
	var expected: Dictionary = expected_value
	_case_count += 1
	if files.size() != int(expected.get("file_count", -1)) or files.size() != 12:
		_failures.append("Manifest must list exactly 12 chapter files")

	var manifest_seen: Dictionary = {}
	for entry: Variant in files:
		var manifest_path: String = str(entry)
		if not entry is String or manifest_path.is_absolute_path() \
			or manifest_path.contains("..") or not manifest_path.begins_with("game-architecture/"):
			_failures.append("Manifest contains an unsafe chapter path: " + manifest_path)
		elif manifest_seen.has(manifest_path):
			_failures.append("Manifest contains a duplicate chapter path: " + manifest_path)
		else:
			manifest_seen[manifest_path] = true
	_validate_no_unlisted_chapters(files)

	var all_text: String = ""
	var section_count: int = 0
	var mermaid_count: int = 0
	var definition_counts: Dictionary = {"REQ": 0, "AC": 0, "DEC": 0, "ASM": 0, "RSK": 0}
	var definition_ids: Dictionary = {}
	var chapter_texts: Dictionary = {}
	for entry: Variant in files:
		if not entry is String:
			_infrastructure_error = true
			_failures.append("Manifest contains a non-string file path")
			continue
		var relative_path: String = str(entry)
		var resource_path: String = "res://docs/" + relative_path
		_case_count += 1
		if not FileAccess.file_exists(resource_path):
			_failures.append("Missing manifest chapter: " + relative_path)
			continue
		var chapter: String = FileAccess.get_file_as_string(resource_path)
		if not chapter.contains("v0.2 / Approved"):
			_failures.append("Chapter status is not v0.2 / Approved: " + relative_path)
		chapter_texts[relative_path] = chapter
		all_text += chapter + "\n"
		section_count += _count_matches('<a id="section-[0-9]+"></a>', chapter)
		mermaid_count += chapter.count("```mermaid")
		var definitions: Array[RegExMatch] = _find_all('\\*\\*\\[(REQ-[A-Z]+-[0-9]{3}|AC-[0-9]{3}|DEC-[0-9]{3}|ASM-[0-9]{3}|RSK-[0-9]{3})\\]\\*\\*', chapter)
		for match_value: RegExMatch in definitions:
			var identifier: String = match_value.get_string(1)
			if definition_ids.has(identifier):
				_failures.append("Duplicate definition ID: " + identifier)
			else:
				definition_ids[identifier] = relative_path
			var prefix: String = identifier.get_slice("-", 0)
			definition_counts[prefix] = int(definition_counts[prefix]) + 1
		_validate_links(relative_path, chapter, chapter_texts, files)

	_case_count += 3
	if section_count != int(expected.get("section_count", -1)):
		_failures.append("Section count mismatch: %d" % section_count)
	if mermaid_count != int(expected.get("mermaid_count", -1)):
		_failures.append("Mermaid count mismatch: %d" % mermaid_count)
	var expected_ids: Dictionary = expected.get("ids", {}) as Dictionary
	for key: String in definition_counts:
		_case_count += 1
		if int(definition_counts[key]) != int(expected_ids.get(key, -1)):
			_failures.append("Definition count mismatch for %s: %d" % [key, definition_counts[key]])

	_validate_traceability(definition_ids, chapter_texts)
	_validate_aggregate_hash(manifest, files)


func _validate_no_unlisted_chapters(manifest_files: Array) -> void:
	var discovered: Array[String] = []
	var directory: DirAccess = DirAccess.open("res://docs/game-architecture")
	if directory == null:
		_infrastructure_error = true
		_failures.append("Unable to enumerate architecture chapters")
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.ends_with(".md"):
			discovered.append("game-architecture/" + entry)
		entry = directory.get_next()
	directory.list_dir_end()
	discovered.sort()
	var declared: Array[String] = []
	for value: Variant in manifest_files:
		declared.append(str(value))
	declared.sort()
	_case_count += 1
	if discovered != declared:
		_failures.append("Manifest must cover exactly the 12 architecture chapter files")


func _validate_links(source_relative_path: String, text: String, known_texts: Dictionary, manifest_files: Array) -> void:
	var links: Array[RegExMatch] = _find_all('\\[[^\\]]*\\]\\(([^)]+)\\)', text)
	for link_match: RegExMatch in links:
		var target: String = link_match.get_string(1)
		if target.begins_with("http://") or target.begins_with("https://") or target.begins_with("mailto:"):
			continue
		var path_part: String = target.get_slice("#", 0)
		var anchor: String = ""
		if target.contains("#"):
			anchor = target.substr(target.find("#") + 1)
		if path_part.is_empty():
			continue
		var resolved: String = source_relative_path.get_base_dir().path_join(path_part).simplify_path()
		_case_count += 1
		if not manifest_files.has(resolved) and resolved != "game-architecture-spec.md" and resolved != "implementation-slices.md":
			_failures.append("Link escapes manifest/known docs: %s -> %s" % [source_relative_path, target])
			continue
		var target_resource: String = "res://docs/" + resolved
		if not FileAccess.file_exists(target_resource):
			_failures.append("Broken local link: %s -> %s" % [source_relative_path, target])
			continue
		if not anchor.is_empty():
			var target_text: String = str(known_texts.get(resolved, FileAccess.get_file_as_string(target_resource)))
			if target_text.find('id="' + anchor + '"') < 0:
				_failures.append("Broken anchor: %s -> %s" % [source_relative_path, target])


func _validate_traceability(definition_ids: Dictionary, chapter_texts: Dictionary) -> void:
	var matrix_path: String = "game-architecture/10-traceability-matrix.md"
	var matrix: String = str(chapter_texts.get(matrix_path, ""))
	if matrix.is_empty():
		_failures.append("Traceability matrix chapter is unavailable")
		return
	var rows: Array[RegExMatch] = _find_all('(?m)^\\|\\s*(REQ-[^|]+)\\|', matrix)
	var row_counts: Dictionary = {}
	for row: RegExMatch in rows:
		for requirement_match: RegExMatch in _find_all(
			'REQ-[A-Z]+-[0-9]{3}',
			row.get_string(1)
		):
			var requirement_id: String = requirement_match.get_string(0)
			row_counts[requirement_id] = int(row_counts.get(requirement_id, 0)) + 1
	for identifier: String in definition_ids:
		if identifier.begins_with("REQ-"):
			_case_count += 1
			if int(row_counts.get(identifier, 0)) != 1:
				_failures.append("REQ trace row must appear exactly once: " + identifier)
	for requirement_id: String in row_counts:
		if not definition_ids.has(requirement_id):
			_failures.append("Trace matrix references undefined REQ: " + requirement_id)


func _validate_aggregate_hash(manifest: Dictionary, files: Array) -> void:
	_case_count += 1
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		_infrastructure_error = true
		_failures.append("Unable to initialize SHA-256")
		return
	context.update(CANONICAL_PREFIX.to_utf8_buffer())
	context.update(PackedByteArray([0]))
	for entry: Variant in files:
		var relative_path: String = str(entry)
		var raw: PackedByteArray = FileAccess.get_file_as_bytes("res://docs/" + relative_path)
		if raw.size() >= 3 and raw[0] == 0xef and raw[1] == 0xbb and raw[2] == 0xbf:
			raw = raw.slice(3)
		var decoded: String = raw.get_string_from_utf8()
		if decoded.to_utf8_buffer() != raw:
			_failures.append("Chapter is not strict UTF-8: " + relative_path)
			continue
		var canonical_text: String = decoded.replace("\r\n", "\n").replace("\r", "\n")
		context.update(relative_path.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(canonical_text.to_utf8_buffer())
		context.update(PackedByteArray([0]))
	var actual: String = context.finish().hex_encode()
	var expected_hash: String = str(manifest.get("aggregate_sha256", ""))
	if actual != expected_hash:
		_failures.append("Aggregate SHA-256 mismatch: expected %s, got %s" % [expected_hash, actual])


func _validate_source_contracts(manifest: Dictionary) -> void:
	var expected: Dictionary = manifest.get("expected", {}) as Dictionary
	var source_paths: Array[String] = []
	for root_path: String in ["res://app", "res://domain", "res://content", "res://services"]:
		_collect_files(root_path, ".gd", source_paths)
	var class_files: Dictionary = {}
	var all_source: String = ""
	for source_path: String in source_paths:
		var source: String = FileAccess.get_file_as_string(source_path)
		var current_class_name: String = ""
		all_source += source + "\n"
		for class_match: RegExMatch in _find_all('(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)', source):
			var class_name_value: String = class_match.get_string(1)
			current_class_name = class_name_value
			if class_files.has(class_name_value):
				_failures.append("Duplicate class_name: " + class_name_value)
			else:
				class_files[class_name_value] = source_path
		_validate_public_api_types(source_path, source)
		_validate_public_fields(source_path, source)
		_validate_signal_types(source_path, source)
		_validate_silent_null_contract(source_path, source)
		_validate_result_mutual_exclusion(source_path, source)
		_validate_error_shape(current_class_name, source_path, source)
		_validate_save_boundary_dependencies(source_path, source)
		_validate_domain_dependency_boundary(source_path, source)
		if not source_path.contains("services/save/save_json_codec"):
			_validate_no_public_dictionary(source_path, source)
		if source.contains("assert(false"):
			_failures.append("Production source contains an assert-only abstract contract: " + source_path)
		if source.contains("Time.") and not source_path.ends_with("/run_commit_clock.gd"):
			_failures.append("Production source reads wall/monotonic time outside RunCommitClock: " + source_path)
		if _count_matches('\\b(ObjectID|get_instance_id)\\b', source) > 0:
			_failures.append("Production source derives identity from ObjectID: " + source_path)
		if _count_matches('ResourceLoader\\.load|preload\\(\"res://content/definitions', source) > 0:
			_failures.append("Production source directly loads authoring Resource content: " + source_path)

	_validate_autoloads(expected, class_files)
	_validate_expected_apis(expected, class_files)
	_validate_locked_service_public_apis(expected, class_files)
	_validate_result_invariant_helper()
	_case_count += 1
	if _count_matches('\\b(randf|randi|randomize|RandomNumberGenerator)\\b', all_source) > 0:
		_failures.append("Production source contains a forbidden gameplay random API")
	_validate_battle_receipt_boundary(source_paths)
	_validate_content_snapshot_boundary(source_paths)
	var deferred_classes: Array = expected.get("deferred_class_names", []) as Array
	for deferred: Variant in deferred_classes:
		_case_count += 1
		if class_files.has(str(deferred)):
			_failures.append("Deferred class must not exist in S1: " + str(deferred))


func _validate_battle_receipt_boundary(source_paths: Array[String]) -> void:
	var validator_path := "res://domain/battle/battle_setup_inputs_validator.gd"
	var authority_path := "res://domain/battle/battle_setup_validation_authority.gd"
	var receipt_path := "res://domain/battle/battle_setup_validation_receipt.gd"
	var builder_path := "res://domain/battle/battle_setup_hash_builder.gd"
	for source_path: String in source_paths:
		var source := FileAccess.get_file_as_string(source_path)
		var is_validator := source_path == validator_path
		if source.contains("BattleSetupValidationAuthority.new") and not is_validator:
			_failures.append(
				"Production source constructs a battle validation authority outside the trusted validator: " \
				+ source_path
			)
		if _count_matches('\\._issue_validated\\s*\\(', source) > 0 and not is_validator:
			_failures.append(
				"Production source issues a battle validation receipt outside the trusted validator: " \
				+ source_path
			)
		if _count_matches('\\._verifies\\s*\\(', source) > 0 and not is_validator:
			_failures.append(
				"Production source verifies a battle validation receipt outside the trusted validator: " \
				+ source_path
			)
		if source.contains("_trusted_authority") and not is_validator:
			_failures.append(
				"Production source reaches into the trusted battle validation authority: " \
				+ source_path
			)
		if source.contains("BattleSetupValidationReceipt.new") \
			and source_path != authority_path \
			and source_path != receipt_path:
			_failures.append(
				"Production source constructs a battle validation receipt directly: " \
				+ source_path
			)
	if not FileAccess.file_exists(validator_path) or not FileAccess.file_exists(builder_path):
		_failures.append("Battle validation receipt boundary sources are missing")
		return
	var validator_source := FileAccess.get_file_as_string(validator_path)
	_case_count += 1
	if _count_matches('BattleSetupValidationAuthority\\.new\\s*\\(', validator_source) != 1 \
		or _count_matches('\\._issue_validated\\s*\\(', validator_source) != 1 \
		or not validator_source.contains("func validate_for_build(") \
		or not validator_source.contains("static func _verifies_receipt("):
		_failures.append("Trusted battle validation receipt issuer contract mismatch")
	var builder_source := FileAccess.get_file_as_string(builder_path)
	_case_count += 1
	if builder_source.contains("BattleSetupValidationAuthority") \
		or builder_source.contains("validation_authority") \
		or not builder_source.contains("BattleSetupInputsValidator._verifies_receipt("):
		_failures.append("BattleSetupHashBuilder permits injected receipt authority")


func _validate_content_snapshot_boundary(source_paths: Array[String]) -> void:
	var state_path := "res://domain/run/content_snapshot_state.gd"
	for source_path: String in source_paths:
		var source := FileAccess.get_file_as_string(source_path)
		if source_path != state_path and source.contains("ContentSnapshotState.new"):
			_failures.append(
				"Production source bypasses the receipt-gated content snapshot factory: " \
				+ source_path
			)
		if source_path != state_path and source.contains("_construction_seal"):
			_failures.append(
				"Production source reaches into the content snapshot construction seal: " \
				+ source_path
			)
	if not FileAccess.file_exists(state_path):
		_failures.append("ContentSnapshotState receipt-gated factory is missing")
		return
	var state_source := FileAccess.get_file_as_string(state_path)
	_case_count += 1
	if not state_source.contains("static func from_pinned_receipt(") \
		or not state_source.contains("static func from_persisted(") \
		or not state_source.contains("static var _construction_seal:") \
		or not state_source.contains("func is_validated() -> bool:"):
		_failures.append("ContentSnapshotState construction boundary contract mismatch")


func _validate_autoloads(expected: Dictionary, class_files: Dictionary) -> void:
	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	var configured: Dictionary = {}
	for autoload_match: RegExMatch in _find_all('(?m)^([A-Za-z_][A-Za-z0-9_]*)="\\*res://([^"]+)"', project_text):
		configured[autoload_match.get_string(1)] = "res://" + autoload_match.get_string(2)
	var expected_autoloads: Dictionary = expected.get("autoloads", {}) as Dictionary
	_case_count += 1
	if configured != expected_autoloads:
		_failures.append("Autoload set/path mismatch")
	for instance_name: String in configured:
		if class_files.has(instance_name):
			_failures.append("Autoload instance collides with class_name: " + instance_name)


func _validate_expected_apis(expected: Dictionary, class_files: Dictionary) -> void:
	var apis: Array = expected.get("public_apis", []) as Array
	for api_value: Variant in apis:
		_case_count += 1
		if not api_value is Dictionary:
			_failures.append("public_apis contains an invalid entry")
			continue
		var api: Dictionary = api_value
		var owner: String = str(api.get("class", ""))
		if not class_files.has(owner):
			_failures.append("Public API owner class is missing: " + owner)
			continue
		var source: String = FileAccess.get_file_as_string(str(class_files[owner]))
		var method_name: String = str(api.get("method", ""))
		var return_type: String = str(api.get("return", ""))
		var pattern: String = '(?s)func\\s+' + method_name + '\\s*\\(.*?\\)\\s*->\\s*' + return_type + '\\s*:'
		if _count_matches(pattern, source) != 1:
			_failures.append("Public API signature mismatch: %s.%s -> %s" % [owner, method_name, return_type])


func _validate_locked_service_public_apis(
	expected: Dictionary,
	class_files: Dictionary
) -> void:
	var owner: String = "SaveRepository"
	_case_count += 1
	if not class_files.has(owner):
		_failures.append("Locked public API owner is missing: " + owner)
		return
	var allowed: Dictionary = {}
	var api_values: Array = expected.get("public_apis", []) as Array
	for api_value: Variant in api_values:
		if api_value is Dictionary:
			var api: Dictionary = api_value
			if str(api.get("class", "")) == owner:
				allowed[str(api.get("method", ""))] = true
	var actual: Dictionary = {}
	var source: String = FileAccess.get_file_as_string(str(class_files[owner]))
	for method_match: RegExMatch in _find_all(
		'(?m)^(?:static\\s+)?func\\s+(?!_)([A-Za-z_][A-Za-z0-9_]*)\\s*\\(',
		source
	):
		actual[method_match.get_string(1)] = true
	if not _same_key_set(actual, allowed):
		_failures.append(
			"SaveRepository public API must exactly match the manifest contract"
		)


func _validate_save_boundary_dependencies(source_path: String, source: String) -> void:
	if not source_path.begins_with("res://services/save/"):
		return
	_case_count += 1
	for forbidden_type: String in [
		"ContentRegistryService",
		"ContentRegistryReceiptAdapter",
		"ContentRegistryMigrationAdapter",
	]:
		if _count_matches("\\b" + forbidden_type + "\\b", source) > 0:
			_failures.append(
				"Save boundary depends on concrete content infrastructure: %s -> %s"
				% [source_path, forbidden_type]
			)


func _validate_domain_dependency_boundary(source_path: String, source: String) -> void:
	if not source_path.begins_with("res://domain/"):
		return
	_case_count += 1
	for forbidden_type: String in [
		"Node",
		"Resource",
		"Callable",
		"SceneTree",
		"NodePath",
		"FileAccess",
		"ObjectID",
		"get_instance_id",
	]:
		if _count_matches("\\b" + forbidden_type + "\\b", source) > 0:
			_failures.append(
				"Domain source depends on a forbidden engine type/API: %s -> %s"
				% [source_path, forbidden_type]
			)


func _validate_foundation_spec() -> void:
	var texts: Array[String] = []
	var expected_requirements: Dictionary = _set_from_strings(FOUNDATION_REQUIREMENTS)
	for path: String in FOUNDATION_SPEC_PATHS:
		_case_count += 1
		if not FileAccess.file_exists(path):
			_failures.append("Foundation spec file is missing: " + path)
			continue
		var text: String = FileAccess.get_file_as_string(path)
		texts.append(text)
		if not text.contains("Approved / Implementation gate passed"):
			_failures.append("Foundation spec gate is not approved: " + path)
		var file_requirements: Dictionary = {}
		for match_value: RegExMatch in _find_all(
			"REQ-(TECH|DATA|RNG|SAVE|CONTENT)-[0-9]{3}",
			text
		):
			file_requirements[match_value.get_string(0)] = true
		if not _same_key_set(file_requirements, expected_requirements):
			_failures.append("Foundation requirement set mismatch: " + path)
	if texts.size() != FOUNDATION_SPEC_PATHS.size():
		return

	var requirements_text: String = texts[0]
	var tasks_text: String = texts[2]
	var requirement_mapping: Dictionary = {}
	var s1_acceptance_ids: Dictionary = {}
	for match_value: RegExMatch in _find_all(
		'(?m)^\\|\\s*\\*\\*(S1-AC-[0-9]{3})\\*\\*\\s*\\|\\s*\\[(REQ-(?:TECH|DATA|RNG|SAVE|CONTENT)-[0-9]{3})\\]',
		requirements_text
	):
		var acceptance_id: String = match_value.get_string(1)
		var requirement_id: String = match_value.get_string(2)
		if s1_acceptance_ids.has(acceptance_id) or requirement_mapping.has(requirement_id):
			_failures.append("Duplicate foundation acceptance/requirement row: " + acceptance_id)
		s1_acceptance_ids[acceptance_id] = true
		requirement_mapping[requirement_id] = acceptance_id
	_case_count += 1
	if s1_acceptance_ids.size() != 23 or not _same_key_set(requirement_mapping, expected_requirements):
		_failures.append("Foundation requirements table must map exactly 23 REQ to 23 S1-AC")

	var task_mapping: Dictionary = {}
	for match_value: RegExMatch in _find_all(
		'(?m)^\\|\\s*(REQ-(?:TECH|DATA|RNG|SAVE|CONTENT)-[0-9]{3})\\s*\\|\\s*(S1-AC-[0-9]{3})\\s*\\|',
		tasks_text
	):
		var requirement_id: String = match_value.get_string(1)
		var acceptance_id: String = match_value.get_string(2)
		if task_mapping.has(requirement_id):
			_failures.append("Duplicate foundation task coverage row: " + requirement_id)
		task_mapping[requirement_id] = acceptance_id
	_case_count += 1
	if task_mapping != requirement_mapping:
		_failures.append("Foundation requirements/tasks mappings are not bidirectionally equal")

	var parsed_f: Dictionary = _classification_set(requirements_text, "F")
	var parsed_x: Dictionary = _classification_set(requirements_text, "X")
	var parsed_d: Dictionary = _classification_set(requirements_text, "D")
	_case_count += 4
	if not _same_key_set(parsed_f, _set_from_strings(FOUNDATION_F)):
		_failures.append("Foundation F classification must contain the locked 15 ACs")
	if not _same_key_set(parsed_x, _set_from_strings(FOUNDATION_X)):
		_failures.append("Foundation X classification must contain the locked 7 ACs")
	if not _same_key_set(parsed_d, _set_from_strings(FOUNDATION_D)):
		_failures.append("Foundation D classification must contain the locked 11 ACs")
	var union: Dictionary = {}
	var overlap: bool = false
	for classification: Dictionary in [parsed_f, parsed_x, parsed_d]:
		for acceptance_id: String in classification:
			if union.has(acceptance_id):
				overlap = true
			union[acceptance_id] = true
	if overlap or union.size() != 33:
		_failures.append("Foundation F/X/D classifications must be disjoint with union size 33")


func _classification_set(text: String, classification: String) -> Dictionary:
	for line: String in text.split("\n"):
		if line.begins_with("- **" + classification + "（"):
			var output: Dictionary = {}
			for match_value: RegExMatch in _find_all("AC-[0-9]{3}", line):
				output[match_value.get_string(0)] = true
			return output
	return {}


func _set_from_strings(values: Array[String]) -> Dictionary:
	var output: Dictionary = {}
	for value: String in values:
		output[value] = true
	return output


func _same_key_set(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left:
		if not right.has(key):
			return false
	return true


func _validate_public_api_types(source_path: String, source: String) -> void:
	for signature: RegExMatch in _find_all('(?ms)^(?:static\\s+)?func\\s+(?!_)([A-Za-z_][A-Za-z0-9_]*)\\s*\\((.*?)\\)\\s*(?:->\\s*([^:\n]+))?\\s*:', source):
		_case_count += 1
		var method_name: String = signature.get_string(1)
		var parameters: String = signature.get_string(2)
		var return_type: String = signature.get_string(3).strip_edges()
		for parameter: String in _split_top_level_parameters(parameters):
			var colon_index: int = parameter.find(":")
			var equals_index: int = parameter.find("=")
			if colon_index < 0 or (equals_index >= 0 and colon_index > equals_index):
				_failures.append("Public API parameter lacks a type: %s.%s(%s)" % [source_path, method_name, parameter.strip_edges()])
				continue
			var parameter_type: String = parameter.substr(
				colon_index + 1,
				(equals_index if equals_index >= 0 else parameter.length()) - colon_index - 1
			).strip_edges()
			if parameter_type == "Variant" or parameter_type.contains("Dictionary") or _contains_untyped_array(parameter_type):
				_failures.append("Public API exposes an untyped parameter: %s.%s" % [source_path, method_name])
		if return_type == "Variant":
			_failures.append("Public API exposes Variant: %s.%s" % [source_path, method_name])
		if return_type.is_empty():
			_failures.append("Public API lacks return annotation: %s.%s" % [source_path, method_name])


func _validate_no_public_dictionary(source_path: String, source: String) -> void:
	for signature: RegExMatch in _find_all('(?ms)^(?:static\\s+)?func\\s+(?!_)([A-Za-z_][A-Za-z0-9_]*)\\s*\\((.*?)\\)\\s*(?:->\\s*([^:\n]+))?\\s*:', source):
		var method_name: String = signature.get_string(1)
		var parameters: String = signature.get_string(2)
		var return_type: String = signature.get_string(3)
		if parameters.contains(": Dictionary") or return_type.contains("Dictionary") or _contains_untyped_array(parameters) or _contains_untyped_array(return_type):
			_failures.append("Public API exposes Dictionary/untyped Array: %s.%s" % [source_path, method_name])


func _validate_public_fields(source_path: String, source: String) -> void:
	for field_match: RegExMatch in _find_all(
		'(?m)^(?:@[A-Za-z_][^\\n]*\\s+)?var\\s+(?!_)([A-Za-z_][A-Za-z0-9_]*)(?:\\s*:\\s*([^=\\n]+))?',
		source
	):
		_case_count += 1
		var field_name: String = field_match.get_string(1)
		var field_type: String = field_match.get_string(2).strip_edges()
		if field_type.is_empty():
			_failures.append("Public field lacks a type: %s.%s" % [source_path, field_name])
		elif field_type == "Variant" or field_type.contains("Dictionary") or _contains_untyped_array(field_type):
			_failures.append("Public field exposes an untyped container/value: %s.%s" % [source_path, field_name])


func _validate_signal_types(source_path: String, source: String) -> void:
	for signal_match: RegExMatch in _find_all(
		'(?m)^signal\\s+([A-Za-z_][A-Za-z0-9_]*)(?:\\(([^)]*)\\))?',
		source
	):
		_case_count += 1
		var signal_name: String = signal_match.get_string(1)
		for parameter: String in _split_top_level_parameters(signal_match.get_string(2)):
			if parameter.find(":") < 0:
				_failures.append("Signal parameter lacks a type: %s.%s" % [source_path, signal_name])
				continue
			var signal_type: String = parameter.substr(parameter.find(":") + 1).strip_edges()
			if signal_type == "Variant" or signal_type.contains("Dictionary") or _contains_untyped_array(signal_type):
				_failures.append("Signal exposes an untyped value: %s.%s" % [source_path, signal_name])


func _validate_silent_null_contract(source_path: String, source: String) -> void:
	for method_match: RegExMatch in _find_all(
		'(?ms)^(?:static\\s+)?func\\s+(?!_)([A-Za-z_][A-Za-z0-9_]*)\\s*\\(.*?\\)\\s*(?:->\\s*[^:\n]+)?\\s*:(.*?)(?=^(?:static\\s+)?func\\s+|\\z)',
		source
	):
		var method_name: String = method_match.get_string(1)
		var body: String = method_match.get_string(2)
		var explicitly_nullable: bool = source_path.ends_with("/content_registry_service.gd") \
			and method_name == "try_resolve"
		explicitly_nullable = explicitly_nullable \
			or method_name.begins_with("try_") \
			or method_name.begins_with("from_") \
			or method_name == "validate"
		if not explicitly_nullable and body.contains("return null"):
			_failures.append("Public API has a silent-null path: %s.%s" % [source_path, method_name])


func _validate_result_mutual_exclusion(source_path: String, source: String) -> void:
	if not source_path.ends_with("_result.gd") \
		or _count_matches('(?m)^var\\s+ok\\s*:\\s*bool', source) == 0:
		return
	_case_count += 1
	var init_matches: Array[RegExMatch] = _find_all(
		'(?ms)^func\\s+_init\\s*\\((.*?)\\)\\s*->\\s*void\\s*:(.*?)(?=^(?:static\\s+)?func\\s+|\\z)',
		source
	)
	if init_matches.size() != 1:
		_failures.append("Result must have one required constructor: " + source_path)
		return
	var init_parameters: Array[String] = _split_top_level_parameters(
		init_matches[0].get_string(1)
	)
	if init_parameters.is_empty() \
		or not init_parameters[0].contains(": bool") \
		or init_parameters[0].contains("="):
		_failures.append("Result constructor must require p_ok: bool: " + source_path)
	for init_parameter: String in init_parameters:
		if init_parameter.contains("="):
			_failures.append("Result constructor parameters must all be required: " + source_path)
			break
	var init_body: String = init_matches[0].get_string(2)
	var guard_count: int = _count_matches(
		'ResultInvariant\\.require\\s*\\(\\s*p_ok\\s*,\\s*p_error\\s*,',
		init_body
	)
	var guard_index: int = init_body.find("ResultInvariant.require")
	var state_write_index: int = init_body.find("ok = p_ok")
	if guard_count != 1:
		_failures.append(
			"Result constructor must enforce the canonical mutual-exclusion invariant: "
			+ source_path
		)
	elif state_write_index < 0 or guard_index > state_write_index:
		_failures.append(
			"Result constructor must enforce its invariant before writing state: "
			+ source_path
		)
	if _count_matches('(?ms)static\\s+func\\s+[A-Za-z_][A-Za-z0-9_]*.*?return\\s+[A-Za-z_][A-Za-z0-9_]*\\.new\\(\\s*true', source) == 0:
		_failures.append("Result lacks a constructor-backed success factory: " + source_path)
	if _count_matches('(?ms)static\\s+func\\s+[A-Za-z_][A-Za-z0-9_]*.*?return\\s+[A-Za-z_][A-Za-z0-9_]*\\.new\\(\\s*false', source) == 0:
		_failures.append("Result lacks a constructor-backed failure factory: " + source_path)


func _validate_result_invariant_helper() -> void:
	_case_count += 1
	var helper_path: String = "res://domain/common/result_invariant.gd"
	if not FileAccess.file_exists(helper_path):
		_failures.append("Result invariant helper is missing")
		return
	var source: String = FileAccess.get_file_as_string(helper_path)
	for required_implementation: String in [
		"return p_error == null and p_success_payload_valid",
		"return p_error != null and p_failure_payload_clear",
		"assert(",
		"ERROR_MESSAGE",
	]:
		if not source.contains(required_implementation):
			_failures.append(
				"Result invariant helper implementation is incomplete: "
				+ required_implementation
			)


func _validate_error_shape(
	class_name_value: String,
	source_path: String,
	source: String
) -> void:
	var required_error_classes: Array[String] = [
		"ContentResolveError", "RunTransitionError", "CommandError",
		"SaveError", "LoadError", "MigrationError", "RngDeriveError",
		"PinnedCatalogReceiptError",
	]
	if not required_error_classes.has(class_name_value):
		return
	_case_count += 1
	for required_field: String in [
		"var code: StringName",
		"var field_path: StringName",
		"var source_id: OptionalStringNameValue",
		"var diagnostic_values: Array[DiagnosticValue]",
	]:
		if not source.contains(required_field):
			_failures.append("Public service error lacks common field in %s: %s" % [source_path, required_field])


func _split_top_level_parameters(value: String) -> Array[String]:
	var output: Array[String] = []
	var current: String = ""
	var depth: int = 0
	var in_string: bool = false
	var escaped: bool = false
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1)
		if in_string:
			current += character
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				in_string = false
			continue
		if character == "\"":
			in_string = true
			current += character
		elif character in ["(", "[", "{"]:
			depth += 1
			current += character
		elif character in [")", "]", "}"]:
			depth -= 1
			current += character
		elif character == "," and depth == 0:
			if not current.strip_edges().is_empty():
				output.append(current.strip_edges())
			current = ""
		else:
			current += character
	if not current.strip_edges().is_empty():
		output.append(current.strip_edges())
	return output


func _contains_untyped_array(value: String) -> bool:
	var regex: RegEx = RegEx.new()
	if regex.compile('\\bArray\\b(?!\\s*\\[)') != OK:
		return false
	return regex.search(value) != null


func _collect_files(root_path: String, suffix: String, output: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(root_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var full_path: String = root_path.path_join(entry)
		if directory.current_is_dir():
			if entry != "." and entry != "..":
				_collect_files(full_path, suffix, output)
		elif entry.ends_with(suffix):
			output.append(full_path)
		entry = directory.get_next()
	directory.list_dir_end()
	output.sort()


func _find_all(pattern: String, text: String) -> Array[RegExMatch]:
	var regex: RegEx = RegEx.new()
	var compile_error: int = regex.compile(pattern)
	if compile_error != OK:
		_infrastructure_error = true
		_failures.append("Runner regex failed to compile: " + pattern)
		return []
	return regex.search_all(text)


func _count_matches(pattern: String, text: String) -> int:
	return _find_all(pattern, text).size()


func _finish() -> void:
	var completed: Array[String] = ["manifest", "links", "ids", "traceability", "aggregate_hash", "source_contracts"]
	var deferred: Array[String] = ["full_run_gameplay_ac"]
	var report: Dictionary = Support.base_report("spec-contract", _started_at_utc, completed, deferred)
	report["case_count"] = _case_count
	report["failures"] = _failures
	report["passed"] = _failures.is_empty()
	report["foundation_classification"] = _foundation_classification_report()
	var artifact_error: int = Support.write_json_artifact(ARTIFACT_PATH, report)
	if artifact_error != OK or _infrastructure_error:
		quit(3)
	elif _failures.is_empty():
		quit(0)
	else:
		quit(2)


func _foundation_classification_report() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for acceptance_id: String in FOUNDATION_F:
		output.append({
			"acceptance_id": acceptance_id,
			"classification": "F",
			"status": "contract_verified_requires_all_suites",
		})
	for acceptance_id: String in FOUNDATION_X:
		output.append({
			"acceptance_id": acceptance_id,
			"classification": "X",
			"status": "foundation_contract_verified_downstream_pending",
		})
	for acceptance_id: String in FOUNDATION_D:
		output.append({
			"acceptance_id": acceptance_id,
			"classification": "D",
			"status": "downstream_deferred",
		})
	return output
