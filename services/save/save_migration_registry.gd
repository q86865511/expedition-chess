class_name SaveMigrationRegistry
extends RefCounted

const _SCHEMA_ZERO_KEYS: Array[String] = [
	"schema_version", "content_version", "app_version", "rng_version",
	"saved_at_utc", "profile", "run",
]
const _SCHEMA_ONE_SNAPSHOT_KEYS: Array[String] = [
	"content_version", "enabled_content_ids", "economy_config_id",
	"reward_table_ids", "map_node_def_ids", "challenge_unlock_def_ids",
	"meta_reward_table_id", "manifest_digest",
]
const MIGRATION_RECEIPT_DIAGNOSTIC: StringName = &"LOAD_CONTENT_GENERATION_MIGRATED"

var _codec: SaveJsonCodec
var _generation_port: ContentGenerationMigrationPort


func _init(
	codec: SaveJsonCodec,
	generation_port: ContentGenerationMigrationPort = null
) -> void:
	_codec = codec
	_generation_port = generation_port if generation_port != null else ContentGenerationMigrationPort.new()


func migrate(raw_json_text: String) -> MigrationResult:
	var parser := JSON.new()
	if parser.parse(raw_json_text) != OK or not parser.data is Dictionary:
		return _failure(UnknownSourceSchemaVersion.new(), MigrationError.PARSE_INVALID, &"root")
	var data: Dictionary = (parser.data as Dictionary).duplicate(true)
	if not data.has("schema_version") or not _integer_value(data["schema_version"]):
		return _failure(UnknownSourceSchemaVersion.new(), MigrationError.PARSE_INVALID, &"schema_version")
	var source_schema := int(data["schema_version"])
	var known := KnownSourceSchemaVersion.new(source_schema)
	if source_schema < 0 or source_schema > SaveJsonCodec.SCHEMA_VERSION:
		return _failure(known, MigrationError.STEP_MISSING, &"schema_version")
	if source_schema == SaveJsonCodec.SCHEMA_VERSION:
		return _decode_current(raw_json_text, known)
	if source_schema == 0:
		var zero_error := _upgrade_zero_to_one(data)
		if not zero_error.is_empty():
			return _failure(known, MigrationError.PARSE_INVALID, zero_error)
	elif source_schema != 1:
		return _failure(known, MigrationError.STEP_MISSING, &"schema_version")
	return _upgrade_one_to_two(data, raw_json_text, known)


func _decode_current(raw_json_text: String, source_schema: SourceSchemaVersionState) -> MigrationResult:
	var decoded := _codec.decode_text(raw_json_text)
	if not decoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, decoded.error.field_path)
	if decoded.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
		return MigrationResult.incompatible_preserved(
			source_schema,
			raw_json_text,
			decoded.profile,
			decoded.diagnostics,
			decoded.incompatible_content_ids
		)
	if decoded.root == null:
		return _failure(source_schema, MigrationError.PARSE_INVALID, &"root")
	return MigrationResult.success(
		source_schema,
		raw_json_text,
		decoded.root,
		decoded.incompatible_content_ids,
		null,
		decoded.diagnostics
	)


func _upgrade_zero_to_one(data: Dictionary) -> StringName:
	if not _exact_keys(data, _SCHEMA_ZERO_KEYS):
		return &"root"
	data["schema_version"] = 1
	data["hash_version"] = 1
	return &""


func _upgrade_one_to_two(
	data: Dictionary,
	original_json_text: String,
	source_schema: SourceSchemaVersionState
) -> MigrationResult:
	var profile := _decode_profile_for_preservation(data)
	if profile == null:
		return _failure(source_schema, MigrationError.PARSE_INVALID, &"profile")
	if data.get("run") == null:
		data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
		return _decode_and_canonicalize(data, source_schema)
	if not data["run"] is Dictionary:
		return _failure(source_schema, MigrationError.PARSE_INVALID, &"run")
	var run_data: Dictionary = data["run"]
	if not _active_run_can_change_generation(run_data):
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			MigrationError.RUN_INCOMPATIBLE_PRESERVED,
			&"run"
		)
	var request := _generation_request(run_data)
	if request == null:
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			MigrationError.GENERATION_MIGRATION_FAILED,
			&"run.content_snapshot"
		)
	var migrated := _generation_port.migrate_generation(request)
	if not migrated.ok:
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			migrated.error.code,
			migrated.error.field_path
		)
	if not _generation_result_matches(request, migrated):
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"run.content_snapshot"
		)
	_apply_target_receipt(data, run_data, migrated.target_receipt)
	var decoded := _decode_candidate(data)
	if not decoded.ok or decoded.root == null:
		var path := decoded.error.field_path if decoded.error != null else &"root"
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			ContentGenerationMigrationError.TARGET_MISMATCH,
			path
		)
	var encoded := _codec.encode(decoded.root)
	if not encoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, encoded.error.field_path)
	var receipt_values: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"receipt_digest", migrated.migration_receipt.receipt_digest),
		DiagnosticValue.from_string(&"target_manifest_digest", migrated.migration_receipt.target_manifest_digest),
	]
	var diagnostics: Array[LoadDiagnostic] = [
		LoadDiagnostic.new(MIGRATION_RECEIPT_DIAGNOSTIC, &"run.content_snapshot", receipt_values),
	]
	return MigrationResult.success(
		source_schema,
		encoded.json_text.value,
		decoded.root,
		[],
		migrated.migration_receipt,
		diagnostics
	)


