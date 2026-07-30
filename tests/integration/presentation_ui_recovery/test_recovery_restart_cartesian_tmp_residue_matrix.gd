extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_recovery/recovery_test_support.gd"
)


func test_recovery_restart_cartesian_tmp_residue_matrix() -> void:
	var versions: Dictionary = Support.encoded_versions()
	var base_states: Array[String] = [
		"main_old",
		"main_old_archive",
		"backup_old_archive",
		"main_new_backup_old_archive",
	]
	var residue_states: Array[String] = [
		"none",
		"archive_tmp",
		"save_tmp",
		"both",
	]
	for base_state: String in base_states:
		for residue_state: String in residue_states:
			_assert_restart_case(base_state, residue_state, versions)


func _assert_restart_case(
	base_state: String,
	residue_state: String,
	versions: Dictionary
) -> void:
	var label: String = "%s × %s" % [base_state, residue_state]
	var storage: Variant = Support.RecoveryFakeStorage.new()
	_seed_base_state(storage, base_state, versions)
	var archive_tmp_path: StringName = StringName(
		"%s.%s.matrix%s" % [
			Support.ARCHIVE_PREFIX,
			versions["old_digest"],
			Support.ARCHIVE_TMP_MARKER,
		]
	)
	if residue_state in ["archive_tmp", "both"]:
		storage.seed_file(archive_tmp_path, versions["divergent_bytes"])
	if residue_state in ["save_tmp", "both"]:
		storage.seed_file(StorageFaultKey.TMP, versions["divergent_bytes"])

	var repository: SaveRepository = SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var loaded: LoadResult = repository.load()
	assert_true(loaded.ok, "%s restart must select a valid authority" % label)
	if not loaded.ok:
		return

	var expects_cleared_main: bool = base_state == "main_new_backup_old_archive"
	assert_eq(
		loaded.run_status,
		LoadResult.RunStatus.NONE if expects_cleared_main else LoadResult.RunStatus.LOADED,
		"%s must prefer valid main, otherwise repair byte-identical backup old" % label
	)
	if not expects_cleared_main:
		assert_not_null(loaded.run, "%s must retain the active run" % label)
		if loaded.run != null:
			assert_eq(
				loaded.run.run_id,
				versions["old_root"].run.run_id,
				"%s must recover the exact retained run" % label
			)

	var expected_main: PackedByteArray = (
		versions["cleared_bytes"]
		if expects_cleared_main
		else versions["old_bytes"]
	)
	var main: OptionalBytesValue = storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(main, "%s must leave or repair a valid main" % label)
	if main != null:
		assert_eq(
			main.value,
			expected_main,
			"%s must never promote archive/save tmp residue to authority" % label
		)
		assert_eq(
			Support.profile_fingerprint(main.value),
			Support.profile_fingerprint(versions["old_bytes"]),
			"%s must preserve profile exactly" % label
		)
	assert_true(
		storage.has_exact_copy(versions["old_bytes"], versions["archive_path"]),
		"%s must retain one byte-identical copy of the old committed run" % label
	)
	assert_false(
		storage.has_path(archive_tmp_path),
		"%s must clear or isolate archive tmp residue" % label
	)
	assert_false(
		storage.has_path(StorageFaultKey.TMP),
		"%s must clear or isolate save tmp residue" % label
	)


func _seed_base_state(
	storage: Variant,
	base_state: String,
	versions: Dictionary
) -> void:
	match base_state:
		"main_old":
			storage.seed_file(StorageFaultKey.MAIN, versions["old_bytes"])
		"main_old_archive":
			storage.seed_file(StorageFaultKey.MAIN, versions["old_bytes"])
			storage.seed_file(versions["archive_path"], versions["old_bytes"])
		"backup_old_archive":
			storage.seed_file(StorageFaultKey.BACKUP, versions["old_bytes"])
			storage.seed_file(versions["archive_path"], versions["old_bytes"])
		"main_new_backup_old_archive":
			storage.seed_file(StorageFaultKey.MAIN, versions["cleared_bytes"])
			storage.seed_file(StorageFaultKey.BACKUP, versions["old_bytes"])
			storage.seed_file(versions["archive_path"], versions["old_bytes"])
		_:
			assert(false, "unknown recovery base state")
