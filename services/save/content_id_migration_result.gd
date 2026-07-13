class_name ContentIdMigrationResult
extends RefCounted

enum Disposition { ACTIVE, ALIAS, SAFE_ABSENT, SAFE_REPLACE, INCOMPATIBLE_REQUIRED }

var ok: bool
var disposition: Disposition
var resolved_id: OptionalStringNameValue
var error: ContentIdMigrationError

static func active(content_id: StringName) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.new(true, Disposition.ACTIVE, OptionalStringNameValue.new(content_id), null)

static func alias(resolved: StringName) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.new(true, Disposition.ALIAS, OptionalStringNameValue.new(resolved), null)

static func safe_absent() -> ContentIdMigrationResult:
	return ContentIdMigrationResult.new(true, Disposition.SAFE_ABSENT, null, null)

static func safe_replace(resolved: StringName) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.new(true, Disposition.SAFE_REPLACE, OptionalStringNameValue.new(resolved), null)

static func incompatible(error_value: ContentIdMigrationError) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.new(false, Disposition.INCOMPATIBLE_REQUIRED, null, error_value)

func _init(
	p_ok: bool,
	p_disposition: Disposition,
	p_resolved_id: OptionalStringNameValue,
	p_error: ContentIdMigrationError
) -> void:
	var success_payload_valid := (
		(
			p_disposition == Disposition.ACTIVE
			or p_disposition == Disposition.ALIAS
			or p_disposition == Disposition.SAFE_REPLACE
		)
		and p_resolved_id != null
	) or (
		p_disposition == Disposition.SAFE_ABSENT and p_resolved_id == null
	)
	var failure_payload_clear := (
		p_disposition == Disposition.INCOMPATIBLE_REQUIRED
		and p_resolved_id == null
	)
	ResultInvariant.require(
		p_ok, p_error, success_payload_valid, failure_payload_clear
	)
	ok = p_ok
	disposition = p_disposition
	resolved_id = p_resolved_id.deep_clone() if p_resolved_id != null else null
	error = p_error.deep_clone() if p_error != null else null

func deep_clone() -> ContentIdMigrationResult:
	return ContentIdMigrationResult.new(ok, disposition, resolved_id, error)
