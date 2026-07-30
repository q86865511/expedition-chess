extends GutTest

## G2 wave2-B L7 regression (fix/g2-ui-review-findings): SettingsRepository
## held its storage boundary as `var _storage: Variant`, so an incomplete
## test double or misuse would only surface deep inside a specific
## read_bytes/write_bytes/... call (often inside a fault-injection branch)
## instead of failing immediately at construction. This locks the fix: the
## storage boundary must be the named SettingsStoragePort type (mirroring how
## SaveStoragePort is a named boundary for SaveRepository), not a Variant --
## and every port method returns the named SettingsStorageResult, not a bare
## Dictionary (project convention: public domain APIs use named types; the
## first cut of this fix returned Dictionary from the six port methods and
## was rejected by the Spec suite's public-API-typing contract).
##
## This test only checks the static contract (source text + method surface).
## It deliberately does not construct SettingsRepository with a type that
## fails the SettingsStoragePort type check: that failure is itself a script
## error, and this repo's GUT runner treats any script error as a fatal test
## failure (see runner_contract/fixtures/push_error), so asserting it here
## would make the fix's own regression test flip the suite red.

const PORT_PATH := "res://services/settings/settings_storage_port.gd"
const RESULT_PATH := "res://services/settings/settings_storage_result.gd"
const REPOSITORY_PATH := "res://services/settings/settings_repository.gd"


func test_settings_storage_port_exists_with_the_named_result_contract() -> void:
	assert_true(
		FileAccess.file_exists(PORT_PATH),
		"T02/L7 must add a named SettingsStoragePort (services/settings/settings_storage_port.gd)"
	)
	assert_true(
		FileAccess.file_exists(RESULT_PATH),
		"T02/L7 must add a named SettingsStorageResult (services/settings/settings_storage_result.gd)"
	)
	if not FileAccess.file_exists(PORT_PATH) or not FileAccess.file_exists(RESULT_PATH):
		return
	var script := load(PORT_PATH) as GDScript
	assert_not_null(script)
	if script == null:
		return
	var instance: Object = script.new()
	assert_eq(
		String(instance.get_class()),
		"RefCounted",
		"SettingsStoragePort must be a lightweight RefCounted boundary, like SaveStoragePort"
	)
	for method_name: StringName in [
		&"read_bytes", &"write_bytes", &"promote_bytes",
		&"copy_bytes", &"restore_bytes", &"remove_bytes",
	]:
		assert_true(
			instance.has_method(method_name),
			"SettingsStoragePort must declare %s" % method_name
		)
	var default_result: Variant = instance.call(&"read_bytes", &"probe")
	assert_true(
		default_result is SettingsStorageResult,
		"every SettingsStoragePort method must return the named SettingsStorageResult, not a Dictionary"
	)
	if default_result is SettingsStorageResult:
		assert_false(
			(default_result as SettingsStorageResult).ok,
			"an unoverridden port method must fail closed by default, like SaveStoragePort"
		)


func test_settings_repository_holds_storage_through_the_named_port_type() -> void:
	assert_true(FileAccess.file_exists(REPOSITORY_PATH))
	if not FileAccess.file_exists(REPOSITORY_PATH):
		return
	var source := FileAccess.get_file_as_string(REPOSITORY_PATH)
	assert_string_contains(
		source,
		"var _storage: SettingsStoragePort",
		"SettingsRepository must not degrade its storage boundary to Variant"
	)
	assert_false(
		source.contains("var _storage: Variant"),
		"the pre-fix Variant-typed storage field must be gone"
	)
	assert_string_contains(
		source,
		"func _init(storage: SettingsStoragePort = null)",
		"SettingsRepository's constructor must type-check its storage argument"
	)
	assert_string_contains(
		source,
		"extends SettingsStoragePort",
		"the production FileSettingsStorage adapter must implement the named port"
	)
	for signature: String in [
		"func read_bytes(path: StringName) -> SettingsStorageResult:",
		"func write_bytes(path: StringName, bytes: PackedByteArray) -> SettingsStorageResult:",
		"func promote_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:",
		"func copy_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:",
		"func restore_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:",
		"func remove_bytes(path: StringName) -> SettingsStorageResult:",
	]:
		assert_string_contains(
			source,
			signature,
			"FileSettingsStorage must not re-degrade its overrides back to Dictionary returns"
		)
