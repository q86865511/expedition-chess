extends GutTest

func test_content_codec_golden_and_roundtrip() -> void:
	var golden: Dictionary = ContentVerificationSuite.new().run("golden")
	assert_eq(int(golden["case_count"]), 1)
	assert_true(bool(golden["ok"]), JSON.stringify(golden["failures"]))
	var roundtrip: Dictionary = ContentVerificationSuite.new().run("payload_roundtrip")
	assert_true(bool(roundtrip["ok"]), JSON.stringify(roundtrip["failures"]))

func test_registry_generation_pinning_and_clone_isolation() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("registry_pinning")
	assert_eq(int(result["case_count"]), 1)
	assert_true(bool(result["ok"]), JSON.stringify(result["failures"]))

func test_registry_failed_builds_do_not_publish_partial_generations() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("registry_transaction_rollback")
	assert_eq(int(result["case_count"]), 1)
	assert_true(bool(result["ok"]), JSON.stringify(result["failures"]))

func test_codec_and_lookup_negative_contracts() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("codec_negative")
	assert_true(bool(result["ok"]), JSON.stringify(result["failures"]))

func test_unknown_operation_subclasses_fail_compilation() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("unknown_operation_compile")
	assert_eq(int(result["case_count"]), 1)
	assert_true(bool(result["ok"]), JSON.stringify(result["failures"]))

func test_filtered_case_reports_only_executed_coverage() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("golden")
	assert_eq(result["completed_scopes"], ["content_codec_golden_fixture"])

func test_alias_probe_compiles_new_pinned_receipt() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("alias_receipt_migration")
	assert_true(bool(result["ok"]), JSON.stringify(result["failures"]))

func test_required_tombstone_never_guesses_safe_replacement() -> void:
	var result: Dictionary = ContentVerificationSuite.new().run("required_tombstone_incompatible")
	assert_true(bool(result["ok"]), JSON.stringify(result["failures"]))

func test_content_ref_requires_digest_and_stable_id() -> void:
	assert_false(ContentRef.new("bad", &"unit.a").is_valid())
	assert_false(ContentRef.new("0000000000000000000000000000000000000000000000000000000000000000", &"").is_valid())
	assert_true(ContentRef.new("0000000000000000000000000000000000000000000000000000000000000000", &"unit.a").is_valid())

func test_authoring_resource_tres_roundtrip_compiles() -> void:
	var path := "user://foundation-content-unit-fixture.tres"
	assert_eq(ResourceSaver.save(ContentGoldenFixture.unit_definition(), path), OK)
	var loaded := ResourceLoader.load(path)
	assert_true(loaded is UnitDef)
	var compiled := ContentDefinitionCompiler.new().compile(loaded as UnitDef)
	assert_true(compiled.ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
