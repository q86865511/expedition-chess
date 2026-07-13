class_name RunSessionFactory
extends RefCounted

var _registry: ContentRegistryService

func _init(p_registry: ContentRegistryService) -> void:
	_registry = p_registry

func create(profile: ProfileState, run: RunState) -> RunSessionBuildResult:
	if _registry == null \
		or profile == null \
		or run == null \
		or run.content_snapshot == null:
		return RunSessionBuildResult.failure(
			RunSessionBuildError.new(
				RunSessionBuildError.INPUT_INVALID,
				&"run.content_snapshot"
			)
		)
	if not run.content_snapshot.is_validated():
		return RunSessionBuildResult.failure(
			RunSessionBuildError.new(
				RunSessionBuildError.INPUT_INVALID,
				&"run.content_snapshot.validation"
			)
		)
	var receipt := _registry._receipt_for_digest(
		run.content_snapshot.manifest_digest_value()
	)
	if receipt == null:
		return RunSessionBuildResult.failure(
			RunSessionBuildError.new(
				RunSessionBuildError.PINNED_RECEIPT_MISSING,
				&"run.content_snapshot.manifest_digest"
			)
		)
	var expected_result := ContentSnapshotState.from_pinned_receipt(receipt)
	if not expected_result.ok \
		or not run.content_snapshot.canonical_equals(expected_result.snapshot):
		return RunSessionBuildResult.failure(
			RunSessionBuildError.new(
				RunSessionBuildError.SNAPSHOT_MISMATCH,
				&"run.content_snapshot"
			)
		)
	var handle_result := _registry.catalog_handle(
		run.content_snapshot.manifest_digest_value()
	)
	if not handle_result.ok or handle_result.value == null:
		return RunSessionBuildResult.failure(
			RunSessionBuildError.new(
				RunSessionBuildError.CATALOG_MISSING,
				&"run.content_snapshot.manifest_digest"
			)
		)
	var lease_result := _registry.acquire_catalog_lease(handle_result.value)
	if not lease_result.ok or lease_result.lease == null:
		return RunSessionBuildResult.failure(
			RunSessionBuildError.new(
				RunSessionBuildError.LEASE_FAILED,
				&"run.content_snapshot.manifest_digest"
			)
		)
	return RunSessionBuildResult.success(
		RunSession.new(profile, run, lease_result.lease)
	)
