extends RefCounted

## T06 runtime fixture for retained-run recovery.  G2-R12-A02 remains review
## debt: these tests intentionally do not decide the terminal snapshot capture
## ownership question.

const SERVICE_PATH := "res://services/save/retained_run_recovery_service.gd"
const ARCHIVE_PREFIX := "recovery/"
const ARCHIVE_SUFFIX := ".save"
const ARCHIVE_TMP_MARKER := ".tmp"


class RecoveryFakeStorage:
	extends FakeSaveStorage

	var _matching_faults: Array[Dictionary] = []

	func inject_matching_fault(
		operation_kind: StringName,
		path_prefix: String,
		path_suffix: String = "",
		occurrence: int = -1
	) -> void:
		_matching_faults.append({
			"operation_kind": operation_kind,
			"path_prefix": path_prefix,
			"path_suffix": path_suffix,
			"occurrence": occurrence,
		})

	func clear_all_faults() -> void:
		clear_faults()
		_matching_faults.clear()

	func paths() -> Array[StringName]:
		var output: Array[StringName] = []
		for stored: FakeStoredFile in _files:
			output.append(stored.logical_path)
		return output

	func has_path(path: StringName) -> bool:
		return _find_file(path) != null

	func has_exact_copy(bytes: PackedByteArray, archive_path: StringName) -> bool:
		for path: StringName in [StorageFaultKey.MAIN, StorageFaultKey.BACKUP, archive_path]:
			var value: OptionalBytesValue = file_bytes(path)
			if value != null and value.value == bytes:
				return true
		return false

	func residue_paths() -> Array[StringName]:
		var output: Array[StringName] = []
		for path: StringName in paths():
			var text: String = String(path)
			if path == StorageFaultKey.TMP \
				or (text.begins_with(ARCHIVE_PREFIX) and text.contains(ARCHIVE_TMP_MARKER)):
				output.append(path)
		return output

	func _should_fail(key: StorageFaultKey) -> bool:
		for pattern: Dictionary in _matching_faults:
			var expected_occurrence: int = int(pattern["occurrence"])
			var text: String = String(key.logical_path)
			if key.operation_kind == pattern["operation_kind"] \
				and text.begins_with(String(pattern["path_prefix"])) \
				and text.ends_with(String(pattern["path_suffix"])) \
				and (expected_occurrence < 0 or key.occurrence == expected_occurrence):
				return true
		return super._should_fail(key)


static func seeded_context(test: GutTest) -> Dictionary:
	var storage: RecoveryFakeStorage = RecoveryFakeStorage.new()
	var repository: SaveRepository = SaveRootFixture.create_repository(storage)
	test.add_child_autofree(repository)
	var root: SaveRoot = SaveRootFixture.create_valid_root()
	var save_result: SaveResult = repository.save(root)
	var main_value: OptionalBytesValue = storage.file_bytes(StorageFaultKey.MAIN)
	var old_bytes: PackedByteArray = (
		main_value.value.duplicate()
		if main_value != null
		else PackedByteArray()
	)
	var loaded: LoadResult = repository.load()
	return {
		"storage": storage,
		"repository": repository,
		"root": root,
		"save_result": save_result,
		"loaded": loaded,
		"old_bytes": old_bytes,
		"old_digest": sha256(old_bytes),
		"archive_path": archive_path(old_bytes),
	}


static func encoded_versions() -> Dictionary:
	var codec: SaveJsonCodec = SaveRootFixture.create_codec()
	var old_root: SaveRoot = SaveRootFixture.create_valid_root()
	var cleared_root: SaveRoot = old_root.deep_clone()
	cleared_root.run = null
	var divergent_root: SaveRoot = cleared_root.deep_clone()
	divergent_root.profile.meta_currency += 999
	var old_encoded: SaveEncodeResult = codec.encode(old_root)
	var cleared_encoded: SaveEncodeResult = codec.encode(cleared_root)
	var divergent_encoded: SaveEncodeResult = codec.encode(divergent_root)
	return {
		"old_root": old_root,
		"old_bytes": old_encoded.bytes.value.duplicate(),
		"cleared_bytes": cleared_encoded.bytes.value.duplicate(),
		"divergent_bytes": divergent_encoded.bytes.value.duplicate(),
		"old_digest": String(old_encoded.digest.value),
		"archive_path": StringName(
			"%s%s%s" % [ARCHIVE_PREFIX, String(old_encoded.digest.value), ARCHIVE_SUFFIX]
		),
	}


static func require_service(test: GutTest, repository: SaveRepository) -> Variant:
	if not FileAccess.file_exists(SERVICE_PATH):
		test.assert_true(
			false,
			"T06 behavioral red: RetainedRunRecoveryService is not implemented"
		)
		return null
	var script: Script = ResourceLoader.load(SERVICE_PATH) as Script
	if script == null:
		test.assert_true(false, "T06 recovery service script must load")
		return null
	var service: Variant = script.new(repository)
	for method_name: StringName in [&"issue_token", &"discard"]:
		if service == null or not service.has_method(method_name):
			test.assert_true(
				false,
				"T06 recovery service must expose %s" % String(method_name)
			)
			return null
	return service


static func issue_token(
	test: GutTest,
	service: Variant,
	loaded: LoadResult,
	expected_run_id: StringName
) -> RetainedRunRecoveryToken:
	if service == null or not service.has_method(&"issue_token"):
		test.assert_true(false, "T06 recovery issue_token contract is unavailable")
		return null
	var token: Variant = service.call(&"issue_token", loaded, expected_run_id)
	test.assert_true(
		token is RetainedRunRecoveryToken,
		"issue_token must return a typed RetainedRunRecoveryToken"
	)
	return token as RetainedRunRecoveryToken


static func discard(
	test: GutTest,
	service: Variant,
	token: RetainedRunRecoveryToken
) -> Variant:
	if service == null or not service.has_method(&"discard"):
		test.assert_true(false, "T06 recovery discard contract is unavailable")
		return null
	var result: Variant = service.call(&"discard", token)
	test.assert_not_null(result, "discard must return a typed result")
	if result == null or not has_property(result, &"ok"):
		test.assert_true(false, "discard result must expose ok")
		return null
	return result


static func has_property(target: Object, property_name: StringName) -> bool:
	if target == null:
		return false
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func result_ok(result: Variant) -> bool:
	return result is Object and has_property(result, &"ok") and bool(result.get("ok"))


static func sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


static func archive_path(bytes: PackedByteArray) -> StringName:
	return StringName("%s%s%s" % [ARCHIVE_PREFIX, sha256(bytes), ARCHIVE_SUFFIX])


static func profile_fingerprint(bytes: PackedByteArray) -> String:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.has("profile"):
		return ""
	return JSON.stringify(parsed["profile"])


static func operation_index(
	storage: RecoveryFakeStorage,
	operation_kind: StringName,
	path_prefix: String,
	start_index: int = 0
) -> int:
	var journal: Array[StorageFaultKey] = storage.journal_snapshot()
	for index: int in range(start_index, journal.size()):
		var key: StorageFaultKey = journal[index]
		if key.operation_kind == operation_kind \
			and String(key.logical_path).begins_with(path_prefix):
			return index
	return -1


static func token_with(
	repository_identity: Object,
	operation_epoch: int,
	committed_digest: String,
	expected_run_id: StringName,
	use_nonce: StringName
) -> RetainedRunRecoveryToken:
	return RetainedRunRecoveryToken.new(
		repository_identity,
		operation_epoch,
		committed_digest,
		expected_run_id,
		use_nonce
	)
