class_name MigrationResult
extends RefCounted

var ok: bool
var source_schema: SourceSchemaVersionState
var target_schema_version: int
var canonical_json_text: OptionalStringValue
var root: SaveRoot
var incompatible_content_ids: Array[StringName] = []
var error: MigrationError

static func success(
	p_source_schema: SourceSchemaVersionState,
	p_canonical_json_text: String,
	p_root: SaveRoot,
	p_incompatible_content_ids: Array[StringName] = []
) -> MigrationResult:
	return MigrationResult.new(
		true, p_source_schema, 1, OptionalStringValue.new(p_canonical_json_text),
		p_root, p_incompatible_content_ids, null
	)

static func failure(
	p_source_schema: SourceSchemaVersionState,
	p_error: MigrationError
) -> MigrationResult:
	return MigrationResult.new(false, p_source_schema, 1, null, null, [], p_error)

func _init(
	p_ok: bool,
	p_source_schema: SourceSchemaVersionState,
	p_target_schema_version: int,
	p_canonical_json_text: OptionalStringValue,
	p_root: SaveRoot,
	p_incompatible_content_ids: Array[StringName],
	p_error: MigrationError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_source_schema != null
			and p_canonical_json_text != null
			and p_root != null,
		p_source_schema != null
			and p_canonical_json_text == null
			and p_root == null
			and p_incompatible_content_ids.is_empty()
	)
	ok = p_ok
	source_schema = p_source_schema.deep_clone()
	target_schema_version = p_target_schema_version
	canonical_json_text = p_canonical_json_text.deep_clone() if p_canonical_json_text != null else null
	root = p_root.deep_clone() if p_root != null else null
	incompatible_content_ids.assign(p_incompatible_content_ids)
	error = p_error.deep_clone() if p_error != null else null
