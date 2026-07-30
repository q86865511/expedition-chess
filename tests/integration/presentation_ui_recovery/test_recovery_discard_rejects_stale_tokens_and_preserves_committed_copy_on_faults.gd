extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_recovery/recovery_test_support.gd"
)
const TOKEN_PATH := "res://app/state/retained_run_recovery_token.gd"


func test_recovery_discard_rejects_stale_tokens_and_preserves_committed_copy_on_faults() -> void:
	var probe: Dictionary = Support.seeded_context(self)
	assert_true(probe["save_result"].ok, "fixture save must succeed")
	assert_true(probe["loaded"].ok, "fixture load must succeed")
	var service: Variant = Support.require_service(self, probe["repository"])
	if service == null:
		return

	_assert_decoded_and_opaque_token_shape(service, probe)
	_assert_wrong_tokens_are_zero_write(service)
	_assert_public_load_and_write_make_tokens_stale()
	_assert_replaced_committed_bytes_are_rejected_by_fresh_digest()
	_assert_archive_and_clear_save_faults_preserve_restartable_committed_copy()
	_assert_success_orders_archive_before_clear_and_existing_digest_is_idempotent()


func _assert_decoded_and_opaque_token_shape(
	service: Variant,
	context: Dictionary
) -> void:
	var repository: SaveRepository = context["repository"]
	var loaded: LoadResult = context["loaded"]
	var expected_run_id: StringName = StringName(context["root"].run.run_id)
	var decoded: RetainedRunRecoveryToken = Support.issue_token(
		self, service, loaded, expected_run_id
	)
	var opaque: RetainedRunRecoveryToken = Support.issue_token(
		self, service, loaded, &""
	)
	if decoded == null or opaque == null:
		return
	for token: RetainedRunRecoveryToken in [decoded, opaque]:
		assert_true(
			token._repository_identity == repository._repository_identity_token(),
			"token must bind the issuing repository identity"
		)
		assert_eq(
			token._operation_epoch,
			repository._current_operation_epoch(),
			"token must bind the load operation epoch"
		)
		assert_eq(
			token._committed_file_digest,
			context["old_digest"],
			"token digest must be SHA-256 of the complete committed file"
		)
	assert_eq(decoded._expected_run_id, expected_run_id)
	assert_false(decoded.is_opaque())
	assert_true(opaque._expected_run_id.is_empty())
	assert_true(opaque.is_opaque())
	var token_source: String = FileAccess.get_file_as_string(TOKEN_PATH)
	assert_false(
		token_source.contains("_run_bytes_digest"),
		"opaque recovery must not invent a run digest"
	)


func _assert_wrong_tokens_are_zero_write(_probe_service: Variant) -> void:
	var cases: Array[Dictionary] = [
		{"label": "decoded wrong repository", "kind": "decoded_repository"},
		{"label": "decoded wrong expected run", "kind": "decoded_run"},
		{"label": "opaque wrong repository", "kind": "opaque_repository"},
		{"label": "opaque wrong committed digest", "kind": "opaque_digest"},
	]
	for case: Dictionary in cases:
		var context: Dictionary = Support.seeded_context(self)
		var storage: Variant = context["storage"]
		var repository: SaveRepository = context["repository"]
		var service: Variant = Support.require_service(self, repository)
		if service == null:
			return
		var expected_run_id: StringName = StringName(context["root"].run.run_id)
		var token: RetainedRunRecoveryToken
		match String(case["kind"]):
			"decoded_repository":
				token = Support.token_with(
					RefCounted.new(),
					repository._current_operation_epoch(),
					context["old_digest"],
					expected_run_id,
					&"decoded_wrong_repository"
				)
			"decoded_run":
				token = Support.token_with(
					repository._repository_identity_token(),
					repository._current_operation_epoch(),
					context["old_digest"],
					&"run.replaced",
					&"decoded_wrong_run"
				)
			"opaque_repository":
				token = Support.token_with(
					RefCounted.new(),
					repository._current_operation_epoch(),
					context["old_digest"],
					&"",
					&"opaque_wrong_repository"
				)
			_:
				token = Support.token_with(
					repository._repository_identity_token(),
					repository._current_operation_epoch(),
					"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
					&"",
					&"opaque_wrong_digest"
				)
		storage.reset_journal()
		var result: Variant = Support.discard(self, service, token)
		assert_false(Support.result_ok(result), String(case["label"]))
		_assert_zero_clear_and_original_main(storage, context, String(case["label"]))


