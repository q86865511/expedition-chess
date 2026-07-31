class_name MigrationResult
extends RefCounted

var ok: bool
var source_schema: SourceSchemaVersionState
var target_schema_version: int
var canonical_json_text: OptionalStringValue
var root: SaveRoot
var profile: ProfileState
var run_status: LoadResult.RunStatus
var migration_receipt: RefCounted
var incompatible_content_ids: Array[StringName] = []
var diagnostics: Array[LoadDiagnostic] = []
var error: MigrationError

static func success(
	p_source_schema: SourceSchemaVersionState,
	p_canonical_json_text: String,
	p_root: SaveRoot,
	p_incompatible_content_ids: Array[StringName] = [],
	p_migration_receipt: RefCounted = null,
	p_diagnostics: Array[LoadDiagnostic] = []
) -> MigrationResult:
	return MigrationResult.new(
		true,
		p_source_schema,
		SaveJsonCodec.SCHEMA_VERSION,
		OptionalStringValue.new(p_canonical_json_text),
		p_root,
		p_root.profile,
		LoadResult.RunStatus.LOADED if p_root.run != null else LoadResult.RunStatus.NONE,
		p_migration_receipt,
		p_incompatible_content_ids,
		p_diagnostics,
		null
	)

static func incompatible_preserved(
	p_source_schema: SourceSchemaVersionState,
	p_original_json_text: String,
	p_profile: ProfileState,
	p_diagnostics: Array[LoadDiagnostic],
	p_incompatible_content_ids: Array[StringName] = []
) -> MigrationResult:
	return MigrationResult.new(
		true,
		p_source_schema,
		SaveJsonCodec.SCHEMA_VERSION,
		OptionalStringValue.new(p_original_json_text),
		null,
		p_profile,
		LoadResult.RunStatus.INCOMPATIBLE_PRESERVED,
		null,
		p_incompatible_content_ids,
		p_diagnostics,
		null
	)

static func failure(
	p_source_schema: SourceSchemaVersionState,
	p_error: MigrationError
) -> MigrationResult:
	return MigrationResult.new(
		false,
		p_source_schema,
		SaveJsonCodec.SCHEMA_VERSION,
		null,
		null,
		null,
		LoadResult.RunStatus.NONE,
		null,
		[],
		[],
		p_error
	)

func _init(
	p_ok: bool,
	p_source_schema: SourceSchemaVersionState,
	p_target_schema_version: int,
	p_canonical_json_text: OptionalStringValue,
	p_root: SaveRoot,
	p_profile: ProfileState,
	p_run_status: LoadResult.RunStatus,
	p_migration_receipt: RefCounted,
	p_incompatible_content_ids: Array[StringName],
	p_diagnostics: Array[LoadDiagnostic],
	p_error: MigrationError
) -> void:
	var success_payload_valid := (
		p_source_schema != null
		and p_canonical_json_text != null
		and p_profile != null
		and (
			(p_root != null and p_run_status != LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
			or (
				p_root == null
				and p_run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED
				and p_migration_receipt == null
			)
		)
	)
	var failure_payload_clear := (
		p_source_schema != null
		and p_canonical_json_text == null
		and p_root == null
		and p_profile == null
		and p_run_status == LoadResult.RunStatus.NONE
		and p_migration_receipt == null
		and p_incompatible_content_ids.is_empty()
		and p_diagnostics.is_empty()
	)
	ResultInvariant.require(
		p_ok,
		p_error,
		success_payload_valid,
		failure_payload_clear
	)
	ok = p_ok
	source_schema = p_source_schema.deep_clone()
	target_schema_version = p_target_schema_version
	canonical_json_text = p_canonical_json_text.deep_clone() if p_canonical_json_text != null else null
	root = p_root.deep_clone() if p_root != null else null
	profile = p_profile.deep_clone() if p_profile != null else null
	run_status = p_run_status
	migration_receipt = (
		p_migration_receipt.call("deep_clone")
		if p_migration_receipt != null and p_migration_receipt.has_method("deep_clone")
		else null
	)
	incompatible_content_ids.assign(p_incompatible_content_ids)
	for diagnostic: LoadDiagnostic in p_diagnostics:
		diagnostics.append(diagnostic.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
