class_name SaveDecodeResult
extends RefCounted

var ok: bool
var root: SaveRoot
var profile: ProfileState
var run_status: LoadResult.RunStatus
var incompatible_content_ids: Array[StringName] = []
var diagnostics: Array[LoadDiagnostic] = []
var error: SaveCodecError

static func success(
	p_root: SaveRoot,
	p_run_status: LoadResult.RunStatus = LoadResult.RunStatus.LOADED,
	p_incompatible_content_ids: Array[StringName] = [],
	p_diagnostics: Array[LoadDiagnostic] = []
) -> SaveDecodeResult:
	return SaveDecodeResult.new(
		true, p_root, p_root.profile, p_run_status,
		p_incompatible_content_ids, p_diagnostics, null
	)

static func incompatible(
	p_profile: ProfileState,
	p_incompatible_content_ids: Array[StringName],
	p_diagnostics: Array[LoadDiagnostic]
) -> SaveDecodeResult:
	return SaveDecodeResult.new(
		true, null, p_profile, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED,
		p_incompatible_content_ids, p_diagnostics, null
	)

static func failure(p_error: SaveCodecError) -> SaveDecodeResult:
	return SaveDecodeResult.new(false, null, null, LoadResult.RunStatus.NONE, [], [], p_error)

func _init(
	p_ok: bool,
	p_root: SaveRoot,
	p_profile: ProfileState,
	p_run_status: LoadResult.RunStatus,
	p_incompatible_content_ids: Array[StringName],
	p_diagnostics: Array[LoadDiagnostic],
	p_error: SaveCodecError
) -> void:
	var success_payload_valid := (
		p_profile != null
		and (
			p_root != null
			or p_run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED
		)
	)
	var failure_payload_clear := (
		p_root == null
		and p_profile == null
		and p_run_status == LoadResult.RunStatus.NONE
		and p_incompatible_content_ids.is_empty()
		and p_diagnostics.is_empty()
	)
	ResultInvariant.require(
		p_ok, p_error, success_payload_valid, failure_payload_clear
	)
	ok = p_ok
	root = p_root.deep_clone() if p_root != null else null
	profile = p_profile.deep_clone() if p_profile != null else null
	run_status = p_run_status
	incompatible_content_ids.assign(p_incompatible_content_ids)
	for diagnostic: LoadDiagnostic in p_diagnostics:
		diagnostics.append(diagnostic.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