func _assert_public_load_and_write_make_tokens_stale() -> void:
	for competing_operation: String in ["load", "write"]:
		var context: Dictionary = Support.seeded_context(self)
		var storage: Variant = context["storage"]
		var repository: SaveRepository = context["repository"]
		var service: Variant = Support.require_service(self, repository)
		if service == null:
			return
		var token: RetainedRunRecoveryToken = Support.issue_token(
			self,
			service,
			context["loaded"],
			StringName(context["root"].run.run_id)
		)
		if token == null:
			return
		if competing_operation == "load":
			var competing_load: LoadResult = repository.load()
			assert_true(competing_load.ok)
		else:
			var competing_save: SaveResult = repository.save(context["root"])
			assert_true(competing_save.ok)
		storage.reset_journal()
		var result: Variant = Support.discard(self, service, token)
		assert_false(
			Support.result_ok(result),
			"another public %s must stale the token" % competing_operation
		)
		assert_true(
			storage.has_exact_copy(context["old_bytes"], context["archive_path"]),
			"stale rejection must retain a byte-identical committed copy"
		)
		var restart_repository: SaveRepository = SaveRootFixture.create_repository(storage)
		add_child_autofree(restart_repository)
		var restarted: LoadResult = restart_repository.load()
		assert_true(restarted.ok)
		assert_eq(restarted.run_status, LoadResult.RunStatus.LOADED)


func _assert_replaced_committed_bytes_are_rejected_by_fresh_digest() -> void:
	var context: Dictionary = Support.seeded_context(self)
	var storage: Variant = context["storage"]
	var repository: SaveRepository = context["repository"]
	var replacement: SaveRoot = context["root"].deep_clone()
	replacement.saved_at_utc = "2026-07-13T00:00:01Z"
	var replacement_save: SaveResult = repository.save(replacement)
	assert_true(replacement_save.ok)
	var current_epoch: int = repository._current_operation_epoch()
	var token: RetainedRunRecoveryToken = Support.token_with(
		repository._repository_identity_token(),
		current_epoch,
		context["old_digest"],
		StringName(context["root"].run.run_id),
		&"replaced_bytes_probe"
	)
	var service: Variant = Support.require_service(self, repository)
	if service == null:
		return
	storage.reset_journal()
	var result: Variant = Support.discard(self, service, token)
	assert_false(
		Support.result_ok(result),
		"same-repository/current-epoch token must still reject replaced committed bytes"
	)
	assert_true(
		storage.has_exact_copy(context["old_bytes"], context["archive_path"]),
		"replacement rejection must retain the old committed run in backup/archive"
	)
	assert_eq(
		Support.profile_fingerprint(context["old_bytes"]),
		Support.profile_fingerprint(
			storage.file_bytes(StorageFaultKey.MAIN).value
		),
		"replacement rejection must not mutate profile"
	)
	var restart_repository: SaveRepository = SaveRootFixture.create_repository(storage)
	add_child_autofree(restart_repository)
	var restarted: LoadResult = restart_repository.load()
	assert_true(restarted.ok)
	assert_eq(restarted.run_status, LoadResult.RunStatus.LOADED)
	assert_eq(restarted.run.run_id, context["root"].run.run_id)


func _assert_archive_and_clear_save_faults_preserve_restartable_committed_copy() -> void:
	var fault_cases: Array[Dictionary] = [
		{"label": "archive tmp write", "op": StorageFaultKey.WRITE, "prefix": Support.ARCHIVE_PREFIX},
		{"label": "archive tmp readback", "op": StorageFaultKey.READ, "prefix": Support.ARCHIVE_PREFIX},
		{"label": "archive promote", "op": StorageFaultKey.RENAME, "prefix": Support.ARCHIVE_PREFIX},
		{"label": "clear save write", "op": StorageFaultKey.WRITE, "prefix": String(StorageFaultKey.TMP)},
		{"label": "clear save readback", "op": StorageFaultKey.READ, "prefix": String(StorageFaultKey.TMP)},
		{"label": "clear save rotate", "op": StorageFaultKey.RENAME, "prefix": String(StorageFaultKey.MAIN)},
		{"label": "clear save promote", "op": StorageFaultKey.RENAME, "prefix": String(StorageFaultKey.TMP)},
	]
	for fault_case: Dictionary in fault_cases:
		var context: Dictionary = Support.seeded_context(self)
		var storage: Variant = context["storage"]
		var repository: SaveRepository = context["repository"]
		var service: Variant = Support.require_service(self, repository)
		if service == null:
			return
		var token: RetainedRunRecoveryToken = Support.issue_token(
			self,
			service,
			context["loaded"],
			StringName(context["root"].run.run_id)
		)
		if token == null:
			return
		storage.reset_journal()
		storage.inject_matching_fault(
			fault_case["op"],
			String(fault_case["prefix"])
		)
		var result: Variant = Support.discard(self, service, token)
		assert_false(Support.result_ok(result), String(fault_case["label"]))
		assert_true(
			storage.has_exact_copy(context["old_bytes"], context["archive_path"]),
			"%s must preserve a byte-identical committed copy" % fault_case["label"]
		)
		storage.clear_all_faults()
		var restart_repository: SaveRepository = SaveRootFixture.create_repository(storage)
		add_child_autofree(restart_repository)
		var restarted: LoadResult = restart_repository.load()
		assert_true(restarted.ok, "%s must be restart-recoverable" % fault_case["label"])
		if restarted.ok:
			assert_eq(
				restarted.run_status,
				LoadResult.RunStatus.LOADED,
				"%s must not clear the retained run" % fault_case["label"]
			)
			assert_eq(
				restarted.run.run_id,
				context["root"].run.run_id,
				"%s must recover the same run" % fault_case["label"]
			)
			assert_eq(
				Support.profile_fingerprint(context["old_bytes"]),
				Support.profile_fingerprint(
					storage.file_bytes(StorageFaultKey.MAIN).value
				),
				"%s restart must preserve profile exactly" % fault_case["label"]
			)
		assert_true(
			storage.residue_paths().is_empty(),
			"%s restart must clear or isolate every tmp residue" % fault_case["label"]
		)


