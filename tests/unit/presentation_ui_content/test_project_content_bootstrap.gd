extends GutTest

## G2 presentation-ui T01 behavioral contract.
##
## T00 intentionally did not declare these production classes.  Keep every
## reference dynamic so a missing T01 file is a normal, countable assertion
## failure rather than a GDScript parser/import abort.
##
## Test-author API decision (the SDD fixes behavior but not these signatures):
## - ProjectContentBootstrap.new(ContentDependencyPort).run(ContentRegistryService)
##   returns an object with ok/error_code/receipt/manifest_digest.
## - ProjectContentDependencyPort.new(LocalizationCatalog) implements the existing
##   ContentDependencyPort asset_exists/localization_key_exists methods.
## - LocalizationCatalog.new() exposes default_locale(), supported_locales(),
##   keys_for_locale(locale), and resolve(locale, key).  resolve returns an object
##   with ok/value/error_code.
##
## Build Lab remains a dev adapter.  It may keep its existing run(registry)
## surface, but its source must delegate to the production bootstrap instead of
## installing the packs with BuildLabDependencyPort or a second validation graph.

const BOOTSTRAP_PATH := "res://app/content/project_content_bootstrap.gd"
const DEPENDENCY_PATH := "res://app/content/project_content_dependency_port.gd"
const LOCALIZATION_PATH := "res://app/content/localization_catalog.gd"
const BUILD_LAB_BOOTSTRAP_PATH := \
	"res://scripts/dev/build_lab/build_lab_content_bootstrap.gd"

const KNOWN_CONTENT_KEY := &"loc.unit_slice_player_00"
const KNOWN_CONTENT_ASSET := \
	"res://content/packs/vertical_slice/units/slice_player_00.tres"
const MISSING_KEY := &"loc.__t01_deleted_fixture__"
const MISSING_ASSET := "res://content/packs/vertical_slice/units/__t01_deleted_fixture__.tres"


class CountingDependencyPort extends ContentDependencyPort:
	var asset_checks: int = 0
	var localization_checks: int = 0
	var reject_assets: bool = false
	var reject_keys: bool = false

	func asset_exists(_path: String) -> bool:
		asset_checks += 1
		return not reject_assets

	func localization_key_exists(_key: StringName) -> bool:
		localization_checks += 1
		return not reject_keys


func test_production_bootstrap_is_injectable_and_returns_one_pinned_receipt() -> void:
	var bootstrap_script := _load_script(BOOTSTRAP_PATH, "ProjectContentBootstrap")
	if bootstrap_script == null:
		return
	var dependency := CountingDependencyPort.new()
	var bootstrap: Object = bootstrap_script.new(dependency)
	var result: Variant = bootstrap.call("run", ContentRegistryService.new())

	assert_true(_field_bool(result, &"ok"), _field_text(result, &"error_code"))
	assert_not_null(_field(result, &"receipt"))
	assert_eq(_field_text(result, &"manifest_digest").length(), 64)
	assert_gt(
		dependency.asset_checks,
		0,
		"production bootstrap must validate real asset dependencies"
	)
	assert_gt(
		dependency.localization_checks,
		0,
		"production bootstrap must validate localization dependencies"
	)


func test_production_bootstrap_names_missing_asset_without_installing() -> void:
	var bootstrap_script := _load_script(BOOTSTRAP_PATH, "ProjectContentBootstrap")
	if bootstrap_script == null:
		return
	var dependency := CountingDependencyPort.new()
	dependency.reject_assets = true
	var result: Variant = bootstrap_script.new(dependency).call(
		"run", ContentRegistryService.new()
	)

	assert_false(_field_bool(result, &"ok"))
	assert_eq(_field_name(result, &"error_code"), &"CONTENT_ASSET_MISSING")
	assert_null(_field(result, &"receipt"))
	assert_gt(dependency.asset_checks, 0)


func test_production_bootstrap_names_missing_localization_key_without_installing() -> void:
	var bootstrap_script := _load_script(BOOTSTRAP_PATH, "ProjectContentBootstrap")
	if bootstrap_script == null:
		return
	var dependency := CountingDependencyPort.new()
	dependency.reject_keys = true
	var result: Variant = bootstrap_script.new(dependency).call(
		"run", ContentRegistryService.new()
	)

	assert_false(_field_bool(result, &"ok"))
	assert_eq(_field_name(result, &"error_code"), &"CONTENT_LOCALIZATION_KEY_MISSING")
	assert_null(_field(result, &"receipt"))
	assert_gt(dependency.localization_checks, 0)


