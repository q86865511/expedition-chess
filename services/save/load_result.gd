class_name LoadResult
extends RefCounted

enum ProfileStatus { LOADED, NOT_FOUND, INVALID }
enum RunStatus { NONE, LOADED, INCOMPATIBLE_PRESERVED }

var ok: bool
var profile_status: ProfileStatus
var run_status: RunStatus
var profile: ProfileState
var run: RunState
var preserved_source_path: OptionalStringValue
var recovery_diagnostics: Array[LoadDiagnostic] = []
var error: LoadError
var _committed_digest: String = ""
var _commit_capability: PersistenceCommitCapability

static func success(
	p_profile: ProfileState,
	p_run: RunState,
	p_run_status: RunStatus,
	p_preserved_source_path: OptionalStringValue = null,
	p_diagnostics: Array[LoadDiagnostic] = []
) -> LoadResult:
	return LoadResult.new(
		true, ProfileStatus.LOADED, p_run_status, p_profile, p_run,
		p_preserved_source_path, p_diagnostics, null, "", null
	)

static func _repository_success(
	p_profile: ProfileState,
	p_run: RunState,
	p_run_status: RunStatus,
	p_preserved_source_path: OptionalStringValue,
	p_diagnostics: Array[LoadDiagnostic],
	p_committed_digest: String,
	p_capability: PersistenceCommitCapability
) -> LoadResult:
	return LoadResult.new(
		true, ProfileStatus.LOADED, p_run_status, p_profile, p_run,
		p_preserved_source_path, p_diagnostics, null,
		p_committed_digest, p_capability
	)

static func failure(p_error: LoadError, p_profile_status: ProfileStatus = ProfileStatus.INVALID) -> LoadResult:
	return LoadResult.new(
		false, p_profile_status, RunStatus.NONE, null, null, null, [], p_error,
		"", null
	)

func _init(
	p_ok: bool,
	p_profile_status: ProfileStatus,
	p_run_status: RunStatus,
	p_profile: ProfileState,
	p_run: RunState,
	p_preserved_source_path: OptionalStringValue,
	p_recovery_diagnostics: Array[LoadDiagnostic],
	p_error: LoadError,
	p_committed_digest: String,
	p_commit_capability: PersistenceCommitCapability
) -> void:
	var run_payload_matches_status := (
		(p_run_status == RunStatus.LOADED and p_run != null)
		or (
			p_run_status != RunStatus.LOADED
			and p_run == null
		)
	)
	var commit_metadata_matches := (
		(p_committed_digest.is_empty() and p_commit_capability == null)
		or (
			not p_committed_digest.is_empty()
			and p_commit_capability != null
		)
	)
	var success_payload_valid := (
		p_profile_status == ProfileStatus.LOADED
		and p_profile != null
		and run_payload_matches_status
		and commit_metadata_matches
	)
	var failure_payload_clear := (
		p_run_status == RunStatus.NONE
		and p_profile == null
		and p_run == null
		and p_preserved_source_path == null
		and p_recovery_diagnostics.is_empty()
		and p_committed_digest.is_empty()
		and p_commit_capability == null
	)
	ResultInvariant.require(
		p_ok, p_error, success_payload_valid, failure_payload_clear
	)
	ok = p_ok
	profile_status = p_profile_status
	run_status = p_run_status
	profile = p_profile.deep_clone() if p_profile != null else null
	run = p_run.deep_clone() if p_run != null else null
	preserved_source_path = p_preserved_source_path.deep_clone() if p_preserved_source_path != null else null
	for diagnostic: LoadDiagnostic in p_recovery_diagnostics:
		recovery_diagnostics.append(diagnostic.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
	_committed_digest = p_committed_digest
	_commit_capability = p_commit_capability
