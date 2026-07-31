extends GutTest

## B3 回歸:正式 boot 的 SaveRepository 組裝必須帶 codec 2→3 generation migration
## port。先前只傳 receipt/id migration 兩個 port,歷史 schema 3／codec 2 save 一律
## PORT_UNCONFIGURED → incompatible_preserved(歷史 fixture 測試會綠,只因為測試
## 自己注入了 port)。本測試走的是正式路徑:正式 bootstrap 安裝內容 →
## ProductionContentGenerationMigrationPortBuilder 封裝 → SaveRepository
## `_configure_content_ports`,再用 5e78ccf 的 fixture bytes 實際 load。

const FIXTURE_PATH := \
	"res://tests/fixtures/save/content_production/5e78ccf.schema3.codec2.json"


func test_production_repository_upgrades_historical_schema3_codec2_save() -> void:
	var registry := autofree(ContentRegistryService.new()) as ContentRegistryService
	var content := ProjectContentBootstrap.new().run(registry)
	content.release_registry_ownership()
	assert_true(content.ok, String(content.error_code))
	if not content.ok:
		return
	assert_not_null(
		content.localization_catalog,
		"正式 bootstrap 必須把安裝中的 localization catalog 交出來"
	)
	var port := ProductionContentGenerationMigrationPortBuilder.new().build(
		registry, content.receipt, content.localization_catalog
	)
	var storage := FakeSaveStorage.new()
	storage.seed_file(
		StorageFaultKey.MAIN, _fixture_text().to_utf8_buffer()
	)
	var repository := SaveRepository.new(storage)
	add_child_autofree(repository)
	var configured := repository._configure_content_ports(
		ContentRegistryReceiptAdapter.new(registry),
		ContentRegistryMigrationAdapter.new(registry),
		port
	)
	assert_true(configured.ok)
	if not configured.ok:
		return

	var loaded := repository.load()
	assert_true(loaded.ok, "歷史 save 必須可載入")
	if not loaded.ok:
		return
	assert_eq(
		loaded.run_status,
		LoadResult.RunStatus.LOADED,
		"接上 production port 後不得再落回 incompatible_preserved"
	)
	if loaded.run == null:
		return
	assert_eq(loaded.run.content_snapshot.catalog_schema_version_value(), 2)
	assert_eq(loaded.run.content_snapshot.content_codec_version_value(), 3)
	assert_eq(
		loaded.run.content_snapshot.manifest_digest_value(),
		content.manifest_digest
	)
	assert_eq(
		loaded.run.commander_id,
		&"commander.slice_c0",
		"歷史 commander id 必須依宣告表 alias 到正式指揮官"
	)


func test_production_port_rejects_unknown_source_generation() -> void:
	var registry := autofree(ContentRegistryService.new()) as ContentRegistryService
	var content := ProjectContentBootstrap.new().run(registry)
	content.release_registry_ownership()
	assert_true(content.ok, String(content.error_code))
	if not content.ok:
		return
	var port := ProductionContentGenerationMigrationPortBuilder.new().build(
		registry, content.receipt, content.localization_catalog
	)
	var empty: Array[StringName] = []
	var references: Array[ContentGenerationMigrationReference] = [
		ContentGenerationMigrationReference.new(
			&"economy_config", &"economy.fixture",
			&"run.content_snapshot.economy_config_id", true
		),
	]
	var enabled: Array[StringName] = [&"economy.fixture"]
	var request := ContentGenerationMigrationRequest.new(
		"0.1.0-unlisted",
		"f".repeat(64),
		enabled,
		&"economy.fixture",
		empty,
		empty,
		empty,
		&"meta.fixture",
		1,
		2,
		references
	)
	var result := port.migrate_generation(request)
	assert_false(result.ok, "未列入 allowlist 的來源世代不得升級")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.PACK_MISSING)


func _fixture_text() -> String:
	var handle := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	return handle.get_as_text() if handle != null else ""