func test_localization_catalog_defaults_to_nonempty_zh_tw_and_en_has_exact_key_set() -> void:
	var catalog_script := _load_script(LOCALIZATION_PATH, "LocalizationCatalog")
	if catalog_script == null:
		return
	var catalog: Object = catalog_script.new()
	var zh_keys := _string_names(catalog.call("keys_for_locale", &"zh_TW"))
	var en_keys := _string_names(catalog.call("keys_for_locale", &"en"))
	zh_keys.sort()
	en_keys.sort()

	assert_eq(catalog.call("default_locale"), &"zh_TW")
	assert_eq(_string_names(catalog.call("supported_locales")), [&"zh_TW", &"en"])
	assert_gt(zh_keys.size(), 0)
	assert_eq(en_keys, zh_keys)
	for key: StringName in zh_keys:
		var resolved: Variant = catalog.call("resolve", &"zh_TW", key)
		assert_true(_field_bool(resolved, &"ok"), String(key))
		assert_false(_field_text(resolved, &"value").strip_edges().is_empty(), String(key))


func test_localization_catalog_rejects_other_locale_and_missing_key_by_name() -> void:
	var catalog_script := _load_script(LOCALIZATION_PATH, "LocalizationCatalog")
	if catalog_script == null:
		return
	var catalog: Object = catalog_script.new()
	var unsupported: Variant = catalog.call("resolve", &"ja", KNOWN_CONTENT_KEY)
	var missing: Variant = catalog.call("resolve", &"zh_TW", MISSING_KEY)

	assert_false(_field_bool(unsupported, &"ok"))
	assert_eq(_field_name(unsupported, &"error_code"), &"UNSUPPORTED_LOCALE")
	assert_false(_field_bool(missing, &"ok"))
	assert_eq(_field_name(missing, &"error_code"), &"LOCALIZATION_KEY_MISSING")


func test_real_dependency_port_checks_resource_and_catalog_instead_of_returning_true() -> void:
	var dependency_script := _load_script(
		DEPENDENCY_PATH, "ProjectContentDependencyPort"
	)
	var catalog_script := _load_script(LOCALIZATION_PATH, "LocalizationCatalog")
	if dependency_script == null or catalog_script == null:
		return
	var dependency: Object = dependency_script.new(catalog_script.new())

	assert_true(dependency.call("asset_exists", KNOWN_CONTENT_ASSET))
	assert_false(dependency.call("asset_exists", MISSING_ASSET))
	assert_true(dependency.call("localization_key_exists", KNOWN_CONTENT_KEY))
	assert_false(dependency.call("localization_key_exists", MISSING_KEY))


func test_build_lab_adapter_consumes_project_bootstrap_without_second_content_graph() -> void:
	assert_true(FileAccess.file_exists(BUILD_LAB_BOOTSTRAP_PATH))
	if not FileAccess.file_exists(BUILD_LAB_BOOTSTRAP_PATH):
		return
	var source := FileAccess.get_file_as_string(BUILD_LAB_BOOTSTRAP_PATH)

	assert_true(
		source.contains("ProjectContentBootstrap"),
		"Build Lab adapter must consume the production bootstrap"
	)
	assert_false(
		source.contains("BuildLabDependencyPort"),
		"Build Lab must not keep an always-true dependency fake"
	)
	assert_false(
		source.contains("ContentValidator.new()"),
		"Build Lab must not keep a second validation/install graph"
	)
	assert_false(
		source.contains("install_validated("),
		"Build Lab must consume the production receipt instead of reinstalling content"
	)


func _load_script(path: String, expected_name: String) -> GDScript:
	var exists := FileAccess.file_exists(path)
	assert_true(exists, "%s production script missing: %s" % [expected_name, path])
	if not exists:
		return null
	var script := load(path) as GDScript
	assert_not_null(script, "%s must load as GDScript: %s" % [expected_name, path])
	return script


func _field(value: Variant, key: StringName) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).get(key)
	if value is Object:
		return (value as Object).get(key)
	return null


func _field_bool(value: Variant, key: StringName) -> bool:
	return bool(_field(value, key))


func _field_text(value: Variant, key: StringName) -> String:
	var field_value: Variant = _field(value, key)
	return "" if field_value == null else String(field_value)


func _field_name(value: Variant, key: StringName) -> StringName:
	return StringName(_field_text(value, key))


func _string_names(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for entry: Variant in value:
			result.append(StringName(entry))
	elif value is PackedStringArray:
		for entry: String in value:
			result.append(StringName(entry))
	return result
