class_name SaveResult
extends RefCounted

var ok: bool
var committed_digest: OptionalStringValue
var warnings: Array[SaveWarning] = []
var error: SaveError
var _commit_capability: PersistenceCommitCapability

static func success(p_digest: String, p_warnings: Array[SaveWarning] = []) -> SaveResult:
	return SaveResult.new(true, OptionalStringValue.new(p_digest), p_warnings, null, null)

static func _repository_success(
	p_digest: String,
	p_warnings: Array[SaveWarning],
	p_capability: PersistenceCommitCapability
) -> SaveResult:
	return SaveResult.new(
		true, OptionalStringValue.new(p_digest), p_warnings, null, p_capability
	)

static func failure(p_error: SaveError) -> SaveResult:
	return SaveResult.new(false, null, [], p_error, null)

func _init(
	p_ok: bool,
	p_committed_digest: OptionalStringValue,
	p_warnings: Array[SaveWarning],
	p_error: SaveError,
	p_commit_capability: PersistenceCommitCapability
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_committed_digest != null,
		p_committed_digest == null
			and p_warnings.is_empty()
			and p_commit_capability == null
	)
	ok = p_ok
	committed_digest = p_committed_digest.deep_clone() if p_committed_digest != null else null
	for warning: SaveWarning in p_warnings:
		warnings.append(warning.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
	_commit_capability = p_commit_capability