func _decode_profile_for_preservation(data: Dictionary) -> ProfileState:
	var profile_only := data.duplicate(true)
	profile_only["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
	profile_only["run"] = null
	var decoded := _codec._decode_root(profile_only)
	return decoded.profile if decoded.ok else null


func _decode_and_canonicalize(
	data: Dictionary,
	source_schema: SourceSchemaVersionState
) -> MigrationResult:
	var decoded := _decode_candidate(data)
	if not decoded.ok or decoded.root == null:
		var path := decoded.error.field_path if decoded.error != null else &"root"
		return _failure(source_schema, MigrationError.PARSE_INVALID, path)
	var encoded := _codec.encode(decoded.root)
	if not encoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, encoded.error.field_path)
	return MigrationResult.success(
		source_schema,
		encoded.json_text.value,
		decoded.root,
		decoded.incompatible_content_ids,
		null,
		decoded.diagnostics
	)


func _decode_candidate(data: Dictionary) -> SaveDecodeResult:
	data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
	return _codec._decode_root(data)


func _active_run_can_change_generation(run_data: Dictionary) -> bool:
	if run_data.get("run_phase") != "MAP" or run_data.get("current_node_id") != null:
		return false
	var resolution: Variant = run_data.get("resolution_state")
	if not resolution is Dictionary or (resolution as Dictionary).get("kind") != "idle":
		return false
	var map_value: Variant = run_data.get("map_state")
	if not map_value is Dictionary:
		return false
	var map_data: Dictionary = map_value
	if map_data.get("current_node_id") != null:
		return false
	var nodes_value: Variant = map_data.get("nodes")
	if not nodes_value is Array:
		return false
	for node_value: Variant in nodes_value:
		if not node_value is Dictionary or (node_value as Dictionary).get("encounter_preview") != null:
			return false
	return true


func _generation_request(run_data: Dictionary) -> ContentGenerationMigrationRequest:
	var snapshot_value: Variant = run_data.get("content_snapshot")
	if not snapshot_value is Dictionary:
		return null
	var snapshot: Dictionary = snapshot_value
	if not _exact_keys(snapshot, _SCHEMA_ONE_SNAPSHOT_KEYS):
		return null
	for scalar_key: String in [
		"content_version", "economy_config_id", "meta_reward_table_id", "manifest_digest"
	]:
		if not snapshot.get(scalar_key) is String:
			return null
	var enabled: Variant = _name_array(snapshot.get("enabled_content_ids"))
	var rewards: Variant = _name_array(snapshot.get("reward_table_ids"))
	var nodes: Variant = _name_array(snapshot.get("map_node_def_ids"))
	var challenges: Variant = _name_array(snapshot.get("challenge_unlock_def_ids"))
	if enabled == null or rewards == null or nodes == null or challenges == null:
		return null
	return ContentGenerationMigrationRequest.new(
		snapshot["content_version"],
		snapshot["manifest_digest"],
		enabled,
		StringName(snapshot["economy_config_id"]),
		rewards,
		nodes,
		challenges,
		StringName(snapshot["meta_reward_table_id"])
	)


func _generation_result_matches(
	request: ContentGenerationMigrationRequest,
	result: ContentGenerationMigrationResult
) -> bool:
	if result == null or not result.ok or result.target_receipt == null \
		or result.migration_receipt == null:
		return false
	var receipt := result.migration_receipt
	return receipt.source_manifest_digest == request.source_manifest_digest \
		and receipt.target_manifest_digest == result.target_receipt.manifest_digest \
		and receipt.from_codec == 1 \
		and receipt.to_codec == 2 \
		and result.target_receipt.content_codec_version == 2


func _apply_target_receipt(
	root_data: Dictionary,
	run_data: Dictionary,
	receipt: PinnedCatalogBuildReceipt
) -> void:
	root_data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
	root_data["content_version"] = receipt.content_version
	var snapshot: Dictionary = run_data["content_snapshot"]
	snapshot["content_version"] = receipt.content_version
	snapshot["enabled_content_ids"] = _strings(receipt.active_entry_ids)
	snapshot["economy_config_id"] = String(receipt.economy_config_id)
	snapshot["reward_table_ids"] = _strings(receipt.reward_table_ids)
	snapshot["map_node_def_ids"] = _strings(receipt.map_node_def_ids)
	snapshot["challenge_unlock_def_ids"] = _strings(receipt.challenge_unlock_def_ids)
	snapshot["meta_reward_table_id"] = String(receipt.meta_reward_table_id)
	snapshot["manifest_digest"] = receipt.manifest_digest
	if _has_property(receipt, &"combat_config_id"):
		snapshot["combat_config_id"] = String(receipt.get("combat_config_id"))


func _name_array(value: Variant) -> Variant:
	if not value is Array:
		return null
	var output: Array[StringName] = []
	for item: Variant in value:
		if not item is String:
			return null
		output.append(StringName(item))
	return output


func _strings(values: Array[StringName]) -> Array[String]:
	var output: Array[String] = []
	for value: StringName in values:
		output.append(String(value))
	return output


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _exact_keys(data: Dictionary, expected: Array[String]) -> bool:
	if data.size() != expected.size():
		return false
	for key: String in expected:
		if not data.has(key):
			return false
	return true


func _integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floor(value) == value)


func _incompatible(
	source_schema: SourceSchemaVersionState,
	original_json_text: String,
	profile: ProfileState,
	code: StringName,
	path: StringName
) -> MigrationResult:
	var diagnostics: Array[LoadDiagnostic] = [LoadDiagnostic.new(code, path)]
	return MigrationResult.incompatible_preserved(
		source_schema,
		original_json_text,
		profile,
		diagnostics
	)


func _failure(
	source_schema: SourceSchemaVersionState,
	code: StringName,
	path: StringName
) -> MigrationResult:
	return MigrationResult.failure(source_schema, MigrationError.new(code, path))