func _assert_success_orders_archive_before_clear_and_existing_digest_is_idempotent() -> void:
	var context: Dictionary = Support.seeded_context(self)
	var storage: Variant = context["storage"]
	var repository: SaveRepository = context["repository"]
	var service: Variant = Support.require_service(self, repository)
	if service == null:
		return
	var token: RetainedRunRecoveryToken = Support.issue_token(
		self,
		service,
		context["loaded"],
		StringName(context["root"].run.run_id)
	)
	if token == null:
		return
	storage.reset_journal()
	var result: Variant = Support.discard(self, service, token)
	assert_true(Support.result_ok(result), "valid decoded token must discard successfully")
	var archive_write: int = Support.operation_index(
		storage, StorageFaultKey.WRITE, Support.ARCHIVE_PREFIX
	)
	var archive_readback: int = Support.operation_index(
		storage, StorageFaultKey.READ, Support.ARCHIVE_PREFIX, archive_write + 1
	)
	var archive_promote: int = Support.operation_index(
		storage, StorageFaultKey.RENAME, Support.ARCHIVE_PREFIX, archive_readback + 1
	)
	var clear_write: int = Support.operation_index(
		storage, StorageFaultKey.OPEN_WRITE, String(StorageFaultKey.TMP), archive_promote + 1
	)
	assert_true(
		archive_write >= 0
			and archive_readback > archive_write
			and archive_promote > archive_readback
			and clear_write > archive_promote,
		"success must order copy→digest archive tmp→readback→promote before clear-run save"
	)
	assert_eq(
		storage.file_bytes(context["archive_path"]).value,
		context["old_bytes"],
		"digest archive must be byte-identical to the original committed file"
	)
	var after_repository: SaveRepository = SaveRootFixture.create_repository(storage)
	add_child_autofree(after_repository)
	var loaded_after: LoadResult = after_repository.load()
	assert_true(loaded_after.ok)
	assert_eq(loaded_after.run_status, LoadResult.RunStatus.NONE)
	assert_eq(
		Support.profile_fingerprint(context["old_bytes"]),
		Support.profile_fingerprint(storage.file_bytes(StorageFaultKey.MAIN).value),
		"successful clear must preserve profile exactly"
	)

	var idempotent: Dictionary = Support.seeded_context(self)
	var idempotent_storage: Variant = idempotent["storage"]
	idempotent_storage.seed_file(idempotent["archive_path"], idempotent["old_bytes"])
	var idempotent_service: Variant = Support.require_service(
		self, idempotent["repository"]
	)
	if idempotent_service == null:
		return
	var idempotent_token: RetainedRunRecoveryToken = Support.issue_token(
		self,
		idempotent_service,
		idempotent["loaded"],
		StringName(idempotent["root"].run.run_id)
	)
	if idempotent_token == null:
		return
	var idempotent_result: Variant = Support.discard(
		self, idempotent_service, idempotent_token
	)
	assert_true(
		Support.result_ok(idempotent_result),
		"an existing byte-identical digest archive must be idempotent success"
	)
	assert_eq(
		idempotent_storage.file_bytes(idempotent["archive_path"]).value,
		idempotent["old_bytes"]
	)


func _assert_zero_clear_and_original_main(
	storage: Variant,
	context: Dictionary,
	label: String
) -> void:
	var main: OptionalBytesValue = storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(main, "%s must retain main" % label)
	if main != null:
		assert_eq(main.value, context["old_bytes"], "%s must not clear run" % label)
	assert_eq(
		Support.profile_fingerprint(context["old_bytes"]),
		Support.profile_fingerprint(main.value) if main != null else "",
		"%s must leave profile unchanged" % label
	)
	assert_eq(
		Support.operation_index(storage, StorageFaultKey.OPEN_WRITE, ""),
		-1,
		"%s must perform zero writes" % label
	)
	var restart_repository: SaveRepository = SaveRootFixture.create_repository(storage)
	add_child_autofree(restart_repository)
	var restarted: LoadResult = restart_repository.load()
	assert_true(restarted.ok, "%s must remain restartable" % label)
	if restarted.ok:
		assert_eq(restarted.run_status, LoadResult.RunStatus.LOADED)
		assert_eq(restarted.run.run_id, context["root"].run.run_id)
